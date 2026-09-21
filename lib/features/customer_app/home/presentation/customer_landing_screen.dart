import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../../../../core/utils/auth_url.dart';

// ── CMS settings provider ──────────────────────────────────────────────────────
final cmsSettingsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  try {
    final res = await Supabase.instance.client.rpc('get_cms_settings');
    if (res is Map) {
      return res.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
  } catch (e) { debugPrint('[Landing] CMS settings error: $e'); }
  return {};
});

// Locale-aware CMS lookup: checks _id suffixed key when locale is 'id'.
String _cmsL(Map<String, String> s, String key, {required String fallback, bool isId = false}) {
  if (isId) {
    final v = s['${key}_id'];
    if (v != null && v.isNotEmpty) return v;
  }
  final v = s[key];
  return (v != null && v.isNotEmpty) ? v : fallback;
}

class CustomerLandingScreen extends ConsumerStatefulWidget {
  CustomerLandingScreen({super.key});

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
      // Exclude terminal states: cancelled and done
      .not('status', 'in', '("0_cancelled","9_done")')
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
    final code = readAuthCode(Uri.base);
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
    final cmsAsync = ref.watch(cmsSettingsProvider);
    final cms = cmsAsync.valueOrNull ?? {};
    final isId = ref.watch(localeProvider).languageCode == 'id';

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      Widget inner = Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: ReVAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeroSection(theme, cms, isId),
            SizedBox(height: 16),
            if (isLoggedIn)
              activeJobAsync.when(
                data: (job) => job != null 
                    ? Column(
                        children: [
                          _buildActiveRepairWidget(theme, job),
                          SizedBox(height: 16),
                        ],
                      )
                    : const SizedBox.shrink(),
                loading: () => Center(child: CircularProgressIndicator()),
                error: (e, st) => Text('Error loading active job: $e'),
              ),
            _buildQuickActions(theme),
            SizedBox(height: 16),
            _buildFeatureHighlight(theme, cms, isId),
            SizedBox(height: 16),
            _buildHowItWorks(theme, cms, isId),
            SizedBox(height: 16),
            _buildRecentInspections(theme),
            SizedBox(height: 16),
            _buildTrustBadges(theme, cms, isId),
            SizedBox(height: 16),
            if (cms['contact_phone'] != null || cms['contact_email'] != null || cms['contact_address'] != null)
              _buildContactSection(theme, cms, isId),
            if (cms['contact_phone'] != null || cms['contact_email'] != null || cms['contact_address'] != null)
              SizedBox(height: 16),
            _buildQuickLinks(theme),
            SizedBox(height: 16),
            _buildFooterWidget(theme),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
      return isDesktop ? Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 800), child: inner)) : inner;
    });
  }

  Widget _buildHeroSection(ThemeData theme, Map<String, String> cms, bool isId) {
    final heroTitle = _cmsL(cms, 'hero_title',    fallback: isId ? 'Perbaikan Bodi\nJadi Mudah.'  : 'Body Repair\nMade Simple.',         isId: isId);
    final heroSub   = _cmsL(cms, 'hero_subtitle', fallback: isId ? 'Estimasi instan berbasis AI & pelacakan real-time. Dapatkan mobil Anda kembali lebih cepat dengan transparansi penuh.' : 'Instant body repair estimation & real-time tracking. Get your car shining faster, with absolute transparency.', isId: isId);
    final heroCta   = _cmsL(cms, 'hero_cta',      fallback: isId ? 'Estimasi AI Gratis'           : 'Get Free AI Estimate',                isId: isId);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: Offset(0, 2)),
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
                Icon(Icons.verified, size: 16, color: AppColors.primary),
                SizedBox(width: 4),
                Text('AUTOMOTIVE AI CARE', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SizedBox(height: 12),
          Text(heroTitle, style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
          SizedBox(height: 8),
          Text(heroSub, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => context.go('/estimator'),
            icon: Icon(Icons.auto_awesome, size: 18),
            label: Text(heroCta, style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.surface,
              minimumSize: Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection(ThemeData theme, Map<String, String> cms, bool isId) {
    final phone = cms['contact_phone'];
    final email = cms['contact_email'];
    final address = cms['contact_address'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CONTACT US', style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (phone != null && phone.isNotEmpty)
            _buildContactRow(theme, Icons.phone_rounded, phone),
          if (email != null && email.isNotEmpty) ...[const SizedBox(height: 8),
            _buildContactRow(theme, Icons.email_rounded, email)],
          if (address != null && address.isNotEmpty) ...[const SizedBox(height: 8),
            _buildContactRow(theme, Icons.location_on_rounded, address)],
        ],
      ),
    );
  }

  Widget _buildContactRow(ThemeData theme, IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.primary),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface))),
    ]);
  }

  Widget _buildActiveRepairWidget(ThemeData theme, Map<String, dynamic> job) {
    final statusStr = job['status'] as String? ?? 'Unknown';
    final jobId = job['id'].toString();

    // Determine what stage the job is at so we show the right actions
    final isEstimated       = statusStr == '2_estimated';  // Needs booking
    final isInvoiced        = statusStr == '3_inspected';  // Re-V invoice issued, needs payment
    // 3_booked = waiting for workshop to admit vehicle — no customer action needed
    final needsAction       = isEstimated || isInvoiced;
    final isActive          = !needsAction && statusStr != '0_cancelled';

    // Progress fraction for the progress bar
    final stages = ['1_intake','2_estimated','3_booked','4_paid','5_admitted','6_in_progress','7_finished','8_awaiting_delivery','9_done'];
    final stageIdx = stages.indexOf(statusStr);
    final progressFraction = stageIdx < 0 ? 0.0 : (stageIdx + 1) / stages.length;

    // Human-readable label
    final statusLabel = statusStr
        .replaceAll(RegExp(r'^\d+_'), '')
        .replaceAll('_', ' ')
        .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        // Highlight pre-payment jobs that need attention
        border: needsAction
            ? Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.5), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.directions_car, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      needsAction ? 'ACTION REQUIRED' : 'ACTIVE REPAIR',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: needsAction ? AppColors.primaryContainer : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Job #${jobId.length > 8 ? jobId.substring(0, 8) : jobId}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: needsAction
                      ? AppColors.primaryContainer.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: needsAction
                      ? Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.4))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: needsAction ? AppColors.primaryContainer : theme.colorScheme.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: needsAction ? AppColors.primaryContainer : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Action-required banner ───────────────────────────────────────
          if (needsAction)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.primaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isInvoiced
                          ? 'Re-V has issued your invoice based on the workshop inspection. Review the final cost and confirm payment.'
                          : isEstimated
                              ? 'Your AI estimate is ready. Continue to complete your booking.'
                              : 'Booking confirmed. Our team is performing the final inspection — you will be notified when the invoice is ready.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.primaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Progress bar ─────────────────────────────────────────────────
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
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('Repair Progress', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    Text(
                      isActive ? 'In Progress' : (needsAction ? 'Awaiting Confirmation' : 'Pending'),
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progressFraction,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Action buttons — status-aware ────────────────────────────────
          if (needsAction) ...[
            // PRE-PAYMENT: Continue + Cancel
            Row(
              children: [
                // Cancel button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmAndCancelJob(context, jobId),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel Job', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Continue button
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (isEstimated) {
                        context.push('/booking/$jobId');
                      } else if (isInvoiced) {
                        context.push('/checkout/$jobId?paymentOnly=true');
                      } else {
                        context.push('/checkout/$jobId');
                      }
                    },
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text(
                      isInvoiced ? 'Review Invoice & Pay' : (isEstimated ? 'Continue Booking' : 'Complete Checkout'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (statusStr == '3_booked') ...[
            // WAITING STATE: Booking confirmed, vehicle not yet admitted
            // Show informational card + Track + Cancel only
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.schedule_outlined, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Waiting for Vehicle Intake',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                            const SizedBox(height: 3),
                            Text(
                              'Your booking is confirmed. Once your vehicle is received, '
                              'our workshop will perform a final inspection and Re-V will issue your invoice. '
                              'You will be notified by email and WhatsApp.',
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade700, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmAndCancelJob(context, jobId),
                        icon: const Icon(Icons.cancel_outlined, size: 15),
                        label: const Text('Cancel Booking', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => context.go('/track/$jobId'),
                        icon: const Icon(Icons.sensors, size: 15),
                        label: const Text('Track Live', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else ...[
            // POST-PAYMENT or tracking state: Track Live only
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Updated: ${job['created_at'].toString().substring(0, 10)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => context.go('/track/$jobId'),
                  icon: const Icon(Icons.sensors, size: 16),
                  label: const Text('Track Live', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Shows a confirmation dialog then calls the customer_cancel_job RPC.
  Future<void> _confirmAndCancelJob(BuildContext context, String jobId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('Cancel Repair Job?'),
          ],
        ),
        content: const Text(
          'This will cancel your repair request. Your estimation data will be preserved '
          'but the booking slot will be released.\n\n'
          'You can start a new estimate at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Job'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final result = await Supabase.instance.client
          .rpc('customer_cancel_job', params: {'p_job_id': jobId});

      final response = result is Map<String, dynamic> ? result : <String, dynamic>{};

      if (!mounted) return;

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job cancelled. You can start a new estimate anytime.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        // Refresh the active job widget
        ref.invalidate(activeJobProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['error']?.toString() ?? 'Could not cancel job. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('[CancelJob] Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('PostgrestException', '').trim()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.photo_camera, color: Theme.of(context).colorScheme.surface),
                  ),
                  SizedBox(height: 12),
                  Text('New Claim', style: theme.textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold)),
                  Text('Scan car damage with AI', style: theme.textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8))),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Start Scan', style: theme.textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 14, color: Theme.of(context).colorScheme.surface),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => context.go('/profile'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: Offset(0, 2)),
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
                  SizedBox(height: 12),
                  Text('Track Status', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Live workshop cameras', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text('View Queue', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 14, color: AppColors.primary),
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

  Widget _buildFeatureHighlight(ThemeData theme, Map<String, String> cms, bool isId) {
    final ftTitle = _cmsL(cms, 'feature_title', fallback: isId ? 'Jaringan Tersertifikasi Jabodetabek' : 'Jabodetabek Certified Network', isId: isId);
    final ftBody  = _cmsL(cms, 'feature_body',  fallback: isId ? 'Lebih dari 38 spray booth OEM-compliant dengan presisi color-matching hingga 99,4% akurasi pabrik.' : 'Over 38 OEM-compliant spray booths with digitized color-matching precision down to 99.4% factory accuracy.', isId: isId);
    final ftBadge = _cmsL(cms, 'feature_badge', fallback: 'SLA < 48 Hrs', isId: isId);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 144,
            decoration: BoxDecoration(
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
                    Text(ftBadge, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                SizedBox(height: 8),
                Text(ftTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text(ftBody, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks(ThemeData theme, Map<String, String> cms, bool isId) {
    // Step fallbacks
    final steps = [
      (_cmsL(cms, 'step_1_title', fallback: isId ? 'Foto Kerusakan' : 'Snap Damage Photos', isId: isId),
       _cmsL(cms, 'step_1_desc',  fallback: isId ? 'Ambil 3 foto jelas seputar penyok, goresan, atau celah panel langsung di web scanner.' : 'Take 3 clear photos around your vehicle dents, scratches, or panel gaps directly in the web scanner.', isId: isId),
       Icons.photo_camera, '1'),
      (_cmsL(cms, 'step_2_title', fallback: isId ? 'Penilaian AI Instan' : 'Instant AI Assessment', isId: isId),
       _cmsL(cms, 'step_2_desc',  fallback: isId ? 'Dapatkan analisis suku cadang sub-milimeter dan estimasi harga tetap yang dijamin.' : 'Get sub-millimeter part analysis and guaranteed fixed-price estimate with parts catalog breakdown.', isId: isId),
       Icons.smart_toy, '2'),
      (_cmsL(cms, 'step_3_title', fallback: isId ? 'Pilih Bengkel & Bay' : 'Select Hub & Bay', isId: isId),
       _cmsL(cms, 'step_3_desc',  fallback: isId ? 'Pilih bengkel tersertifikasi terdekat dan kunci reservasi slot prioritas dengan layanan towing.' : 'Choose your closest certified workshop and lock priority slot reservation with door-to-door towing.', isId: isId),
       Icons.garage, '3'),
      (_cmsL(cms, 'step_4_title', fallback: isId ? 'Lacak Langsung hingga Serah Terima' : 'Live Tracking to Handover', isId: isId),
       _cmsL(cms, 'step_4_desc',  fallback: isId ? 'Pantau real-time persiapan, pengecatan, dan kontrol kualitas hingga pengiriman ke rumah Anda.' : 'Watch real-time prep, booth painting, and quality control telemetry until delivery back to your driveway.', isId: isId),
       Icons.check_circle, '4'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: Offset(0, 2)),
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
          SizedBox(height: 16),
          for (final step in steps) ...[
            _buildStepItem(theme, step.$4, step.$1, step.$2, step.$3),
            SizedBox(height: 12),
          ],
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
            child: Text(number, style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 12),
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
                SizedBox(height: 4),
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
          BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: Offset(0, 2)),
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
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
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
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Bumper Repair', style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 10)),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
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
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Color Matching', style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 10)),
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

  Widget _buildTrustBadges(ThemeData theme, Map<String, String> cms, bool isId) {
    final b1v = _cmsL(cms, 'badge_1_value', fallback: '38+', isId: isId);
    final b1l = _cmsL(cms, 'badge_1_label', fallback: isId ? 'Bengkel Mitra' : 'Partner Hubs', isId: isId);
    final b2v = _cmsL(cms, 'badge_2_value', fallback: '4.9/5', isId: isId);
    final b2l = _cmsL(cms, 'badge_2_label', fallback: isId ? 'Rating Pelanggan' : 'Customer Rating', isId: isId);
    final b3v = _cmsL(cms, 'badge_3_value', fallback: '12K+', isId: isId);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Text('VERIFIED STANDARDS', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text(isId ? 'Terpercaya oleh Ribuan Pengemudi di Jabodetabek dan Bandung' : 'Trusted by Thousands Across Jabodetabek and Bandung',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          SizedBox(height: 16),
          _buildBadgeItem(theme, '$b1v $b1l', isId ? 'Pusat di Jakarta Bogor Depok Tangerang Bekasi dan Bandung' : '38+ Centers in Jakarta Bogor Depok Tangerang Bekasi and Bandung', Icons.hub, AppColors.primary),
          SizedBox(height: 8),
          _buildBadgeItem(theme, 'Garda Oto & Astra SLA Compliant', isId ? 'Integrasi langsung asuransi & garansi' : 'Direct insurance paperwork integration & warranty', Icons.shield, AppColors.primary),
          SizedBox(height: 8),
          _buildBadgeItem(theme, '$b2v $b2l ($b3v+ ${isId ? "Pengemudi" : "Drivers"})', isId ? '98,7% metrik pengiriman tepat waktu terverifikasi telemetri' : '98.7% on-time delivery metric verified by telemetry', Icons.star, theme.colorScheme.secondary),
          SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => context.go('/partner/register'),
              icon: Icon(Icons.handshake),
              label: Text(isId ? 'Bergabung sebagai Bengkel Mitra Tersertifikasi' : 'Become a Certified Partner Workshop'),
              style: TextButton.styleFrom(foregroundColor: AppColors.fireRed),
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
                BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 2),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          SizedBox(width: 12),
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

  Widget _buildQuickLinks(ThemeData theme) {
    final cs = theme.colorScheme;
    final isId = ref.read(localeProvider).languageCode == 'id';
    final links = [
      {'icon': Icons.quiz_rounded, 'label': 'FAQ', 'route': '/faq',
       'sub': isId ? 'Pertanyaan umum' : 'Common questions'},
      {'icon': Icons.info_outline_rounded, 'label': isId ? 'Tentang Kami' : 'About Us', 'route': '/about',
       'sub': isId ? 'Tentang Revive' : 'About Revive'},
      {'icon': Icons.privacy_tip_outlined, 'label': isId ? 'Kebijakan Privasi' : 'Privacy Policy', 'route': '/privacy',
       'sub': isId ? 'Kebijakan privasi' : 'Data & privacy'},
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isId ? 'TAUTAN PENTING' : 'IMPORTANT LINKS', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(children: links.map<Widget>((l) => Expanded(
          child: InkWell(
            onTap: () => context.go(l['route'] as String),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Icon(l['icon'] as IconData, size: 20, color: cs.primary),
                const SizedBox(height: 5),
                Text(l['label'] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
                Text(l['sub'] as String, style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
              ]),
            ),
          ),
        )).toList()),
      ]),
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
              SizedBox(height: 4),
              Text('Talk with an on-duty master estimator', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => context.go('/support'),
            icon: Icon(Icons.chat, size: 16),
            label: Text('Consult', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerLowest,
              foregroundColor: theme.colorScheme.onSurface,
              elevation: 1,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: Size(0, 36),
            ),
          ),
        ],
      ),
    );
  }
}
