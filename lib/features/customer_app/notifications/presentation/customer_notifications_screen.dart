import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../application/notifications_provider.dart';
import '../domain/app_notification.dart';

class CustomerNotificationsScreen extends ConsumerWidget {
  const CustomerNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final notifState = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: ReVAppBar(
        title: const Text('Notifikasi'),
        showBackButton: true,
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(notificationsProvider.notifier).markAllAsRead(),
            child: Text(
              'Tandai Semua Dibaca',
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.primaryContainer,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: notifState.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.fireRed),
            ),
            error: (e, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('Gagal memuat notifikasi', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(notificationsProvider),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            ),
            data: (notifications) => notifications.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notif = notifications[index];
                      return _NotificationTile(
                        notif: notif,
                        isDark: isDark,
                        onTap: () {
                          if (!notif.isRead) {
                            ref
                                .read(notificationsProvider.notifier)
                                .markAsRead(notif.id);
                          }
                        },
                        onDismiss: () {
                          ref
                              .read(notificationsProvider.notifier)
                              .removeNotification(notif.id);
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.notifications_off_outlined,
          size: 64,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 16),
        Text(
          'Belum ada notifikasi',
          style: theme.textTheme.titleLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          'Update status booking akan muncul di sini.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual notification tile
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notif,
    required this.isDark,
    required this.onTap,
    required this.onDismiss,
  });

  final AppNotification notif;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: Key(notif.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDismiss(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
            border: notif.isRead
                ? null
                : Border.all(
                    color: AppColors.primaryContainer.withValues(alpha: 0.4),
                    width: 1,
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: notif.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(notif.icon, color: notif.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: TextStyle(
                              fontWeight: notif.isRead
                                  ? FontWeight.w600
                                  : FontWeight.bold,
                              fontSize: 15,
                              color: notif.isRead
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTimestamp(notif.timestamp),
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notif.body,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (!notif.isRead) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m lalu';
    if (diff.inHours < 24) return '${diff.inHours}j lalu';
    return '${diff.inDays}h lalu';
  }
}
