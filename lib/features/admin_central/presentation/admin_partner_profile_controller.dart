import 'dart:async';
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

  AdminPartnerProfileController(this.partnerId)
      : currentUserId = Supabase.instance.client.auth.currentUser!.id,
        super(AdminPartnerProfileState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      // 1. Fetch Partner Data
      final pRes = await _supabase.from('partners').select().eq('id', partnerId).single();

      // 2. Fetch Schedule
      Map<String, dynamic>? schedData;
      try {
        schedData = await _supabase.from('partner_schedules').select().eq('partner_id', partnerId).single();
      } catch (_) {}

      // 3. Fetch Jobs
      final jobsRes = await _supabase.from('repair_jobs').select('''
        id, status, created_at, updated_at,
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
          final updated = DateTime.tryParse(j['updated_at']?.toString() ?? '') ?? DateTime.now();
          totalDays += updated.difference(created).inHours / 24.0;
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
        final objects = await _supabase.storage.from('revive-photos-r2-proxy').list(path: 'facility/$partnerId/');
        for (final o in objects) {
          if (o.name.isNotEmpty) {
            photoUrls.add(_supabase.storage.from('revive-photos-r2-proxy').getPublicUrl('facility/$partnerId/${o.name}'));
          }
        }
      } catch (_) {}

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

      // 6. Subscribe to new messages
      _messageSubscription = _supabase
          .from('partner_messages')
          .stream(primaryKey: ['id'])
          .eq('partner_id', partnerId)
          .order('created_at', ascending: true)
          .listen((data) {
            final msgs = (data as List).map((e) => _parseMessage(e as Map<String, dynamic>)).toList();
            state = state.copyWith(messages: msgs);
            final unread = data.where((e) => e['is_read'] == false && e['sender_id'] != currentUserId).toList();
            if (unread.isNotEmpty) {
              _supabase.from('partner_messages')
                  .update({'is_read': true})
                  .eq('partner_id', partnerId)
                  .neq('sender_id', currentUserId)
                  .eq('is_read', false)
                  .then((_) {});
            }
          });
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  PartnerMessageNode _parseMessage(Map<String, dynamic> data) {
    return PartnerMessageNode(
      id: data['id'],
      senderId: data['sender_id'],
      content: data['content'],
      createdAt: DateTime.parse(data['created_at']),
      isAdmin: data['sender_id'] == currentUserId,
    );
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _supabase.from('partner_messages').insert({
        'partner_id': partnerId,
        'sender_id': currentUserId,
        'content': text.trim(),
      });
    } catch (_) {}
  }

  Future<void> suspendPartner() async {
    try {
      await _supabase.from('partners').update({'is_active': false}).eq('id', partnerId);
      final updated = Map<String, dynamic>.from(state.partnerData ?? {});
      updated['is_active'] = false;
      state = state.copyWith(partnerData: updated, successMessage: 'Partner suspended successfully.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to suspend partner: $e');
    }
  }

  Future<void> reactivatePartner() async {
    try {
      await _supabase.from('partners').update({'is_active': true}).eq('id', partnerId);
      final updated = Map<String, dynamic>.from(state.partnerData ?? {});
      updated['is_active'] = true;
      state = state.copyWith(partnerData: updated, successMessage: 'Partner reactivated successfully.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to reactivate partner: $e');
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}

final adminPartnerProfileProvider =
    StateNotifierProvider.family<AdminPartnerProfileController, AdminPartnerProfileState, String>(
  (ref, id) => AdminPartnerProfileController(id),
);
