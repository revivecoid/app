import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── DOMAIN MODELS ────────────────────────────────────────────────────────────

class AdminJobNode {
  final String id;
  final String customerName;
  final String carIdentity;
  final String status;
  final String partnerName;
  final String? partnerId;
  final DateTime? scheduledDate;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  final String? paymentProofUrl;
  final double? finalPrice;

  AdminJobNode({
    required this.id,
    required this.customerName,
    required this.carIdentity,
    required this.status,
    required this.partnerName,
    this.partnerId,
    this.scheduledDate,
    required this.createdAt,
    required this.lastUpdatedAt,
    this.paymentProofUrl,
    this.finalPrice,
  });

  AdminJobNode copyWith({
    String? status,
    String? partnerName,
    String? partnerId,
    DateTime? lastUpdatedAt,
    String? paymentProofUrl,
  }) {
    return AdminJobNode(
      id: id,
      customerName: customerName,
      carIdentity: carIdentity,
      status: status ?? this.status,
      partnerName: partnerName ?? this.partnerName,
      partnerId: partnerId ?? this.partnerId,
      scheduledDate: scheduledDate,
      createdAt: createdAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      paymentProofUrl: paymentProofUrl ?? this.paymentProofUrl,
      finalPrice: finalPrice,
    );
  }

  String get timeElapsedCurrentStage {
    final diff = DateTime.now().difference(lastUpdatedAt);
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  bool get isPaid => status == 'completed' || status == '4_paid' || status == '5_scheduled';
  bool get isUnassigned => partnerId == null || partnerId!.isEmpty;
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
  final String? serviceArea;
  final int? bayCapacity;

  PartnerCrmNode({
    required this.id,
    required this.shopName,
    required this.tier,
    required this.isActive,
    required this.activeVolume,
    required this.avgVelocityDays,
    required this.disputeCount,
    this.unreadMessageCount = 0,
    this.serviceArea,
    this.bayCapacity,
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
  final String payloadFormat;

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

// ─── SORT / FILTER ────────────────────────────────────────────────────────────

enum AssignSortField { createdAt, customerName, vehicle, assignStatus, paymentStatus }
enum AssignStatusFilter { all, unassigned, assigned, inProgress }
enum PaymentStatusFilter { all, pending, paid, overdue }

// ─── STATE ────────────────────────────────────────────────────────────────────

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
  final String? successMessage;
  final String searchQuery;

  // Live admin identity
  final String adminName;
  final String adminRole;
  final String adminLevel; // 'sysadmin' | 'admin' — future: from profiles.admin_level
  final String activeHubName;

  // Daily settlement
  final double dailySettlementAmount;
  final bool settlementLoading;

  // Assign jobs sort/filter
  final AssignSortField assignSortField;
  final bool assignSortAsc;
  final AssignStatusFilter assignStatusFilter;
  final PaymentStatusFilter assignPaymentFilter;
  final DateTime? assignDateFrom;
  final DateTime? assignDateTo;

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
    this.successMessage,
    this.searchQuery = '',
    this.adminName = 'Loading...',
    this.adminRole = '',
    this.adminLevel = 'admin',
    this.activeHubName = '—',
    this.dailySettlementAmount = 0,
    this.settlementLoading = true,
    this.assignSortField = AssignSortField.createdAt,
    this.assignSortAsc = true,
    this.assignStatusFilter = AssignStatusFilter.all,
    this.assignPaymentFilter = PaymentStatusFilter.all,
    this.assignDateFrom,
    this.assignDateTo,
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
    String? successMessage,
    String? searchQuery,
    String? adminName,
    String? adminRole,
    String? adminLevel,
    String? activeHubName,
    double? dailySettlementAmount,
    bool? settlementLoading,
    AssignSortField? assignSortField,
    bool? assignSortAsc,
    AssignStatusFilter? assignStatusFilter,
    PaymentStatusFilter? assignPaymentFilter,
    DateTime? assignDateFrom,
    DateTime? assignDateTo,
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
      successMessage: successMessage ?? this.successMessage,
      searchQuery: searchQuery ?? this.searchQuery,
      adminName: adminName ?? this.adminName,
      adminRole: adminRole ?? this.adminRole,
      adminLevel: adminLevel ?? this.adminLevel,
      activeHubName: activeHubName ?? this.activeHubName,
      dailySettlementAmount: dailySettlementAmount ?? this.dailySettlementAmount,
      settlementLoading: settlementLoading ?? this.settlementLoading,
      assignSortField: assignSortField ?? this.assignSortField,
      assignSortAsc: assignSortAsc ?? this.assignSortAsc,
      assignStatusFilter: assignStatusFilter ?? this.assignStatusFilter,
      assignPaymentFilter: assignPaymentFilter ?? this.assignPaymentFilter,
      assignDateFrom: assignDateFrom ?? this.assignDateFrom,
      assignDateTo: assignDateTo ?? this.assignDateTo,
    );
  }

  // ── Derived: filtered + sorted assign jobs list ──────────────────────────────
  List<AdminJobNode> get assignJobsFiltered {
    var jobs = List<AdminJobNode>.from(activeJobs);

    // Status filter
    switch (assignStatusFilter) {
      case AssignStatusFilter.unassigned:
        jobs = jobs.where((j) => j.isUnassigned).toList();
      case AssignStatusFilter.assigned:
        jobs = jobs.where((j) => !j.isUnassigned && j.status == '3_booked').toList();
      case AssignStatusFilter.inProgress:
        jobs = jobs.where((j) => j.status == '6_in_progress').toList();
      case AssignStatusFilter.all:
        break;
    }

    // Payment filter
    switch (assignPaymentFilter) {
      case PaymentStatusFilter.paid:
        jobs = jobs.where((j) => j.isPaid).toList();
      case PaymentStatusFilter.pending:
        jobs = jobs.where((j) => !j.isPaid && j.status != 'overdue').toList();
      case PaymentStatusFilter.overdue:
        jobs = jobs.where((j) => j.status == 'overdue').toList();
      case PaymentStatusFilter.all:
        break;
    }

    // Date filter
    if (assignDateFrom != null) {
      jobs = jobs.where((j) => j.createdAt.isAfter(assignDateFrom!)).toList();
    }
    if (assignDateTo != null) {
      final to = assignDateTo!.add(const Duration(days: 1));
      jobs = jobs.where((j) => j.createdAt.isBefore(to)).toList();
    }

    // Search
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      jobs = jobs.where((j) =>
        j.customerName.toLowerCase().contains(q) ||
        j.carIdentity.toLowerCase().contains(q) ||
        j.id.toLowerCase().contains(q) ||
        j.partnerName.toLowerCase().contains(q)
      ).toList();
    }

    // Sort
    jobs.sort((a, b) {
      int cmp;
      switch (assignSortField) {
        case AssignSortField.customerName:
          cmp = a.customerName.compareTo(b.customerName);
        case AssignSortField.vehicle:
          cmp = a.carIdentity.compareTo(b.carIdentity);
        case AssignSortField.assignStatus:
          cmp = a.status.compareTo(b.status);
        case AssignSortField.paymentStatus:
          cmp = (a.isPaid ? 1 : 0).compareTo(b.isPaid ? 1 : 0);
        case AssignSortField.createdAt:
          cmp = a.createdAt.compareTo(b.createdAt);
      }
      return assignSortAsc ? cmp : -cmp;
    });

    return jobs;
  }
}

// ─── PROVIDER ─────────────────────────────────────────────────────────────────

final adminDashboardProvider =
    StateNotifierProvider<AdminDashboardController, AdminDashboardState>((ref) {
  return AdminDashboardController(Supabase.instance.client);
});

// ─── CONTROLLER ───────────────────────────────────────────────────────────────

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
        _fetchAdminProfile(),
        _fetchActiveJobs(),
        _fetchCrmData(),
        _fetchAiConfigs(),
        _fetchDailySettlement(),
      ]);
      _subscribeToJobMutations();
      _startExceptionPolling();
      _subscribeToUnreadMessages();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to initialize master command center: $e',
      );
    }
  }

  // ── Admin profile ─────────────────────────────────────────────────────────

  Future<void> _fetchAdminProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Use SECURITY DEFINER RPC to bypass any RLS issues on profiles
      final res = await _supabase.rpc('get_admin_profile');

      final Map<String, dynamic> data =
          res is Map<String, dynamic> ? res : {};

      String fullName;
      if (data['full_name'] != null &&
          (data['full_name'] as String).trim().isNotEmpty) {
        fullName = data['full_name'].toString().trim();
      } else {
        final email = data['email']?.toString() ?? user.email ?? 'Admin';
        fullName = email.contains('@') ? email.split('@').first : email;
      }

      final adminLevel = data['admin_level']?.toString() ?? 'admin';
      final role = data['role']?.toString() ?? 'master_admin';

      // Fetch first active partner as the active hub display
      String hubName = '—';
      final firstPartner = await _supabase
          .from('partners')
          .select('shop_name')
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();
      hubName = firstPartner?['shop_name']?.toString() ?? '—';

      debugPrint('Admin profile: name=$fullName level=$adminLevel');

      if (!mounted) return;
      state = state.copyWith(
        adminName: fullName,
        adminRole: role,
        adminLevel: adminLevel,
        activeHubName: hubName,
      );
    } catch (e) {
      debugPrint('Admin profile fetch error: $e');
      final user = _supabase.auth.currentUser;
      if (user != null && mounted) {
        final email = user.email ?? 'Admin';
        final name = email.contains('@') ? email.split('@').first : email;
        state = state.copyWith(adminName: name);
      }
    }
  }

  // ── Daily settlement ──────────────────────────────────────────────────────

  Future<void> _fetchDailySettlement() async {
    try {
      state = state.copyWith(settlementLoading: true);
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final res = await _supabase
          .from('repair_jobs')
          .select('final_cost')
          .eq('status', 'completed')
          .gte('created_at', '${todayStr}T00:00:00')
          .lte('created_at', '${todayStr}T23:59:59');

      double total = 0;
      for (final row in (res as List)) {
        final price = row['final_cost'];
        if (price != null) {
          total += (price as num).toDouble();
        }
      }

      if (!mounted) return;
      state = state.copyWith(
        dailySettlementAmount: total,
        settlementLoading: false,
      );
    } catch (e) {
      debugPrint('Settlement fetch error: $e');
      state = state.copyWith(settlementLoading: false);
    }
  }

  // ── Jobs ──────────────────────────────────────────────────────────────────

  void _subscribeToUnreadMessages() {
    _messageSub = _supabase
        .from('partner_messages')
        .stream(primaryKey: ['id']).listen((data) {
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
          serviceArea: p.serviceArea,
          bayCapacity: p.bayCapacity,
        );
      }).toList();
      state = state.copyWith(partners: updatedPartners);
    });
  }

  void changeView(int index) => state = state.copyWith(currentViewIndex: index);

  void setSearchQuery(String query) => state = state.copyWith(searchQuery: query);

  Future<void> _fetchActiveJobs() async {
    try {
      // Use SECURITY DEFINER RPC to bypass RLS on repair_jobs
      final response = await _supabase.rpc('get_admin_active_jobs');

      final List<dynamic> rows = response is List
          ? response
          : (response == null ? [] : [response]);

      debugPrint('Admin jobs via RPC: ${rows.length} rows');

      final cdnBucketPath =
          _supabase.storage.from('revive-photos').getPublicUrl('');

      final List<AdminJobNode> jobs = rows.map((job) {
        final j = job as Map<String, dynamic>;
        return AdminJobNode(
          id: j['id'].toString(),
          customerName: j['customer_name']?.toString() ?? 'Unknown',
          carIdentity:
              '${j['make'] ?? ''} ${j['model'] ?? ''} - ${j['license_plate'] ?? ''}',
          status: j['status']?.toString() ?? 'unknown',
          partnerName: j['partner_name']?.toString() ?? 'Unassigned',
          partnerId: j['partner_id']?.toString(),
          scheduledDate: j['scheduled_date'] != null
              ? DateTime.tryParse(j['scheduled_date'].toString())
              : null,
          createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
              DateTime.now(),
          lastUpdatedAt: DateTime.now(),
          paymentProofUrl: null,
          finalPrice: null, // column doesn't exist in repair_jobs
        );
      }).toList();

      if (!mounted) return;
      state = state.copyWith(activeJobs: jobs);
    } catch (e) {
      debugPrint('⚠️ _fetchActiveJobs RPC error: $e');
      // Fallback: try direct query without filter
      try {
        final response = await _supabase.from('repair_jobs').select('''
          id, status, scheduled_date, created_at, partner_id, final_price,
          profiles:customer_id (full_name),
          vehicles:vehicle_id (make, model, license_plate),
          partners:partner_id (shop_name)
        ''').limit(50);
        final cdnBucketPath =
            _supabase.storage.from('revive-photos').getPublicUrl('');
        final List<AdminJobNode> jobs = (response as List).map((job) {
          final customerData = job['profiles'] as Map<String, dynamic>? ?? {};
          final vehicleData = job['vehicles'] as Map<String, dynamic>? ?? {};
          final partnerData = job['partners'] as Map<String, dynamic>? ?? {};
          return AdminJobNode(
            id: job['id'].toString(),
            customerName: customerData['full_name']?.toString() ?? 'Unknown',
            carIdentity:
                '${vehicleData['make'] ?? ''} ${vehicleData['model'] ?? ''} - ${vehicleData['license_plate'] ?? ''}',
            status: job['status'].toString(),
            partnerName: partnerData['shop_name']?.toString() ?? 'Unassigned',
            partnerId: job['partner_id']?.toString(),
            scheduledDate: job['scheduled_date'] != null
                ? DateTime.parse(job['scheduled_date'].toString())
                : null,
            createdAt: DateTime.parse(job['created_at'].toString()),
            lastUpdatedAt: DateTime.now(),
            paymentProofUrl: null,
            finalPrice: job['final_cost'] != null
                ? (job['final_cost'] as num).toDouble()
                : null,
          );
        }).toList();
        if (!mounted) return;
        state = state.copyWith(activeJobs: jobs);
      } catch (e2) {
        debugPrint('⚠️ Fallback job fetch error: $e2');
      }
    }
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
            final existingJobIndex =
                state.activeJobs.indexWhere((j) => j.id == jobId);
            if (existingJobIndex != -1) {
              final job = state.activeJobs[existingJobIndex];
              final updatedJobs =
                  List<AdminJobNode>.from(state.activeJobs);
              updatedJobs[existingJobIndex] = job.copyWith(
                status: newStatus,
                lastUpdatedAt: DateTime.now(),
              );
              List<String> newToasts = List.from(state.toastQueue);
              if (newStatus == '7_finished') {
                newToasts.add(
                    'CRITICAL CHECKOUT: Job $jobId (${job.customerName}) finished. Needs validation.');
              } else if (newStatus == '8_awaiting_delivery') {
                newToasts.add(
                    'DISPATCH READY: Job $jobId awaiting delivery protocol.');
              }
              state = state.copyWith(
                  activeJobs: updatedJobs, toastQueue: newToasts);
            } else {
              _fetchActiveJobs();
            }
          },
        ).subscribe();
  }

  Future<void> overrideJobStatus(String jobId, String newStatus) async {
    try {
      await _supabase
          .from('repair_jobs')
          .update({'status': newStatus}).eq('id', jobId);
    } catch (e) {
      state =
          state.copyWith(errorMessage: 'Manual override failed: $e');
    }
  }

  void popToast() {
    if (state.toastQueue.isNotEmpty) {
      final updatedQueue =
          List<String>.from(state.toastQueue)..removeAt(0);
      state = state.copyWith(toastQueue: updatedQueue);
    }
  }

  // ── Assign Jobs ───────────────────────────────────────────────────────────

  Future<void> assignJobToPartner(
      String jobId, String partnerId, String partnerName) async {
    try {
      // Primary: use SECURITY DEFINER RPC that bypasses the pg_net webhook trigger
      await _supabase.rpc('admin_assign_job', params: {
        'p_job_id': jobId,
        'p_partner_id': partnerId,
        'p_status': '3_booked',
      });
    } on PostgrestException catch (rpcErr) {
      // Fallback: RPC not deployed yet — direct update (will hit trigger)
      debugPrint('⚠️ admin_assign_job RPC not found, using direct update: ${rpcErr.code}');
      try {
        await _supabase.from('repair_jobs').update({
          'partner_id': partnerId,
          'status': '3_booked',
        }).eq('id', jobId);
      } catch (directErr) {
        debugPrint('❌ direct assign error: $directErr');
        state = state.copyWith(
            errorMessage: 'Assignment failed: $directErr\n\n'
                'Apply the migration in supabase/migrations/20260909_fix_notification_trigger_and_admin_rpcs.sql');
        return;
      }
    } catch (e) {
      debugPrint('❌ assignJobToPartner error: $e');
      state = state.copyWith(errorMessage: 'Assignment failed: $e');
      return;
    }

    final idx = state.activeJobs.indexWhere((j) => j.id == jobId);
    if (idx != -1) {
      final updated = List<AdminJobNode>.from(state.activeJobs);
      updated[idx] = state.activeJobs[idx].copyWith(
        status: '3_booked',
        partnerName: partnerName,
        partnerId: partnerId,
        lastUpdatedAt: DateTime.now(),
      );
      state = state.copyWith(
        activeJobs: updated,
        successMessage: 'Job assigned to $partnerName',
      );
    }
    debugPrint('✅ Job $jobId assigned to $partnerName');
  }

  Future<void> unassignJob(String jobId) async {
    try {
      await _supabase.rpc('admin_unassign_job', params: {
        'p_job_id': jobId,
      });
    } on PostgrestException catch (rpcErr) {
      debugPrint('⚠️ admin_unassign_job RPC not found, using direct update: ${rpcErr.code}');
      try {
        await _supabase.from('repair_jobs').update({
          'partner_id': null,
          'status': '2_estimated',
        }).eq('id', jobId);
      } catch (directErr) {
        debugPrint('❌ direct unassign error: $directErr');
        state = state.copyWith(errorMessage: 'Unassign failed: $directErr');
        return;
      }
    } catch (e) {
      debugPrint('❌ unassignJob error: $e');
      state = state.copyWith(errorMessage: 'Unassign failed: $e');
      return;
    }

    final idx = state.activeJobs.indexWhere((j) => j.id == jobId);
    if (idx != -1) {
      final updated = List<AdminJobNode>.from(state.activeJobs);
      updated[idx] = state.activeJobs[idx].copyWith(
        status: '2_estimated',
        partnerName: 'Unassigned',
        partnerId: '',
        lastUpdatedAt: DateTime.now(),
      );
      state = state.copyWith(
        activeJobs: updated,
        successMessage: 'Job unassigned',
      );
    }
    debugPrint('✅ Job $jobId unassigned');
  }

  // ── Assign sort / filter ──────────────────────────────────────────────────

  void setAssignSort(AssignSortField field) {
    if (state.assignSortField == field) {
      state = state.copyWith(assignSortAsc: !state.assignSortAsc);
    } else {
      state =
          state.copyWith(assignSortField: field, assignSortAsc: true);
    }
  }

  void setAssignStatusFilter(AssignStatusFilter f) =>
      state = state.copyWith(assignStatusFilter: f);

  void setAssignPaymentFilter(PaymentStatusFilter f) =>
      state = state.copyWith(assignPaymentFilter: f);

  void setAssignDateRange(DateTime? from, DateTime? to) =>
      state = state.copyWith(assignDateFrom: from, assignDateTo: to);

  // ── CRM ───────────────────────────────────────────────────────────────────

  Future<void> _fetchCrmData() async {
    final profilesRes = await _supabase
        .from('profiles')
        .select()
        .eq('role', 'customer');
    final List<CustomerCrmNode> loadedCustomers =
        (profilesRes as List).map((p) {
      return CustomerCrmNode(
        id: p['id'].toString(),
        fullName: p['full_name']?.toString() ?? 'Unregistered',
        email: p['email'].toString(),
        phone: p['phone']?.toString() ?? 'N/A',
        lifetimeValue: 0.0,
        activeJobs: 1,
        adminNotes: 'Standard account.',
      );
    }).toList();

    final partnersRes =
        await _supabase.from('partners').select();
    final List<PartnerCrmNode> loadedPartners =
        (partnersRes as List).map((p) {
      return PartnerCrmNode(
        id: p['id'].toString(),
        shopName: p['shop_name'].toString(),
        tier: p['tier']?.toString() ?? 'standard',
        isActive: p['is_active'] as bool? ?? true,
        activeVolume: state.activeJobs
            .where((j) =>
                j.partnerName == p['shop_name'].toString())
            .length,
        avgVelocityDays: 4.2,
        disputeCount: 0,
        serviceArea: p['service_area']?.toString(),
        bayCapacity: p['bay_capacity'] as int?,
      );
    }).toList();

    final appsRes = await _supabase
        .from('partner_applications')
        .select()
        .eq('status', 'pending');
    final List<PartnerApplicationNode> loadedApplications =
        (appsRes as List).map((a) {
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

    state = state.copyWith(
      customers: loadedCustomers,
      partners: loadedPartners,
      pendingApplications: loadedApplications,
    );
  }

  Future<void> approvePartnerApplication(String applicationId) async {
    try {
      final res = await _supabase.functions
          .invoke('approve-partner', body: {'applicationId': applicationId});
      if (res.status == 200) {
        final updatedApps = state.pendingApplications
            .where((a) => a.id != applicationId)
            .toList();
        state = state.copyWith(pendingApplications: updatedApps);
        _fetchCrmData();
      } else {
        throw Exception(res.data['error'] ?? 'Unknown error');
      }
    } catch (e) {
      state = state.copyWith(
          errorMessage: 'Failed to approve application: $e');
    }
  }

  Future<void> declinePartnerApplication(String applicationId) async {
    try {
      await _supabase
          .from('partner_applications')
          .update({'status': 'rejected'}).eq('id', applicationId);
      final updatedApps = state.pendingApplications
          .where((a) => a.id != applicationId)
          .toList();
      state = state.copyWith(pendingApplications: updatedApps);
    } catch (e) {
      state = state.copyWith(
          errorMessage: 'Failed to decline application: $e');
    }
  }

  Future<void> togglePartnerStatus(
      String partnerId, bool isActive) async {
    try {
      await _supabase
          .from('partners')
          .update({'is_active': isActive}).eq('id', partnerId);
      final index =
          state.partners.indexWhere((p) => p.id == partnerId);
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
          serviceArea: old.serviceArea,
          bayCapacity: old.bayCapacity,
        );
        state = state.copyWith(partners: updated);
      }
    } catch (e) {
      state = state.copyWith(
          errorMessage: 'Failed to toggle partner status: $e');
    }
  }

  void removePartnerLocal(String partnerId) {
    final updated =
        state.partners.where((p) => p.id != partnerId).toList();
    state = state.copyWith(partners: updated);
  }

  // ── Exception Polling ─────────────────────────────────────────────────────

  void _startExceptionPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _evaluateLateBreaches();
    });
    _evaluateLateBreaches();
  }

  void _evaluateLateBreaches() {
    final now = DateTime.now();
    final List<BreachAlert> detectedBreaches = [];
    for (final job in state.activeJobs) {
      if (job.scheduledDate != null) {
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

  // ── AI Engine ─────────────────────────────────────────────────────────────

  Future<void> _fetchAiConfigs() async {
    try {
      final res = await _supabase
          .from('ai_config')
          .select()
          .order('priority_order', ascending: true);

      final List<AiConfigNode> configs = (res as List).map((c) {
        final provider = c['provider']?.toString() ?? '';
        double price = switch (provider) {
          'OpenAI' => 0.005,
          _ => 0.000,
        };

        return AiConfigNode(
          id: c['id'].toString(),
          modelName: c['model_name'].toString(),
          provider: provider,
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
    }
  }

  Future<void> setActiveAiModel(String targetConfigId) async {
    try {
      await _supabase
          .from('ai_config')
          .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
          .neq('id', targetConfigId);
      await _supabase
          .from('ai_config')
          .update({'is_active': true, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', targetConfigId);
      final updatedConfigs = state.aiConfigs.map((c) {
        return c.copyWith(isActive: c.id == targetConfigId);
      }).toList();
      state = state.copyWith(aiConfigs: updatedConfigs);
    } catch (e) {
      debugPrint('🚨 AI hot-swap failure: $e');
      state = state.copyWith(errorMessage: 'Failed to hot-swap AI engine: $e');
    }
  }
}
