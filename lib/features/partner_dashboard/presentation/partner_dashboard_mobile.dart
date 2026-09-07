import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'partner_dashboard_controller.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _primary = Color(0xFFa40016);
const _primaryContainer = Color(0xFFd10721);
const _onPrimary = Color(0xFFffffff);
const _emerald500 = Color(0xFF10B981);
const _amber500 = Color(0xFFF59E0B);
const _blue500 = Color(0xFF3B82F6);

String _statusLabel(String raw) =>
    raw.replaceAll(RegExp(r'^\d+_'), '').replaceAll('_', ' ').toUpperCase();

class PartnerDashboardMobile extends ConsumerStatefulWidget {
  const PartnerDashboardMobile({super.key});
  @override
  ConsumerState<PartnerDashboardMobile> createState() => _PartnerDashboardMobileState();
}

class _PartnerDashboardMobileState extends ConsumerState<PartnerDashboardMobile> {
  int _navIndex = 0;
  String _filterStatus = 'All';
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(partnerDashboardProvider);
    final controller = ref.read(partnerDashboardProvider.notifier);

    ref.listen<PartnerDashboardState>(partnerDashboardProvider, (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: next.errorMessage!.contains('successfully') ? _emerald500 : _primaryContainer,
        ));
      }
    });

    if (state.isLoading && state.activeJobs.isEmpty) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    // Filter jobs
    List<PartnerJobNode> filteredJobs = state.activeJobs.where((j) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!j.carMake.toLowerCase().contains(q) &&
            !j.carModel.toLowerCase().contains(q) &&
            !j.licensePlate.toLowerCase().contains(q) &&
            !j.customerName.toLowerCase().contains(q)) return false;
      }
      switch (_filterStatus) {
        case 'Incoming': return j.status == '3_booked' || j.status == '4_paid';
        case 'In Bay': return j.status == '5_admitted' || j.status == '6_in_progress';
        case 'Paint': return j.status == '7_finished';
        case 'QC': return j.status == '8_awaiting_delivery';
        default: return true;
      }
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: SafeArea(
        child: Column(children: [
          _MobileHeader(
            unreadCount: state.unreadMessageCount,
            isLive: !state.isOfflineSyncing,
            onSettings: () => context.push('/partner-dashboard/settings'),
            onCommlink: () => context.push('/partner-dashboard/commlink'),
          ),
          _KpiRow(state: state),
          _SearchBar(ctrl: _searchCtrl, onSearch: (q) => setState(() => _searchQuery = q)),
          _FilterChips(
            selected: _filterStatus,
            jobs: state.activeJobs,
            onSelect: (f) => setState(() => _filterStatus = f),
          ),
          Expanded(child: _JobList(jobs: filteredJobs, controller: controller)),
        ]),
      ),
      bottomNavigationBar: _BottomNav(
        current: _navIndex,
        unread: state.unreadMessageCount,
        onTap: (i) {
          setState(() => _navIndex = i);
          switch (i) {
            case 0: break; // stay on dashboard
            case 1: context.push('/partner-dashboard/schedule'); break;
            case 2: context.push('/partner-dashboard/commlink'); break;
            case 3: context.push('/partner-dashboard/profile'); break;
          }
        },
      ),
    );
  }
}

// ─── Mobile Header ────────────────────────────────────────────────────────────
class _MobileHeader extends StatelessWidget {
  final int unreadCount;
  final bool isLive;
  final VoidCallback onSettings;
  final VoidCallback onCommlink;
  const _MobileHeader({required this.unreadCount, required this.isLive, required this.onSettings, required this.onCommlink});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: _primaryContainer, shape: BoxShape.circle), child: Icon(Icons.build_circle, color: _onPrimary, size: 16)),
        SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('re-V Partner', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
          Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: isLive ? _emerald500 : Colors.orange, shape: BoxShape.circle)),
            SizedBox(width: 4),
            Text(isLive ? 'Live Sync' : 'Reconnecting…', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ]),
        const Spacer(),
        Badge(
          isLabelVisible: unreadCount > 0,
          label: Text('$unreadCount', style: TextStyle(fontSize: 9)),
          backgroundColor: _primaryContainer,
          child: IconButton(icon: Icon(Icons.forum_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant), onPressed: onCommlink),
        ),
        IconButton(icon: Icon(Icons.tune_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant), onPressed: onSettings),
      ]),
    );
  }
}

// ─── KPI Row ──────────────────────────────────────────────────────────────────
class _KpiRow extends StatelessWidget {
  final PartnerDashboardState state;
  const _KpiRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final total = state.activeJobs.length;
    final inBay = state.activeJobs.where((j) => j.status == '5_admitted' || j.status == '6_in_progress').length;
    final qc = state.activeJobs.where((j) => j.status == '8_awaiting_delivery').length;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        Expanded(child: _MobileKpi(label: 'Active Jobs', value: '$total', color: _primary, icon: Icons.build_outlined)),
        SizedBox(width: 8),
        Expanded(child: _MobileKpi(label: 'In Bay', value: '$inBay', color: _amber500, icon: Icons.hardware_outlined)),
        SizedBox(width: 8),
        Expanded(child: _MobileKpi(label: 'QC Ready', value: '$qc', color: _emerald500, icon: Icons.local_shipping_outlined)),
        SizedBox(width: 8),
        Expanded(child: _MobileKpi(label: 'Messages', value: '${state.unreadMessageCount}', color: _blue500, icon: Icons.forum_outlined, highlight: state.unreadMessageCount > 0)),
      ]),
    );
  }
}

class _MobileKpi extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  final bool highlight;
  const _MobileKpi({required this.label, required this.value, required this.color, required this.icon, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: highlight ? Border.all(color: color.withValues(alpha: 0.3)) : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        SizedBox(height: 4),
        Text(value, style: TextStyle(color: highlight ? color : Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 2),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ─── Search Bar ───────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final ValueChanged<String> onSearch;
  const _SearchBar({required this.ctrl, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        height: 38,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHigh)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 16),
          SizedBox(width: 8),
          Expanded(child: TextField(
            controller: ctrl,
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search vehicle, plate, customer…',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              border: InputBorder.none,
              isDense: true,
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
          )),
        ]),
      ),
    );
  }
}

// ─── Filter Chips ─────────────────────────────────────────────────────────────
class _FilterChips extends StatelessWidget {
  final String selected;
  final List<PartnerJobNode> jobs;
  final ValueChanged<String> onSelect;
  const _FilterChips({required this.selected, required this.jobs, required this.onSelect});

  int _count(String filter) {
    switch (filter) {
      case 'Incoming': return jobs.where((j) => j.status == '3_booked' || j.status == '4_paid').length;
      case 'In Bay': return jobs.where((j) => j.status == '5_admitted' || j.status == '6_in_progress').length;
      case 'Paint': return jobs.where((j) => j.status == '7_finished').length;
      case 'QC': return jobs.where((j) => j.status == '8_awaiting_delivery').length;
      default: return jobs.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    const filters = ['All', 'Incoming', 'In Bay', 'Paint', 'QC'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: filters.length,
        separatorBuilder: (_, __) => SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = filters[i];
          final isActive = f == selected;
          return GestureDetector(
            onTap: () => onSelect(f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? _primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: isActive ? null : Border.all(color: Theme.of(context).colorScheme.surfaceContainerHigh),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(f, style: TextStyle(color: isActive ? _onPrimary : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500)),
                SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: isActive ? Colors.white.withValues(alpha: 0.25) : Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
                  child: Text('${_count(f)}', style: TextStyle(color: isActive ? _onPrimary : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─── Job List ─────────────────────────────────────────────────────────────────
class _JobList extends StatelessWidget {
  final List<PartnerJobNode> jobs;
  final PartnerDashboardController controller;
  const _JobList({required this.jobs, required this.controller});

  Color _statusColor(String status) {
    if (status == '3_booked' || status == '4_paid') return _blue500;
    if (status == '5_admitted' || status == '6_in_progress') return _primary;
    if (status == '7_finished') return _amber500;
    return _emerald500;
  }

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.emoji_transportation, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
        SizedBox(height: 12),
        Text('No Jobs Found', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 17, fontWeight: FontWeight.bold)),
        SizedBox(height: 6),
        Text('Try changing your filter or search term.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      itemCount: jobs.length,
      itemBuilder: (_, i) {
        final job = jobs[i];
        final color = _statusColor(job.status);
        final elapsed = DateTime.now().difference(job.admittedAt);
        final elapsedText = elapsed.inHours > 0 ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m' : '${elapsed.inMinutes}m';
        final jobIdShort = job.id.length > 8 ? job.id.substring(0, 8).toUpperCase() : job.id.toUpperCase();

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Card header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(left: BorderSide(color: color, width: 4)),
              ),
              child: Row(children: [
                Text('#$jobIdShort', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(_statusLabel(job.status), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
                const Spacer(),
                Icon(Icons.timer_outlined, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                SizedBox(width: 3),
                Text(elapsedText, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
              ]),
            ),
            // Card body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${job.carMake} ${job.carModel}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(4), border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHigh)),
                    child: Text(job.licensePlate.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                  ),
                  SizedBox(width: 8),
                  Text('• ${job.customerName}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                ]),
                SizedBox(height: 12),
                Row(children: [
                  Expanded(child: SizedBox(
                    height: 34,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryContainer,
                        side: const BorderSide(color: _primaryContainer),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(Icons.photo_camera_outlined, size: 14),
                      label: Text('Photo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => controller.captureAndUploadProgressPhoto(job.id, job.status),
                    ),
                  )),
                  SizedBox(width: 8),
                  if (job.status != '9_done') Expanded(child: SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: Icon(Icons.arrow_forward, size: 14),
                      label: Text(
                        (job.status == '3_booked' || job.status == '4_paid') ? 'Admit' : 'Advance',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => controller.advanceJobStage(job.id, job.status),
                    ),
                  )),
                ]),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ─── Bottom Nav ───────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int current;
  final int unread;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.current, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          _NavItem(icon: Icons.view_kanban_outlined, label: 'Pipeline', index: 0, current: current, onTap: onTap),
          _NavItem(icon: Icons.calendar_month_outlined, label: 'Schedule', index: 1, current: current, onTap: onTap),
          _NavItem(icon: Icons.forum_outlined, label: 'Commlink', index: 2, current: current, onTap: onTap, badge: unread),
          _NavItem(icon: Icons.person_outlined, label: 'Profile', index: 3, current: current, onTap: onTap),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index, current;
  final int badge;
  final ValueChanged<int> onTap;
  const _NavItem({required this.icon, required this.label, required this.index, required this.current, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return Expanded(child: GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon, color: active ? _primary : Theme.of(context).colorScheme.onSurfaceVariant, size: 22),
            if (badge > 0) Positioned(top: -4, right: -8, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: _primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Text('$badge', style: TextStyle(color: _onPrimary, fontSize: 9, fontWeight: FontWeight.bold)),
            )),
          ]),
          SizedBox(height: 3),
          Text(label, style: TextStyle(color: active ? _primary : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    ));
  }
}
