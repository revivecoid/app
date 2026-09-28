import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PartnerMessageNode {
  final String id;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final bool isAdmin;

  PartnerMessageNode({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.isAdmin,
  });
}

class AdminPartnerProfileState {
  final bool isLoading;
  final Map<String, dynamic>? partnerData;
  final Map<String, dynamic>? scheduleData;
  final List<Map<String, dynamic>> activeJobs;
  final List<Map<String, dynamic>> pastJobs;
  final List<PartnerMessageNode> messages;
  final List<String> facilityPhotoUrls;
  final int totalJobsDone;
  final double avgRepairDays;
  final String? errorMessage;
  final String? successMessage;

  AdminPartnerProfileState({
    this.isLoading = true,
    this.partnerData,
    this.scheduleData,
    this.activeJobs = const [],
    this.pastJobs = const [],
    this.messages = const [],
    this.facilityPhotoUrls = const [],
    this.totalJobsDone = 0,
    this.avgRepairDays = 0.0,
    this.errorMessage,
    this.successMessage,
  });

  AdminPartnerProfileState copyWith({
    bool? isLoading,
    Map<String, dynamic>? partnerData,
    Map<String, dynamic>? scheduleData,
    List<Map<String, dynamic>>? activeJobs,
    List<Map<String, dynamic>>? pastJobs,
    List<PartnerMessageNode>? messages,
    List<String>? facilityPhotoUrls,
    int? totalJobsDone,
    double? avgRepairDays,
    String? errorMessage,
    String? successMessage,
  }) {
    return AdminPartnerProfileState(
      isLoading: isLoading ?? this.isLoading,
      partnerData: partnerData ?? this.partnerData,
      scheduleData: scheduleData ?? this.scheduleData,
      activeJobs: activeJobs ?? this.activeJobs,
      pastJobs: pastJobs ?? this.pastJobs,
      messages: messages ?? this.messages,
      facilityPhotoUrls: facilityPhotoUrls ?? this.facilityPhotoUrls,
      totalJobsDone: totalJobsDone ?? this.totalJobsDone,
      avgRepairDays: avgRepairDays ?? this.avgRepairDays,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class AdminPartnerProfileController extends StateNotifier<AdminPartnerProfileState> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String partnerId;
  StreamSubscription? _messageSubscription;
  final String currentUserId;

  // REL-10 fix: safe currentUser access — empty string if session expired
  AdminPartnerProfileController(this.partnerId)
      : currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '',
        super(AdminPartnerProfileState()) {
    if (currentUserId.isEmpty) {
      // Session expired — don't init, let UI redirect to login
      state = AdminPartnerProfileState(isLoading: false, errorMessage: 'Session expired. Please log in again.');
      return;
    }
    _init();
  }

  Future<void> _init() async {
    try {
      // 1. Fetch Partner Data
      final pRes = await _supabase.from('partners').select().eq('id', partnerId).maybeSingle();
      if (pRes == null) {
        state = state.copyWith(isLoading: false, errorMessage: 'Partner not found.');
        return;
      }

      // 2. Fetch Schedule
      Map<String, dynamic>? schedData;
      try {
        schedData = await _supabase.from('partner_schedules').select().eq('partner_id', partnerId).single();
      } catch (e) { debugPrint('[AdminPartner] schedule fetch error: $e'); }

      // 3. Fetch Jobs
      final jobsRes = await _supabase.from('repair_jobs').select('''
        id, status, created_at, scheduled_date,
        vehicles:vehicle_id (make, model, license_plate),
        profiles:customer_id (full_name)
      ''').eq('partner_id', partnerId);

      final active = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];
      double totalDays = 0;

      for (final j in jobsRes as List) {
        final st = j['status'] as String;
        if (st == '9_done') {
          past.add(j as Map<String, dynamic>);
          final created = DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now();
          // Approximate velocity using scheduled_date if available, else now
          final scheduled = DateTime.tryParse(j['scheduled_date']?.toString() ?? '') ?? DateTime.now();
          totalDays += scheduled.difference(created).inHours / 24.0;
        } else {
          active.add(j as Map<String, dynamic>);
        }
      }

      final avgDays = past.isNotEmpty ? totalDays / past.length : 0.0;

      // 4. Fetch initial messages
      final msgRes = await _supabase
          .from('partner_messages')
          .select()
          .eq('partner_id', partnerId)
          .order('created_at', ascending: true);
      final initialMessages = (msgRes as List).map((e) => _parseMessage(e as Map<String, dynamic>)).toList();

      // 5. Fetch facility photos from storage
      final photoUrls = <String>[];
      try {
        // REL-04 FIX: Use unified 'revive-photos' bucket
        final objects = await _supabase.storage.from('revive-photos').list(path: 'facility/$partnerId/');
        for (final o in objects) {
          if (o.name.isNotEmpty) {
            // SEC-04: Bucket private — simpan file_key, UI akan request signed URL on-demand.
            // TODO: await signedPhotoUrl('facility/$partnerId/${o.name}')
            photoUrls.add('facility/$partnerId/${o.name}');
          }
        }
      } catch (e) { debugPrint('[AdminPartner] facility photos error: $e'); }

      state = state.copyWith(
        isLoading: false,
        partnerData: pRes,
        scheduleData: schedData,
        activeJobs: active,
        pastJobs: past,
        messages: initialMessages,
        facilityPhotoUrls: photoUrls,
        totalJobsDone: past.length,
        avgRepairDays: avgDays,
      );

      // 6. Subscribe to new messages (C-26 fix: no mark-read in stream — use explicit RPC)
      _messageSubscription = _supabase
          .from('partner_messages')
          .stream(primaryKey: ['id'])
          .eq('partner_id', partnerId)
          .order('created_at', ascending: false)
          .limit(50)
          .listen((data) {
            // Show newest-first from server, reverse for display
            final msgs = (data as List)
                .map((e) => _parseMessage(e as Map<String, dynamic>))
                .toList()
                .reversed
                .toList();
            state = state.copyWith(messages: msgs);
            // REL-07 fix: do NOT mark read inside stream listener
            // Call markMessagesRead() explicitly when chat screen is visible
          });
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  PartnerMessageNode _parseMessage(Map<String, dynamic> data) {
    // C-81 fix: toLocal() for correct timezone display
    final raw = data['created_at']?.toString() ?? '';
    final dt = DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    return PartnerMessageNode(
      id: data['id'],
      senderId: data['sender_id'],
      content: data['content'],
      createdAt: dt,
      // C-25 fix: use from_admin field set by DB trigger, not sender comparison
      isAdmin: data['from_admin'] == true,
    );
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    try {
      // C-25 fix: from_admin set by DB trigger — do NOT send it from client
      await _supabase.from('partner_messages').insert({
        'partner_id': partnerId,
        'sender_id': currentUserId,
        'content': text.trim(),
        // from_admin intentionally omitted — set by set_partner_message_from_admin trigger
      });
    } catch (e) {
      state = state.copyWith(errorMessage: 'Send failed: $e');
    }
  }

  /// C-26, REL-07 fix: call this when admin chat screen becomes visible.
  Future<void> markMessagesRead() async {
    try {
      await _supabase.rpc('mark_messages_read', params: {
        'p_partner_id': partnerId,
      });
    } catch (_) {}
  }

  Future<void> suspendPartner() async {
    try {
      // INT-04 FIX: Use RPC with audit trail instead of direct UPDATE
      await _supabase.rpc('admin_suspend_partner', params: {
        'p_partner_id': partnerId,
        'p_suspend': true,
      });
      final updated = Map<String, dynamic>.from(state.partnerData ?? {});
      updated['is_active'] = false;
      state = state.copyWith(partnerData: updated, successMessage: 'Partner suspended successfully.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to suspend partner.');
      debugPrint('[AdminPartner] suspendPartner error: $e');
    }
  }

  Future<void> reactivatePartner() async {
    try {
      // INT-04 FIX: Use RPC with audit trail instead of direct UPDATE
      await _supabase.rpc('admin_suspend_partner', params: {
        'p_partner_id': partnerId,
        'p_suspend': false,
      });
      final updated = Map<String, dynamic>.from(state.partnerData ?? {});
      updated['is_active'] = true;
      state = state.copyWith(partnerData: updated, successMessage: 'Partner reactivated successfully.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to reactivate partner.');
      debugPrint('[AdminPartner] reactivatePartner error: $e');
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}

final adminPartnerProfileProvider =
    StateNotifierProvider.autoDispose.family<AdminPartnerProfileController, AdminPartnerProfileState, String>(
  (ref, id) => AdminPartnerProfileController(id),
);
