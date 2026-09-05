import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';

class CustomerConciergeNlpStudioScreen extends StatelessWidget {
  const CustomerConciergeNlpStudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.sleekBlack;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ReVAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer Concierge AI NLP Intent Studio', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 8),
                    const Text('Manage NLP intents, training phrases, and chatbot routing rules.', style: TextStyle(color: AppColors.daysGray)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surface : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
              ),
              height: 500,
              child: Center(child: Text('NLP Intent Management Interface Placeholder', style: TextStyle(color: textColor))),
            ),
          ],
        ),
      ),
    );
  }
}
