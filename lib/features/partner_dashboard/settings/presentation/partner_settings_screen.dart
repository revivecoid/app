import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../presentation/partner_shell_screen.dart';

class PartnerSettingsScreen extends ConsumerWidget {
  PartnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final currentLocale = ref.watch(localeProvider);
    final currentTheme = ref.watch(themeModeProvider);
    final l = AppL.of(context)!;

    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '—';
    final displayName = user?.userMetadata?['full_name']?.toString()
        ?? user?.userMetadata?['name']?.toString()
        ?? email.split('@').first;

    Widget body = SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section: Display & Language ─────────────────────────────────
            _SectionHeader(
              icon: Icons.palette_outlined,
              title: '${l.appearance} & ${l.language}',
              subtitle: 'Personalize how the partner portal looks and which language it uses.',
            ),
            const SizedBox(height: 16),

            // Theme card
            _SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsLabel(icon: Icons.dark_mode_outlined, label: 'Theme'),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined, size: 16), label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark,  icon: Icon(Icons.dark_mode_outlined, size: 16),  label: Text('Dark')),
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined, size: 16), label: Text('System')),
                    ],
                    selected: {currentTheme},
                    onSelectionChanged: (val) {
                      ref.read(themeModeProvider.notifier).state = val.first;
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return AppColors.fireRed;
                        }
                        return cs.surfaceContainerHighest.withValues(alpha: 0.5);
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return Colors.white;
                        return cs.onSurfaceVariant;
                      }),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Language card
            _SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsLabel(icon: Icons.language_outlined, label: l.language),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('🇬🇧  English')),
                      ButtonSegment(value: 'id', label: Text('🇮🇩  Bahasa Indonesia')),
                    ],
                    selected: {currentLocale.languageCode},
                    onSelectionChanged: (val) {
                      ref.read(localeProvider.notifier).state = Locale(val.first);
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return AppColors.fireRed;
                        }
                        return cs.surfaceContainerHighest.withValues(alpha: 0.5);
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return Colors.white;
                        return cs.onSurfaceVariant;
                      }),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Section: Account ─────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.manage_accounts_outlined,
              title: 'Account',
              subtitle: 'Your account details and sign-out options.',
            ),
            const SizedBox(height: 16),

            _SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsLabel(icon: Icons.person_outline, label: 'Signed in as'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(color: AppColors.fireRed, shape: BoxShape.circle),
                      child: const Icon(Icons.person, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(displayName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
                      Text(email, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    ])),
                  ]),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Quick links row
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    _QuickLink(
                      icon: Icons.storefront_outlined,
                      label: 'My Profile',
                      onTap: () => context.go('/partner-dashboard/profile'),
                    ),
                    _QuickLink(
                      icon: Icons.calendar_month_outlined,
                      label: 'Schedule Config',
                      onTap: () => context.go('/partner-dashboard/schedule'),
                    ),
                    _QuickLink(
                      icon: Icons.speed_outlined,
                      label: 'Quota & Durations',
                      onTap: () => context.go('/partner-dashboard/quota'),
                    ),
                    _QuickLink(
                      icon: Icons.forum_outlined,
                      label: 'Commlink',
                      onTap: () => context.go('/partner-dashboard/commlink'),
                    ),
                  ]),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Sign out
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign Out', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.fireRed,
                        side: const BorderSide(color: AppColors.fireRed),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await Supabase.instance.client.auth.signOut();
                        if (context.mounted) context.go('/');
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Section: About ───────────────────────────────────────────────
            _SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsLabel(icon: Icons.info_outline, label: 'About re-V Partner Portal'),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Platform', value: 're-V Partner Ops Core'),
                  _InfoRow(label: 'Version', value: '2.0.0'),
                  _InfoRow(label: 'Support', value: 'partner-support@revive.co.id'),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );

    return PartnerShellScreen(
      activeRoute: '/partner-dashboard/settings',
      pageTitle: 'Workshop Settings',
      child: body,
    );
  }
}

// ─── Reusable sub-widgets ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionHeader({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.fireRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.fireRed, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
      ),
    ]);
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: child,
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SettingsLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.fireRed),
      const SizedBox(width: 8),
      Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5)),
    ]);
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickLink({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: AppColors.fireRed),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface)),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 100,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500))),
      ]),
    );
  }
}
