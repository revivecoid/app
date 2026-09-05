import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import 'partner_dashboard_controller.dart';

// ─── Color tokens (keep consistent with the original design) ─────────────────
const _surface = Color(0xFFfdf8f9);
const _surfaceLowest = Color(0xFFffffff);
const _surfaceLow = Color(0xFFf7f2f3);
const _surfaceContainer = Color(0xFFf1edee);
const _surfaceHigh = Color(0xFFebe7e8);
const _primary = Color(0xFFa40016);
const _primaryContainer = Color(0xFFd10721);
const _onPrimary = Color(0xFFffffff);
const _onPrimaryContainer = Color(0xFFffe1de);
const _onSurface = Color(0xFF1c1b1c);
const _onSurfaceVariant = Color(0xFF5d3f3d);
const _errorContainer = Color(0xFFffdad6);
const _onErrorContainer = Color(0xFF93000a);
const _emerald500 = Color(0xFF10B981);
const _amber500 = Color(0xFFF59E0B);
const _blue500 = Color(0xFF3B82F6);

// ─── Status bucket helpers ────────────────────────────────────────────────────
String _statusLabel(String raw) =>
    raw.replaceAll(RegExp(r'^\d+_'), '').replaceAll('_', ' ').toUpperCase();

// ─── Main Widget ─────────────────────────────────────────────────────────────
class PartnerDashboardDesktop extends ConsumerStatefulWidget {
  const PartnerDashboardDesktop({super.key});

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

    // Error / success snackbar
    ref.listen<PartnerDashboardState>(partnerDashboardProvider, (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: next.errorMessage!.contains('successfully') ? Colors.green[800] : _primaryContainer,
        ));
      }
    });

    // ── Filtered jobs ──
    final allJobs = state.activeJobs.where((j) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return j.carMake.toLowerCase().contains(q) ||
          j.carModel.toLowerCase().contains(q) ||
          j.licensePlate.toLowerCase().contains(q) ||
          j.id.toLowerCase().contains(q) ||
          j.customerName.toLowerCase().contains(q);
    }).toList();

    final incoming = allJobs.where((j) => j.status == '3_booked' || j.status == '4_paid').toList();
    final inBay = allJobs.where((j) => j.status == '5_admitted' || j.status == '6_in_progress').toList();
    final inPaint = allJobs.where((j) => j.status == '7_finished').toList();
    final inQC = allJobs.where((j) => j.status == '8_awaiting_delivery').toList();

    return Scaffold(
      backgroundColor: _surface,
      body: state.isLoading && state.activeJobs.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _primaryContainer))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── SIDEBAR ───────────────────────────────────────────────
                _Sidebar(
                  userName: userName,
                  unreadCount: state.unreadMessageCount,
                  onNavigate: (route) => context.push(route),
                ),

                // ─── MAIN CONTENT ──────────────────────────────────────────
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
                              const SizedBox(height: 24),

                              // TITLE + FILTER PILLS
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text('Workshop Job Board & Active Pipeline',
                                          style: TextStyle(color: _onSurface, fontSize: 28, fontWeight: FontWeight.bold)),
                                      SizedBox(height: 4),
                                      Text('Live repair pipeline — tap any card to advance the stage.',
                                          style: TextStyle(color: _onSurfaceVariant, fontSize: 13)),
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
                              const SizedBox(height: 24),

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
                                    const SizedBox(width: 16),
                                    _Swimlane(
                                      title: 'Body Repair / Frame',
                                      color: _primary,
                                      jobs: inBay,
                                      controller: controller,
                                    ),
                                    const SizedBox(width: 16),
                                    _Swimlane(
                                      title: 'Heated Paint Chamber',
                                      color: _amber500,
                                      jobs: inPaint,
                                      controller: controller,
                                    ),
                                    const SizedBox(width: 16),
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
    return Container(
      width: 272,
      decoration: const BoxDecoration(
        color: _surfaceLowest,
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
                decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _surfaceHigh))),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: const BoxDecoration(color: _primaryContainer, shape: BoxShape.circle),
                      child: const Icon(Icons.build_circle, color: _onPrimary, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('re-V', style: TextStyle(color: _onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('OPS CORE', style: TextStyle(color: _primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Active Hub info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _surfaceLow, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.warehouse_outlined, color: _primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('ACTIVE HUB', style: TextStyle(color: _onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            Text('Workshop Operations', style: TextStyle(color: _onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                onTap: () => onNavigate('/partner-dashboard/settings'),
              ),

            ],
          ),
          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            color: _surfaceLow,
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                  child: const Icon(Icons.person, color: _onPrimary, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SIGNED IN', style: TextStyle(color: _onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.bold)),
                      Text('Partner Account', style: TextStyle(color: _onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _emerald500, shape: BoxShape.circle)),
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
              Icon(icon, color: isActive ? _onPrimaryContainer : _onSurfaceVariant, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: isActive ? _onPrimaryContainer : _onSurfaceVariant, fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.w500))),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _primaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: Text('$badge', style: const TextStyle(color: _onPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
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

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Color(0xE6FFFFFF),
        boxShadow: [BoxShadow(color: Color(0x0A000000), offset: Offset(0, 1), blurRadius: 8)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Search
          Container(
            width: 380,
            height: 38,
            decoration: BoxDecoration(color: _surfaceLow, borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.search, color: _onSurfaceVariant, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearch,
                    decoration: const InputDecoration(
                      hintText: "Search vehicle, license plate, or job ID…",
                      hintStyle: TextStyle(color: _onSurfaceVariant, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: const TextStyle(color: _onSurface, fontSize: 13),
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
                decoration: BoxDecoration(color: _surfaceLow, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: isLive ? _emerald500 : Colors.orange, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(isLive ? 'LIVE SYNC' : 'RECONNECTING', style: TextStyle(color: _onSurface, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: _onSurfaceVariant),
                tooltip: 'Toggle Theme',
                onPressed: () {
                  ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              const SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(userName, style: const TextStyle(color: _onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                  const Text('Workshop Partner', style: TextStyle(color: _onSurfaceVariant, fontSize: 11)),
                ],
              ),
              const SizedBox(width: 10),
              Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                child: const Icon(Icons.person, color: _onPrimary, size: 18),
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
    return Row(
      children: [
        Expanded(child: _KpiCard(title: 'Active Repairs', value: '$totalJobs', subtitle: 'total jobs', icon: Icons.build_outlined, iconColor: _primary)),
        const SizedBox(width: 16),
        Expanded(child: _KpiCard(title: 'In Active Bay', value: '$inProgress', subtitle: 'in-progress', icon: Icons.hardware_outlined, iconColor: _amber500)),
        const SizedBox(width: 16),
        Expanded(child: _KpiCard(title: 'Awaiting Dispatch', value: '$awaiting', subtitle: 'ready to go', icon: Icons.local_shipping_outlined, iconColor: _emerald500)),
        const SizedBox(width: 16),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: highlight ? _primaryContainer.withValues(alpha: 0.08) : _surfaceLowest,
        borderRadius: BorderRadius.circular(12),
        border: highlight ? Border.all(color: _primaryContainer.withValues(alpha: 0.3)) : null,
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title.toUpperCase(), style: const TextStyle(color: _onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(color: highlight ? _primaryContainer : _onSurface, fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text(subtitle, style: const TextStyle(color: _onSurfaceVariant, fontSize: 13)),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? _primaryContainer : _surfaceLowest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
        ),
        child: Row(
          children: [
            Text(text, style: TextStyle(color: isActive ? _onPrimary : _onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? const Color(0x33FFFFFF) : _surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(count, style: TextStyle(color: isActive ? _onPrimary : _onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold)),
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
                  child: Text('${jobs.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (jobs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _surfaceHigh, style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, color: _onSurfaceVariant, size: 28),
                  const SizedBox(height: 6),
                  Text('No jobs in this stage', style: TextStyle(color: _onSurfaceVariant, fontSize: 12)),
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
    final jobIdShort = job.id.length > 8 ? job.id.substring(0, 8).toUpperCase() : job.id.toUpperCase();
    final elapsed = DateTime.now().difference(job.admittedAt);
    final elapsedText = elapsed.inHours > 0 ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m' : '${elapsed.inMinutes}m';

    return Container(
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
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
                    style: const TextStyle(color: _onSurface, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _surfaceLow, borderRadius: BorderRadius.circular(4), border: Border.all(color: _surfaceHigh)),
                      child: Text(job.licensePlate.toUpperCase(), style: const TextStyle(color: _onSurface, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                    ),
                    const SizedBox(width: 8),
                    Text('• ${job.customerName}', style: const TextStyle(color: _onSurfaceVariant, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 13, color: _onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(elapsedText, style: const TextStyle(color: _onSurfaceVariant, fontSize: 11)),
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
                                side: const BorderSide(color: _primaryContainer, width: 1),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              icon: const Icon(Icons.photo_camera_outlined, size: 13),
                              label: const Text('Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () => controller.captureAndUploadProgressPhoto(job.id, job.status),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 28,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.arrow_forward, size: 13),
                              label: Text((job.status == '3_booked' || job.status == '4_paid') ? 'Admit Vehicle' : 'Advance', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(64),
      child: Column(
        children: const [
          Icon(Icons.emoji_transportation, size: 56, color: _onSurfaceVariant),
          SizedBox(height: 16),
          Text('No Active Jobs', style: TextStyle(color: _onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Jobs will appear here once a customer booking is assigned to your workshop.',
              style: TextStyle(color: _onSurfaceVariant, fontSize: 14), textAlign: TextAlign.center),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: _errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 40, color: _onErrorContainer),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: _onErrorContainer, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Check that your partner account has a partner_id set in user metadata.',
              style: TextStyle(color: _onErrorContainer, fontSize: 12), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
