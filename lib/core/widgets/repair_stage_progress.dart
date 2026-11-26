import 'package:flutter/material.dart';

import '../jobs/repair_stages.dart';

/// The six-step body & paint progress list, drawn the same way on every surface.
///
/// One widget, three call sites — customer tracker, partner dashboard (desktop
/// and mobile) — because the same six steps shown three different ways is how a
/// customer and a workshop end up disagreeing about what "selesai" means.
///
/// [progress] comes from `job_milestones`. A stage with no row is pending; a row
/// with status `completed` is done. Photo counts are displayed when present but
/// are never a completion condition — progress photos are optional by design.
///
/// [onTapStage] turns the list into a control. When null the list is read-only,
/// which is what the customer sees.
class RepairStageProgressList extends StatelessWidget {
  final Map<String, RepairStageProgress> progress;

  /// `'id'` or `'en'`. Resolved against the stage registry's own labels, so the
  /// workshop floor and the customer read the same words for the same step.
  final String languageCode;

  /// Stages this caller may complete right now. Anything not in here renders as
  /// pending but not tappable. Ignored when [onTapStage] is null.
  final Set<String> actionableKeys;

  final void Function(OpsStageDefinition stage)? onTapStage;

  /// Compact spacing for a dashboard card; the customer tracker uses the
  /// default. Both keep the same dot-and-connector shape.
  final bool dense;

  /// Show the "3 dari 6 tahap selesai" line above the steps.
  final bool showCounter;

  const RepairStageProgressList({
    super.key,
    required this.progress,
    this.languageCode = 'id',
    this.actionableKeys = const {},
    this.onTapStage,
    this.dense = false,
    this.showCounter = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = bodyPaintCompletedCount(progress);
    final total = kBodyPaintStageKeys.length;
    final next = nextBodyPaintStage(progress);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCounter) ...[
          Row(
            children: [
              Text(
                '$done / $total',
                style: TextStyle(
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.bold,
                  color: done == total
                      ? const Color(0xFF059669)
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  done == total ? 'Pengerjaan selesai' : 'Tahap pengerjaan',
                  style: TextStyle(
                    fontSize: dense ? 11 : 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: dense ? 6 : 10),
        ],
        ...List.generate(kBodyPaintStages.length, (i) {
          final stage = kBodyPaintStages[i];
          final entry = progress[stage.stageKey];
          final isDone = entry?.isComplete ?? false;
          final isNext = next?.stageKey == stage.stageKey;
          final canTap = onTapStage != null &&
              !isDone &&
              actionableKeys.contains(stage.stageKey);

          return _StageRow(
            index: i,
            stage: stage,
            label: stage.labelFor(languageCode),
            isDone: isDone,
            isNext: isNext,
            canTap: canTap,
            completedAt: entry?.completedAt,
            photoCount: entry?.photoCount ?? 0,
            isLast: i == kBodyPaintStages.length - 1,
            dense: dense,
            onTap: canTap ? () => onTapStage!(stage) : null,
          );
        }),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  final int index;
  final OpsStageDefinition stage;
  final String label;
  final bool isDone;
  final bool isNext;
  final bool canTap;
  final DateTime? completedAt;
  final int photoCount;
  final bool isLast;
  final bool dense;
  final VoidCallback? onTap;

  const _StageRow({
    required this.index,
    required this.stage,
    required this.label,
    required this.isDone,
    required this.isNext,
    required this.canTap,
    required this.completedAt,
    required this.photoCount,
    required this.isLast,
    required this.dense,
    required this.onTap,
  });

  static const _fireRed = Color(0xFFD10721);
  static const _green = Color(0xFF059669);

  String _date(DateTime d) {
    // WIB, always — the floor and the customer are in the same timezone and a
    // UTC rendering of "14:20" reads as a different day near midnight.
    final wib = d.toUtc().add(const Duration(hours: 7));
    final dd = wib.day.toString().padLeft(2, '0');
    final mm = wib.month.toString().padLeft(2, '0');
    final hh = wib.hour.toString().padLeft(2, '0');
    final mi = wib.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dot = isDone
        ? _green
        : isNext
            ? _fireRed
            : cs.surfaceContainerHigh;
    final titleSize = dense ? 12.0 : 13.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dot + connector
            SizedBox(
              width: dense ? 22 : 26,
              child: Column(
                children: [
                  Container(
                    width: dense ? 18 : 20,
                    height: dense ? 18 : 20,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    child: isDone
                        ? Icon(Icons.check, size: dense ? 11 : 13,
                            color: Colors.white)
                        : isNext
                            ? Center(
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              )
                            : null,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isDone
                            ? _green.withValues(alpha: 0.45)
                            : cs.surfaceContainerHigh,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: dense ? 8 : 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : (dense ? 10 : 14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${index + 1}.',
                          style: TextStyle(
                            fontSize: titleSize - 1,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight:
                                  isDone || isNext ? FontWeight.bold : FontWeight.w500,
                              color: isDone
                                  ? cs.onSurface
                                  : isNext
                                      ? _fireRed
                                      : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (canTap)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _fireRed.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Tandai selesai',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _fireRed,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (isDone) ...[
                      const SizedBox(height: 2),
                      Text(
                        completedAt != null
                            ? '${_date(completedAt!)}'
                                '${photoCount > 0 ? ' · $photoCount foto' : ''}'
                            : (photoCount > 0 ? '$photoCount foto' : 'Selesai'),
                        style: TextStyle(
                          fontSize: dense ? 9 : 10,
                          color: _green,
                        ),
                      ),
                    ] else if (isNext && onTap == null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Sedang dikerjakan',
                        style: TextStyle(
                          fontSize: dense ? 9 : 10,
                          color: _fireRed.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
