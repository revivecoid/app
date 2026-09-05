import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- DOMAIN MODELS ---

class AdminJobNode {
  final String id;
  final String customerName;
  final String carIdentity;
  final String status;
  final String partnerName;
  final DateTime? scheduledDate;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  final String? paymentProofUrl;

  AdminJobNode({
    required this.id,
    required this.customerName,
    required this.carIdentity,
    required this.status,
    required this.partnerName,
    this.scheduledDate,
    required this.createdAt,
    required this.lastUpdatedAt,
    this.paymentProofUrl,
  });

  AdminJobNode copyWith({String? status, DateTime? lastUpdatedAt, String? paymentProofUrl}) {
    return AdminJobNode(
      id: id,
      customerName: customerName,
      carIdentity: carIdentity,
      status: status ?? this.status,
      partnerName: partnerName,
      scheduledDate: scheduledDate,
      createdAt: createdAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      paymentProofUrl: paymentProofUrl ?? this.paymentProofUrl,
    );
  }

  String get timeElapsedCurrentStage {
    final diff = DateTime.now().difference(lastUpdatedAt);
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }
}

class CustomerCrmNode {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final double lifetimeValue;
  final int activeJobs;
  final String adminNotes;

  CustomerCrmNode({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.lifetimeValue,
    required this.activeJobs,
    required this.adminNotes,
  });
}

class PartnerApplicationNode {
  final String id;
  final String shopName;
  final String ownerName;
  final String email;
  final String phone;
  final String address;
  final String status;
  final DateTime createdAt;

  PartnerApplicationNode({
    required this.id,
    required this.shopName,
    required this.ownerName,
    required this.email,
    required this.phone,
    required this.address,
    required this.status,
    required this.createdAt,
  });
}

class PartnerCrmNode {
  final String id;
  final String shopName;
  final String tier;
  final bool isActive;
  final int activeVolume;
  final double avgVelocityDays;
  final int disputeCount;
  final int unreadMessageCount;

  PartnerCrmNode({
    required this.id,
    required this.shopName,
    required this.tier,
    required this.isActive,
    required this.activeVolume,
    required this.avgVelocityDays,
    required this.disputeCount,
    this.unreadMessageCount = 0,
  });
}

class AiConfigNode {
  final String id;
  final String modelName;
  final String provider;
  final bool isActive;
  final double tokenPriceParam;
  final int priorityOrder;
  final String apiBaseUrl;
  final String payloadFormat; // 'gemini' | 'openai' | 'groq'

  AiConfigNode({
    required this.id,
    required this.modelName,
    required this.provider,
    required this.isActive,
    required this.tokenPriceParam,
    required this.priorityOrder,
    required this.apiBaseUrl,
    required this.payloadFormat,
  });

  AiConfigNode copyWith({bool? isActive, double? tokenPriceParam}) {
    return AiConfigNode(
      id: id,
      modelName: modelName,
      provider: provider,
      isActive: isActive ?? this.isActive,
      tokenPriceParam: tokenPriceParam ?? this.tokenPriceParam,
      priorityOrder: priorityOrder,
      apiBaseUrl: apiBaseUrl,
      payloadFormat: payloadFormat,
    );
  }
}

class BreachAlert {
  final String jobId;
  final String customerName;
  final String reason;
  final DateTime detectedAt;

  BreachAlert({
    required this.jobId,
    required this.customerName,
    required this.reason,
    required this.detectedAt,
  });
}

// --- STATE MANAGEMENT ---

class AdminDashboardState {
  final int currentViewIndex;
  final List<AdminJobNode> activeJobs;
  final List<CustomerCrmNode> customers;
  final List<PartnerCrmNode> partners;
  final List<PartnerApplicationNode> pendingApplications;
  final List<AiConfigNode> aiConfigs;
  final List<BreachAlert> breaches;
  final List<String> toastQueue;
  final bool isLoading;
  final String? errorMessage;
  final String searchQuery;

  AdminDashboardState({
    this.currentViewIndex = 0,
    this.activeJobs = const [],
    this.customers = const [],
    this.partners = const [],
    this.pendingApplications = const [],
    this.aiConfigs = const [],
    this.breaches = const [],
    this.toastQueue = const [],
    this.isLoading = true,
    this.errorMessage,
    this.searchQuery = '',
  });

  AdminDashboardState copyWith({
    int? currentViewIndex,
    List<AdminJobNode>? activeJobs,
    List<CustomerCrmNode>? customers,
    List<PartnerCrmNode>? partners,
    List<PartnerApplicationNode>? pendingApplications,
    List<AiConfigNode>? aiConfigs,
    List<BreachAlert>? breaches,
    List<String>? toastQueue,
    bool? isLoading,
    String? errorMessage,
    String? searchQuery,
  }) {
    return AdminDashboardState(
      currentViewIndex: currentViewIndex ?? this.currentViewIndex,
      activeJobs: activeJobs ?? this.activeJobs,
      customers: customers ?? this.customers,
      partners: partners ?? this.partners,
      pendingApplications: pendingApplications ?? this.pendingApplications,
      aiConfigs: aiConfigs ?? this.aiConfigs,
      breaches: breaches ?? this.breaches,
      toastQueue: toastQueue ?? this.toastQueue,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

final adminDashboardProvider = StateNotifierProvider<AdminDashboardController, AdminDashboardState>((ref) {
  return AdminDashboardController(Supabase.instance.client);
});

class AdminDashboardController extends StateNotifier<AdminDashboardState> {
  final SupabaseClient _supabase;
  RealtimeChannel? _jobRealtimeSub;
  Timer? _pollingTimer;
  StreamSubscription? _messageSub;

  AdminDashboardController(this._supabase) : super(AdminDashboardState()) {
    _initializeDashboard();
  }

  @override
  void dispose() {
    _jobRealtimeSub?.unsubscribe();
    _messageSub?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeDashboard() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await Future.wait([
        _fetchActiveJobs(),
        _fetchCrmData(),
        _fetchAiConfigs(),
      ]);
      _subscribeToJobMutations();
      _startExceptionPolling();
      _subscribeToUnreadMessages();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to initialize master command center: $e');
    }
  }

  void _subscribeToUnreadMessages() {
    _messageSub = _supabase
        .from('partner_messages')
        .stream(primaryKey: ['id'])
        .listen((data) {
      final currentUserId = _supabase.auth.currentUser?.id;
      final Map<String, int> counts = {};
      
      for (final row in data) {
        if (row['sender_id'] != currentUserId && row['is_read'] == false) {
          final pId = row['partner_id'] as String;
          counts[pId] = (counts[pId] ?? 0) + 1;
        }
      }
      
      if (!mounted) return;
      
      final updatedPartners = state.partners.map((p) {
        final count = counts[p.id] ?? 0;
        return PartnerCrmNode(
          id: p.id,
          shopName: p.shopName,
          tier: p.tier,
          isActive: p.isActive,
          activeVolume: p.activeVolume,
          avgVelocityDays: p.avgVelocityDays,
          disputeCount: p.disputeCount,
          unreadMessageCount: count,
        );
      }).toList();
      
      state = state.copyWith(partners: updatedPartners);
    });
  }

  void changeView(int index) {
    state = state.copyWith(currentViewIndex: index);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  // --- VIEW A: MATRIX & REALTIME STREAM ---

  Future<void> _fetchActiveJobs() async {
    // Left Join profile, vehicle, and partner names natively
    final response = await _supabase.from('repair_jobs').select('''
      id, status, scheduled_date, created_at,
      profiles:customer_id (full_name),
      vehicles:vehicle_id (make, model, license_plate),
      partners:partner_id (shop_name),
      repair_photos (step_context, r2_file_key)
    ''').neq('status', '9_done'); // Only track active

    final cdnBucketPath = _supabase.storage.from('revive-photos').getPublicUrl('');

    final List<AdminJobNode> jobs = (response as List).map((job) {
      final customerData = job['profiles'] as Map<String, dynamic>? ?? {};
      final vehicleData = job['vehicles'] as Map<String, dynamic>? ?? {};
      final partnerData = job['partners'] as Map<String, dynamic>? ?? {};
      
      final photos = (job['repair_photos'] as List?) ?? [];
      String? proofUrl;
      for (final p in photos) {
        final key = p['r2_file_key']?.toString();
        if (key != null && key.startsWith('proof_')) {
          proofUrl = '$cdnBucketPath/$key';
          break;
        }
      }

      return AdminJobNode(
        id: job['id'].toString(),
        customerName: customerData['full_name']?.toString() ?? 'Unknown User',
        carIdentity: '${vehicleData['make'] ?? ''} ${vehicleData['model'] ?? ''} - ${vehicleData['license_plate'] ?? ''}',
        status: job['status'].toString(),
        partnerName: partnerData['shop_name']?.toString() ?? 'Unassigned',
        scheduledDate: job['scheduled_date'] != null ? DateTime.parse(job['scheduled_date'].toString()) : null,
        createdAt: DateTime.parse(job['created_at'].toString()),
        // If we had a state_changed_at col we'd use it, simulating via now if unknown
        lastUpdatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        paymentProofUrl: proofUrl,
      );
    }).toList();

    state = state.copyWith(activeJobs: jobs);
  }

  void _subscribeToJobMutations() {
    _jobRealtimeSub?.unsubscribe();
    _jobRealtimeSub = _supabase
        .channel('public:repair_jobs_admin')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'repair_jobs',
          callback: (payload) {
            final jobId = payload.newRecord['id'].toString();
            final newStatus = payload.newRecord['status'].toString();

            // 1. Update UI Matrix State
            final existingJobIndex = state.activeJobs.indexWhere((j) => j.id == jobId);
            if (existingJobIndex != -1) {
              final job = state.activeJobs[existingJobIndex];
              final updatedJobs = List<AdminJobNode>.from(state.activeJobs);
              updatedJobs[existingJobIndex] = job.copyWith(
                status: newStatus,
                lastUpdatedAt: DateTime.now(),
              );

              // 2. Evaluate Global Toast Exception rule for View C
              List<String> newToasts = List.from(state.toastQueue);
              if (newStatus == '7_finished') {
                newToasts.add('CRITICAL CHECKOUT: Job $jobId (${job.customerName}) has finished repairs. Needs validation.');
              } else if (newStatus == '8_awaiting_delivery') {
                newToasts.add('DISPATCH READY: Job $jobId is awaiting customer delivery protocol.');
              }

              state = state.copyWith(activeJobs: updatedJobs, toastQueue: newToasts);
            } else {
              // It's a new job entering active pipeline, re-fetch joins
              _fetchActiveJobs();
            }
          },
        ).subscribe();
  }

  Future<void> overrideJobStatus(String jobId, String newStatus) async {
    try {
      await _supabase.from('repair_jobs').update({'status': newStatus}).eq('id', jobId);
      // Realtime listener catches this and updates the UI Matrix automatically.
    } catch (e) {
      state = state.copyWith(errorMessage: 'Manual override failed: $e');
    }
  }

  void popToast() {
    if (state.toastQueue.isNotEmpty) {
      final updatedQueue = List<String>.from(state.toastQueue)..removeAt(0);
      state = state.copyWith(toastQueue: updatedQueue);
    }
  }

  // --- VIEW B: CRM PORTAL ---

  Future<void> _fetchCrmData() async {
    // 1. Fetch Profiles explicitly marked as customer
    final profilesRes = await _supabase.from('profiles').select().eq('role', 'customer');
    final List<CustomerCrmNode> loadedCustomers = (profilesRes as List).map((p) {
      return CustomerCrmNode(
        id: p['id'].toString(),
        fullName: p['full_name']?.toString() ?? 'Unregistered',
        email: p['email'].toString(),
        phone: p['phone']?.toString() ?? 'N/A',
        lifetimeValue: 0.0, // Aggregate logic omitted for speed, structurally typed
        activeJobs: 1,      // Computed property simulation
        adminNotes: 'Standard account.',
      );
    }).toList();

    // 2. Fetch Partner Health
    final partnersRes = await _supabase.from('partners').select();
    final List<PartnerCrmNode> loadedPartners = (partnersRes as List).map((p) {
      return PartnerCrmNode(
        id: p['id'].toString(),
        shopName: p['shop_name'].toString(),
        tier: p['tier']?.toString() ?? 'standard',
        isActive: p['is_active'] as bool? ?? true,
        activeVolume: state.activeJobs.where((j) => j.partnerName == p['shop_name'].toString()).length,
        avgVelocityDays: 4.2,
        disputeCount: 0,
      );
    }).toList();

    // 3. Fetch Pending Applications
    final appsRes = await _supabase.from('partner_applications').select().eq('status', 'pending');
    final List<PartnerApplicationNode> loadedApplications = (appsRes as List).map((a) {
      return PartnerApplicationNode(
        id: a['id'].toString(),
        shopName: a['shop_name'].toString(),
        ownerName: a['owner_name'].toString(),
        email: a['email'].toString(),
        phone: a['phone'].toString(),
        address: a['address'].toString(),
        status: a['status'].toString(),
        createdAt: DateTime.parse(a['created_at'].toString()),
      );
    }).toList();

    state = state.copyWith(customers: loadedCustomers, partners: loadedPartners, pendingApplications: loadedApplications);
  }

  Future<void> approvePartnerApplication(String applicationId) async {
    try {
      final res = await _supabase.functions.invoke(
        'approve-partner',
        body: {'applicationId': applicationId},
      );
      if (res.status == 200) {
        // Remove from pending list
        final updatedApps = state.pendingApplications.where((a) => a.id != applicationId).toList();
        state = state.copyWith(pendingApplications: updatedApps);
        // Refresh CRM data to see the new partner
        _fetchCrmData();
      } else {
        throw Exception(res.data['error'] ?? 'Unknown error');
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to approve application: $e');
    }
  }

  Future<void> declinePartnerApplication(String applicationId) async {
    try {
      await _supabase.from('partner_applications').update({'status': 'rejected'}).eq('id', applicationId);
      // Remove from pending list
      final updatedApps = state.pendingApplications.where((a) => a.id != applicationId).toList();
      state = state.copyWith(pendingApplications: updatedApps);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to decline application: $e');
    }
  }

  Future<void> togglePartnerStatus(String partnerId, bool isActive) async {
    try {
      await _supabase.from('partners').update({'is_active': isActive}).eq('id', partnerId);
      final index = state.partners.indexWhere((p) => p.id == partnerId);
      if (index != -1) {
        final updated = List<PartnerCrmNode>.from(state.partners);
        final old = updated[index];
        updated[index] = PartnerCrmNode(
          id: old.id,
          shopName: old.shopName,
          tier: old.tier,
          isActive: isActive,
          activeVolume: old.activeVolume,
          avgVelocityDays: old.avgVelocityDays,
          disputeCount: old.disputeCount,
          unreadMessageCount: old.unreadMessageCount,
        );
        state = state.copyWith(partners: updated);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to toggle partner capacity mode: $e');
    }
  }

  void removePartnerLocal(String partnerId) {
    final updated = state.partners.where((p) => p.id != partnerId).toList();
    state = state.copyWith(partners: updated);
  }

  // --- VIEW C: GLOBAL EXCEPTION & LATE SCHEDULE WARNING LOGIC ---

  void _startExceptionPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _evaluateLateBreaches();
    });
    _evaluateLateBreaches(); // Initial run
  }

  void _evaluateLateBreaches() {
    final now = DateTime.now();
    final List<BreachAlert> detectedBreaches = [];

    for (final job in state.activeJobs) {
      if (job.scheduledDate != null) {
        // Condition 1: Car not admitted 2 hours past scheduled time
        if (job.status == '3_booked' || job.status == '4_paid') {
          if (now.difference(job.scheduledDate!).inHours >= 2) {
            detectedBreaches.add(BreachAlert(
              jobId: job.id,
              customerName: job.customerName,
              reason: 'Missing Admission. Exceeds schedule by 2+ hours.',
              detectedAt: now,
            ));
          }
        }
      }
      
      // Condition 2: Stuck in progress for unusually long (simulated > 10 days)
      if (job.status == '6_in_progress') {
        if (now.difference(job.createdAt).inDays > 10) {
          detectedBreaches.add(BreachAlert(
            jobId: job.id,
            customerName: job.customerName,
            reason: 'Production Stalled. In progress for > 10 days.',
            detectedAt: now,
          ));
        }
      }
    }

    state = state.copyWith(breaches: detectedBreaches);
  }

  // --- VIEW D: AI ENGINE CONSOLE ---
  // ai_config is a multi-row model registry ordered by priority_order.
  // priority_order 1 = primary active engine, 2+ = ordered fallbacks.

  Future<void> _fetchAiConfigs() async {
    try {
      final res = await _supabase
          .from('ai_config')
          .select()
          .order('priority_order', ascending: true);

      final List<AiConfigNode> configs = (res as List).map((c) {
        // Pricing reference (admin display only — actual billing tracked server-side)
        final provider = c['provider']?.toString() ?? '';
        final modelName = c['model_name']?.toString() ?? '';
        
        double price = 0.0;
        if (modelName.toLowerCase().contains('free')) {
          price = 0.000;
        } else {
          price = switch (provider) {
            'OpenAI'        => 0.005,  // GPT-4o vision ~$0.005/image
            'Google Gemini' => 0.000,  // Gemini 3.5 Flash — free tier
            'Groq'          => 0.000,  // Groq llama vision — free tier
            _               => 0.000,
          };
        }

        return AiConfigNode(
          id: c['id'].toString(),
          modelName: c['model_name'].toString(),
          provider: c['provider'].toString(),
          isActive: c['is_active'] as bool? ?? false,
          tokenPriceParam: price,
          priorityOrder: c['priority_order'] as int? ?? 99,
          apiBaseUrl: c['api_base_url']?.toString() ?? '',
          payloadFormat: c['payload_format']?.toString() ?? 'openai',
        );
      }).toList();

      state = state.copyWith(aiConfigs: configs);
    } catch (e) {
      debugPrint('🚨 AI Config fetch error: $e');
      state = state.copyWith(errorMessage: 'Failed to load AI engine config: $e');
    }
  }

  Future<void> setActiveAiModel(String targetConfigId) async {
    // Per system design spec section 3: Only one model is active at a time.
    // Deactivate all → activate the selected UUID row.
    try {
      // Batch deactivate all models first (safe: no-op if already false)
      await _supabase
          .from('ai_config')
          .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
          .neq('id', targetConfigId);

      // Activate the selected model
      await _supabase
          .from('ai_config')
          .update({'is_active': true, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', targetConfigId);

      // Optimistic local state update (no re-fetch needed)
      final updatedConfigs = state.aiConfigs.map((c) {
        return c.copyWith(isActive: c.id == targetConfigId);
      }).toList();
      state = state.copyWith(aiConfigs: updatedConfigs);
    } catch (e) {
      debugPrint('🚨 AI hot-swap failure: $e');
      state = state.copyWith(errorMessage: 'Failed to hot-swap AI routing engine: $e');
    }
  }
}
