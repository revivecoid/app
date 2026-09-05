import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';

class FrontendContentStudioScreen extends StatelessWidget {
  const FrontendContentStudioScreen({super.key});

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
                    Text('Frontend Content Studio', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
                    SizedBox(height: 8),
                    Text('WYSIWYG style editor for managing app/web landing page content and copy.', style: TextStyle(color: AppColors.daysGray)),
                  ],
                ),
              ],
            ),
            SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surface : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
              ),
              height: 500,
              child: Center(child: Text('Content Editor Placeholder', style: TextStyle(color: textColor))),
            ),
          ],
        ),
      ),
    );
  }
}
