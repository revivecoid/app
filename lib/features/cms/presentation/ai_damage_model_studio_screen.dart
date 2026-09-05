import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';

class AiDamageModelStudioScreen extends StatelessWidget {
  const AiDamageModelStudioScreen({super.key});

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
            // Breadcrumbs & Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Operations Hub', style: TextStyle(color: AppColors.daysGray, fontSize: 12)),
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.tertiary),
                    const Text('Automated Estimation Core', style: TextStyle(color: AppColors.daysGray, fontSize: 12)),
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.tertiary),
                    Text('Pricing & AI Model Rules', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(color: AppColors.fireRed, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text('ENGINE v2.4 (ResNet-CarDent)', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: textColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.fireRed.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('VISION MATRIX 2025.03', style: TextStyle(color: AppColors.fireRed, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        const Text('Jabodetabek Zone Alpha', style: TextStyle(color: AppColors.daysGray, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('AI Damage Model & Dynamic Pricing Rules Studio', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 8),
                    const Text('Configure computer vision confidence thresholds, panel repair baseline rates, severity multipliers, and tri-coat formulas.', style: TextStyle(color: AppColors.daysGray)),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.biotech, size: 18),
                      label: const Text('CV Sandbox'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('Audit Logs'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.rocket_launch, size: 18),
                      label: const Text('Deploy Rules'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // KPI Tiles
            Row(
              children: [
                Expanded(child: _buildKpiTile('Active Vision Model', 'v2.4-YOLO-AutoDent', '99.4% OCR & Part Seg', Icons.camera_indoor, AppColors.fireRed, isDark)),
                const SizedBox(width: 16),
                Expanded(child: _buildKpiTile('Calibrated Panels', '14 Panels Active', '100% Geometry Matched', Icons.tune, Colors.blue, isDark)),
                const SizedBox(width: 16),
                Expanded(child: _buildKpiTile('Dynamic Margin Index', '32.5% Target GM', '+2.4% vs Standard', Icons.query_stats, Colors.green, isDark)),
                const SizedBox(width: 16),
                Expanded(child: _buildKpiTile('Production Latency', '340ms Inference', 'ResNet TensorRT', Icons.speed, Colors.orange, isDark)),
              ],
            ),
            const SizedBox(height: 24),
            
            // Main Content Split
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surface : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Panel Rate Editor Matrix', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                            const SizedBox(height: 16),
                            // Placeholder for table
                            Container(
                              height: 300,
                              color: AppColors.background,
                              child: Center(child: Text('Table content goes here', style: TextStyle(color: textColor))),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Right Column
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surface : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.view_in_ar, color: AppColors.fireRed),
                            const SizedBox(width: 8),
                            Text('Live AI Inference Simulator', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(child: Text('AI Image Simulator Placeholder', style: TextStyle(color: Colors.white))),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Simulated Mobile App Quote', style: TextStyle(color: AppColors.daysGray, fontSize: 12)),
                              const SizedBox(height: 4),
                              const Text('Rp 3.575.000', style: TextStyle(color: AppColors.fireRed, fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiTile(String title, String value, String subtitle, IconData icon, Color iconColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.daysGray)),
              Icon(icon, size: 20, color: iconColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.sleekBlack)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.daysGray)),
        ],
      ),
    );
  }
}
