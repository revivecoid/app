import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class CustomerSupportScreen extends StatelessWidget {
  const CustomerSupportScreen({super.key});

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: const ReVAppBar(title: Text('FAQ & Support'), showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page header
                Text(
                  'How can we help you?',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Find answers to common questions or reach out to our team.',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.daysGray),
                ),
                SizedBox(height: 32),

                // ── Contact Cards ───────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _buildContactCard(
                        context,
                        icon: Icons.chat_bubble_outline,
                        title: 'Live Chat',
                        subtitle: 'Talk to a master estimator',
                        actionLabel: 'Open Chat',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Live chat launching soon'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        ),
                        isDark: isDark,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildContactCard(
                        context,
                        icon: Icons.phone_outlined,
                        title: 'Call Us',
                        subtitle: '+62 800-123-456',
                        actionLabel: 'Copy Number',
                        onTap: () =>
                            _copyToClipboard(context, '+62800123456', 'Phone number'),
                        isDark: isDark,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildContactCard(
                        context,
                        icon: Icons.email_outlined,
                        title: 'Email',
                        subtitle: 'support@re-v.co.id',
                        actionLabel: 'Copy Email',
                        onTap: () =>
                            _copyToClipboard(context, 'support@re-v.co.id', 'Email'),
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ── Emergency hotlines strip ────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primaryContainer.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_taxi,
                            color: AppColors.primaryContainer, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('24/7 Towing & Emergency Hotline',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.sleekBlack)),
                            Text('+62 800-TOW-REVIVE  ·  WhatsApp preferred',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.daysGray)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _copyToClipboard(context, '+6280086973483', 'Hotline'),
                        child: const Text('Copy',
                            style: TextStyle(color: AppColors.primaryContainer)),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 32),

                // ── FAQ ─────────────────────────────────────────────────────
                Text(
                  'Frequently Asked Questions',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),

                _buildFaqItem(
                  context,
                  'How does the AI estimation work?',
                  'Simply upload 3–4 photos of the damaged area from different angles. '
                      'Our Vision AI analyses the depth and span of the damage and provides '
                      'an estimated repair cost and time within seconds.',
                  isDark,
                ),
                _buildFaqItem(
                  context,
                  'Can I choose which partner workshop handles my repair?',
                  'Yes. After receiving the AI estimate, you will see a list of certified '
                      'partner workshops in your area. You can select one based on ratings, '
                      'distance, and availability.',
                  isDark,
                ),
                _buildFaqItem(
                  context,
                  'Is the repair quality guaranteed?',
                  'All re-V certified partners adhere to our SLA standards, and all repairs '
                      'come with a 24-month warranty on workmanship and paint matching '
                      'verified by our digital telemetry certificate.',
                  isDark,
                ),
                _buildFaqItem(
                  context,
                  'How do I track my repair progress?',
                  'Open the "Digital Garage" section of your profile. The Live Tracker '
                      'shows real-time stage updates — from intake, through active bodywork '
                      'and painting, to handover. Each stage is photo-documented.',
                  isDark,
                ),
                _buildFaqItem(
                  context,
                  'What is the Revive 24-Month Paint Guarantee?',
                  'Every job completed through re-V includes a digitally signed 24-month '
                      'guarantee certificate covering paint adhesion, colour accuracy, and '
                      'surface finish. It is stored in your Garage Profile and transferable '
                      'with the vehicle.',
                  isDark,
                ),
                _buildFaqItem(
                  context,
                  'How are insurance claims handled?',
                  'Link your Garda Oto or Astra insurance policy in Profile → Saved Insurance '
                      'Policies. Our platform auto-generates the required loss-adjustment '
                      'documentation and submits directly to your insurer for faster approval.',
                  isDark,
                ),

                const SizedBox(height: 32),

                // ── Back to Profile ─────────────────────────────────────────
                Center(
                  child: TextButton.icon(
                    onPressed: () => context.go('/profile'),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back to My Garage Profile'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryContainer),
                  ),
                ),
                SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (!isDark)
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: AppColors.primaryContainer),
          ),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryContainer,
                side: BorderSide(
                    color: AppColors.primaryContainer.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(actionLabel,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem(
      BuildContext context, String question, String answer, bool isDark) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(question,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(answer,
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.6,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
