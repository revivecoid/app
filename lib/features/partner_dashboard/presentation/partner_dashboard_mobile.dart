import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import 'partner_dashboard_controller.dart';

class PartnerDashboardMobile extends ConsumerWidget {
  const PartnerDashboardMobile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(partnerDashboardProvider);
    final controller = ref.read(partnerDashboardProvider.notifier);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final surfaceColor = isDark ? AppColors.surface : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.sleekBlack;
    final iconColor = isDark ? Colors.white70 : AppColors.sleekBlack;

    // Global Notification Listener mapped for Mobile Viewport constraints
    ref.listen<PartnerDashboardState>(partnerDashboardProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: next.errorMessage!.contains('offline') || next.errorMessage!.contains('successfully') 
                ? Colors.green[800] 
                : AppColors.fireRed,
          ),
        );
      }
    });

    if (state.isLoading && state.activeJobs.isEmpty) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator(color: AppColors.fireRed)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: ReVAppBar(
        title: Text('Garage Floor Mechanic', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
        actions: [
          Badge(
            isLabelVisible: state.unreadMessageCount > 0,
            label: Text(state.unreadMessageCount.toString()),
            child: IconButton(
              icon: Icon(Icons.settings, color: iconColor),
              tooltip: 'Workshop Settings & Commlink',
              onPressed: () => context.push('/partner-dashboard/settings'),
            ),
          ),
          if (state.isOfflineSyncing)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Icon(Icons.sync, color: Colors.greenAccent),
            ),
        ],
      ),
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.only(top: 12.0, left: 12.0, right: 12.0, bottom: 80.0),
            itemCount: state.activeJobs.length,
            itemBuilder: (context, index) {
              final job = state.activeJobs[index];
              return Card(
                color: surfaceColor,
                margin: const EdgeInsets.only(bottom: 12),
                elevation: isDark ? 4 : 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isDark ? Colors.transparent : Colors.grey.shade300)
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Car Identity Column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${job.carMake} ${job.carModel}', 
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor),
                            ),
                            SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black : Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: isDark ? Colors.white30 : Colors.grey),
                              ),
                              child: Text(
                                job.licensePlate.toUpperCase(), 
                                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Status: ${job.status.replaceAll(RegExp(r'^\d+_'), '').toUpperCase()}', 
                              style: const TextStyle(color: AppColors.fireRed, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      
                      // Direct High-Contrast Camera Trigger
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.fireRed.withValues(alpha: 0.1),
                          border: Border.all(color: AppColors.fireRed, width: 2),
                        ),
                        child: IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.camera_alt, color: AppColors.fireRed),
                          onPressed: () => controller.captureAndUploadProgressPhoto(job.id, job.status),
                          tooltip: 'Upload Progress Photo',
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Processing Overlay Guard
          if (state.isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: surfaceColor,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.fireRed, strokeWidth: 2)),
                    const SizedBox(width: 16),
                    Text('Compressing & Uploading...', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
