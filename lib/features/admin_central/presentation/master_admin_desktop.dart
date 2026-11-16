import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/jobs/job_status.dart'; // S-08 fix
import '../../../core/services/r2_storage.dart';
import 'admin_dashboard_controller.dart';

part 'desktop_parts/sidebar.dart';
part 'desktop_parts/top_header.dart';
part 'desktop_parts/ops_matrix.dart';
part 'desktop_parts/workshop_settings_quotas.dart';
part 'desktop_parts/partner_hub_management.dart';
part 'desktop_parts/customer_crm.dart';
part 'desktop_parts/placeholder.dart';
part 'desktop_parts/verification_modal.dart';
part 'desktop_parts/info_box.dart';
part 'desktop_parts/shared_micro_widgets.dart';


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
  _NavItem('Invoice & Admission', Icons.receipt_long_outlined, route: '/admin-central/invoices'),
  _NavItem('Partner Assessment', Icons.store_mall_directory_outlined, route: '/admin-central/partners'),
  _NavItem('Workshop Settings & Quotas', Icons.tune_outlined),
  _NavItem('Assign Jobs Hub', Icons.assignment_outlined),
  _NavItem('Customer Database', Icons.people_outline_rounded),
  _NavItem('Pricing Rules', Icons.price_change_outlined,
      route: '/admin-central/cms/pricing-rules', sysadminOnly: true),
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
                // The modal writes the payment itself (admin_review_payment or
                // admin_record_manual_payment). All that is left is to close
                // and refresh — moving the job status here without a payment
                // row is what left invoices unpaid.
                setState(() => _verifyingJob = null);
              },
              onReject: () async {
                setState(() => _verifyingJob = null);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, AdminDashboardState state,
      AdminDashboardController controller) {
    // Keyed on the label, not on the index. The two lists drifted apart, so
    // "Workshop Settings & Quotas" opened the assignment screen and "Assign
    // Jobs Hub" opened the customer list, and the workshop settings could not
    // be opened at all. Route-driven items push their own route and never
    // reach this switch; the placeholder names the page instead.
    final label = _navItems[_activeNavIndex].label;
    switch (label) {
      case 'Job Board / Pipeline':
        return _OpsMatrixContent(
          cs: cs,
          state: state,
          controller: controller,
          onVerify: (job) => setState(() => _verifyingJob = job),
        );
      case 'Workshop Settings & Quotas':
        return _WorkshopSettingsContent(
            cs: cs, state: state, controller: controller);
      case 'Assign Jobs Hub':
        return _AssignJobsContent(
            cs: cs, state: state, controller: controller);
      case 'Customer Database':
        return _CustomerCrmContent(cs: cs, state: state);
      default:
        return _PlaceholderContent(cs: cs, label: label);
    }
  }
}

