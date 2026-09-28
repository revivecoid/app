part of '../master_admin_desktop.dart';

// ─── Sidebar ──────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final int activeIndex;
  final void Function(int, String?) onNav;
  final VoidCallback onExit;

  const _Sidebar(
      {required this.cs,
      required this.state,
      required this.activeIndex,
      required this.onNav,
      required this.onExit});

  @override
  Widget build(BuildContext context) {
    final isSysadmin = state.adminLevel == 'sysadmin';
    return Container(
      width: 288,
      color: cs.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo bar
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              InkWell(
                onTap: () => context.go('/'),
                borderRadius: BorderRadius.circular(8),
                child: Row(children: [
                  Image.asset(
                    'assets/images/revive_logo.png',
                    height: 26,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('re-V',
                      style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: 0.5)),
                ]),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4)),
                child: Text('OPS CORE',
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
              ),
            ]),
          ),
          // Active Hub
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active Operational Hub',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.warehouse_outlined,
                          color: cs.primary, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                        state.activeHubName,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      )),
                      Icon(Icons.unfold_more,
                          color: cs.onSurfaceVariant, size: 16),
                    ]),
                  ]),
            ),
          ),
          // Nav items
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(children: [
                ...List.generate(_navItems.length, (i) {
                  final item = _navItems[i];
                  final isLocked =
                      item.sysadminOnly && !isSysadmin;
                  final isActive =
                      i == activeIndex && item.route == null;
                  return _SidebarNavItem(
                    cs: cs,
                    icon: item.icon,
                    label: item.label,
                    isActive: isActive,
                    isLocked: isLocked,
                    isSysadminBadge: item.sysadminOnly,
                    onTap: isLocked
                        ? null
                        : () => onNav(i, item.route),
                  );
                }),
                const Spacer(),
                _SidebarNavItem(
                  cs: cs,
                  icon: Icons.arrow_back_rounded,
                  label: 'Exit Central',
                  isActive: false,
                  onTap: onExit,
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          // Telemetry
          Container(
            padding: const EdgeInsets.all(12),
            color: cs.surfaceContainerLow,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Core Telemetry',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.8)),
                        Text('v4.18.2',
                            style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant)),
                      ]),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const _PulseDot(
                          color: Color(0xFF10b981)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('Active Sync: OK',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface))),
                      Text('34ms',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isLocked;
  final bool isSysadminBadge;
  final VoidCallback? onTap;

  const _SidebarNavItem({
    required this.cs,
    required this.icon,
    required this.label,
    required this.isActive,
    this.isLocked = false,
    this.isSysadminBadge = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? cs.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(icon,
              size: 18,
              color: isLocked
                  ? cs.onSurfaceVariant.withValues(alpha: 0.4)
                  : isActive
                      ? cs.primary
                      : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isLocked
                          ? cs.onSurfaceVariant
                              .withValues(alpha: 0.4)
                          : isActive
                              ? cs.primary
                              : cs.onSurfaceVariant))),
          if (isLocked)
            Icon(Icons.lock_outline,
                size: 14,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4))
          else if (isSysadminBadge)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color:
                      cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3)),
              child: Text('SYS',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: cs.primary)),
            ),
        ]),
      ),
    );
  }
}

