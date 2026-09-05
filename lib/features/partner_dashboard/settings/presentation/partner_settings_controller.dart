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
    partnerId = user.userMetadata?['partner_id'] ?? '';
    
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

      // Stream Messages
      _messageSubscription = _supabase
          .from('partner_messages')
          .stream(primaryKey: ['id'])
          .eq('partner_id', partnerId)
          .order('created_at', ascending: true)
          .listen((data) {
        final msgs = (data as List).map((e) => _parseMessage(e as Map<String, dynamic>)).toList();
        state = state.copyWith(messages: msgs, isLoading: false);
        
        // Mark unread messages as read
        final unread = data.where((e) => e['is_read'] == false && e['sender_id'] != currentUserId).toList();
        if (unread.isNotEmpty) {
          _supabase.from('partner_messages').update({'is_read': true})
              .eq('partner_id', partnerId).neq('sender_id', currentUserId).eq('is_read', false).then((_) {});
        }
      }, onError: (err) {
        state = state.copyWith(errorMessage: 'Message sync error: $err', isLoading: false);
      });
      
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  PartnerMessageNode _parseMessage(Map<String, dynamic> row) {
    return PartnerMessageNode(
      id: row['id'],
      senderId: row['sender_id'],
      content: row['content'],
      createdAt: DateTime.parse(row['created_at']),
      isAdmin: row['sender_id'] != currentUserId, // If not sent by me, it's from admin
    );
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
