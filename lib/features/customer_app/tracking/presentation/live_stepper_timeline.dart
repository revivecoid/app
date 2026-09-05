import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import 'job_stream_controller.dart';

// ─── Status → step index mapping ───────────────────────────────────────────
const _statusSteps = [
  '1_intake',
  '2_estimated',
  '3_booked',
  '4_paid',
  '5_admitted',
  '6_in_progress',
  '7_finished',
  '8_awaiting_delivery',
  '9_done',
];

const _stepLabels = [
  'Intake & Submission',
  'AI Evaluated',
  'Schedule Booked',
  'Payment Confirmed',
  'Vehicle Admitted',
  'Active Body & Painting',
  'Quality Control Passed',
  'Ready for Pickup / Valet',
  'Handover Complete',
];

const _stepDescriptions = [
  'Your repair request has been received and your vehicle details registered.',
  'Our AI has evaluated the damage and produced a cost estimate for your review.',
  'Your appointment slot has been secured at the partner workshop.',
  'Payment received and confirmed. Your vehicle is queued for admission.',
  'Your vehicle has been admitted to the workshop bay and work is starting soon.',
  'Active bodywork and painting operations are underway on your vehicle.',
  'Repair work complete. Your vehicle is undergoing our 32-point quality audit.',
  'Your vehicle is ready for collection or valet pickup.',
  'Handover complete. Thank you for choosing Revive!',
];

// ─── Main Screen ────────────────────────────────────────────────────────────
class LiveStepperTimeline extends ConsumerWidget {
  final String jobId;
  const LiveStepperTimeline({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamState = ref.watch(jobStreamProvider(jobId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1D1C1D) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF2C2B2C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1D1C1D);
    final mutedColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1D1C1D) : Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => context.go('/profile'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live Tracker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
            Text(
              jobId.length > 8 ? '#${jobId.substring(0, 8).toUpperCase()}' : '#$jobId',
              style: TextStyle(fontSize: 11, color: AppColors.fireRed, letterSpacing: 1.0),
            ),
          ],
        ),
        actions: [
          if (streamState.isDisconnected)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Chip(
                backgroundColor: Colors.orange,
                label: Text('Reconnecting…', style: TextStyle(color: Colors.white, fontSize: 11)),
                padding: EdgeInsets.zero,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                backgroundColor: Colors.green.withValues(alpha: 0.15),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.circle, size: 8, color: Colors.green),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: mutedColor),
            tooltip: 'Toggle Theme',
            onPressed: () {
              ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: streamState.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.fireRed))
          : _TrackerBody(
              jobId: jobId,
              status: streamState.currentStatus,
              photos: streamState.photos,
              cardColor: cardColor,
              textColor: textColor,
              mutedColor: mutedColor,
              isDark: isDark,
            ),
    );
  }
}

// ─── Body ───────────────────────────────────────────────────────────────────
class _TrackerBody extends StatelessWidget {
  final String jobId;
  final String status;
  final List<RepairPhoto> photos;
  final Color cardColor;
  final Color textColor;
  final Color mutedColor;
  final bool isDark;

  const _TrackerBody({
    required this.jobId,
    required this.status,
    required this.photos,
    required this.cardColor,
    required this.textColor,
    required this.mutedColor,
    required this.isDark,
  });

  int get currentStepIndex => _statusSteps.indexOf(status).clamp(0, _statusSteps.length - 1);

  @override
  Widget build(BuildContext context) {
    final progressPhotos = photos.where((p) => p.context == 'progress' || p.context == 'finished').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Status Banner ───
          _StatusBanner(status: status, mutedColor: mutedColor),
          const SizedBox(height: 16),

          // ─── Timeline ───
          _card(
            cardColor: cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Service Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                const SizedBox(height: 4),
                Text(
                  'Step ${currentStepIndex + 1} of ${_statusSteps.length}',
                  style: TextStyle(fontSize: 12, color: AppColors.fireRed, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ...List.generate(_statusSteps.length, (i) {
                  final stepStatus = i < currentStepIndex
                      ? _StepState.completed
                      : i == currentStepIndex
                          ? _StepState.active
                          : _StepState.pending;
                  return _TimelineStep(
                    label: _stepLabels[i],
                    description: _stepDescriptions[i],
                    state: stepStatus,
                    isLast: i == _statusSteps.length - 1,
                    textColor: textColor,
                    mutedColor: mutedColor,
                    isDark: isDark,
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ─── Live Photo Stream ───
          _card(
            cardColor: cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.camera_alt, color: AppColors.fireRed, size: 18),
                    const SizedBox(width: 8),
                    Text('Workshop Photo Stream', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                  ],
                ),
                const SizedBox(height: 12),
                if (progressPhotos.isEmpty)
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_search, size: 36, color: mutedColor),
                        const SizedBox(height: 8),
                        Text(
                          'Awaiting photo updates from the workshop floor…',
                          style: TextStyle(color: mutedColor, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: progressPhotos.length,
                    itemBuilder: (context, idx) {
                      final photo = progressPhotos[idx];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              photo.publicUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            ),
                            Positioned(
                              bottom: 4, left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  photo.context.toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ─── Job Details ───
          _card(
            cardColor: cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Job Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                const SizedBox(height: 12),
                _detailRow(Icons.tag, 'Job ID', jobId, textColor, mutedColor),
                const SizedBox(height: 8),
                _detailRow(Icons.info_outline, 'Current Status', status.replaceAll('_', ' ').toUpperCase(), textColor, mutedColor),
                const SizedBox(height: 8),
                _detailRow(Icons.photo_library, 'Workshop Photos', '${progressPhotos.length} uploaded', textColor, mutedColor),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color tc, Color mc) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.fireRed),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: mc)),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: tc)),
          ],
        ),
      ],
    );
  }

  Widget _card({required Widget child, required Color cardColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}

// ─── Status Banner ───────────────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final String status;
  final Color mutedColor;
  const _StatusBanner({required this.status, required this.mutedColor});

  @override
  Widget build(BuildContext context) {
    final label = status.replaceAll(RegExp(r'^\d+_'), '').replaceAll('_', ' ').toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.fireRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.fireRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync, color: AppColors.fireRed, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CURRENT STATUS', style: TextStyle(fontSize: 10, color: AppColors.fireRed, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              Text(label, style: const TextStyle(fontSize: 14, color: AppColors.fireRed, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Timeline Step ───────────────────────────────────────────────────────────
enum _StepState { completed, active, pending }

class _TimelineStep extends StatelessWidget {
  final String label;
  final String description;
  final _StepState state;
  final bool isLast;
  final Color textColor;
  final Color mutedColor;
  final bool isDark;

  const _TimelineStep({
    required this.label,
    required this.description,
    required this.state,
    required this.isLast,
    required this.textColor,
    required this.mutedColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = state == _StepState.completed;
    final isActive = state == _StepState.active;
    final isPending = state == _StepState.pending;

    Color dotColor = isPending
        ? (isDark ? Colors.white12 : Colors.grey[300]!)
        : isActive
            ? AppColors.fireRed
            : Colors.green;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Dot + connector ───
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  child: isCompleted
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : isActive
                          ? const Center(child: Icon(Icons.circle, size: 8, color: Colors.white))
                          : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: isDark ? Colors.white12 : Colors.grey[200]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // ─── Content ───
          Expanded(
            child: Opacity(
              opacity: isPending ? 0.55 : 1.0,
              child: Container(
                margin: EdgeInsets.only(bottom: isLast ? 0 : 20),
                padding: isActive ? const EdgeInsets.all(10) : EdgeInsets.zero,
                decoration: isActive
                    ? BoxDecoration(
                        color: AppColors.fireRed.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.fireRed.withValues(alpha: 0.25)),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isActive ? AppColors.fireRed : textColor,
                            ),
                          ),
                        ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.fireRed, borderRadius: BorderRadius.circular(8)),
                            child: const Text('ACTIVE', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(description, style: TextStyle(fontSize: 11, color: isActive ? AppColors.fireRed.withValues(alpha: 0.85) : mutedColor)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
