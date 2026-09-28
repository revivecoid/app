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

class PartnerSettingsState {
  final bool isLoading;
  final Map<String, dynamic>? scheduleData;
  final List<PartnerMessageNode> messages;
  final String? errorMessage;
  final bool isSaving;

  PartnerSettingsState({
    this.isLoading = true,
    this.scheduleData,
    this.messages = const [],
    this.errorMessage,
    this.isSaving = false,
  });

  PartnerSettingsState copyWith({
    bool? isLoading,
    Map<String, dynamic>? scheduleData,
    List<PartnerMessageNode>? messages,
    String? errorMessage,
    bool? isSaving,
  }) {
    return PartnerSettingsState(
      isLoading: isLoading ?? this.isLoading,
      scheduleData: scheduleData ?? this.scheduleData,
      messages: messages ?? this.messages,
      errorMessage: errorMessage,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

class PartnerSettingsController extends StateNotifier<PartnerSettingsState> {
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription? _messageSubscription;
  late final String currentUserId;
  late final String partnerId;

  PartnerSettingsController() : super(PartnerSettingsState()) {
    _init();
  }

  Future<void> _init() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    
    currentUserId = user.id;
    // SEC-08 FIX: Read partner_id from app_metadata ONLY (set by service_role)
    partnerId = user.appMetadata['partner_id']?.toString() ?? '';
    
    if (partnerId.isEmpty) {
      state = state.copyWith(isLoading: false, errorMessage: 'Partner ID not found in token.');
      return;
    }

    try {
      // Fetch schedule data
      final sRes = await _supabase
          .from('partner_schedules')
          .select()
          .eq('partner_id', partnerId)
          .maybeSingle();

      if (sRes != null) {
        state = state.copyWith(scheduleData: sRes);
      } else {
        // Create default schedule if none exists
        final defaultSchedule = {
          'partner_id': partnerId,
          'standard_working_days': [1, 2, 3, 4, 5, 6],
          'simultaneous_panel_capacity': 1,
          'guaranteed_slots_per_day': 2,
        };
        final newRes = await _supabase
            .from('partner_schedules')
            .insert(defaultSchedule)
            .select()
            .single();
        state = state.copyWith(scheduleData: newRes);
      }

      // C-53 fix: newest 50, reversed for display. No mark-read in stream (REL-07).
      _messageSubscription = _supabase
          .from('partner_messages')
          .stream(primaryKey: ['id'])
          .eq('partner_id', partnerId)
          .order('created_at', ascending: false)
          .limit(50)
          .listen((data) {
        final msgs = (data as List)
            .map((e) => _parseMessage(e as Map<String, dynamic>))
            .toList()
            .reversed
            .toList();
        state = state.copyWith(messages: msgs, isLoading: false);
        // REL-07 fix: mark-read via explicit RPC call, not here
      }, onError: (err) {
        state = state.copyWith(errorMessage: 'Message sync error: $err', isLoading: false);
      });
      
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  PartnerMessageNode _parseMessage(Map<String, dynamic> row) {
    // C-81 fix: toLocal() for correct timezone display
    final raw = row['created_at']?.toString() ?? '';
    final dt = DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    return PartnerMessageNode(
      id: row['id'],
      senderId: row['sender_id'],
      content: row['content'],
      createdAt: dt,
      // CODE-03 fix: use from_admin from DB, not sender comparison
      isAdmin: row['from_admin'] == true,
    );
  }

  /// REL-07 fix: call explicitly when chat screen is visible.
  Future<void> markMessagesRead() async {
    try {
      await _supabase.rpc('mark_messages_read', params: {
        'p_partner_id': partnerId,
      });
    } catch (_) {}
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    try {
      await _supabase.from('partner_messages').insert({
        'partner_id': partnerId,
        'sender_id': currentUserId,
        'content': content.trim(),
      });
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to send message: $e');
    }
  }

  Future<void> updateSchedule({
    required List<int> workingDays,
    required int capacity,
    required int slots,
    required List<String> blacklistedDates,
  }) async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final res = await _supabase
          .from('partner_schedules')
          .update({
            'standard_working_days': workingDays,
            'simultaneous_panel_capacity': capacity,
            'guaranteed_slots_per_day': slots,
            'blacklisted_dates': blacklistedDates,
          })
          .eq('partner_id', partnerId)
          .select()
          .single();
      
      state = state.copyWith(isSaving: false, scheduleData: res);
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'Failed to update schedule: $e');
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}

final partnerSettingsProvider = StateNotifierProvider.autoDispose<PartnerSettingsController, PartnerSettingsState>((ref) {
  return PartnerSettingsController();
});
