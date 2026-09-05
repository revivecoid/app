import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../../estimator/providers/customer_intake_provider.dart';

enum DeliveryOption { selfDeliver, pickup }
enum PaymentStatus { pending, awaitingWebhook, paid, failed, manualTransferPending }
enum PaymentMethod { onlineGateway, manualTransfer }

class CheckoutState {
  final String jobId;
  final double estimatedCost;
  final DeliveryOption deliveryOption;
  final String? pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final DateTime? scheduledDate;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final String? errorMessage;
  final bool isLoading;
  final XFile? transferProof;

  CheckoutState({
    required this.jobId,
    required this.estimatedCost,
    this.deliveryOption = DeliveryOption.selfDeliver,
    this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    this.scheduledDate,
    this.paymentMethod = PaymentMethod.onlineGateway,
    this.paymentStatus = PaymentStatus.pending,
    this.errorMessage,
    this.isLoading = false,
    this.transferProof,
  });

  CheckoutState copyWith({
    String? jobId,
    double? estimatedCost,
    DeliveryOption? deliveryOption,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    DateTime? scheduledDate,
    PaymentMethod? paymentMethod,
    PaymentStatus? paymentStatus,
    String? errorMessage,
    bool? isLoading,
    XFile? transferProof,
  }) {
    return CheckoutState(
      jobId: jobId ?? this.jobId,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      deliveryOption: deliveryOption ?? this.deliveryOption,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      isLoading: isLoading ?? this.isLoading,
      transferProof: transferProof ?? this.transferProof,
    );
  }
}

final checkoutControllerProvider = StateNotifierProvider.family<CheckoutController, CheckoutState, String>((ref, jobId) {
  // Use the cached estimated cost from the intake flow for new (unassigned) jobs
  final intakeState = ref.read(customerIntakeProvider);
  return CheckoutController(Supabase.instance.client, jobId, intakeState.estimatedCost);
});

class CheckoutController extends StateNotifier<CheckoutState> {
  final SupabaseClient _supabase;
  RealtimeChannel? _paymentChannel;

  CheckoutController(this._supabase, String jobId, double fallbackEstimatedCost)
      : super(CheckoutState(jobId: jobId, estimatedCost: fallbackEstimatedCost)) {
    _loadInitialJobDetails(fallbackEstimatedCost);
  }

  @override
  void dispose() {
    _paymentChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadInitialJobDetails(double fallbackCost) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _supabase
          .from('repair_jobs')
          .select('initial_estimation_cost')
          .eq('id', state.jobId)
          .single();
          
      final cost = (response['initial_estimation_cost'] as num?)?.toDouble() ?? fallbackCost;
      state = state.copyWith(estimatedCost: cost, isLoading: false);
    } catch (e) {
      // If the job doesn't exist yet (e.g. dummy job id from Estimator), recover from SharedPreferences directly
      double recoveredCost = fallbackCost;
      if (recoveredCost == 0.0) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final data = prefs.getString('customer_intake');
          if (data != null) {
            final map = jsonDecode(data);
            recoveredCost = (map['estimatedCost'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (_) {}
      }

      state = state.copyWith(
        estimatedCost: recoveredCost,
        isLoading: false,
      );
    }
  }

  void setPaymentMethod(PaymentMethod method) {
    state = state.copyWith(paymentMethod: method, errorMessage: null);
  }

  void setTransferProof(XFile proof) {
    state = state.copyWith(transferProof: proof, errorMessage: null);
  }

  void setDeliveryOption(DeliveryOption option) {
    state = state.copyWith(deliveryOption: option, errorMessage: null);
  }

  void setPickupLocation(String address, double? lat, double? lng) {
    state = state.copyWith(pickupAddress: address, pickupLat: lat, pickupLng: lng, errorMessage: null);
  }

  Future<bool> checkAndSetScheduledDate(DateTime date, String partnerId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final dateString = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final int weekday = date.weekday; // 1 = Monday, 7 = Sunday
      
      if (partnerId != 'auto_assign' && partnerId.isNotEmpty) {
        // Specific Partner Check
        final partnerScheduleResp = await _supabase
            .from('partner_schedules')
            .select()
            .eq('partner_id', partnerId)
            .maybeSingle();
            
        if (partnerScheduleResp != null) {
          final List<dynamic> blacklisted = partnerScheduleResp['blacklisted_dates'] ?? [];
          final List<dynamic> standardDays = partnerScheduleResp['standard_working_days'] ?? [];
          final int capacity = partnerScheduleResp['guaranteed_slots_per_day'] ?? 5;
          
          if (blacklisted.contains(dateString)) {
            state = state.copyWith(isLoading: false, errorMessage: 'The selected workshop is closed on this date (Exception/Holiday).');
            return false;
          }
          if (!standardDays.contains(weekday)) {
            state = state.copyWith(isLoading: false, errorMessage: 'The selected workshop does not operate on this day of the week.');
            return false;
          }
          
          final countResponse = await _supabase
              .from('repair_jobs')
              .select('id')
              .eq('partner_id', partnerId)
              .gte('scheduled_date', '${dateString}T00:00:00Z')
              .lte('scheduled_date', '${dateString}T23:59:59Z')
              .count();
              
          if (countResponse.count >= capacity) {
            state = state.copyWith(isLoading: false, errorMessage: 'This workshop is fully booked for the selected date.');
            return false;
          }
        }
      } else {
        // Global Auto-Assign Check
        final allSchedules = await _supabase.from('partner_schedules').select();
        int totalAvailableCapacity = 0;
        
        for (final schedule in allSchedules) {
          final List<dynamic> blacklisted = schedule['blacklisted_dates'] ?? [];
          final List<dynamic> standardDays = schedule['standard_working_days'] ?? [];
          final int capacity = schedule['guaranteed_slots_per_day'] ?? 5;
          
          if (!blacklisted.contains(dateString) && standardDays.contains(weekday)) {
            totalAvailableCapacity += capacity;
          }
        }
        
        if (totalAvailableCapacity == 0) {
          state = state.copyWith(isLoading: false, errorMessage: 'No workshops are available on the selected date (Holiday/Weekend).');
          return false;
        }

        final countResponse = await _supabase
            .from('repair_jobs')
            .select('id')
            .gte('scheduled_date', '${dateString}T00:00:00Z')
            .lte('scheduled_date', '${dateString}T23:59:59Z')
            .count();
            
        if (countResponse.count >= totalAvailableCapacity) {
          state = state.copyWith(isLoading: false, errorMessage: 'All workshops in our network are fully booked for this date.');
          return false;
        }
      }

      state = state.copyWith(scheduledDate: date, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to verify schedule availability. Please try again later.'
      );
      return false;
    }
  }

  Future<void> executePaymentAndBooking() async {
    if (state.deliveryOption == DeliveryOption.pickup && state.pickupAddress == null) {
      state = state.copyWith(errorMessage: 'Please select a pickup location for Valet Pickup.');
      return;
    }
    if (state.scheduledDate == null) {
      state = state.copyWith(errorMessage: 'Please select a preferred date.');
      return;
    }
    if (state.paymentMethod == PaymentMethod.manualTransfer && state.transferProof == null) {
      state = state.copyWith(errorMessage: 'Please upload your transfer proof.');
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final deliveryTypeDbEnum = state.deliveryOption == DeliveryOption.selfDeliver ? 'self_deliver' : 'pickup';
      
      if (!state.jobId.startsWith('JB-')) {
        // Upload transfer proof if applicable
        if (state.paymentMethod == PaymentMethod.manualTransfer && state.transferProof != null) {
          final fileExt = state.transferProof!.name.split('.').last;
          final fileName = 'proof_${state.jobId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
          final bytes = await state.transferProof!.readAsBytes();
          
          await _supabase.storage.from('revive-photos').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$fileExt'),
          );

          await _supabase.from('repair_photos').insert({
            'job_id': state.jobId,
            'step_context': 'intake',
            'r2_file_key': fileName,
          });
        }

        await _supabase.from('repair_jobs').update({
          'status': '3_booked',
          'delivery_type': deliveryTypeDbEnum,
          'scheduled_date': state.scheduledDate!.toIso8601String(),
        }).eq('id', state.jobId);
      }

      if (state.paymentMethod == PaymentMethod.manualTransfer) {
        // Manual transfer branch: skip webhook wait and immediately mark as pending manual confirmation
        await Future.delayed(const Duration(milliseconds: 500)); // Brief simulated network delay
        state = state.copyWith(
          paymentStatus: PaymentStatus.manualTransferPending,
          isLoading: false,
        );
        return;
      }

      // 2. Prepare payment screen gateway (e.g., Simulated intent creation for Xendit/Midtrans Webhook prep)
      await Future.delayed(const Duration(seconds: 1)); // Wait for simulated payment gateway token binding

      state = state.copyWith(
        paymentStatus: PaymentStatus.awaitingWebhook,
        isLoading: false,
      );

      // 3. Register explicit client listener for server-to-server webhook confirmation
      _listenForPaymentWebhook();

    } catch (e, stackTrace) {
      print('PAYMENT_ERROR: $e');
      print('PAYMENT_STACKTRACE: $stackTrace');
      state = state.copyWith(
        isLoading: false,
        paymentStatus: PaymentStatus.failed,
        errorMessage: 'Transaction failed to process securely. We encountered a network error. Please try again.',
      );
    }
  }

  void _listenForPaymentWebhook() {
    if (state.jobId.startsWith('JB-')) {
      // UI Demo Mode: Simulate successful webhook payment after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        state = state.copyWith(paymentStatus: PaymentStatus.paid);
      });
      return;
    }

    _paymentChannel?.unsubscribe();
    
    // Subscribe to strict RLS-filtered changes for this exact job row
    _paymentChannel = _supabase.channel('public:repair_jobs:id=eq.${state.jobId}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'repair_jobs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, 
          column: 'id', 
          value: state.jobId
        ),
        callback: (payload) {
          final newRecord = payload.newRecord;
          if (newRecord['status'] == '4_paid') {
            state = state.copyWith(paymentStatus: PaymentStatus.paid);
            _paymentChannel?.unsubscribe();
          }
        },
      )
      .subscribe();
  }
}
