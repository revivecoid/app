import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import 'partner_dashboard_controller.dart';

// ─── Brand accent colors (theme-invariant) ────────────────────────────────────
const _shellPrimary = Color(0xFFa40016);
const _shellPrimaryContainer = Color(0xFFd10721);
const _shellOnPrimary = Color(0xFFffffff);
const _shellEmerald500 = Color(0xFF10B981);

/// Canonical partner dashboard shell — sidebar + top bar.
///
/// Wrap any partner sub-page child widget with this to get a consistent
/// navigation chrome, theme toggle, and user info bar without duplicating
/// the layout in every screen.
class PartnerShellScreen extends ConsumerWidget {
  /// The page content to embed in the main area.
  final Widget child;

  /// Route path of the currently active page — used to highlight the sidebar item.
  final String activeRoute;

  /// Optional title to show in the top bar.
  final String? pageTitle;

  /// Optional widgets placed in the top-bar trailing area (e.g. Save button).
  final List<Widget>? trailingActions;

  const PartnerShellScreen({
    super.key,
    required this.child,
    required this.activeRoute,
    this.pageTitle,
    this.trailingActions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name'] as String? ??
        user?.email?.split('@').first ??
        'Partner';

    // Unread badge count from the dashboard state (shared provider)
    final unreadCount = ref.watch(
      partnerDashboardProvider.select((s) => s.unreadMessageCount),
    );

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;

      return Scaffold(
        backgroundColor: cs.surface,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Sidebar ────────────────────────────────────────────────────
            if (isDesktop)
              _PartnerShellSidebar(
                activeRoute: activeRoute,
                unreadCount: unreadCount,
              ),

            // ── Main content area ──────────────────────────────────────────
            Expanded(
              child: Column(
                children: [
                  // Top bar
                  _PartnerShellTopBar(
                    pageTitle: pageTitle,
                    userName: userName,
                    trailingActions: trailingActions,
                  ),
                  // Page body
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─── Sidebar ──────────────────────────────────────────────────────────────────
class _PartnerShellSidebar extends ConsumerWidget {
  final String activeRoute;
  final int unreadCount;

  const _PartnerShellSidebar({
    required this.activeRoute,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    final navItems = [
      (Icons.view_kanban_outlined, 'Job Board / Pipeline', '/partner-dashboard', 0),
      (Icons.calendar_month_outlined, 'Schedule Config', '/partner-dashboard/schedule', 0),
      (Icons.speed_outlined, 'Quota & Panel Durations', '/partner-dashboard/quota', 0),
      (Icons.storefront_outlined, 'My Profile', '/partner-dashboard/profile', 0),
      (Icons.people_outline, 'Staff & Drivers', '/partner-dashboard/staff', 0),
      (Icons.tune_outlined, 'Workshop Settings', '/partner-dashboard/settings', 0),
      (Icons.forum_outlined, 'Commlink & Messages', '/partner-dashboard/commlink', unreadCount),
    ];

    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        boxShadow: [BoxShadow(color: const Color(0x0A000000), offset: const Offset(0, 1), blurRadius: 8)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              // Logo header
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: cs.outlineVariant)),
                ),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: const BoxDecoration(color: _shellPrimaryContainer, shape: BoxShape.circle),
                    child: const Icon(Icons.build_circle, color: _shellOnPrimary, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('re-V', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(AppL.of(context)!.partnerOpsCore,
                          style: const TextStyle(color: _shellPrimary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ],
                  ),
                ]),
              ),

              const SizedBox(height: 8),
              // Active hub info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warehouse_outlined, color: _shellPrimary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(AppL.of(context)!.partnerActiveHub,
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        Text(AppL.of(context)!.partnerWorkshopOps,
                            style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                ),
              ),

              const SizedBox(height: 12),
              // Nav items
              for (final item in navItems)
                _ShellNavItem(
                  icon: item.$1,
                  text: item.$2,
                  isActive: activeRoute == item.$3,
                  badge: item.$4,
                  onTap: () => context.go(item.$3),
                ),
            ],
          ),

          // Footer — signed in user
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(color: _shellPrimary, shape: BoxShape.circle),
                child: const Icon(Icons.person, color: _shellOnPrimary, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppL.of(context)!.partnerSignedIn,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.bold)),
                  Text(AppL.of(context)!.partnerAccount,
                      style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
              Container(width: 8, height: 8,
                  decoration: const BoxDecoration(color: _shellEmerald500, shape: BoxShape.circle)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ShellNavItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isActive;
  final int badge;
  final VoidCallback onTap;

  const _ShellNavItem({
    required this.icon,
    required this.text,
    required this.isActive,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? _shellPrimaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(icon,
                color: isActive ? const Color(0xFFFFE1DE) : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    color: isActive ? const Color(0xFFFFE1DE) : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  )),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: _shellPrimaryContainer, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge',
                    style: const TextStyle(color: _shellOnPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────
class _PartnerShellTopBar extends ConsumerWidget {
  final String? pageTitle;
  final String userName;
  final List<Widget>? trailingActions;

  const _PartnerShellTopBar({
    required this.pageTitle,
    required this.userName,
    this.trailingActions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: const Color(0x0A000000), offset: const Offset(0, 1), blurRadius: 8)],
      ),
      child: Row(children: [
        // Page title / breadcrumb
        if (pageTitle != null) ...[
          Text(pageTitle!,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(width: 16),
        ],

        // Custom trailing actions (e.g. Save / Edit buttons passed by sub-page)
        if (trailingActions != null) ...trailingActions!,

        const Spacer(),

        // Theme toggle
        IconButton(
          icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: cs.onSurfaceVariant),
          tooltip: 'Toggle Theme',
          onPressed: () {
            ref.read(themeModeProvider.notifier).state =
                isDark ? ThemeMode.light : ThemeMode.dark;
          },
        ),

        const SizedBox(width: 8),

        // User name
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(userName,
                style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(AppL.of(context)!.partnerWorkshopPartner,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          ],
        ),
        const SizedBox(width: 10),
        Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(color: _shellPrimary, shape: BoxShape.circle),
          child: const Icon(Icons.person, color: _shellOnPrimary, size: 18),
        ),
      ]),
    );
  }
}
