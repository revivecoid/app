import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/app_notification.dart';

class NotificationsNotifier extends StateNotifier<List<AppNotification>> {
  NotificationsNotifier() : super([]) {
    _loadInitialNotifications();
  }

  void _loadInitialNotifications() {
    // In a real app, this would fetch from an API or local DB (e.g. Supabase).
    // For now, we seed it with initial data so it's a "live" module.
    state = [
      AppNotification(
        id: '1',
        title: 'Payment Received',
        body: 'Your payment of Rp 1.500.000 for job #REV-8842 has been confirmed.',
        type: NotificationType.payment,
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
      AppNotification(
        id: '2',
        title: 'Car Repair Finished',
        body: 'Good news! Your bumper repair is complete and passed QC.',
        type: NotificationType.repairComplete,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      AppNotification(
        id: '3',
        title: 'Ready for Pickup',
        body: 'Your Honda CR-V (B 1234 XYZ) is washed and ready for pickup at Hub #04.',
        type: NotificationType.pickupReady,
        timestamp: DateTime.now().subtract(const Duration(hours: 3)),
      ),
    ];
  }

  void markAsRead(String id) {
    state = state.map((notif) {
      if (notif.id == id) {
        return notif.copyWith(isRead: true);
      }
      return notif;
    }).toList();
  }

  void markAllAsRead() {
    state = state.map((notif) => notif.copyWith(isRead: true)).toList();
  }

  void addNotification(AppNotification notification) {
    state = [notification, ...state];
  }

  void removeNotification(String id) {
    state = state.where((notif) => notif.id != id).toList();
  }
}

final notificationsProvider = StateNotifierProvider<NotificationsNotifier, List<AppNotification>>((ref) {
  return NotificationsNotifier();
});

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider);
  return notifications.where((n) => !n.isRead).length;
});
