import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';
import '../../../core/widgets/signed_image.dart';
import 'ai_learning_dashboard_controller.dart';

/// AI Learning dashboard: what respondents confirmed or rejected in the
/// estimates the AI produced. Sits beside the AI Damage Model studio, which
/// owns pricing and the engine cascade; this screen owns the accuracy signal.
class AiLearningDashboardScreen extends ConsumerWidget {
  const AiLearningDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.sleekBlack;
    final stats = ref.watch(learningStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ReVAppBar(showBackButton: true),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(learningStatsProvider),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Operations Hub',
                      style: TextStyle(color: AppColors.daysGray, fontSize: 12)),
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppColors.tertiary),
                  const Text('Automated Estimation Core',
                      style: TextStyle(color: AppColors.daysGray, fontSize: 12)),
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppColors.tertiary),
                  Text('AI Learning',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              Text('AI Learning Dashboard',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor)),
              const SizedBox(height: 8),
              const Text(
                'Panel and spare-part verdicts submitted by respondents, used to '
                'measure and correct estimator accuracy.',
                style: TextStyle(color: AppColors.daysGray),
              ),
              const SizedBox(height: 24),
              stats.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Could not load reviews: $e',
                    style: const TextStyle(color: AppColors.error)),
                data: (s) => _Body(stats: s, isDark: isDark, textColor: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.stats,
    required this.isDark,
    required this.textColor,
  });

  final LearningStats stats;
  final bool isDark;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── KPIs
        Row(
          children: [
            Expanded(
              child: _kpi('Panel accuracy',
                  _pct(stats.panelAccuracy),
                  '${stats.confirmedPanelReviews}/${stats.totalPanelReviews} confirmed',
                  Icons.fact_check_outlined, AppColors.fireRed),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _kpi('Spare-part accuracy',
                  _pct(stats.partAccuracy),
                  '${stats.confirmedPartReviews}/${stats.totalPartReviews} confirmed',
                  Icons.settings_suggest_outlined, Colors.blue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _kpi('Reviewed scans',
                  '${stats.reviewedSubmissions}',
                  'of ${stats.totalSubmissions} submissions',
                  Icons.photo_library_outlined, Colors.green),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _kpi('Respondents',
                  '${stats.respondentCount}',
                  'registered accounts',
                  Icons.people_outline, Colors.orange),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Tables
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: _tableCard(
                context,
                'Panel accuracy',
                'Lowest first — where the estimator is wrong most often.',
                stats.panels.isEmpty
                    ? null
                    : Column(
                        children: [
                          for (final p in stats.panels.take(15))
                            _row(
                              context,
                              label: p.panelName,
                              ratio: p.accuracy,
                              detail:
                                  '${p.confirmed}/${p.total} · ${p.rejected} rejected',
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 6,
              child: _tableCard(
                context,
                'Spare-part accuracy',
                'Parts the AI predicted that respondents did or did not confirm.',
                stats.parts.isEmpty
                    ? null
                    : Column(
                        children: [
                          for (final p in stats.parts.take(15))
                            _row(
                              context,
                              label: p.partName,
                              ratio: p.accuracy,
                              detail: '${p.confirmed}/${p.total} confirmed',
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Recent submissions
        _tableCard(
          context,
          'Recent reviewed scans',
          'Photos are stored in R2; the thumbnail is signed on demand.',
          stats.recent.isEmpty
              ? null
              : Column(
                  children: [
                    for (final s in stats.recent)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              height: 42,
                              child: SignedImage(
                                fileKey:
                                    s.photoKeys.isEmpty ? null : s.photoKeys.first,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(s.respondentName,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: textColor)),
                            ),
                            SizedBox(
                              width: 90,
                              child: Text('${s.panelCount} panels',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.daysGray)),
                            ),
                            SizedBox(
                              width: 110,
                              child: Text('${s.reviewedCount} reviewed',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.daysGray)),
                            ),
                            SizedBox(
                              width: 150,
                              child: Text(_date(s.createdAt),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.daysGray)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _kpi(String title, String value, String subtitle, IconData icon,
      Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.daysGray)),
              Icon(icon, size: 20, color: iconColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.daysGray)),
        ],
      ),
    );
  }

  Widget _tableCard(
      BuildContext context, String title, String subtitle, Widget? content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.daysGray)),
          const SizedBox(height: 12),
          content ??
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No reviews yet',
                      style: TextStyle(fontSize: 13, color: textColor)),
                ),
              ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context,
      {required String label, required double ratio, required String detail}) {
    final pct = (ratio * 100).round();
    final color = pct >= 80
        ? AppColors.statusSuccess
        : pct >= 50
            ? AppColors.accentWarning
            : AppColors.fireRed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: textColor)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: AppColors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text('$pct%',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 112,
            child: Text(detail,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.daysGray)),
          ),
        ],
      ),
    );
  }

  static String _pct(double v) => '${(v * 100).round()}%';

  static String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
