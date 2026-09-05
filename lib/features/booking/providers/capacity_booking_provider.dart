import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/scheduling_engine.dart';

class CapacityBookingState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;

  CapacityBookingState({this.isLoading = false, this.error, this.isSuccess = false});
}

class CapacityBookingNotifier extends StateNotifier<CapacityBookingState> {
  final SupabaseClient _supabase;

  CapacityBookingNotifier(this._supabase) : super(CapacityBookingState());

  /// Commits a multi-day capacity booking sequence to the database.
  Future<void> commitTransactionSequence({
    required String jobId,
    required String partnerId,
    required DateTime startDate,
    required int requiredDays,
    required List<int> standardWorkingDays,
    required List<DateTime> combinedHolidays,
  }) async {
    state = CapacityBookingState(isLoading: true);
    try {
      // 1. Calculate the exact sequence of valid working days spanning the required duration
      final sequence = SchedulingEngine.calculateWorkingDaysSequence(
        startDate: startDate,
        requiredDays: requiredDays,
        standardWorkingDays: standardWorkingDays,
        allHolidays: combinedHolidays,
      );

      // 2. Build the payload for batch insert representing each discrete active day
      final List<Map<String, dynamic>> payload = sequence.map((date) => {
        'job_id': jobId,
        'partner_id': partnerId,
        'allocated_date': date.toIso8601String().split('T')[0],
      }).toList();

      // 3. Execute batch insert to 'partner_slot_allocations' as a single transaction batch query
      await _supabase.from('partner_slot_allocations').insert(payload);

      state = CapacityBookingState(isSuccess: true);
    } catch (e) {
      state = CapacityBookingState(error: e.toString());
    }
  }
}

final capacityBookingProvider = StateNotifierProvider<CapacityBookingNotifier, CapacityBookingState>((ref) {
  return CapacityBookingNotifier(Supabase.instance.client);
});
