import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/app_notification.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notification preferences model
// ─────────────────────────────────────────────────────────────────────────────
class NotificationPreferences {
  final bool inApp;
  final bool email;
  final bool whatsapp;
  final String emailAddress;
  final String whatsappNumber;

  const NotificationPreferences({
    this.inApp = true,
    this.email = true,
    this.whatsapp = false,
    this.emailAddress = '',
    this.whatsappNumber = '',
  });

  NotificationPreferences copyWith({
    bool? inApp,
    bool? email,
    bool? whatsapp,
    String? emailAddress,
    String? whatsappNumber,
  }) {
    return NotificationPreferences(
      inApp: inApp ?? this.inApp,
      email: email ?? this.email,
      whatsapp: whatsapp ?? this.whatsapp,
      emailAddress: emailAddress ?? this.emailAddress,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
    );
  }

  factory NotificationPreferences.fromMap(Map<String, dynamic> map) {
    return NotificationPreferences(
      inApp: map['in_app'] as bool? ?? true,
      email: map['email'] as bool? ?? true,
      whatsapp: map['whatsapp'] as bool? ?? false,
      emailAddress: map['email_address'] as String? ?? '',
      whatsappNumber: map['whatsapp_number'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'in_app': inApp,
    'email': email,
    'whatsapp': whatsapp,
    'email_address': emailAddress.isEmpty ? null : emailAddress,
    'whatsapp_number': whatsappNumber.isEmpty ? null : whatsappNumber,
    'updated_at': DateTime.now().toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications provider — live from Supabase Realtime
// ─────────────────────────────────────────────────────────────────────────────
class NotificationsNotifier extends StateNotifier<AsyncValue<List<AppNotification>>> {
  NotificationsNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  Future<void> _init() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      state = const AsyncValue.data([]);
      return;
    }

    // Initial fetch
    await _fetchAll();

    // Subscribe to realtime inserts on the notifications table
    _channel = _supabase
        .channel('notifications:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final newNotif = AppNotification.fromMap(
              payload.newRecord as Map<String, dynamic>,
            );
            final current = state.valueOrNull ?? [];
            state = AsyncValue.data([newNotif, ...current]);
          },
        )
        .subscribe();
  }

  Future<void> _fetchAll() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      final list = (res as List<dynamic>)
          .map((e) => AppNotification.fromMap(e as Map<String, dynamic>))
          .toList();

      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> markAsRead(String id) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id);

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList(),
    );
  }

  Future<void> markAllAsRead() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id)
        .eq('is_read', false);

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.map((n) => n.copyWith(isRead: true)).toList(),
    );
  }

  Future<void> removeNotification(String id) async {
    await _supabase.from('notifications').delete().eq('id', id);

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((n) => n.id != id).toList());
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, AsyncValue<List<AppNotification>>>(
  (ref) => NotificationsNotifier(),
);

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final state = ref.watch(notificationsProvider);
  return state.valueOrNull?.where((n) => !n.isRead).length ?? 0;
});

// ─────────────────────────────────────────────────────────────────────────────
// Notification preferences provider
// ─────────────────────────────────────────────────────────────────────────────
class NotificationPreferencesNotifier
    extends StateNotifier<AsyncValue<NotificationPreferences>> {
  NotificationPreferencesNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  final _supabase = Supabase.instance.client;

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      state = const AsyncValue.data(NotificationPreferences());
      return;
    }
    try {
      final res = await _supabase
          .from('notification_preferences')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (res == null) {
        // Create default row
        await _supabase.from('notification_preferences').upsert({
          'user_id': user.id,
          'email_address': user.email ?? '',
        });
        state = AsyncValue.data(
          NotificationPreferences(emailAddress: user.email ?? ''),
        );
      } else {
        state = AsyncValue.data(
          NotificationPreferences.fromMap(res as Map<String, dynamic>),
        );
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> update(NotificationPreferences prefs) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    state = AsyncValue.data(prefs);

    await _supabase.from('notification_preferences').upsert({
      'user_id': user.id,
      ...prefs.toMap(),
    });
  }
}

final notificationPreferencesProvider = StateNotifierProvider<
    NotificationPreferencesNotifier, AsyncValue<NotificationPreferences>>(
  (ref) => NotificationPreferencesNotifier(),
);
