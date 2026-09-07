import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import 'admin_dashboard_controller.dart';

// ─── Nav Items ────────────────────────────────────────────────────────────────

class _NavItem {
  final String label;
  final IconData icon;
  final String? route;
  final bool sysadminOnly;
  const _NavItem(this.label, this.icon,
      {this.route, this.sysadminOnly = false});
}

const _navItems = [
  _NavItem('Job Board / Pipeline', Icons.view_kanban_outlined),
  _NavItem('Workshop Settings & Quotas', Icons.tune_outlined),
  _NavItem('Assign Jobs Hub', Icons.assignment_outlined),
  _NavItem('Customer Database', Icons.people_outline_rounded),
  _NavItem('System Settings', Icons.settings_outlined, sysadminOnly: true),
  _NavItem('User Accounts', Icons.manage_accounts_outlined,
      route: '/admin-central/users', sysadminOnly: true),
  _NavItem('Frontend Settings', Icons.palette_outlined,
      route: '/admin-central/frontend-settings', sysadminOnly: true),
];

// ─── Root Widget ──────────────────────────────────────────────────────────────

class MasterAdminDesktop extends ConsumerStatefulWidget {
  const MasterAdminDesktop({super.key});
  @override
  ConsumerState<MasterAdminDesktop> createState() =>
      _MasterAdminDesktopState();
}

class _MasterAdminDesktopState
    extends ConsumerState<MasterAdminDesktop> {
  int _activeNavIndex = 0;
  AdminJobNode? _verifyingJob;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(adminDashboardProvider);
    final controller = ref.read(adminDashboardProvider.notifier);
    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          Row(
            children: [
              _Sidebar(
                cs: cs,
                state: state,
                activeIndex: _activeNavIndex,
                onNav: (i, route) {
                  if (route != null) {
                    context.push(route);
                  } else {
                    setState(() => _activeNavIndex = i);
                  }
                },
                onExit: () => context.go('/'),
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopHeader(
                      cs: cs,
                      state: state,
                      ref: ref,
                      searchCtrl: _searchCtrl,
                      onSearch: (q) => controller.setSearchQuery(q),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: _buildContent(cs, state, controller),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_verifyingJob != null)
            _VerificationModal(
              cs: cs,
              job: _verifyingJob!,
              onClose: () =>
                  setState(() => _verifyingJob = null),
              onApprove: () async {
                await controller.overrideJobStatus(
                    _verifyingJob!.id, 'completed');
                setState(() => _verifyingJob = null);
              },
              onReject: () async {
                await controller.overrideJobStatus(
                    _verifyingJob!.id, '3_booked');
                setState(() => _verifyingJob = null);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, AdminDashboardState state,
      AdminDashboardController controller) {
    switch (_activeNavIndex) {
      case 0:
        return _OpsMatrixContent(
          cs: cs,
          state: state,
          controller: controller,
          onVerify: (job) => setState(() => _verifyingJob = job),
        );
      case 1:
        return _WorkshopSettingsContent(
            cs: cs, state: state, controller: controller);
      case 2:
        return _AssignJobsContent(
            cs: cs, state: state, controller: controller);
      case 3:
        return _CustomerCrmContent(cs: cs, state: state);
      case 4:
        return _PlaceholderContent(
          cs: cs,
          label: 'System Settings',
          subtitle: 'Sysadmin-only. Contact your system administrator.',
          icon: Icons.settings_outlined,
        );
      default:
        return _PlaceholderContent(
          cs: cs,
          label: _navItems[_activeNavIndex].label,
        );
    }
  }
}

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
              Icon(Icons.shield_rounded,
                  color: cs.primary, size: 28),
              const SizedBox(width: 10),
              Text('REVIVE',
                  style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 0.5)),
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

// ─── Top Header ───────────────────────────────────────────────────────────────

class _TopHeader extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final WidgetRef ref;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;

  const _TopHeader(
      {required this.cs,
      required this.state,
      required this.ref,
      required this.searchCtrl,
      required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;
    // Role display label
    final roleLabel = state.adminRole
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty
            ? ''
            : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return Container(
      height: 64,
      color: cs.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        // Search
        Expanded(
          flex: 3,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.search_rounded,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                controller: searchCtrl,
                onChanged: onSearch,
                style:
                    TextStyle(fontSize: 14, color: cs.onSurface),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText:
                      'Search VIN, license plate, or order ID...',
                  hintStyle: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 14),
                  isDense: true,
                  suffixIcon: searchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            searchCtrl.clear();
                            onSearch('');
                          },
                          child: Icon(Icons.close,
                              size: 16,
                              color: cs.onSurfaceVariant))
                      : null,
                ),
              )),
            ]),
          ),
        ),
        const SizedBox(width: 24),
        // Live node
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const _PulseDot(color: Color(0xFF10b981)),
            const SizedBox(width: 6),
            Text('NODE 04: LIVE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
          ]),
        ),
        const SizedBox(width: 8),
        // Notifications
        Stack(children: [
          IconButton(
              icon: Icon(Icons.notifications_outlined,
                  color: cs.onSurface),
              onPressed: () {}),
          Positioned(
              top: 8,
              right: 8,
              child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: cs.surfaceContainerLowest,
                          width: 1.5)))),
        ]),
        // Theme toggle
        IconButton(
          icon: Icon(
              isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              color: cs.onSurface),
          tooltip: 'Toggle Theme',
          onPressed: () =>
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark,
        ),
        const SizedBox(width: 8),
        // Admin identity — clickable
        InkWell(
          onTap: () => _showAdminProfileSheet(context, state, cs),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(children: [
              Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(state.adminName,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            height: 1.2)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(state.adminLevel == 'sysadmin' ? 'System Administrator' : 'Administrator',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              height: 1.2)),
                      if (state.adminLevel == 'sysadmin') ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3)),
                          child: Text('SYS',
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ]),
                  ]),
              const SizedBox(width: 10),
              Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: cs.primary, shape: BoxShape.circle),
                  child: Icon(Icons.person_rounded,
                      color: cs.onPrimary, size: 18)),
            ]),
          ),
        ),
      ]),
    );
  }

  void _showAdminProfileSheet(
      BuildContext context, AdminDashboardState state, ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 56,
              height: 56,
              decoration:
                  BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              child: Icon(Icons.person_rounded, color: cs.onPrimary, size: 30)),
          const SizedBox(height: 12),
          Text(state.adminName,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(
              state.adminLevel == 'sysadmin'
                  ? 'System Administrator'
                  : 'Administrator',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          if (state.adminLevel == 'sysadmin') ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('SYSADMIN ACCESS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                      letterSpacing: 1)),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.hub_outlined,
                color: cs.onSurfaceVariant, size: 20),
            title: Text('Active Hub',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            trailing: Text(state.activeHubName,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            dense: true,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: Icon(Icons.logout, color: cs.error, size: 18),
            label: Text('Sign Out',
                style:
                    TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
            onPressed: () async {
              Navigator.pop(context);
              await Supabase.instance.client.auth.signOut();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ─── Ops Matrix ───────────────────────────────────────────────────────────────

class _OpsMatrixContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;
  final void Function(AdminJobNode) onVerify;

  const _OpsMatrixContent(
      {required this.cs,
      required this.state,
      required this.controller,
      required this.onVerify});

  String _formatRupiah(double amount) {
    final f = NumberFormat('#,###', 'id_ID');
    return 'Rp ${f.format(amount)}';
  }

  @override
  Widget build(BuildContext context) {
    final pendingJobs = state.activeJobs
        .where((j) =>
            j.status == '3_booked' ||
            j.status == 'manual_verification_pending')
        .toList();

    final settlementLabel = state.settlementLoading
        ? 'Loading...'
        : _formatRupiah(state.dailySettlementAmount);

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    _Chip(
                        cs: cs,
                        label: 'Master Ops Matrix',
                        bgColor: cs.surfaceContainerHigh,
                        fgColor: cs.primary),
                    const SizedBox(width: 8),
                    Text('BCA / VA Liquidity Gateway Live',
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                      'Active Financial Clearing & Dispatch Matrix',
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                ])),
            const SizedBox(width: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _KpiCard(
                  cs: cs,
                  icon: Icons.account_balance_outlined,
                  label: 'Daily Vault Settlement',
                  value: settlementLabel),
              _KpiCard(
                  cs: cs,
                  icon: Icons.hourglass_top_rounded,
                  label: 'Unreconciled Slips',
                  value: '${pendingJobs.length} Action Required',
                  highlight: pendingJobs.isNotEmpty),
              OutlinedButton.icon(
                onPressed: () {},
                icon: Icon(Icons.history_rounded,
                    size: 16, color: cs.onSurface),
                label: Text('Gateway Audit',
                    style: TextStyle(
                        color: cs.onSurface, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.outline),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          // Filter bar
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color:
                          cs.onSurface.withValues(alpha: 0.04),
                      blurRadius: 8)
                ]),
            child: Row(children: [
              Expanded(
                  child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12),
                decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.filter_list_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text('Status: All Active',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface)),
                ]),
              )),
              const SizedBox(width: 8),
              _Chip(
                  cs: cs,
                  label:
                      '${state.activeJobs.length} jobs',
                  bgColor: cs.surfaceContainerLow,
                  fgColor: cs.onSurfaceVariant),
              const Spacer(),
              const _PulseDot(color: Color(0xFF10b981)),
              const SizedBox(width: 6),
              Text('Live Realtime',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant)),
              const SizedBox(width: 12),
              IconButton(
                  icon: Icon(Icons.download_rounded,
                      color: cs.onSurfaceVariant, size: 20),
                  tooltip: 'Export',
                  onPressed: () {}),
            ]),
          ),
          const SizedBox(height: 16),
          // Table
          Container(
            decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color:
                          cs.onSurface.withValues(alpha: 0.04),
                      blurRadius: 8)
                ]),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Container(
                color: cs.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(children: [
                  _TH(cs: cs, label: 'Job ID', flex: 2),
                  _TH(cs: cs, label: 'Vehicle & Plate', flex: 3),
                  _TH(cs: cs, label: 'Owner', flex: 3),
                  _TH(cs: cs, label: 'Assigned Hub', flex: 3),
                  _TH(cs: cs, label: 'Payment', flex: 2),
                  _TH(
                      cs: cs,
                      label: 'Status',
                      flex: 3),
                  _TH(
                      cs: cs,
                      label: 'Action',
                      flex: 2,
                      right: true),
                ]),
              ),
              if (state.activeJobs.isEmpty && !state.isLoading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 48, color: cs.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text('No active jobs in the pipeline.',
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                  ],
                ),
              ),
            )
              else
                ...state.activeJobs.map((j) => _JobRow(
                      cs: cs,
                      job: j,
                      partners: state.partners,
                      onVerify: () => onVerify(j),
                      onOverride: (newStatus) =>
                          controller.overrideJobStatus(
                              j.id, newStatus),
                    )),
              if (state.isLoading)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: cs.primary))),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                color: cs.surfaceContainerLow,
                child: Row(children: [
                  const _PulseDot(
                      color: Color(0xFF10b981)),
                  const SizedBox(width: 6),
                  Text('BCA Settlement Webhook: ',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant)),
                  Text('200 OK (0.12s latency)',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                ]),
              ),
            ]),
          ),
        ]);
  }
}

class _JobRow extends StatelessWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  final List<PartnerCrmNode> partners;
  final VoidCallback onVerify;
  final ValueChanged<String> onOverride;

  const _JobRow(
      {required this.cs,
      required this.job,
      required this.partners,
      required this.onVerify,
      required this.onOverride});

  bool get _pending =>
      job.status == '3_booked' ||
      job.status == 'manual_verification_pending';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: _pending
              ? cs.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          border: Border(
              bottom: BorderSide(
                  color: cs.surfaceContainerHigh, width: 1))),
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 12),
      child: Row(children: [
        // Job ID
        Expanded(
            flex: 2,
            child: Row(children: [
              if (_pending)
                Container(
                    width: 3,
                    height: 20,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius:
                            BorderRadius.circular(2))),
              Expanded(
                  child: Text('#${job.id}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: _pending
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: _pending
                              ? cs.primary
                              : cs.onSurface,
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis)),
            ])),
        // Vehicle
        Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(
                  job.carIdentity.contains('-')
                      ? job.carIdentity
                          .split('-')
                          .first
                          .trim()
                      : job.carIdentity,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              if (job.carIdentity.contains('-'))
                Text(
                    job.carIdentity
                        .split('-')
                        .last
                        .trim(),
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace')),
            ])),
        // Owner
        Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(job.customerName,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              Text(job.timeElapsedCurrentStage + ' elapsed',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant)),
            ])),
        // Hub
        Expanded(
            flex: 3,
            child: Row(children: [
              Icon(Icons.warehouse_outlined,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(job.partnerName,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis)),
            ])),
        // Payment
        Expanded(
            flex: 2,
            child: job.finalPrice != null
                ? Text(
                    'Rp ${NumberFormat('#,###', 'id_ID').format(job.finalPrice)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: job.isPaid
                            ? const Color(0xFF059669)
                            : cs.onSurface,
                        fontFamily: 'monospace'))
                : Text('—',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant))),
        // Status
        Expanded(
            flex: 3,
            child: _StatusBadge(cs: cs, status: job.status)),
        // Action
        Expanded(
            flex: 2,
            child: Align(
                alignment: Alignment.centerRight,
                child: _pending
                    ? ElevatedButton.icon(
                        onPressed: onVerify,
                        icon: Icon(Icons.visibility_outlined,
                            size: 14, color: cs.onPrimary),
                        label: Text('Review Slip',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onPrimary)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize
                                .shrinkWrap),
                      )
                    : PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz,
                            color: cs.onSurfaceVariant,
                            size: 18),
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'view',
                            child: Row(children: [
                              Icon(Icons.open_in_new_rounded,
                                  size: 16,
                                  color: cs.onSurface),
                              const SizedBox(width: 10),
                              Text('View Job Details',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'override',
                            child: Row(children: [
                              Icon(
                                  Icons
                                      .swap_horiz_rounded,
                                  size: 16,
                                  color: cs.onSurface),
                              const SizedBox(width: 10),
                              Text('Override Status',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'flag',
                            child: Row(children: [
                              Icon(Icons.flag_outlined,
                                  size: 16,
                                  color: cs.error),
                              const SizedBox(width: 10),
                              Text('Flag / Escalate',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.error)),
                            ]),
                          ),
                        ],
                        onSelected: (val) {
                          switch (val) {
                            case 'view':
                              context.push('/track/${job.id}');
                            case 'override':
                              _showStatusPicker(
                                  context, job, onOverride);
                            case 'flag':
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                    'Job #${job.id} flagged for escalation',
                                    style: TextStyle(
                                        color: cs.onSurface)),
                                backgroundColor:
                                    cs.surfaceContainerHigh,
                              ));
                          }
                        },
                      ))),
      ]),
    );
  }

  void _showStatusPicker(BuildContext context, AdminJobNode job,
      ValueChanged<String> onOverride) {
    final cs = Theme.of(context).colorScheme;
    final statuses = [
      ('2_estimated', 'Estimated'),
      ('3_booked', 'Booked'),
      ('4_paid', 'Paid'),
      ('5_scheduled', 'Scheduled'),
      ('6_in_progress', 'In Progress'),
      ('7_finished', 'Finished'),
      ('8_awaiting_delivery', 'Awaiting Delivery'),
      ('9_done', 'Done'),
      ('completed', 'Completed'),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerLowest,
        title: Text('Override Status — #${job.id}',
            style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses
              .map((s) => ListTile(
                    leading: Radio<String>(
                      value: s.$1,
                      groupValue: job.status,
                      activeColor: cs.primary,
                      onChanged: (v) {
                        if (v != null) {
                          onOverride(v);
                          Navigator.of(ctx).pop();
                        }
                      },
                    ),
                    title: Text(s.$2,
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface)),
                    subtitle: Text(s.$1,
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                            fontFamily: 'monospace')),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: TextStyle(color: cs.onSurfaceVariant)))
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ColorScheme cs;
  final String status;
  const _StatusBadge({required this.cs, required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    late String label;
    late IconData icon;
    switch (status) {
      case 'manual_verification_pending':
      case '3_booked':
        bg = cs.primary.withValues(alpha: 0.1);
        fg = cs.primary;
        label = 'Pending Verification';
        icon = Icons.circle;
      case 'completed':
        bg = const Color(0xFF10b981).withValues(alpha: 0.15);
        fg = const Color(0xFF059669);
        label = 'PAID & VERIFIED';
        icon = Icons.check_circle_outline;
      case 'overdue':
        bg = cs.secondaryContainer.withValues(alpha: 0.3);
        fg = cs.onSecondaryContainer;
        label = 'PAYMENT OVERDUE';
        icon = Icons.warning_amber_rounded;
      case '6_in_progress':
        bg = const Color(0xFF0ea5e9).withValues(alpha: 0.15);
        fg = const Color(0xFF0369a1);
        label = 'IN PROGRESS';
        icon = Icons.construction_rounded;
      case '4_paid':
      case '5_scheduled':
        bg = const Color(0xFF10b981).withValues(alpha: 0.1);
        fg = const Color(0xFF059669);
        label = status == '4_paid' ? 'PAID' : 'SCHEDULED';
        icon = Icons.event_available_rounded;
      default:
        bg = cs.surfaceContainerHigh;
        fg = cs.onSurfaceVariant;
        label = status
            .replaceAll('_', ' ')
            .toUpperCase();
        icon = Icons.radio_button_unchecked;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: fg),
        const SizedBox(width: 4),
        Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: fg),
                overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ─── Workshop Settings & Quotas ───────────────────────────────────────────────

class _WorkshopSettingsContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;
  const _WorkshopSettingsContent(
      {required this.cs,
      required this.state,
      required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(children: [
        _Chip(
            cs: cs,
            label: 'Workshop Settings & Quotas',
            bgColor: cs.surfaceContainerHigh,
            fgColor: cs.primary),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => context
              .push('/admin-central/partner/new'),
          icon:
              Icon(Icons.add, size: 16, color: cs.onPrimary),
          label: Text('Register Workshop',
              style: TextStyle(color: cs.onPrimary)),
          style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Registered Partner Workshops',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onSurface)),
      const SizedBox(height: 4),
      Text(
          '${state.partners.length} workshop(s) registered in the network.',
          style:
              TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      const SizedBox(height: 20),

      // Partner table
      if (state.isLoading)
        Center(
            child: CircularProgressIndicator(
                color: cs.primary))
      else if (state.partners.isEmpty)
        _InfoBox(
            cs: cs,
            icon: Icons.warehouse_outlined,
            title: 'No Workshops Registered',
            subtitle:
                'Use "Register Workshop" to onboard your first partner hub.')
      else
        Container(
          decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color:
                        cs.onSurface.withValues(alpha: 0.04),
                    blurRadius: 8)
              ]),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // Header
            Container(
              color: cs.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Row(children: [
                _TH(cs: cs, label: 'Workshop', flex: 4),
                _TH(cs: cs, label: 'Area', flex: 3),
                _TH(cs: cs, label: 'Tier', flex: 2),
                _TH(cs: cs, label: 'Active Jobs', flex: 2),
                _TH(cs: cs, label: 'Bay Cap.', flex: 2),
                _TH(cs: cs, label: 'Status', flex: 2),
                _TH(
                    cs: cs,
                    label: 'Actions',
                    flex: 2,
                    right: true),
              ]),
            ),
            ...state.partners.map((p) => Container(
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: cs.surfaceContainerHigh,
                              width: 1))),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                        flex: 4,
                        child: Row(children: [
                          Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                  color: cs.primaryContainer
                                      .withValues(alpha: 0.3),
                                  borderRadius:
                                      BorderRadius.circular(8)),
                              child: Icon(Icons.warehouse,
                                  size: 16,
                                  color: cs.primary)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                Text(p.shopName,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface)),
                                Text('ID: ${p.id.substring(0, 8)}...',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: cs.onSurfaceVariant,
                                        fontFamily: 'monospace')),
                              ])),
                        ])),
                    Expanded(
                        flex: 3,
                        child: Text(
                            p.serviceArea ?? '—',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface))),
                    Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius:
                                  BorderRadius.circular(4)),
                          child: Text(p.tier.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        )),
                    Expanded(
                        flex: 2,
                        child: Text('${p.activeVolume}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: p.activeVolume > 0
                                    ? cs.primary
                                    : cs.onSurfaceVariant))),
                    Expanded(
                        flex: 2,
                        child: Text(
                            p.bayCapacity != null
                                ? '${p.bayCapacity} bays'
                                : '—',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface))),
                    Expanded(
                        flex: 2,
                        child: Row(children: [
                          Switch(
                              value: p.isActive,
                              activeThumbColor: cs.primary,
                              onChanged: (v) => controller
                                  .togglePartnerStatus(
                                      p.id, v)),
                          const SizedBox(width: 4),
                          Text(
                              p.isActive
                                  ? 'Active'
                                  : 'Inactive',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: p.isActive
                                      ? const Color(0xFF059669)
                                      : cs.onSurfaceVariant)),
                        ])),
                    Expanded(
                        flex: 2,
                        child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              IconButton(
                                  icon: Icon(Icons.edit_outlined,
                                      size: 18,
                                      color: cs.onSurfaceVariant),
                                  tooltip: 'Edit',
                                  onPressed: () => context.push(
                                      '/admin-central/partner/${p.id}')),
                              IconButton(
                                  icon: Icon(Icons.bar_chart_rounded,
                                      size: 18,
                                      color: cs.onSurfaceVariant),
                                  tooltip: 'Analytics',
                                  onPressed: () {}),
                            ]))),
                  ]),
                )),
          ]),
        ),

      const SizedBox(height: 28),

      // Pending Applications
      if (state.pendingApplications.isNotEmpty) ...[
        Text('Pending Applications',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        const SizedBox(height: 12),
        ...state.pendingApplications.map((app) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                        color:
                            cs.onSurface.withValues(alpha: 0.04),
                        blurRadius: 4)
                  ]),
              child: Row(children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: cs.primaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.pending_outlined,
                        size: 20, color: cs.primary)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                      Text(app.shopName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                      Text(
                          '${app.ownerName} · ${app.phone} · ${app.address}',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant)),
                    ])),
                OutlinedButton(
                    onPressed: () => controller
                        .declinePartnerApplication(app.id),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cs.outline)),
                    child: Text('Reject',
                        style: TextStyle(
                            color: cs.onSurfaceVariant))),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                    onPressed: () => controller
                        .approvePartnerApplication(app.id),
                    icon: Icon(Icons.check_rounded,
                        size: 16,
                        color: cs.onPrimary),
                    label: Text('Approve',
                        style: TextStyle(color: cs.onPrimary)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(8)))),
              ]),
            )),
      ],
    ]);
  }
}

// ─── Assign Jobs Hub ──────────────────────────────────────────────────────────

class _AssignJobsContent extends ConsumerStatefulWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;

  const _AssignJobsContent(
      {required this.cs,
      required this.state,
      required this.controller});

  @override
  ConsumerState<_AssignJobsContent> createState() =>
      _AssignJobsContentState();
}

class _AssignJobsContentState
    extends ConsumerState<_AssignJobsContent> {
  final Set<String> _selected = {};

  ColorScheme get cs => widget.cs;
  AdminDashboardState get state => widget.state;
  AdminDashboardController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final jobs = state.assignJobsFiltered;
    final partners = state.partners
        .where((p) => p.isActive)
        .toList();

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      // Header
      Row(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          _Chip(
              cs: cs,
              label: 'Assign Jobs Hub',
              bgColor: cs.surfaceContainerHigh,
              fgColor: cs.primary),
          const SizedBox(height: 6),
          Text('Job Assignment & Dispatch Matrix',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          Text(
              '${jobs.length} job(s) matching filters · ${state.partners.length} active hub(s)',
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant)),
        ])),
        if (_selected.isNotEmpty)
          ElevatedButton.icon(
            onPressed: () => _showBulkAssignDialog(
                context, partners),
            icon: Icon(Icons.assignment_turned_in_rounded,
                size: 16, color: cs.onPrimary),
            label: Text(
                'Bulk Assign ${_selected.length} Jobs',
                style: TextStyle(color: cs.onPrimary)),
            style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
          ),
      ]),
      const SizedBox(height: 16),

      // Filter bar
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  blurRadius: 8)
            ]),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          // Assignment status
          _FilterChipGroup<AssignStatusFilter>(
            cs: cs,
            label: 'Status',
            options: const [
              (AssignStatusFilter.all, 'All'),
              (AssignStatusFilter.unassigned, 'Unassigned'),
              (AssignStatusFilter.assigned, 'Assigned'),
              (AssignStatusFilter.inProgress, 'In Progress'),
            ],
            selected: state.assignStatusFilter,
            onSelected: controller.setAssignStatusFilter,
          ),
          const SizedBox(width: 8),
          // Payment status
          _FilterChipGroup<PaymentStatusFilter>(
            cs: cs,
            label: 'Payment',
            options: const [
              (PaymentStatusFilter.all, 'All'),
              (PaymentStatusFilter.pending, 'Pending'),
              (PaymentStatusFilter.paid, 'Paid'),
              (PaymentStatusFilter.overdue, 'Overdue'),
            ],
            selected: state.assignPaymentFilter,
            onSelected: controller.setAssignPaymentFilter,
          ),
          const SizedBox(width: 8),
          // Date range
          OutlinedButton.icon(
            onPressed: () =>
                _pickDateRange(context),
            icon: Icon(Icons.date_range_outlined,
                size: 14, color: cs.onSurface),
            label: Text(
                state.assignDateFrom != null
                    ? '${DateFormat('d MMM').format(state.assignDateFrom!)} – ${state.assignDateTo != null ? DateFormat('d MMM').format(state.assignDateTo!) : '...'}'
                    : 'Date Range',
                style:
                    TextStyle(color: cs.onSurface, fontSize: 12)),
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.outline),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
          ),
          if (state.assignDateFrom != null)
            IconButton(
                icon: Icon(Icons.close,
                    size: 16, color: cs.onSurfaceVariant),
                onPressed: () => controller.setAssignDateRange(
                    null, null)),
        ]),
      ),
      const SizedBox(height: 16),

      // Table
      Container(
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  blurRadius: 8)
            ]),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // Table header with sort
          Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            child: Row(children: [
              SizedBox(
                  width: 36,
                  child: Checkbox(
                    value: _selected.length == jobs.length &&
                        jobs.isNotEmpty,
                    tristate: true,
                    activeColor: cs.primary,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.addAll(jobs.map((j) => j.id));
                      } else {
                        _selected.clear();
                      }
                    }),
                  )),
              _SortHeader(
                  cs: cs,
                  label: 'Job ID',
                  flex: 2,
                  field: AssignSortField.createdAt,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _SortHeader(
                  cs: cs,
                  label: 'Vehicle',
                  flex: 3,
                  field: AssignSortField.vehicle,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _SortHeader(
                  cs: cs,
                  label: 'Customer',
                  flex: 3,
                  field: AssignSortField.customerName,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _SortHeader(
                  cs: cs,
                  label: 'Assign Status',
                  flex: 3,
                  field: AssignSortField.assignStatus,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _SortHeader(
                  cs: cs,
                  label: 'Payment',
                  flex: 2,
                  field: AssignSortField.paymentStatus,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _TH(
                  cs: cs,
                  label: 'Assign To',
                  flex: 3,
                  right: true),
            ]),
          ),

          if (state.isLoading)
            Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                    child: CircularProgressIndicator(
                        color: cs.primary)))
          else if (jobs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text('No jobs match the current filters.',
                      style: TextStyle(
                          color: cs.onSurfaceVariant))),
            )
          else
            ...jobs.map((j) => _AssignRow(
                  cs: cs,
                  job: j,
                  partners: partners,
                  isSelected: _selected.contains(j.id),
                  onToggleSelect: () => setState(() {
                    if (_selected.contains(j.id)) {
                      _selected.remove(j.id);
                    } else {
                      _selected.add(j.id);
                    }
                  }),
                  onAssign: (partnerId, partnerName) =>
                      controller.assignJobToPartner(
                          j.id, partnerId, partnerName),
                  onUnassign: () =>
                      controller.unassignJob(j.id),
                )),
        ]),
      ),
    ]);
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate:
          DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDateRange: state.assignDateFrom != null
          ? DateTimeRange(
              start: state.assignDateFrom!,
              end: state.assignDateTo ??
                  DateTime.now())
          : null,
    );
    if (range != null) {
      controller.setAssignDateRange(
          range.start, range.end);
    }
  }

  void _showBulkAssignDialog(
      BuildContext context, List<PartnerCrmNode> partners) {
    showDialog(
      context: context,
      builder: (ctx) {
        String? selectedId;
        String? selectedName;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor:
                cs.surfaceContainerLowest,
            title: Text(
                'Bulk Assign ${_selected.length} Jobs',
                style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700)),
            content: DropdownButtonFormField<String>(
              decoration: InputDecoration(
                  labelText: 'Select Workshop',
                  labelStyle: TextStyle(
                      color: cs.onSurfaceVariant)),
              items: partners
                  .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.shopName,
                          style: TextStyle(
                              color: cs.onSurface))))
                  .toList(),
              onChanged: (v) {
                selectedId = v;
                selectedName = partners
                    .firstWhere((p) => p.id == v)
                    .shopName;
              },
            ),
            actions: [
              TextButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(),
                  child: Text('Cancel',
                      style: TextStyle(
                          color: cs.onSurfaceVariant))),
              ElevatedButton(
                onPressed: () async {
                  if (selectedId == null) return;
                  for (final id in _selected) {
                    await controller.assignJobToPartner(
                        id, selectedId!, selectedName!);
                  }
                  setState(() => _selected.clear());
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary),
                child: Text('Assign All',
                    style:
                        TextStyle(color: cs.onPrimary)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AssignRow extends StatelessWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  final List<PartnerCrmNode> partners;
  final bool isSelected;
  final VoidCallback onToggleSelect;
  final Future<void> Function(String id, String name) onAssign;
  final VoidCallback onUnassign;

  const _AssignRow(
      {required this.cs,
      required this.job,
      required this.partners,
      required this.isSelected,
      required this.onToggleSelect,
      required this.onAssign,
      required this.onUnassign});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
              bottom: BorderSide(
                  color: cs.surfaceContainerHigh, width: 1))),
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(
            width: 36,
            child: Checkbox(
              value: isSelected,
              activeColor: cs.primary,
              onChanged: (_) => onToggleSelect(),
            )),
        // Job ID
        Expanded(
            flex: 2,
            child: Text('#${job.id}',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface,
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis)),
        // Vehicle
        Expanded(
            flex: 3,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                  job.carIdentity.contains('-')
                      ? job.carIdentity
                          .split('-')
                          .first
                          .trim()
                      : job.carIdentity,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                  overflow: TextOverflow.ellipsis),
              if (job.carIdentity.contains('-'))
                Text(
                    job.carIdentity
                        .split('-')
                        .last
                        .trim(),
                    style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant)),
            ])),
        // Customer
        Expanded(
            flex: 3,
            child: Text(job.customerName,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface),
                overflow: TextOverflow.ellipsis)),
        // Assign status
        Expanded(
            flex: 3,
            child: job.isUnassigned
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: cs.secondaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius:
                            BorderRadius.circular(20)),
                    child: Text('UNASSIGNED',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onSecondaryContainer)))
                : Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                    Text(job.partnerName,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.primary),
                        overflow: TextOverflow.ellipsis),
                    Text(_statusLabel(job.status),
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant)),
                  ])),
        // Payment
        Expanded(
            flex: 2,
            child: Text(
                job.isPaid ? 'PAID' : 'PENDING',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: job.isPaid
                        ? const Color(0xFF059669)
                        : cs.onSurfaceVariant))),
        // Assign to
        Expanded(
            flex: 3,
            child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  if (!job.isUnassigned)
                    TextButton(
                        onPressed: onUnassign,
                        child: Text('Unassign',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.error))),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: cs.outline)),
                        hintText: 'Assign to...',
                        hintStyle: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant),
                      ),
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface),
                      value: job.partnerId,
                      items: partners
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.shopName,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurface)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          final name = partners
                              .firstWhere((p) => p.id == v)
                              .shopName;
                          onAssign(v, name);
                        }
                      },
                    ),
                  ),
                ]))),
      ]),
    );
  }

  String _statusLabel(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty
          ? ''
          : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _SortHeader extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final int flex;
  final AssignSortField field;
  final AssignSortField current;
  final bool asc;
  final ValueChanged<AssignSortField> onSort;

  const _SortHeader(
      {required this.cs,
      required this.label,
      required this.flex,
      required this.field,
      required this.current,
      required this.asc,
      required this.onSort});

  @override
  Widget build(BuildContext context) {
    final isActive = current == field;
    return Expanded(
        flex: flex,
        child: GestureDetector(
            onTap: () => onSort(field),
            child: Row(children: [
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      letterSpacing: 0.5)),
              if (isActive)
                Icon(
                    asc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 12,
                    color: cs.primary),
            ])));
  }
}

class _FilterChipGroup<T> extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  const _FilterChipGroup(
      {required this.cs,
      required this.label,
      required this.options,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label:',
          style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600)),
      const SizedBox(width: 4),
      ...options.map((o) {
        final isSelected = selected == o.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: GestureDetector(
            onTap: () => onSelected(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primaryContainer
                          .withValues(alpha: 0.4)
                      : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: isSelected
                          ? cs.primary
                          : cs.outline.withValues(alpha: 0.3))),
              child: Text(o.$2,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: isSelected
                          ? cs.primary
                          : cs.onSurface)),
            ),
          ),
        );
      }),
    ]);
  }
}

// ─── Partner & Hub Management ─────────────────────────────────────────────────

class _PartnerHubContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;
  const _PartnerHubContent(
      {required this.cs,
      required this.state,
      required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      _Chip(
          cs: cs,
          label: 'Partner & Hub Management',
          bgColor: cs.surfaceContainerHigh,
          fgColor: cs.primary),
      const SizedBox(height: 6),
      Text('Partner Network CRM',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onSurface)),
      const SizedBox(height: 20),

      // Sub-tabs
      DefaultTabController(
        length: 2,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          TabBar(
            isScrollable: true,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            tabs: const [
              Tab(text: 'Active Partner Workshops'),
              Tab(text: 'Commlink & Messages'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 600,
            child: TabBarView(children: [
              // Tab 1: Active Partners
              Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                ...state.partners.isEmpty
                    ? [
                        _InfoBox(
                            cs: cs,
                            icon: Icons.warehouse_outlined,
                            title: 'No Active Partners',
                            subtitle:
                                'Register workshops in Workshop Settings.')
                      ]
                    : state.partners.map((p) => Container(
                          margin:
                              const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                              color: cs.surfaceContainerLowest,
                              borderRadius:
                                  BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                    color: cs.onSurface
                                        .withValues(alpha: 0.04),
                                    blurRadius: 4)
                              ]),
                          child: ListTile(
                            onTap: () => context.push(
                                '/admin-central/partner/${p.id}'),
                            leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: p.isActive
                                        ? cs.primaryContainer
                                            .withValues(alpha: 0.3)
                                        : cs.surfaceContainerHigh,
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                child: Icon(Icons.warehouse,
                                    color: p.isActive
                                        ? cs.primary
                                        : cs.onSurfaceVariant)),
                            title: Text(p.shopName,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface)),
                            subtitle: Text(
                                '${p.tier.toUpperCase()} · ${p.activeVolume} active · ${p.avgVelocityDays}d avg',
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        cs.onSurfaceVariant)),
                            trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              if (p.unreadMessageCount > 0)
                                Container(
                                    margin: const EdgeInsets
                                        .only(right: 8),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2),
                                    decoration: BoxDecoration(
                                        color: cs.primary,
                                        borderRadius:
                                            BorderRadius.circular(
                                                10)),
                                    child: Text(
                                        '${p.unreadMessageCount}',
                                        style: TextStyle(
                                            color: cs.onPrimary,
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight.w700))),
                              Switch(
                                  value: p.isActive,
                                  activeThumbColor: cs.primary,
                                  onChanged: (v) => controller
                                      .togglePartnerStatus(
                                          p.id, v)),
                            ]),
                          ),
                        )),
              ]),
              // Tab 2: Commlink
              _InfoBox(
                  cs: cs,
                  icon: Icons.forum_outlined,
                  title: 'Partner Commlink',
                  subtitle:
                      'Open a partner profile to access the direct message channel.'),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

// ─── Customer CRM ─────────────────────────────────────────────────────────────

class _CustomerCrmContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  const _CustomerCrmContent(
      {required this.cs, required this.state});

  void _showCustomerDetail(BuildContext context, CustomerCrmNode c) {
    final supabase = Supabase.instance.client;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => FutureBuilder<List<Map<String, dynamic>>>(
          future: supabase
              .from('repair_jobs')
              .select('''
                id, status, created_at, final_price,
                vehicles:vehicle_id (make, model, license_plate),
                partners:partner_id (shop_name)
              ''')
              .eq('customer_id', c.id)
              .order('created_at', ascending: false),
          builder: (ctx, snap) {
            final jobs = snap.data ?? [];
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(24),
              children: [
                // Header
                Row(children: [
                  Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: cs.primary, shape: BoxShape.circle),
                      child: Icon(Icons.person_rounded,
                          color: cs.onPrimary, size: 26)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(c.fullName,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                      Text(c.email,
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  IconButton(
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const Divider(height: 28),
                // Contact info
                _InfoRow(cs: cs, label: 'Phone', value: c.phone),
                _InfoRow(cs: cs, label: 'Customer ID', value: c.id),
                const SizedBox(height: 20),
                // Jobs header
                Text('Repair History',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(height: 10),
                if (snap.connectionState == ConnectionState.waiting)
                  Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                              color: cs.primary)))
                else if (jobs.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No repair jobs found.',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant)))
                else
                  ...jobs.map((job) {
                    final v = job['vehicles'] as Map<String, dynamic>? ?? {};
                    final p = job['partners'] as Map<String, dynamic>? ?? {};
                    final status = job['status']?.toString() ?? '';
                    final price = job['final_price'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: cs.outlineVariant.withValues(
                                  alpha: 0.5))),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            Text(
                                '${v['make'] ?? ''} ${v['model'] ?? ''} · ${v['license_plate'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface)),
                            const SizedBox(height: 2),
                            Text(
                                p['shop_name']?.toString() ??
                                    'Unassigned',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant)),
                          ]),
                        ),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                          _StatusChip(status: status, cs: cs),
                          if (price != null) ...[
                            const SizedBox(height: 4),
                            Text(
                                'Rp ${NumberFormat('#,###').format(price)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary)),
                          ]
                        ]),
                      ]),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Text('Customer Database',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onSurface)),
      const SizedBox(height: 6),
      Text('${state.customers.length} registered customers',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      const SizedBox(height: 20),
      ...state.customers.map((c) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: cs.onSurface.withValues(alpha: 0.04),
                      blurRadius: 4)
                ]),
            child: ListTile(
              onTap: () => _showCustomerDetail(context, c),
              hoverColor: cs.primary.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              leading: CircleAvatar(
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                  child: Text(
                      c.fullName.isNotEmpty
                          ? c.fullName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.primary))),
              title: Text(c.fullName,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              subtitle: Text('${c.email} · ${c.phone}',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant)),
              trailing: Icon(Icons.chevron_right,
                  color: cs.onSurfaceVariant, size: 18),
            ),
          )),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String value;
  const _InfoRow(
      {required this.cs, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface))),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final ColorScheme cs;
  const _StatusChip({required this.status, required this.cs});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      '1_intake' => 'Intake',
      '2_estimated' => 'Estimated',
      '3_booked' => 'Booked',
      '4_paid' => 'Paid',
      '5_scheduled' => 'Scheduled',
      '6_in_progress' => 'In Progress',
      '7_finished' => 'Finished',
      '8_awaiting_delivery' => 'Awaiting',
      '9_done' || 'completed' => 'Done',
      _ => status,
    };
    final color = switch (status) {
      '6_in_progress' => const Color(0xFF0ea5e9),
      '7_finished' || '8_awaiting_delivery' => const Color(0xFFf59e0b),
      '9_done' || 'completed' => const Color(0xFF10b981),
      _ => cs.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}


// ─── Placeholder ──────────────────────────────────────────────────────────────

class _PlaceholderContent extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String? subtitle;
  final IconData? icon;
  const _PlaceholderContent(
      {required this.cs, required this.label, this.subtitle, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
        Icon(icon ?? Icons.construction_rounded,
            size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(label,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        const SizedBox(height: 8),
        Text(subtitle ?? 'This section is under construction.',
            style: TextStyle(
                fontSize: 14, color: cs.onSurfaceVariant)),
      ])),
    );
  }
}

// ─── Verification Modal ───────────────────────────────────────────────────────

class _VerificationModal extends StatefulWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  final VoidCallback onClose;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  const _VerificationModal(
      {required this.cs,
      required this.job,
      required this.onClose,
      required this.onApprove,
      required this.onReject});

  @override
  State<_VerificationModal> createState() =>
      _VerificationModalState();
}

class _VerificationModalState
    extends State<_VerificationModal> {
  bool _notifyWA = true;
  bool _approving = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final job = widget.job;
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 960,
              margin: const EdgeInsets.all(24),
              constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.of(context).size.height *
                          0.9),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color:
                            Colors.black.withValues(alpha: 0.2),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ]),
              child: Column(mainAxisSize: MainAxisSize.min,
                  children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color:
                                  cs.surfaceContainerHigh))),
                  child: Row(children: [
                    Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: cs.primary
                                .withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(8)),
                        child: Icon(Icons.verified_outlined,
                            color: cs.primary, size: 22)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                      Row(children: [
                        Text(
                            'Manual Payment Proof Verification',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface)),
                        const SizedBox(width: 8),
                        Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: cs.surfaceContainerHigh,
                                borderRadius:
                                    BorderRadius.circular(4)),
                            child: Text('#${job.id}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                    fontFamily: 'monospace'))),
                      ]),
                      Text(
                          'Customer: ${job.customerName}  ·  ${job.carIdentity}',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant)),
                    ])),
                    IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: cs.onSurfaceVariant),
                        onPressed: widget.onClose),
                  ]),
                ),
                Flexible(
                    child: SingleChildScrollView(
                        child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                    Expanded(
                        child:
                            _BcaSlip(cs: cs, job: job)),
                    const SizedBox(width: 24),
                    Expanded(
                        child: _ReconcilerPanel(
                            cs: cs,
                            notifyWA: _notifyWA,
                            onToggle: (v) => setState(
                                () => _notifyWA = v))),
                  ]),
                ))),
                Container(
                  padding: const EdgeInsets.fromLTRB(
                      24, 12, 24, 20),
                  decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(
                              color:
                                  cs.surfaceContainerHigh))),
                  child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.end,
                      children: [
                    OutlinedButton.icon(
                      onPressed: _rejecting
                          ? null
                          : () async {
                              setState(
                                  () => _rejecting = true);
                              await widget.onReject();
                              setState(
                                  () => _rejecting = false);
                            },
                      icon: _rejecting
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onSurface))
                          : Icon(Icons.rule_rounded,
                              size: 16, color: cs.onSurface),
                      label: Text(
                          'Reject / Request Re-upload',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface)),
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cs.outline),
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(8))),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _approving
                          ? null
                          : () async {
                              setState(
                                  () => _approving = true);
                              await widget.onApprove();
                              setState(
                                  () => _approving = false);
                            },
                      icon: _approving
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary))
                          : Icon(Icons.lock_rounded,
                              size: 16, color: cs.onPrimary),
                      label: Text(
                          'Approve Payment & Dispatch to Workshop',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimary)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(8)),
                          elevation: 2),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _BcaSlip extends StatelessWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  const _BcaSlip({required this.cs, required this.job});

  List<Widget> _row(String label, String value,
          {bool hl = false, bool grn = false}) =>
      [
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant)),
              const SizedBox(width: 12),
              Flexible(
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hl
                              ? cs.primary
                              : grn
                                  ? const Color(0xFF059669)
                                  : cs.onSurface,
                          fontFamily: 'monospace'),
                      textAlign: TextAlign.right)),
            ])),
        Divider(height: 1, color: cs.surfaceContainer),
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        Text('UPLOADED SLIP RAW VIEWPORT',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.8)),
        Row(children: [
          Icon(Icons.fingerprint_rounded,
              color: cs.primary, size: 14),
          const SizedBox(width: 4),
          Text('SHA256: a8f9..43c2',
              style: TextStyle(
                  fontSize: 11,
                  color: cs.primary,
                  fontFamily: 'monospace')),
        ]),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  blurRadius: 8)
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFF003087),
                      borderRadius:
                          BorderRadius.circular(4)),
                  child: const Text('BCA',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: -0.5))),
              const SizedBox(width: 8),
              Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: const [
                Text('m-Transfer',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF1e3a5f))),
                Text('BERHASIL / SUCCESS',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                        letterSpacing: 0.5)),
              ]),
            ]),
            Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
              Text('12/09/2026',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace')),
              Text('09:12:04 WIB',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace')),
            ]),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              Text('JUMLAH TRANSFER (TOTAL AMOUNT)',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.8)),
              const SizedBox(height: 4),
              Text(
                  job.finalPrice != null
                      ? 'Rp ${NumberFormat('#,###', 'id_ID').format(job.finalPrice)}'
                      : 'Rp —',
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1c1b1c),
                      height: 1.0)),
              const SizedBox(height: 4),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                Icon(Icons.check_circle_outline,
                    size: 14,
                    color: Color(0xFF059669)),
                SizedBox(width: 4),
                Text('Admin Fee Included (Rp 0)',
                    style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF059669))),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          ..._row('Dari Rekening:', job.customerName),
          ..._row('Penerima:',
              'PT REVIVE OTOMOTIF\n8830-192-381'),
          ..._row('No. Referensi:', '#${job.id}', hl: true),
          ..._row('Engine Routing:',
              'BCA SWITCHING ENGINE: OK',
              grn: true),
          const SizedBox(height: 12),
          Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
            Row(children: [
              Icon(Icons.document_scanner_outlined,
                  color: cs.primary, size: 16),
              const SizedBox(width: 6),
              Text('Vision OCR Confidence',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ]),
            Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('99.4% Match',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                        fontFamily: 'monospace'))),
          ]),
        ]),
      ),
    ]);
  }
}

class _ReconcilerPanel extends StatelessWidget {
  final ColorScheme cs;
  final bool notifyWA;
  final ValueChanged<bool> onToggle;
  const _ReconcilerPanel(
      {required this.cs,
      required this.notifyWA,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        Text('AUTOMATED RECONCILER DIAGNOSTICS',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.8)),
        _Chip(
            cs: cs,
            label: '3 of 3 Rules Met',
            bgColor: cs.surfaceContainerHigh,
            fgColor: cs.onSurface),
      ]),
      const SizedBox(height: 12),
      _Check(
          cs: cs,
          title: 'Payable Total Match',
          subtitle:
              'System Due: Rp 3.575.000  ·  Slip: Rp 3.575.000',
          badge: 'EXACT MATCH'),
      const SizedBox(height: 8),
      _Check(
          cs: cs,
          title: 'Beneficiary Destination',
          subtitle: 'BCA 8830-192-381  PT Revive Otomotif',
          badge: 'REVIVE ACCT'),
      const SizedBox(height: 8),
      _Check(
          cs: cs,
          title: 'Target Workshop Reservation',
          subtitle: 'Hub Bay 04  ·  Confirmed',
          badge: 'RESERVED'),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color:
                      cs.onSurface.withValues(alpha: 0.06),
                  blurRadius: 4)
            ]),
        child: Row(children: [
          Icon(Icons.chat_bubble_outline_rounded,
              color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
            Text('Customer Notification Bridge',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            Text(
                'Send instant WhatsApp confirmation with digital valet slip',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant)),
          ])),
          Switch(
              value: notifyWA,
              activeThumbColor: cs.primary,
              onChanged: onToggle),
        ]),
      ),
    ]);
  }
}

class _Check extends StatelessWidget {
  final ColorScheme cs;
  final String title, subtitle, badge;
  const _Check(
      {required this.cs,
      required this.title,
      required this.subtitle,
      required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: cs.onSurface.withValues(alpha: 0.04),
                blurRadius: 4)
          ]),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF059669), size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 11, color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(width: 8),
        Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4)),
            child: Text(badge,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                    letterSpacing: 0.5))),
      ]),
    );
  }
}

// ─── Info Box ─────────────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String title, subtitle;
  const _InfoBox(
      {required this.cs,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(icon, size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(
                fontSize: 13, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ─── Shared micro-widgets ─────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final Color bgColor, fgColor;
  const _Chip(
      {required this.cs,
      required this.label,
      required this.bgColor,
      required this.fgColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fgColor)),
      );
}

class _KpiCard extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label, value;
  final bool highlight;
  const _KpiCard(
      {required this.cs,
      required this.icon,
      required this.label,
      required this.value,
      this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color:
                      cs.onSurface.withValues(alpha: 0.06),
                  blurRadius: 6)
            ]),
        child: Row(children: [
          Icon(icon,
              size: 18,
              color: highlight
                  ? cs.primary
                  : cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant)),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: highlight
                        ? cs.primary
                        : cs.onSurface,
                    fontFamily: 'monospace')),
          ]),
        ]),
      );
}

class _TH extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final int flex;
  final bool right;
  const _TH(
      {required this.cs,
      required this.label,
      required this.flex,
      this.right = false});

  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5),
            textAlign:
                right ? TextAlign.right : TextAlign.left),
      );
}

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
      width: 8,
      height: 8,
      decoration:
          BoxDecoration(color: color, shape: BoxShape.circle));
}