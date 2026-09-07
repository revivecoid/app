import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../application/notifications_provider.dart';

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  late TextEditingController _emailController;
  late TextEditingController _waController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _waController = TextEditingController();

    // Pre-fill once prefs load
    Future.microtask(() {
      final prefs = ref.read(notificationPreferencesProvider).valueOrNull;
      if (prefs != null) {
        _emailController.text = prefs.emailAddress;
        _waController.text = prefs.whatsappNumber;
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _waController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current =
        ref.read(notificationPreferencesProvider).valueOrNull;
    if (current == null) return;

    setState(() => _saving = true);

    await ref.read(notificationPreferencesProvider.notifier).update(
          current.copyWith(
            emailAddress: _emailController.text.trim(),
            whatsappNumber: _waController.text.trim(),
          ),
        );

    setState(() => _saving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preferensi notifikasi disimpan',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface)),
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prefsState = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const ReVAppBar(
        title: Text('Pengaturan Notifikasi'),
        showBackButton: true,
      ),
      body: prefsState.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.fireRed),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (prefs) {
          // Sync controllers once prefs are loaded
          if (_emailController.text.isEmpty &&
              prefs.emailAddress.isNotEmpty) {
            _emailController.text = prefs.emailAddress;
          }
          if (_waController.text.isEmpty &&
              prefs.whatsappNumber.isNotEmpty) {
            _waController.text = prefs.whatsappNumber;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.fireRed.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.fireRed.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.fireRed, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pilih saluran notifikasi yang ingin Anda aktifkan untuk update status booking kendaraan.',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── In-App ─────────────────────────────────────────────
                _buildChannelCard(
                  context: context,
                  cs: cs,
                  icon: Icons.notifications_outlined,
                  iconColor: AppColors.fireRed,
                  title: 'Notifikasi In-App',
                  subtitle:
                      'Terima notifikasi langsung di dalam aplikasi Revive.',
                  badge: null,
                  value: prefs.inApp,
                  enabled: false, // always on
                  onChanged: null,
                  child: null,
                ),
                const SizedBox(height: 12),

                // ── Email ───────────────────────────────────────────────
                _buildChannelCard(
                  context: context,
                  cs: cs,
                  icon: Icons.email_outlined,
                  iconColor: Colors.blue,
                  title: 'Notifikasi Email',
                  subtitle: 'Terima ringkasan status ke email Anda.',
                  badge: null,
                  value: prefs.email,
                  enabled: true,
                  onChanged: (val) {
                    ref
                        .read(notificationPreferencesProvider.notifier)
                        .update(prefs.copyWith(email: val));
                  },
                  child: prefs.email
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextField(
                            controller: _emailController,
                            style: TextStyle(color: cs.onSurface),
                            decoration: InputDecoration(
                              labelText: 'Alamat Email',
                              labelStyle:
                                  TextStyle(color: cs.onSurfaceVariant),
                              prefixIcon: Icon(Icons.alternate_email,
                                  color: cs.onSurfaceVariant),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: cs.outlineVariant),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: cs.outlineVariant),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: cs.primary, width: 2),
                              ),
                              fillColor: cs.surfaceContainerLow,
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),

                // ── WhatsApp ────────────────────────────────────────────
                _buildChannelCard(
                  context: context,
                  cs: cs,
                  icon: Icons.chat_outlined,
                  iconColor: const Color(0xFF25D366),
                  title: 'Notifikasi WhatsApp',
                  subtitle:
                      'Terima pesan status langsung ke WhatsApp Anda.',
                  badge: const _WaBadge(),
                  value: prefs.whatsapp,
                  enabled: true,
                  onChanged: (val) {
                    ref
                        .read(notificationPreferencesProvider.notifier)
                        .update(prefs.copyWith(whatsapp: val));
                  },
                  child: prefs.whatsapp
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _waController,
                                style: TextStyle(color: cs.onSurface),
                                decoration: InputDecoration(
                                  labelText: 'Nomor WhatsApp',
                                  hintText: '0812xxxxxxxx',
                                  labelStyle: TextStyle(
                                      color: cs.onSurfaceVariant),
                                  hintStyle: TextStyle(
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.5)),
                                  prefixIcon: Icon(Icons.phone_outlined,
                                      color: cs.onSurfaceVariant),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: cs.outlineVariant),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: cs.outlineVariant),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: cs.primary, width: 2),
                                  ),
                                  fillColor: cs.surfaceContainerLow,
                                  filled: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 12),
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366)
                                      .withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.schedule,
                                        size: 14,
                                        color: Color(0xFF25D366)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'WhatsApp Business sedang dalam proses aktivasi. Notifikasi akan aktif setelah proses selesai.',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                ),

                const SizedBox(height: 28),

                // Save button
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.fireRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Simpan Pengaturan',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChannelCard({
    required BuildContext context,
    required ColorScheme cs,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget? badge,
    required bool value,
    required bool enabled,
    required void Function(bool)? onChanged,
    required Widget? child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: cs.onSurface.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          badge,
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeColor: AppColors.fireRed,
              ),
            ],
          ),
          if (child != null) child,
        ],
      ),
    );
  }
}

class _WaBadge extends StatelessWidget {
  const _WaBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'Segera',
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.orange),
      ),
    );
  }
}
