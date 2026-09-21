import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../presentation/partner_shell_screen.dart';
import '../../../ops_mobile/ops_access.dart';

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

            // ── Section: Workshop Ops Access ────────────────────────────────
            // Owner-only; the card renders nothing for staff, drivers and anyone
            // else who cannot write the partner row.
            const _OpsAccessModeCard(),

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

// ─── Workshop ops access control ──────────────────────────────────────────────

/// Owner-only switch for how staff and drivers may operate the workshop.
///
/// Renders nothing for anyone who cannot write the partner row, so this is safe
/// to place unconditionally. The write is additionally enforced server-side by
/// the partner UPDATE policy — this widget's guard is only cosmetic.
class _OpsAccessModeCard extends ConsumerStatefulWidget {
  const _OpsAccessModeCard();

  @override
  ConsumerState<_OpsAccessModeCard> createState() => _OpsAccessModeCardState();
}

class _OpsAccessModeCardState extends ConsumerState<_OpsAccessModeCard> {
  bool _saving = false;

  bool get _mayConfigure {
    final role = Supabase.instance.client.auth.currentUser?.appMetadata['role'] as String?;
    return role == 'partner_mechanic' || role == 'master_admin';
  }

  /// Longer owner-facing explanation per mode, with the "why you'd pick this"
  /// that the one-line enum description cannot carry. The ops settings screen
  /// shows [OpsViewMode.description] to the operator, so these two must agree.
  String _modeDetail(OpsViewMode mode) => switch (mode) {
        OpsViewMode.allAccess =>
          'Full access — staff and drivers both see every tab and every job in this '
              'workshop, and either role can complete any repair stage. Use this when a '
              'customer may change their mind about pickup or self-delivery mid-job.',
        OpsViewMode.viewAllActOwn =>
          'View all, act on their own — staff and drivers see every job and every repair '
              'stage, so anyone can tell a customer where their car is. Completing a stage '
              'stays with the role responsible for it: a driver cannot close out '
              'disassembly, welding or QC. Enforced by the database, not just hidden in '
              'the app.',
        OpsViewMode.originalRole =>
          'Strict roles — staff only handle self-delivery intake and drivers only handle '
              'valet pickup, each completing just their own repair stages, and neither '
              'sees the other\'s jobs at all. This is the original behaviour.',
      };

  Future<void> _save(OpsViewMode mode) async {
    final user = Supabase.instance.client.auth.currentUser;
    final partnerId = user?.appMetadata['partner_id'] as String?;
    if (partnerId == null || partnerId.isEmpty) {
      _notify('No workshop linked to your account.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('partners')
          .update({'ops_view_mode': mode.dbValue})
          .eq('id', partnerId);

      // Refresh the shared provider so the ops app reflects this immediately.
      ref.invalidate(opsViewModeProvider);

      // Three modes, so the confirmation has to say which one landed — a binary
      // message would report the new mode as "back to role-specific", which is
      // wrong in both directions for view_all_act_own.
      _notify(switch (mode) {
        OpsViewMode.allAccess =>
          'Staff and drivers can now see and handle every job.',
        OpsViewMode.viewAllActOwn =>
          'Staff and drivers can see every job, but only complete their own stages.',
        OpsViewMode.originalRole =>
          'Staff and drivers are back to their role-specific jobs.',
      });
    } catch (e) {
      _notify('Could not save access mode: ${e.toString().replaceAll('PostgrestException', '').trim()}',
          isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!_mayConfigure) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final modeAsync = ref.watch(opsViewModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.badge_outlined,
          title: 'Workshop Access',
          subtitle: 'Control what your staff and drivers can see and handle.',
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SettingsLabel(icon: Icons.tune, label: 'Staff & Driver Access'),
              const SizedBox(height: 12),
              modeAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, _) => Text('Could not load access mode: $err'),
                data: (mode) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<OpsViewMode>(
                      segments: const [
                        ButtonSegment(
                          value: OpsViewMode.allAccess,
                          icon: Icon(Icons.visibility_outlined, size: 16),
                          label: Text('Full access'),
                        ),
                        ButtonSegment(
                          value: OpsViewMode.viewAllActOwn,
                          icon: Icon(Icons.remove_red_eye_outlined, size: 16),
                          label: Text('View all, act own'),
                        ),
                        ButtonSegment(
                          value: OpsViewMode.originalRole,
                          icon: Icon(Icons.badge_outlined, size: 16),
                          label: Text('Strict roles'),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: _saving
                          ? null
                          : (val) {
                              if (val.first != mode) _save(val.first);
                            },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) return AppColors.fireRed;
                          return cs.surfaceContainerHighest.withValues(alpha: 0.5);
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) return Colors.white;
                          return cs.onSurfaceVariant;
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // One source for the wording: the enum, which the ops
                    // settings screen shows back to the operator. Keeping the
                    // copy here and there in step matters — a driver reading a
                    // different explanation than the owner chose is how a
                    // deliberate restriction looks like a bug.
                    Text(
                      _modeDetail(mode),
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4),
                    ),
                    if (_saving) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text('Saving…', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
