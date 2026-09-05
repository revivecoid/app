import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class CustomerLandingScreen extends ConsumerStatefulWidget {
  const CustomerLandingScreen({super.key});

  @override
  ConsumerState<CustomerLandingScreen> createState() => _CustomerLandingScreenState();
}

final activeJobProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  final data = await Supabase.instance.client
      .from('repair_jobs')
      .select('*, vehicles(*)')
      .eq('customer_id', user.id)
      .not('status', 'in', '("8_completed","9_cancelled")')
      .order('created_at', ascending: false)
      .limit(1);
  final list = List<Map<String, dynamic>>.from(data);
  return list.isNotEmpty ? list.first : null;
});

class _CustomerLandingScreenState extends ConsumerState<CustomerLandingScreen> {
  @override
  void initState() {
    super.initState();
    _handleOAuthFallback();
  }

  Future<void> _handleOAuthFallback() async {
    final code = Uri.base.queryParameters['code'];
    if (code != null && mounted) {
      try {
        await Supabase.instance.client.auth.exchangeCodeForSession(code);
      } catch (e) {
        debugPrint('OAuth fallback exchange error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = Supabase.instance.client.auth.currentUser;
    final bool isLoggedIn = user != null;
    final activeJobAsync = ref.watch(activeJobProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: const ReVAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeroSection(theme),
            const SizedBox(height: 16),
            if (isLoggedIn)
              activeJobAsync.when(
                data: (job) => job != null 
                    ? Column(
                        children: [
                          _buildActiveRepairWidget(theme, job),
                          const SizedBox(height: 16),
                        ],
                      )
                    : const SizedBox.shrink(),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Text('Error loading active job: $e'),
              ),
            _buildQuickActions(theme),
            const SizedBox(height: 16),
            _buildFeatureHighlight(theme),
            const SizedBox(height: 16),
            _buildHowItWorks(theme),
            const SizedBox(height: 16),
            _buildRecentInspections(theme),
            const SizedBox(height: 16),
            _buildTrustBadges(theme),
            const SizedBox(height: 16),
            _buildFooterWidget(theme),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text('AUTOMOTIVE AI CARE', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Body Repair\nMade Simple.', style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 8),
          Text('Instant body repair estimation & real-time tracking. Get your car shining faster, with absolute transparency.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => context.go('/estimator'),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Get Free AI Estimate', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRepairWidget(ThemeData theme, Map<String, dynamic> job) {
    final statusStr = job['status'] as String? ?? 'Unknown';
    final isAllocated = statusStr.compareTo('1') > 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.directions_car, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ACTIVE REPAIR', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                    Text('Job #' + job['id'].toString().substring(0, 8), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: theme.colorScheme.secondary, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(statusStr.replaceAll('_', ' ').toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('Repair Progress', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    Text(isAllocated ? 'In Progress' : 'Pending', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: isAllocated ? null : 0.1,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Updated: ' + job['created_at'].toString().substring(0, 10), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => context.go('/track/' + job['id'].toString()),
                icon: const Icon(Icons.sensors, size: 16),
                label: const Text('Track Live', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildQuickActions(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => context.go('/estimator'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.photo_camera, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text('New Claim', style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('Scan car damage with AI', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Start Scan', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, size: 14, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => context.go('/profile'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.query_stats, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 12),
                  Text('Track Status', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Live workshop cameras', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('View Queue', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, size: 14, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureHighlight(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 144,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuD6_i0-JevFbsWeSnSO-l4IiY1GyUK7WV8CKi3uoVHz3hbyZvdc9AjQf28OLUud3jPKYG3nJqCx453hc1_drevXy14QhHxmO1J31oVAFFW9t0n_DFjBq83jjXHNjCcvugxkPP4SJKyCim_FG1XQFvvx3hRzreVpwfziy22BMKVxMeX1GaMZ_bcd8S-duhC43IxiXpwE12m-t3AVup9TPAlQGgk-M_Hmp38P27rvWsy6r0XRXjdYKkbnxw'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('AI TELEMETRY HUB', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold)),
                    Text('SLA < 48 Hrs', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Jabodetabek Certified Network', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Over 38 OEM-compliant spray booths with digitized color-matching precision down to 99.4% factory accuracy.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SEAMLESS PROCESS', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                  Text('How It Works', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, shape: BoxShape.circle),
                child: Icon(Icons.verified_user, size: 16, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStepItem(theme, '1', 'Snap Damage Photos', 'Take 3 clear photos around your vehicle dents, scratches, or panel gaps directly in the web scanner.', Icons.photo_camera),
          const SizedBox(height: 12),
          _buildStepItem(theme, '2', 'Instant AI Assessment', 'Get sub-millimeter part analysis and guaranteed fixed-price estimate with parts catalog breakdown.', Icons.smart_toy),
          const SizedBox(height: 12),
          _buildStepItem(theme, '3', 'Select Hub & Bay', 'Choose your closest certified workshop and lock priority slot reservation with door-to-door towing.', Icons.garage),
          const SizedBox(height: 12),
          _buildStepItem(theme, '4', 'Live Tracking to Handover', 'Watch real-time prep, booth painting, and quality control telemetry until delivery back to your driveway.', Icons.check_circle),
        ],
      ),
    );
  }

  Widget _buildStepItem(ThemeData theme, String number, String title, String description, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(number, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentInspections(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Inspections', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text('100% Guaranteed', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: const DecorationImage(
                      image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuCE6uwD7ofjFSiCWhMiFGQD3Y0UrKl8Y3YkAb5-O4Gi_FEIqMalS-4jdQXRW3Zjx5JELKha7HI-FBhuxXWs1wEPRQxhc1CJTArcb5HqJSgtGvznaKJoIkbHLnkp_hTQZ3LTYj1gwxlzuAZ1NKxa8l97kWBOvYL6JwL2MncDJdAsIbbAMbRKXMe47PKRa3Iu1QTGnCdbcaF9EMVCJHoONkKT2DMKKiiLi8jMSO3bZCliuQDyTTBIaHZQww'),
                      fit: BoxFit.cover,
                    ),
                  ),
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Bumper Repair', style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: const DecorationImage(
                      image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuB0Vm52V0Oiw2niui1LP_P5o0HD_NstOTd58mvawvQm66g_yE7X1Z5no1FWGtJ7vhWrPkuWIEW5upsuL6ya7f5RoSMizLmetbHrHztG9NrUl5NpURzmrttwBAA-PDHNgrYLUJkQ_r7ouXfnZkNX6fMdQvf3ZJY_oqrcGTrIV9Q0XH9XrxMdfoznTa1UKhG7y1NvqykaIcRmK_f4dx6HQbziRpHqUlXLTHT-Iz8a2lg2eEBth0HFopUKYg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Color Matching', style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBadges(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Text('VERIFIED STANDARDS', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Trusted by Thousands Across Jabodetabek and Bandung', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          _buildBadgeItem(theme, 'Certified Partner Hubs', '38+ Centers in Jakarta Bogor Depok Tangerang Bekasi and Bandung', Icons.hub, AppColors.primary),
          const SizedBox(height: 8),
          _buildBadgeItem(theme, 'Garda Oto & Astra SLA Compliant', 'Direct insurance paperwork integration & warranty', Icons.shield, AppColors.primary),
          const SizedBox(height: 8),
          _buildBadgeItem(theme, '4.9 / 5 Rating (12,000+ Drivers)', '98.7% on-time delivery metric verified by telemetry', Icons.star, theme.colorScheme.secondary),
          const SizedBox(height: 16),
          // Partner Registration Link
          Center(
            child: TextButton.icon(
              onPressed: () => context.go('/partner/register'),
              icon: const Icon(Icons.handshake),
              label: const Text('Become a Certified Partner Workshop'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.fireRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeItem(ThemeData theme, String title, String subtitle, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterWidget(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NEED QUICK HELP?', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Talk with an on-duty master estimator', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => context.go('/support'),
            icon: const Icon(Icons.chat, size: 16),
            label: const Text('Consult', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerLowest,
              foregroundColor: theme.colorScheme.onSurface,
              elevation: 1,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 36),
            ),
          ),
        ],
      ),
    );
  }
}
