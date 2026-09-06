import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'admin_dashboard_controller.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String? route;
  const _NavItem(this.label, this.icon, {this.route});
}

const _navItems = [
  _NavItem('Job Board / Pipeline', Icons.view_kanban_outlined),
  _NavItem('Workshop Settings & Quotas', Icons.tune_outlined),
  _NavItem('Master Matrix (Admin)', Icons.grid_view_outlined),
  _NavItem('Customer Inquiries & Commlink', Icons.forum_outlined),
  _NavItem('Analytics & Telemetry', Icons.speed_outlined),
  _NavItem('System Settings', Icons.settings_outlined),
  _NavItem('Assign Jobs Hub', Icons.assignment_outlined, route: '/admin-central/assign'),
];

class MasterAdminDesktop extends ConsumerStatefulWidget {
  const MasterAdminDesktop({super.key});
  @override
  ConsumerState<MasterAdminDesktop> createState() => _MasterAdminDesktopState();
}

class _MasterAdminDesktopState extends ConsumerState<MasterAdminDesktop> {
  int _activeNavIndex = 2;
  AdminJobNode? _verifyingJob;

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
              _Sidebar(cs: cs, activeIndex: _activeNavIndex, onNav: (i, route) { if (route != null) { context.push(route); } else { setState(() => _activeNavIndex = i); } }, onExit: () => context.go('/')),
              Expanded(child: Column(children: [
                _TopHeader(cs: cs, state: state, ref: ref),
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: _buildContent(cs, state, controller))),
              ])),
            ],
          ),
          if (_verifyingJob != null)
            _VerificationModal(
              cs: cs, job: _verifyingJob!,
              onClose: () => setState(() => _verifyingJob = null),
              onApprove: () async {
                await controller.overrideJobStatus(_verifyingJob!.id, 'completed');
                setState(() => _verifyingJob = null);
              },
              onReject: () async {
                await controller.overrideJobStatus(_verifyingJob!.id, '3_booked');
                setState(() => _verifyingJob = null);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, AdminDashboardState state, AdminDashboardController controller) {
    switch (_activeNavIndex) {
      case 0: case 2: return _OpsMatrixContent(cs: cs, state: state, controller: controller, onVerify: (job) => setState(() => _verifyingJob = job));
      case 3: return _PartnerCmsContent(cs: cs, state: state, controller: controller);
      case 4: return _CustomerCrmContent(cs: cs, state: state);
      default: return _PlaceholderContent(cs: cs, label: _navItems[_activeNavIndex].label);
    }
  }
}
// ─── Sidebar ─────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final ColorScheme cs;
  final int activeIndex;
  final void Function(int, String?) onNav;
  final VoidCallback onExit;
  const _Sidebar({required this.cs, required this.activeIndex, required this.onNav, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 288,
      color: cs.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 64, padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.shield_rounded, color: cs.primary, size: 28),
              const SizedBox(width: 10),
              Text('REVIVE', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 0.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
                child: Text('OPS CORE', style: TextStyle(color: cs.primary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Active Operational Hub', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.warehouse_outlined, color: cs.primary, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Hub #04 - Kebon Jeruk', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
                  Icon(Icons.unfold_more, color: cs.onSurfaceVariant, size: 16),
                ]),
              ]),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(children: [
                ...List.generate(_navItems.length, (i) {
                  final item = _navItems[i];
                  final isActive = i == activeIndex && item.route == null;
                  return _SidebarNavItem(cs: cs, icon: item.icon, label: item.label, isActive: isActive, onTap: () => onNav(i, item.route));
                }),
                const Spacer(),
                _SidebarNavItem(cs: cs, icon: Icons.arrow_back_rounded, label: 'Exit Central', isActive: false, onTap: onExit),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: cs.surfaceContainerLow,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Core Telemetry', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.8)),
                Text('v4.18.2', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const _PulseDot(color: Color(0xFF10b981)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Active Sync: OK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface))),
                  Text('34ms', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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
  final VoidCallback onTap;
  const _SidebarNavItem({required this.cs, required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: isActive ? cs.primaryContainer.withValues(alpha: 0.3) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, size: 18, color: isActive ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? cs.primary : cs.onSurfaceVariant))),
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
  const _TopHeader({required this.cs, required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 64, color: cs.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Container(
            height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                style: TextStyle(fontSize: 14, color: cs.onSurface),
                decoration: InputDecoration(border: InputBorder.none, hintText: 'Search VIN, license plate, or order ID...', hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14), isDense: true),
              )),
            ]),
          ),
        ),
        const SizedBox(width: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const _PulseDot(color: Color(0xFF10b981)),
            const SizedBox(width: 6),
            Text('NODE 04: LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
          ]),
        ),
        const SizedBox(width: 8),
        Stack(children: [
          IconButton(icon: Icon(Icons.notifications_outlined, color: cs.onSurface), onPressed: () {}),
          Positioned(top: 8, right: 8, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle, border: Border.all(color: cs.surfaceContainerLowest, width: 1.5)))),
        ]),
        IconButton(
          icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: cs.onSurface),
          tooltip: 'Toggle Theme',
          onPressed: () => ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark,
        ),
        const SizedBox(width: 8),
        Row(children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Arya Pratama', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface, height: 1.2)),
            Text('Chief Dispatcher', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.2)),
          ]),
          const SizedBox(width: 10),
          Container(width: 32, height: 32, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle), child: Icon(Icons.person_rounded, color: cs.onPrimary, size: 18)),
        ]),
      ]),
    );
  }
}
// ─── Ops Matrix ───────────────────────────────────────────────────────────────

class _OpsMatrixContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;
  final void Function(AdminJobNode) onVerify;
  const _OpsMatrixContent({required this.cs, required this.state, required this.controller, required this.onVerify});

  @override
  Widget build(BuildContext context) {
    final pendingJobs = state.activeJobs.where((j) => j.status == '3_booked' || j.status == 'manual_verification_pending').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Chip(cs: cs, label: 'Master Ops Matrix', bgColor: cs.surfaceContainerHigh, fgColor: cs.primary),
            const SizedBox(width: 8),
            Text('BCA / VA Liquidity Gateway Live', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          ]),
          const SizedBox(height: 6),
          Text('Active Financial Clearing & Dispatch Matrix', style: TextStyle(color: cs.onSurface, fontSize: 22, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(width: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _KpiCard(cs: cs, icon: Icons.account_balance_outlined, label: 'Daily Vault Settlement', value: 'Rp 148.920.000'),
          _KpiCard(cs: cs, icon: Icons.hourglass_top_rounded, label: 'Unreconciled Slips', value: ' Action Required', highlight: pendingJobs.isNotEmpty),
          OutlinedButton.icon(
            onPressed: () {},
            icon: Icon(Icons.history_rounded, size: 16, color: cs.onSurface),
            label: Text('Gateway Audit', style: TextStyle(color: cs.onSurface, fontSize: 13)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: cs.outline), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ]),
      ]),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.04), blurRadius: 8)]),
        child: Row(children: [
          Expanded(child: Container(
            height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.filter_list_rounded, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Status: Pending Verification', style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ]),
          )),
          const SizedBox(width: 8),
          _Chip(cs: cs, label: 'Hub 04  x', bgColor: cs.surfaceContainerLow, fgColor: cs.onSurfaceVariant),
          const Spacer(),
          const _PulseDot(color: Color(0xFF10b981)),
          const SizedBox(width: 6),
          Text('Auto-Refresh in 14s', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(width: 12),
          IconButton(icon: Icon(Icons.download_rounded, color: cs.onSurfaceVariant, size: 20), tooltip: 'Export', onPressed: () {}),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.04), blurRadius: 8)]),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              _TH(cs: cs, label: 'Job ID', flex: 2),
              _TH(cs: cs, label: 'Vehicle & Plate', flex: 3),
              _TH(cs: cs, label: 'Owner & Comms', flex: 3),
              _TH(cs: cs, label: 'Assigned Hub', flex: 3),
              _TH(cs: cs, label: 'Scope', flex: 2),
              _TH(cs: cs, label: 'Total Payable', flex: 2),
              _TH(cs: cs, label: 'Reconciliation', flex: 3),
              _TH(cs: cs, label: 'Action', flex: 2, right: true),
            ]),
          ),
          if (state.activeJobs.isEmpty && !state.isLoading)
            _SampleRows(cs: cs, onVerify: onVerify)
          else
            ...state.activeJobs.map((j) => _JobRow(cs: cs, job: j, onVerify: () => onVerify(j))),
          if (state.isLoading)
            Padding(padding: const EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: cs.primary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: cs.surfaceContainerLow,
            child: Row(children: [
              const _PulseDot(color: Color(0xFF10b981)),
              const SizedBox(width: 6),
              Text('BCA Settlement Webhook: ', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              Text('200 OK (0.12s latency)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              _PB(cs: cs, label: '<- Prev', enabled: false),
              const SizedBox(width: 4),
              _PB(cs: cs, label: '1', active: true),
              const SizedBox(width: 4),
              _PB(cs: cs, label: '2'),
              const SizedBox(width: 4),
              _PB(cs: cs, label: '3'),
              const SizedBox(width: 4),
              _PB(cs: cs, label: 'Next ->'),
            ]),
          ),
        ]),
      ),
    ]);
  }
}
class _SampleRows extends StatelessWidget {
  final ColorScheme cs;
  final void Function(AdminJobNode) onVerify;
  const _SampleRows({required this.cs, required this.onVerify});

  @override
  Widget build(BuildContext context) {
    final jobs = [
      AdminJobNode(id: 'JB-03537083', customerName: 'Budi Wicaksono', carIdentity: 'Toyota Innova Zenix - B 1984 REV', status: 'manual_verification_pending', partnerName: 'Revive Hub 04 - Kebon Jeruk', createdAt: DateTime.now().subtract(const Duration(hours: 2)), lastUpdatedAt: DateTime.now().subtract(const Duration(minutes: 30))),
      AdminJobNode(id: 'JB-03536644', customerName: 'Hendri Kusuma', carIdentity: 'Mitsubishi Pajero Dakar - B 1888 SUV', status: 'completed', partnerName: 'Revive Hub 09 - Kelapa Gading', createdAt: DateTime.now().subtract(const Duration(days: 1)), lastUpdatedAt: DateTime.now().subtract(const Duration(hours: 6))),
      AdminJobNode(id: 'JB-03536502', customerName: 'Clara Sutedja', carIdentity: 'Wuling Air EV Long - B 2441 KLL', status: 'overdue', partnerName: 'Revive Hub 04 - Kebon Jeruk', createdAt: DateTime.now().subtract(const Duration(days: 3)), lastUpdatedAt: DateTime.now().subtract(const Duration(days: 2))),
    ];
    return Column(children: jobs.map((j) => _JobRow(cs: cs, job: j, onVerify: () => onVerify(j))).toList());
  }
}

class _JobRow extends StatelessWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  final VoidCallback onVerify;
  const _JobRow({required this.cs, required this.job, required this.onVerify});

  bool get _pending => job.status == '3_booked' || job.status == 'manual_verification_pending';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: _pending ? cs.primary.withValues(alpha: 0.05) : Colors.transparent, border: Border(bottom: BorderSide(color: cs.surfaceContainerHigh, width: 1))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(flex: 2, child: Row(children: [
          if (_pending) Container(width: 3, height: 20, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2))),
          Expanded(child: Text('#', style: TextStyle(fontSize: 12, fontWeight: _pending ? FontWeight.w700 : FontWeight.w400, color: _pending ? cs.primary : cs.onSurface, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
        ])),
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(job.carIdentity.split('-').first.trim(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
          if (job.carIdentity.contains('-')) Text(job.carIdentity.split('-').last.trim(), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
        ])),
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(job.customerName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
          Text(' elapsed', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ])),
        Expanded(flex: 3, child: Row(children: [
          Icon(Icons.warehouse_outlined, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Expanded(child: Text(job.partnerName, style: TextStyle(fontSize: 12, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
        ])),
        Expanded(flex: 2, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
          child: Text('See details', style: TextStyle(fontSize: 11, color: cs.onSurface)),
        )),
        Expanded(flex: 2, child: Text('--', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface, fontFamily: 'monospace'))),
        Expanded(flex: 3, child: _StatusBadge(cs: cs, status: job.status)),
        Expanded(flex: 2, child: Align(
          alignment: Alignment.centerRight,
          child: _pending
              ? ElevatedButton.icon(onPressed: onVerify, icon: Icon(Icons.visibility_outlined, size: 14, color: cs.onPrimary), label: Text('Review Slip', style: TextStyle(fontSize: 11, color: cs.onPrimary)), style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap))
              : IconButton(icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant, size: 18), onPressed: () {}),
        )),
      ]),
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
      case 'manual_verification_pending': case '3_booked':
        bg = cs.primary.withValues(alpha: 0.1); fg = cs.primary; label = 'Pending Verification'; icon = Icons.circle;
      case 'completed':
        bg = const Color(0xFF10b981).withValues(alpha: 0.15); fg = const Color(0xFF059669); label = 'PAID & VERIFIED'; icon = Icons.check_circle_outline;
      case 'overdue':
        bg = cs.secondaryContainer.withValues(alpha: 0.3); fg = cs.onSecondaryContainer; label = 'PAYMENT OVERDUE'; icon = Icons.warning_amber_rounded;
      default:
        bg = cs.surfaceContainerHigh; fg = cs.onSurfaceVariant; label = status.replaceAll('_', ' ').toUpperCase(); icon = Icons.radio_button_unchecked;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: fg),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg), overflow: TextOverflow.ellipsis)),
      ]),
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
  const _VerificationModal({required this.cs, required this.job, required this.onClose, required this.onApprove, required this.onReject});

  @override
  State<_VerificationModal> createState() => _VerificationModalState();
}

class _VerificationModalState extends State<_VerificationModal> {
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
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
              decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 24, offset: const Offset(0, 8))]),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.surfaceContainerHigh))),
                  child: Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.verified_outlined, color: cs.primary, size: 22)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('Manual Payment Proof Verification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: cs.onSurface)),
                        const SizedBox(width: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)), child: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary, fontFamily: 'monospace'))),
                      ]),
                      Text('Customer:   -  ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ])),
                    IconButton(icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant), onPressed: widget.onClose),
                  ]),
                ),
                Flexible(child: SingleChildScrollView(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _BcaSlip(cs: cs, job: job)),
                    const SizedBox(width: 24),
                    Expanded(child: _ReconcilerPanel(cs: cs, notifyWA: _notifyWA, onToggle: (v) => setState(() => _notifyWA = v))),
                  ]),
                ))),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.surfaceContainerHigh))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    OutlinedButton.icon(
                      onPressed: _rejecting ? null : () async { setState(() => _rejecting = true); await widget.onReject(); setState(() => _rejecting = false); },
                      icon: _rejecting ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface)) : Icon(Icons.rule_rounded, size: 16, color: cs.onSurface),
                      label: Text('Reject / Request Re-upload', style: TextStyle(fontSize: 13, color: cs.onSurface)),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: cs.outline), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _approving ? null : () async { setState(() => _approving = true); await widget.onApprove(); setState(() => _approving = false); },
                      icon: _approving ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary)) : Icon(Icons.lock_rounded, size: 16, color: cs.onPrimary),
                      label: Text('Approve Payment & Dispatch to Workshop', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimary)),
                      style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 2),
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

  List<Widget> _row(String label, String value, {bool hl = false, bool grn = false}) => [
    Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      const SizedBox(width: 12),
      Flexible(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hl ? cs.primary : grn ? const Color(0xFF059669) : cs.onSurface, fontFamily: 'monospace'), textAlign: TextAlign.right)),
    ])),
    Divider(height: 1, color: cs.surfaceContainer),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('UPLOADED SLIP RAW VIEWPORT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.8)),
        Row(children: [Icon(Icons.fingerprint_rounded, color: cs.primary, size: 14), const SizedBox(width: 4), Text('SHA256: a8f9..43c2', style: TextStyle(fontSize: 11, color: cs.primary, fontFamily: 'monospace'))]),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.08), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF003087), borderRadius: BorderRadius.circular(4)), child: const Text('BCA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: -0.5))),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('m-Transfer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1e3a5f))),
                const Text('BERHASIL / SUCCESS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF059669), letterSpacing: 0.5)),
              ]),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('12/09/2026', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
              Text('09:12:04 WIB', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
            ]),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              Text('JUMLAH TRANSFER (TOTAL AMOUNT)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.8)),
              const SizedBox(height: 4),
              const Text('Rp 3.575.000', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF1c1b1c), height: 1.0)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF059669)),
                const SizedBox(width: 4),
                const Text('Admin Fee Included (Rp 0)', style: TextStyle(fontSize: 11, color: Color(0xFF059669))),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          ..._row('Dari Rekening:', 'BUDI WICAKSONO\n5221-xxxx-4491'),
          ..._row('Penerima:', 'PT REVIVE OTOMOTIF\n8830-192-381'),
          ..._row('No. Referensi:', '98821034'),
          ..._row('Berita / Notes:', '#', hl: true),
          ..._row('Engine Routing:', 'BCA SWITCHING ENGINE: OK', grn: true),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Icon(Icons.document_scanner_outlined, color: cs.primary, size: 16),
              const SizedBox(width: 6),
              Text('Vision OCR Confidence', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
            ]),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)), child: const Text('99.4% Match', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669), fontFamily: 'monospace'))),
          ]),
        ]),
      ),
      if (job.paymentProofUrl != null) ...[
        const SizedBox(height: 8),
        TextButton.icon(onPressed: () {}, icon: Icon(Icons.open_in_new_rounded, size: 14, color: cs.primary), label: Text('Open Original JPG', style: TextStyle(fontSize: 12, color: cs.primary))),
      ],
    ]);
  }
}
class _ReconcilerPanel extends StatelessWidget {
  final ColorScheme cs;
  final bool notifyWA;
  final ValueChanged<bool> onToggle;
  const _ReconcilerPanel({required this.cs, required this.notifyWA, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('AUTOMATED RECONCILER DIAGNOSTICS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.8)),
        _Chip(cs: cs, label: '3 of 3 Rules Met', bgColor: cs.surfaceContainerHigh, fgColor: cs.onSurface),
      ]),
      const SizedBox(height: 12),
      _Check(cs: cs, title: 'Payable Total Match', subtitle: 'System Due: Rp 3.575.000  -  Slip: Rp 3.575.000', badge: 'EXACT MATCH'),
      const SizedBox(height: 8),
      _Check(cs: cs, title: 'Beneficiary Destination', subtitle: 'BCA 8830-192-381  PT Revive Otomotif', badge: 'REVIVE ACCT'),
      const SizedBox(height: 8),
      _Check(cs: cs, title: 'Target Workshop Reservation', subtitle: 'Kebon Jeruk Hub Bay 04  -  14 Sep, 11:00 WIB', badge: 'RESERVED'),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ADMIN AUDIT TRAILING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Verification Auditor', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              Text('Chief Dispatcher (Arya P.)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
            ])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pipeline Action', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              Text("Advance to 'Scheduled & Paid'", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
            ])),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.06), blurRadius: 4)]),
        child: Row(children: [
          Icon(Icons.chat_bubble_outline_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Customer Notification Bridge', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
            Text('Send instant WhatsApp confirmation with digital valet slip', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ])),
          Switch(value: notifyWA, activeThumbColor: cs.primary, onChanged: onToggle),
        ]),
      ),
    ]);
  }
}

class _Check extends StatelessWidget {
  final ColorScheme cs;
  final String title, subtitle, badge;
  const _Check({required this.cs, required this.title, required this.subtitle, required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.04), blurRadius: 4)]),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
          Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)), child: Text(badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF059669), letterSpacing: 0.5))),
      ]),
    );
  }
}
// ─── Partner CMS ──────────────────────────────────────────────────────────────

class _PartnerCmsContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;
  const _PartnerCmsContent({required this.cs, required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Partner CMS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 20),
      if (state.pendingApplications.isNotEmpty) ...[
        Text('Pending Applications', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 12),
        ...state.pendingApplications.map((app) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.04), blurRadius: 4)]),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.shopName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
              Text(' - ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ])),
            OutlinedButton(onPressed: () => controller.declinePartnerApplication(app.id), child: Text('Reject', style: TextStyle(color: cs.onSurfaceVariant))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () => controller.approvePartnerApplication(app.id), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)), child: const Text('Approve', style: TextStyle(color: Colors.white))),
          ]),
        )),
        const SizedBox(height: 24),
      ],
      Text('Active Partner Workshops', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 12),
      ...state.partners.map((p) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.04), blurRadius: 4)]),
        child: ListTile(
          onTap: () => context.push('/admin-central/partner/${p.id}'),
          title: Text(p.shopName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
          subtitle: Text('Active: ${p.activeVolume} · Avg ${p.avgVelocityDays}d', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          trailing: Switch(value: p.isActive, activeThumbColor: cs.primary, onChanged: (v) => controller.togglePartnerStatus(p.id, v)),
        ),
      )),
    ]);
  }
}

// ─── Customer CRM ─────────────────────────────────────────────────────────────

class _CustomerCrmContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  const _CustomerCrmContent({required this.cs, required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Customer Database', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 20),
      ...state.customers.map((c) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.04), blurRadius: 4)]),
        child: ListTile(
          title: Text(c.fullName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
          subtitle: Text(' - ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Text(' active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
          ),
        ),
      )),
    ]);
  }
}

// ─── Placeholder ──────────────────────────────────────────────────────────────

class _PlaceholderContent extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  const _PlaceholderContent({required this.cs, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.construction_rounded, size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 8),
        Text('This section is under construction.', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
      ])),
    );
  }
}

// ─── Shared micro-widgets ─────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final Color bgColor, fgColor;
  const _Chip({required this.cs, required this.label, required this.bgColor, required this.fgColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fgColor)),
  );
}

class _KpiCard extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label, value;
  final bool highlight;
  const _KpiCard({required this.cs, required this.icon, required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.06), blurRadius: 6)]),
    child: Row(children: [
      Icon(icon, size: 18, color: highlight ? cs.primary : cs.onSurfaceVariant),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: highlight ? cs.primary : cs.onSurface, fontFamily: 'monospace')),
      ]),
    ]),
  );
}

class _TH extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final int flex;
  final bool right;
  const _TH({required this.cs, required this.label, required this.flex, this.right = false});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5), textAlign: right ? TextAlign.right : TextAlign.left),
  );
}

class _PB extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final bool active, enabled;
  const _PB({required this.cs, required this.label, this.active = false, this.enabled = true});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: enabled ? () {} : null,
    style: TextButton.styleFrom(backgroundColor: active ? cs.surfaceContainer : cs.surfaceContainerLowest, foregroundColor: active ? cs.onSurface : cs.onSurfaceVariant, minimumSize: const Size(32, 32), padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
  );
}

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}