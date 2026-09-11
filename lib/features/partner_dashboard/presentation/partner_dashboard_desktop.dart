import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import 'partner_dashboard_controller.dart';
import 'partner_dashboard_mobile.dart';

// ─── Brand accent colors (theme-invariant) ───────────────────────────────────
const _primary = Color(0xFFa40016);
const _primaryContainer = Color(0xFFd10721);
const _onPrimary = Color(0xFFffffff);
const _emerald500 = Color(0xFF10B981);
const _amber500 = Color(0xFFF59E0B);
const _blue500 = Color(0xFF3B82F6);

// ─── Status bucket helpers ────────────────────────────────────────────────────
String _statusLabel(String raw) =>
    raw.replaceAll(RegExp(r'^\d+_'), '').replaceAll('_', ' ').toUpperCase();

// ─── Main Widget ─────────────────────────────────────────────────────────────
class PartnerDashboardDesktop extends ConsumerStatefulWidget {
  PartnerDashboardDesktop({super.key});

  @override
  ConsumerState<PartnerDashboardDesktop> createState() => _PartnerDashboardDesktopState();
}

class _PartnerDashboardDesktopState extends ConsumerState<PartnerDashboardDesktop> {
  String _activeFilter = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(partnerDashboardProvider);
    final controller = ref.read(partnerDashboardProvider.notifier);
    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name'] as String? ?? user?.email?.split('@').first ?? 'Partner';
    final cs = Theme.of(context).colorScheme;

    // Reactive error/offline notification
    ref.listen<PartnerDashboardState>(partnerDashboardProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: next.errorMessage!.contains('offline') || next.errorMessage!.contains('successfully')
                ? _emerald500
                : _primaryContainer,
          ),
        );
      }
    });

    // Group jobs by workflow stage
    final allJobs = state.activeJobs.where((j) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return j.carMake.toLowerCase().contains(q) ||
          j.carModel.toLowerCase().contains(q) ||
          j.licensePlate.toLowerCase().contains(q) ||
          j.customerName.toLowerCase().contains(q);
    }).toList();

    // Filter by active filter pill
    final filteredJobs = switch (_activeFilter) {
      'In-Bay' => allJobs.where((j) => j.status == '5_admitted' || j.status == '6_in_progress').toList(),
      'Paint'  => allJobs.where((j) => j.status == '7_finished').toList(),
      'QC'     => allJobs.where((j) => j.status == '8_awaiting_delivery').toList(),
      _        => allJobs,
    };

    final incoming = filteredJobs.where((j) => j.status == '3_booked' || j.status == '4_paid').toList();
    final inBay    = filteredJobs.where((j) => j.status == '5_admitted' || j.status == '6_in_progress').toList();
    final inPaint  = filteredJobs.where((j) => j.status == '7_finished').toList();
    final inQC     = allJobs.where((j) => j.status == '8_awaiting_delivery').toList();

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      if (!isDesktop) return const PartnerDashboardMobile();
      Widget inner = Scaffold(
      backgroundColor: cs.surface,
      body: state.isLoading && state.activeJobs.isEmpty
          ? Center(child: CircularProgressIndicator(color: _primaryContainer))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── SIDEBAR ──────────────────────────────────────────────────────────────
                _Sidebar(
                  userName: userName,
                  unreadCount: state.unreadMessageCount,
                  onNavigate: (route) => context.push(route),
                ),

                // ─── MAIN CONTENT ──────────────────────────────────────────────────────
                Expanded(
                  child: Column(
                    children: [
                      // HEADER
                      _Header(
                        searchController: _searchController,
                        onSearch: (q) => setState(() => _searchQuery = q),
                        userName: userName,
                        isLive: !state.isOfflineSyncing,
                        unreadCount: state.unreadMessageCount,
                      ),

                      // BODY
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // KPI STRIP
                              _KpiStrip(
                                totalJobs: allJobs.length,
                                inProgress: inBay.length,
                                awaiting: inQC.length,
                                unread: state.unreadMessageCount,
                              ),
                              SizedBox(height: 24),

                              // TITLE + FILTER PILLS
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(AppL.of(context)!.partnerJobBoard,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(AppL.of(context)!.partnerJobBoardSub,
                                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      for (final filter in ['All', 'In-Bay', 'Paint', 'QC'])
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8),
                                          child: _FilterPill(
                                            text: filter,
                                            count: _filterCount(filter, allJobs, inBay, inPaint, inQC),
                                            isActive: _activeFilter == filter,
                                            onTap: () => setState(() => _activeFilter = filter),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: 24),

                              // KANBAN BOARD
                              if (state.errorMessage != null && allJobs.isEmpty)
                                _ErrorState(message: state.errorMessage!)
                              else if (allJobs.isEmpty)
                                _EmptyState()
                              else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _Swimlane(
                                      title: 'New Bookings',
                                      color: _blue500,
                                      jobs: incoming,
                                      controller: controller,
                                    ),
                                    SizedBox(width: 16),
                                    _Swimlane(
                                      title: 'Body Repair / Frame',
                                      color: _primary,
                                      jobs: inBay,
                                      controller: controller,
                                    ),
                                    SizedBox(width: 16),
                                    _Swimlane(
                                      title: 'Heated Paint Chamber',
                                      color: _amber500,
                                      jobs: inPaint,
                                      controller: controller,
                                    ),
                                    SizedBox(width: 16),
                                    _Swimlane(
                                      title: 'QC Audit & Handover',
                                      color: _emerald500,
                                      jobs: inQC,
                                      controller: controller,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
      return inner;
    });
  }



  String _filterCount(String filter, List<PartnerJobNode> all, List<PartnerJobNode> inBay,
      List<PartnerJobNode> inPaint, List<PartnerJobNode> inQC) {
    switch (filter) {
      case 'In-Bay': return inBay.length.toString();
      case 'Paint': return inPaint.length.toString();
      case 'QC': return inQC.length.toString();
      default: return all.length.toString();
    }
  }
}

// ─── Sidebar ──────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final String userName;
  final int unreadCount;
  final void Function(String route) onNavigate;

  const _Sidebar({required this.userName, required this.unreadCount, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        boxShadow: [BoxShadow(color: Color(0x0A000000), offset: Offset(0, 1), blurRadius: 8)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              // Logo
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: cs.outlineVariant))),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: _primaryContainer, shape: BoxShape.circle),
                      child: Icon(Icons.build_circle, color: _onPrimary, size: 18),
                    ),
                    SizedBox(width: 8),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('re-V', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(AppL.of(context)!.partnerOpsCore, style: TextStyle(color: _primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
              // Active Hub info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(Icons.warehouse_outlined, color: _primary, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppL.of(context)!.partnerActiveHub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            Text(AppL.of(context)!.partnerWorkshopOps, style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Nav
              _SidebarNavItem(icon: Icons.view_kanban_outlined, text: 'Job Board / Pipeline', isActive: true),
              _SidebarNavItem(
                icon: Icons.calendar_month_outlined,
                text: 'Schedule Config',
                onTap: () => onNavigate('/partner-dashboard/schedule'),
              ),
              _SidebarNavItem(
                icon: Icons.speed_outlined,
                text: 'Quota & Panel Durations',
                onTap: () => onNavigate('/partner-dashboard/quota'),
              ),
              _SidebarNavItem(
                icon: Icons.storefront_outlined,
                text: 'My Profile',
                onTap: () => onNavigate('/partner-dashboard/profile'),
              ),
              _SidebarNavItem(
                icon: Icons.tune_outlined,
                text: 'Workshop Settings',
                onTap: () => onNavigate('/partner-dashboard/settings'),
              ),
              _SidebarNavItem(
                icon: Icons.forum_outlined,
                text: 'Commlink & Messages',
                badge: unreadCount,
                onTap: () => onNavigate('/partner-dashboard/commlink'),
              ),

            ],
          ),
          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: _primary, shape: BoxShape.circle),
                  child: Icon(Icons.person, color: _onPrimary, size: 18),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppL.of(context)!.partnerSignedIn, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.bold)),
                      Text(AppL.of(context)!.partnerAccount, style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _emerald500, shape: BoxShape.circle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isActive;
  final int badge;
  final VoidCallback? onTap;

  const _SidebarNavItem({
    required this.icon,
    required this.text,
    this.isActive = false,
    this.badge = 0,
    this.onTap,
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
            color: isActive ? _primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: isActive ? const Color(0xFFFFE1DE) : Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: isActive ? const Color(0xFFFFE1DE) : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.w500))),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _primaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: Text('$badge', style: TextStyle(color: _onPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────
class _Header extends ConsumerWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final String userName;
  final bool isLive;
  final int unreadCount;

  const _Header({
    required this.searchController,
    required this.onSearch,
    required this.userName,
    required this.isLive,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Color(0x0A000000), offset: Offset(0, 1), blurRadius: 8)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Search
          Container(
            width: 380,
            height: 38,
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.search, color: cs.onSurfaceVariant, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: "Search vehicle, license plate, or job ID…",
                      hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: TextStyle(color: cs.onSurface, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          // Right side
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: isLive ? _emerald500 : Colors.orange, shape: BoxShape.circle)),
                    SizedBox(width: 6),
                    Text(isLive ? 'LIVE SYNC' : 'RECONNECTING', style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              SizedBox(width: 16),
              IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: cs.onSurfaceVariant),
                tooltip: 'Toggle Theme',
                onPressed: () {
                  ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(userName, style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(AppL.of(context)!.partnerWorkshopPartner, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                ],
              ),
              SizedBox(width: 10),
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: _primary, shape: BoxShape.circle),
                child: Icon(Icons.person, color: _onPrimary, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── KPI Strip ────────────────────────────────────────────────────────────────
class _KpiStrip extends StatelessWidget {
  final int totalJobs;
  final int inProgress;
  final int awaiting;
  final int unread;

  const _KpiStrip({required this.totalJobs, required this.inProgress, required this.awaiting, required this.unread});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: _KpiCard(title: 'Active Repairs', value: '$totalJobs', subtitle: 'total jobs', icon: Icons.build_outlined, iconColor: _primary)),
        SizedBox(width: 16),
        Expanded(child: _KpiCard(title: 'In Active Bay', value: '$inProgress', subtitle: 'in-progress', icon: Icons.hardware_outlined, iconColor: _amber500)),
        SizedBox(width: 16),
        Expanded(child: _KpiCard(title: 'Awaiting Dispatch', value: '$awaiting', subtitle: 'ready to go', icon: Icons.local_shipping_outlined, iconColor: _emerald500)),
        SizedBox(width: 16),
        Expanded(child: _KpiCard(title: 'Unread Messages', value: '$unread', subtitle: 'from admin', icon: Icons.forum_outlined, iconColor: _blue500, highlight: unread > 0)),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool highlight;

  const _KpiCard({required this.title, required this.value, required this.subtitle, required this.icon, required this.iconColor, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: highlight ? _primaryContainer.withValues(alpha: 0.08) : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: highlight ? Border.all(color: _primaryContainer.withValues(alpha: 0.3)) : null,
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title.toUpperCase(), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(color: highlight ? _primaryContainer : cs.onSurface, fontSize: 36, fontWeight: FontWeight.bold)),
              SizedBox(width: 6),
              Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Filter Pill ──────────────────────────────────────────────────────────────
class _FilterPill extends StatelessWidget {
  final String text;
  final String count;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterPill({required this.text, required this.count, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? _primaryContainer : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
        ),
        child: Row(
          children: [
            Text(text, style: TextStyle(color: isActive ? _onPrimary : cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
            SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? Color(0x33FFFFFF) : cs.outlineVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(count, style: TextStyle(color: isActive ? _onPrimary : cs.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Swimlane ────────────────────────────────────────────────────────────────
class _Swimlane extends StatelessWidget {
  final String title;
  final Color color;
  final List<PartnerJobNode> jobs;
  final PartnerDashboardController controller;

  const _Swimlane({required this.title, required this.color, required this.jobs, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                  child: Text('${jobs.length}', style: TextStyle(color: cs.surface, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          if (jobs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant, style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, color: cs.onSurfaceVariant, size: 28),
                  SizedBox(height: 6),
                  Text(AppL.of(context)!.partnerNoJobsStage, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            )
          else
            ...jobs.map((job) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _JobCard(job: job, color: color, controller: controller),
            )),
        ],
      ),
    );
  }
}

// ─── Live Job Card ────────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final PartnerJobNode job;
  final Color color;
  final PartnerDashboardController controller;

  const _JobCard({required this.job, required this.color, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final jobIdShort = job.id.length > 8 ? job.id.substring(0, 8).toUpperCase() : job.id.toUpperCase();
    final elapsed = DateTime.now().difference(job.admittedAt);
    final elapsedText = elapsed.inHours > 0 ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m' : '${elapsed.inMinutes}m';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('#$jobIdShort', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(_statusLabel(job.status), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          // Card body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${job.carMake} ${job.carModel}',
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4), border: Border.all(color: cs.outlineVariant)),
                      child: Text(job.licensePlate.toUpperCase(), style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                    ),
                    SizedBox(width: 8),
                    Text('• ${job.customerName}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
                if (job.latestPhotoUrl != null) ...[
                  SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      job.latestPhotoUrl!,
                      width: double.infinity,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 13, color: cs.onSurfaceVariant),
                        SizedBox(width: 4),
                        Text(elapsedText, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                    // Advance stage button + Upload Photo
                    if (job.status != '9_done')
                      Row(
                        children: [
                          SizedBox(
                            height: 28,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _primaryContainer,
                                side: BorderSide(color: _primaryContainer, width: 1),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              icon: Icon(Icons.photo_camera_outlined, size: 13),
                              label: Text(AppL.of(context)!.partnerPhotoBtn, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () => controller.captureAndUploadProgressPhoto(job.id, job.status),
                            ),
                          ),
                          SizedBox(width: 6),
                          SizedBox(
                            height: 28,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: cs.surface,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                elevation: 0,
                              ),
                              icon: Icon(Icons.arrow_forward, size: 13),
                              label: Text((job.status == '3_booked' || job.status == '4_paid') ? 'Admit Vehicle' : 'Advance', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () => controller.advanceJobStage(job.id, job.status),
                            ),
                          ),
                        ],
                      ),

                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty / Error States ────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(64),
      child: Column(
        children: [
          Icon(Icons.emoji_transportation, size: 56, color: cs.onSurfaceVariant),
          SizedBox(height: 16),
          Text(AppL.of(context)!.partnerNoActiveJobs, style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(AppL.of(context)!.partnerNoActiveJobsSub,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: cs.onErrorContainer),
          SizedBox(height: 12),
          Text(message, style: TextStyle(color: cs.onErrorContainer, fontSize: 14), textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text('Check that your partner account has a partner_id set in user metadata.',
              style: TextStyle(color: cs.onErrorContainer, fontSize: 12), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
