import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/session_health.dart';
import '../ops_access.dart';
import 'ops_stage_photo_screen.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

/// Loads all milestones + their photo counts for a given job.
/// Returns a map of stage_key → milestone row (with photo_count).
///
/// Wrapped in retryOnStaleToken: these are the reads that failed with
/// PGRST303 when the session carried a future-dated token, and this keeps a
/// token that goes bad mid-session from locking an operator out of the list.
final jobMilestonesProvider = FutureProvider.autoDispose
    .family<Map<String, Map<String, dynamic>>, String>((ref, jobId) async {
  return retryOnStaleToken(Supabase.instance.client, () async {
    final res = await Supabase.instance.client
        .from('job_milestones')
        .select('id, stage_key, milestone_name, status, completed_by, completed_at, notes')
        .eq('job_id', jobId);

    final Map<String, Map<String, dynamic>> byKey = {};
    for (final row in List<Map<String, dynamic>>.from(res)) {
      final key = row['stage_key'] as String? ?? '';
      if (key.isNotEmpty) byKey[key] = row;
    }

    // Attach photo counts per milestone
    if (byKey.isNotEmpty) {
      final milestoneIds = byKey.values.map((r) => r['id'] as String).toList();
      final photos = await Supabase.instance.client
          .from('job_milestone_photos')
          .select('milestone_id')
          .inFilter('milestone_id', milestoneIds);

      final counts = <String, int>{};
      for (final p in List<Map<String, dynamic>>.from(photos)) {
        final mid = p['milestone_id'] as String;
        counts[mid] = (counts[mid] ?? 0) + 1;
      }

      for (final entry in byKey.entries) {
        final mid = entry.value['id'] as String;
        byKey[entry.key]!['photo_count'] = counts[mid] ?? 0;
      }
    }

    return byKey;
  });
});

/// Loads the job's current status and customer_id.
final jobStatusProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, jobId) async {
  return retryOnStaleToken(Supabase.instance.client, () async {
    final res = await Supabase.instance.client
        .from('repair_jobs')
        .select('id, status, customer_id')
        .eq('id', jobId)
        .maybeSingle();
    return res != null ? Map<String, dynamic>.from(res) : null;
  });
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class OpsMilestonesScreen extends ConsumerWidget {
  final String jobId;
  const OpsMilestonesScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = Supabase.instance.client.auth.currentUser?.appMetadata['role'] as String?;
    final milestonesAsync = ref.watch(jobMilestonesProvider(jobId));
    final jobAsync = ref.watch(jobStatusProvider(jobId));
    final cs = Theme.of(context).colorScheme;

    // The workshop owner decides whether staff and drivers are limited to their
    // own stages or may complete any of them; the same rule the photo screen
    // enforces on submit, so a stage is never offered here only to be refused
    // there.
    final mode = ref.watch(opsViewModeProvider).valueOrNull ?? OpsViewMode.allAccess;

    // Determine which stages are visible to this role
    final visibleStages = kOpsStages
        .where((s) => opsRoleMayActOnStage(mode, role, s.allowedRoles))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Repair Stages'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(jobMilestonesProvider(jobId));
              ref.invalidate(jobStatusProvider(jobId));
            },
          ),
        ],
      ),
      body: jobAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (job) {
          if (job == null) {
            return const Center(child: Text('Job not found.'));
          }
          final currentStatus = job['status'] as String;
          final customerId = job['customer_id'] as String;

          return milestonesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (completedStages) {
              return Column(
                children: [
                  // ── Status chip ─────────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: cs.surfaceContainerHighest,
                    child: Row(children: [
                      const Icon(Icons.info_outline, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Job status: $currentStatus',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),

                  // ── Stage list ──────────────────────────────────────────────
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: visibleStages.length,
                      itemBuilder: (context, index) {
                        final stage = visibleStages[index];
                        final milestone = completedStages[stage.stageKey];
                        final isComplete = milestone != null &&
                            milestone['status'] == 'completed';
                        final photoCount = milestone?['photo_count'] as int? ?? 0;
                        final completedAt = milestone?['completed_at'] as String?;

                        // Determine if this stage is actionable
                        final canAct = _stageIsActionable(
                          stage: stage,
                          currentStatus: currentStatus,
                          isComplete: isComplete,
                          mode: mode,
                          role: role,
                        );

                        return _StageTile(
                          stage: stage,
                          isComplete: isComplete,
                          photoCount: photoCount,
                          completedAt: completedAt,
                          canAct: canAct,
                          onTap: canAct
                              ? () async {
                                  final refreshed = await context.push<bool>(
                                    '/ops/stage-photo/$jobId/$customerId/${stage.stageKey}',
                                  );
                                  if (refreshed == true) {
                                    ref.invalidate(jobMilestonesProvider(jobId));
                                    ref.invalidate(jobStatusProvider(jobId));
                                  }
                                }
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// A stage is actionable when:
  ///   - It has not been completed yet
  ///   - The caller may act on it for this workshop's access mode
  ///   - The job's current status is consistent with starting this stage
  bool _stageIsActionable({
    required OpsStageDefinition stage,
    required String currentStatus,
    required bool isComplete,
    required OpsViewMode mode,
    required String? role,
  }) {
    if (isComplete) return false;
    if (!opsRoleMayActOnStage(mode, role, stage.allowedRoles)) return false;

    switch (stage.stageKey) {
      case 'vehicle_intake':
        return currentStatus == '3_booked' || currentStatus == '4_paid';
      case 'disassembly':
        return currentStatus == '5_admitted' || currentStatus == '6_in_progress';
      case 'welding':
      case 'body_filler':
      case 'painting':
      case 'polishing':
        return currentStatus == '6_in_progress';
      case 'qc_finished':
        return currentStatus == '6_in_progress';
      case 'delivery':
        return currentStatus == '8_awaiting_delivery';
      default:
        return false;
    }
  }
}

// ─── Stage tile ───────────────────────────────────────────────────────────────

class _StageTile extends StatelessWidget {
  final OpsStageDefinition stage;
  final bool isComplete;
  final int photoCount;
  final String? completedAt;
  final bool canAct;
  final VoidCallback? onTap;

  const _StageTile({
    required this.stage,
    required this.isComplete,
    required this.photoCount,
    required this.completedAt,
    required this.canAct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color leadingBg;
    Color leadingFg;
    IconData leadingIcon;

    if (isComplete) {
      leadingBg = Colors.green.shade100;
      leadingFg = Colors.green.shade900;
      leadingIcon = Icons.check_circle;
    } else if (canAct) {
      leadingBg = const Color(0xFFFFE1DE);
      leadingFg = const Color(0xFFD10721);
      leadingIcon = Icons.play_circle_outline;
    } else {
      leadingBg = cs.surfaceContainerHighest;
      leadingFg = cs.onSurfaceVariant;
      leadingIcon = Icons.radio_button_unchecked;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Leading icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: leadingBg, shape: BoxShape.circle),
                child: Icon(leadingIcon, color: leadingFg, size: 22),
              ),
              const SizedBox(width: 14),

              // Stage info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stage.label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isComplete
                            ? cs.onSurface
                            : (canAct ? cs.onSurface : cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (isComplete && completedAt != null) ...[
                      Text(
                        _formatDate(completedAt!),
                        style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                      ),
                      if (photoCount > 0)
                        Text(
                          '$photoCount photo${photoCount != 1 ? 's' : ''} uploaded',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                    ] else if (canAct) ...[
                      Text(
                        'Tap to add photos & complete stage',
                        style: TextStyle(fontSize: 11, color: const Color(0xFFD10721)),
                      ),
                    ] else ...[
                      Text(
                        'Awaiting prior stages or job status',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),

              // Trailing
              if (canAct)
                const Icon(Icons.chevron_right, size: 20)
              else if (isComplete)
                Icon(Icons.camera_alt_outlined, size: 18, color: Colors.green.shade700),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
