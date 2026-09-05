import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'admin_dashboard_controller.dart';

class MasterAdminDesktop extends ConsumerStatefulWidget {
  const MasterAdminDesktop({super.key});

  @override
  ConsumerState<MasterAdminDesktop> createState() => _MasterAdminDesktopState();
}

class _MasterAdminDesktopState extends ConsumerState<MasterAdminDesktop> {
  int _activeTab = 0; // 0 = Ops Matrix, 1 = Partner CMS, 2 = Customer CRM

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminDashboardProvider);
    final controller = ref.read(adminDashboardProvider.notifier);
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.background : Colors.grey[50];
    final surfaceColor = isDark ? AppColors.surface : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.sleekBlack;

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 280,
            color: isDark ? Color(0xFF1c1b1c) : Colors.white,
            child: Column(
              children: [
                Container(
                  height: 64,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const Icon(Icons.shield, color: AppColors.fireRed),
                      const SizedBox(width: 12),
                      Text('Revive Central', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.daysGray),
                const SizedBox(height: 16),
                _buildNavItem(0, Icons.grid_view, 'Master Ops Matrix', textColor),
                _buildNavItem(1, Icons.business, 'Partner CMS', textColor),
                _buildNavItem(2, Icons.people, 'Customer CRM', textColor),
                _buildNavItem(3, Icons.view_kanban, 'Assign Jobs Hub', textColor, route: '/admin-central/assign'),
                const Spacer(),
                const Divider(height: 1, color: AppColors.daysGray),
                ListTile(
                  leading: const Icon(Icons.arrow_back, color: AppColors.daysGray),
                  title: const Text('Exit Central', style: TextStyle(color: AppColors.daysGray)),
                  onTap: () => context.go('/'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          
          // Main Content
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    border: const Border(bottom: BorderSide(color: AppColors.daysGray, width: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _activeTab == 0 ? 'Master Ops Matrix' : _activeTab == 1 ? 'Partner CMS' : 'Customer CRM',
                        style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (state.isLoading)
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 16),
                      IconButton(
                        icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: textColor),
                        tooltip: 'Toggle Theme',
                        onPressed: () {
                          ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
                        },
                      ),
                      IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(adminDashboardProvider), color: textColor),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    child: _activeTab == 0
                        ? _buildOpsMatrix(state, textColor, surfaceColor)
                        : _activeTab == 1
                            ? _buildPartnerCrm(state, controller, textColor, surfaceColor)
                            : _buildCustomerCrm(state, textColor, surfaceColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title, Color textColor, {String? route}) {
    final isActive = _activeTab == index && route == null;
    return InkWell(
      onTap: () {
        if (route != null) {
          context.push(route);
        } else {
          setState(() => _activeTab = index);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        color: isActive ? AppColors.fireRed.withValues(alpha: 0.1) : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, color: isActive ? AppColors.fireRed : AppColors.daysGray),
            const SizedBox(width: 16),
            Text(title, style: TextStyle(color: isActive ? AppColors.fireRed : textColor, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildOpsMatrix(AdminDashboardState state, Color textColor, Color surfaceColor) {
    final pendingVerifications = state.activeJobs.where((j) => j.status == '3_booked' || j.status == 'manual_verification_pending').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard('Active Global Jobs', '${state.activeJobs.length}', Icons.build, surfaceColor, textColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard('System Breaches', '${state.breaches.length}', Icons.warning, surfaceColor, AppColors.fireRed),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text('Manual Payment Verifications', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        if (pendingVerifications.isEmpty)
          const Text('No jobs awaiting manual verification.', style: TextStyle(color: AppColors.daysGray))
        else
          Expanded(
            child: ListView.builder(
              itemCount: pendingVerifications.length,
              itemBuilder: (context, index) {
                final job = pendingVerifications[index];
                return Card(
                  color: surfaceColor,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(job.customerName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                    subtitle: Text('${job.carIdentity} • Assigned to: ${job.partnerName}'),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed),
                      onPressed: () {},
                      child: const Text('Verify Proof', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPartnerCrm(AdminDashboardState state, AdminDashboardController controller, Color textColor, Color surfaceColor) {
    final filteredPartners = state.partners.where((p) {
      if (state.searchQuery.isEmpty) return true;
      return p.shopName.toLowerCase().contains(state.searchQuery.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.pendingApplications.isNotEmpty) ...[
          Text('Pending Partner Applications', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...state.pendingApplications.map((app) => Card(
                color: surfaceColor,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(app.shopName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                  subtitle: Text('${app.ownerName} • ${app.phone}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(onPressed: () => controller.declinePartnerApplication(app.id), child: const Text('Reject', style: TextStyle(color: AppColors.daysGray))),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: () => controller.approvePartnerApplication(app.id),
                        child: const Text('Approve', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 32),
        ],
        Row(
          children: [
            Text('Active Partner Workshops', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            SizedBox(
              width: 300,
              child: TextField(
                onChanged: controller.setSearchQuery,
                decoration: InputDecoration(
                  hintText: 'Search partners...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: surfaceColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: filteredPartners.length,
            itemBuilder: (context, index) {
              final p = filteredPartners[index];
              return Card(
                color: surfaceColor,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  onTap: () => context.push('/admin-central/partner/${p.id}'),
                  title: Row(
                    children: [
                      Text(p.shopName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withValues(alpha: 0.3))),
                        child: Text(p.tier.toUpperCase(), style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      if (p.unreadMessageCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.fireRed, borderRadius: BorderRadius.circular(12)),
                          child: Text('${p.unreadMessageCount} new', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text('Active Jobs: ${p.activeVolume} • Avg Velocity: ${p.avgVelocityDays} days'),
                  trailing: Switch(
                    value: p.isActive,
                    activeThumbColor: AppColors.fireRed,
                    onChanged: (val) => controller.togglePartnerStatus(p.id, val),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerCrm(AdminDashboardState state, Color textColor, Color surfaceColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Customer Database', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: state.customers.length,
            itemBuilder: (context, index) {
              final c = state.customers[index];
              return Card(
                color: surfaceColor,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(c.fullName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                  subtitle: Text('${c.email} • ${c.phone}'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.fireRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                    child: Text('${c.activeJobs} Active Jobs', style: const TextStyle(color: AppColors.fireRed, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color surfaceColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Icon(icon, size: 40, color: textColor),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: AppColors.daysGray)),
              Text(value, style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
