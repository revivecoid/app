import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
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

// Step labels and descriptions are resolved at runtime via AppL.
// See _stepLabel(l, index) / _stepDesc(l, index) helpers below.

String _stepLabel(AppL l, int i) {
  const keys = [
    'trackingStepIntake', 'trackingStepEvaluated', 'trackingStepBooked',
    'trackingStepPaid', 'trackingStepAdmitted', 'trackingStepActive',
    'trackingStepQC', 'trackingStepReady', 'trackingStepDone',
  ];
  switch (i) {
    case 0: return l.trackingStepIntake;
    case 1: return l.trackingStepEvaluated;
    case 2: return l.trackingStepBooked;
    case 3: return l.trackingStepPaid;
    case 4: return l.trackingStepAdmitted;
    case 5: return l.trackingStepActive;
    case 6: return l.trackingStepQC;
    case 7: return l.trackingStepReady;
    default: return l.trackingStepDone;
  }
}

String _stepDesc(AppL l, int i) {
  switch (i) {
    case 0: return l.trackingDescIntake;
    case 1: return l.trackingDescEvaluated;
    case 2: return l.trackingDescBooked;
    case 3: return l.trackingDescPaid;
    case 4: return l.trackingDescAdmitted;
    case 5: return l.trackingDescActive;
    case 6: return l.trackingDescQC;
    case 7: return l.trackingDescReady;
    default: return l.trackingDescDone;
  }
}

// ─── Main Screen ────────────────────────────────────────────────────────────
class LiveStepperTimeline extends ConsumerStatefulWidget {
  final String jobId;
  const LiveStepperTimeline({super.key, required this.jobId});

  @override
  ConsumerState<LiveStepperTimeline> createState() => _LiveStepperTimelineState();
}

class _LiveStepperTimelineState extends ConsumerState<LiveStepperTimeline> {
  bool _isCancelling = false;

  // ── Cancel RPC ─────────────────────────────────────────────────────────────
  Future<void> _confirmAndCancelJob() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 10),
          Text('Cancel Repair Job?'),
        ]),
        content: const Text(
          'This will cancel your repair request and release any booking slot.\n\n'
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
    setState(() => _isCancelling = true);

    try {
      final result = await Supabase.instance.client
          .rpc('customer_cancel_job', params: {'p_job_id': widget.jobId});
      final response = result is Map<String, dynamic> ? result : <String, dynamic>{};

      if (!mounted) return;
      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Job cancelled. You can start a new estimate anytime.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ));
        context.go('/'); // Back to landing
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(response['error']?.toString() ?? 'Could not cancel. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      debugPrint('[Tracker] Cancel error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: ${e.toString().replaceAll('PostgrestException', '').trim()}'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final streamState = ref.watch(jobStreamProvider(widget.jobId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = cs.surface;
    final cardColor = isDark ? const Color(0xFF2C2B2C) : cs.surfaceContainerLowest;
    final textColor = cs.onSurface;
    final mutedColor = cs.onSurfaceVariant;

    final status = streamState.currentStatus;
    final isEstimated = status == '2_estimated';
    final isBooked    = status == '3_booked';
    final needsAction = isEstimated || isBooked;

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      Widget inner = Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 1,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: textColor),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppL.of(context)!.trackingLiveTracker, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
              Text(
                widget.jobId.length > 8 ? '#${widget.jobId.substring(0, 8).toUpperCase()}' : '#${widget.jobId}',
                style: TextStyle(fontSize: 11, color: AppColors.fireRed, letterSpacing: 1.0),
              ),
            ],
          ),
          actions: [
            if (streamState.isDisconnected)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  backgroundColor: Colors.orange,
                  label: Text('Reconnecting…', style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 11)),
                  padding: EdgeInsets.zero,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('LIVE', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
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

        // ── Bottom action bar — only shown for pre-payment states ──────────
        bottomNavigationBar: needsAction
            ? _ActionBar(
                isEstimated: isEstimated,
                jobId: widget.jobId,
                isCancelling: _isCancelling,
                onCancel: _confirmAndCancelJob,
              )
            : null,

        body: streamState.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.fireRed))
            : _TrackerBody(
                jobId: widget.jobId,
                status: status,
                photos: streamState.photos,
                cardColor: cardColor,
                textColor: textColor,
                mutedColor: mutedColor,
                isDark: isDark,
              ),
      );
      return isDesktop
          ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: inner))
          : inner;
    });
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
          SizedBox(height: 16),

          // ─── Timeline ───
          _card(
            cardColor: cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppL.of(context)!.trackingStatus, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                SizedBox(height: 4),
                Text(
                  'Step ${currentStepIndex + 1} of ${_statusSteps.length}',
                  style: TextStyle(fontSize: 12, color: AppColors.fireRed, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                ...List.generate(_statusSteps.length, (i) {
                  final stepStatus = i < currentStepIndex
                      ? _StepState.completed
                      : i == currentStepIndex
                          ? _StepState.active
                          : _StepState.pending;
                  return _TimelineStep(
                    label: _stepLabel(AppL.of(context)!, i),
                    description: _stepDesc(AppL.of(context)!, i),
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
          SizedBox(height: 16),

          // ─── Live Photo Stream ───
          _card(
            cardColor: cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.camera_alt, color: AppColors.fireRed, size: 18),
                    SizedBox(width: 8),
                    Text(AppL.of(context)!.trackingWorkshop, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                  ],
                ),
                SizedBox(height: 12),
                if (progressPhotos.isEmpty)
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.10) : Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_search, size: 36, color: mutedColor),
                        SizedBox(height: 8),
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
                    physics: NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
                                color: Theme.of(context).colorScheme.outlineVariant,
                                child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.outline),
                              ),
                            ),
                            Positioned(
                              bottom: 4, left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  photo.context.toUpperCase(),
                                  style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 9, fontWeight: FontWeight.bold),
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
          SizedBox(height: 16),

          // ─── Job Details ───
          _card(
            cardColor: cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Job Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                SizedBox(height: 12),
                _detailRow(Icons.tag, 'Job ID', jobId, textColor, mutedColor),
                SizedBox(height: 8),
                _detailRow(Icons.info_outline, 'Current Status', status.replaceAll('_', ' ').toUpperCase(), textColor, mutedColor),
                SizedBox(height: 8),
                _detailRow(Icons.photo_library, 'Workshop Photos', '${progressPhotos.length} uploaded', textColor, mutedColor),
              ],
            ),
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color tc, Color mc) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.fireRed),
        SizedBox(width: 10),
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
        boxShadow: [BoxShadow(color: Color(0xFF000000).withValues(alpha: 0.06), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

// ─── Action Bar — shown only for pre-payment jobs ────────────────────────────
class _ActionBar extends StatelessWidget {
  final bool isEstimated;
  final String jobId;
  final bool isCancelling;
  final VoidCallback onCancel;

  const _ActionBar({
    required this.isEstimated,
    required this.jobId,
    required this.isCancelling,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Info hint
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.fireRed.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.fireRed.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 15, color: AppColors.fireRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isEstimated
                        ? 'Your AI estimate is ready — complete your booking to confirm.'
                        : 'Booking saved — complete checkout to secure your repair slot.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.fireRed,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Buttons
          Row(
            children: [
              // Cancel
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isCancelling ? null : onCancel,
                  icon: isCancelling
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                        )
                      : const Icon(Icons.cancel_outlined, size: 16),
                  label: Text(
                    isCancelling ? 'Cancelling…' : 'Cancel Job',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Continue
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: isCancelling
                      ? null
                      : () {
                          if (isEstimated) {
                            context.push('/booking/$jobId');
                          } else {
                            context.push('/checkout/$jobId');
                          }
                        },
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(
                    isEstimated ? 'Continue Booking' : 'Complete Checkout',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.fireRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
          Icon(Icons.sync, color: AppColors.fireRed, size: 18),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CURRENT STATUS', style: TextStyle(fontSize: 10, color: AppColors.fireRed, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              Text(label, style: TextStyle(fontSize: 14, color: AppColors.fireRed, fontWeight: FontWeight.bold)),
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

    final cs = Theme.of(context).colorScheme;
    Color dotColor = isPending
        ? cs.surfaceContainerHigh
        : isActive
            ? AppColors.fireRed
            : cs.primary;

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
                      ? Icon(Icons.check, size: 13, color: Theme.of(context).colorScheme.onPrimary)
                      : isActive
                          ? Center(child: Icon(Icons.circle, size: 8, color: Theme.of(context).colorScheme.onError))
                          : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: Theme.of(context).colorScheme.surfaceContainerHigh),
                  ),
              ],
            ),
          ),
          SizedBox(width: 10),
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
                            child: Text('ACTIVE', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    SizedBox(height: 3),
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
