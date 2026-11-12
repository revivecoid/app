import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Aggregates the respondent reviews of AI estimates into the numbers the
/// admin dashboard shows. Read-only; all reads are gated by the
/// `Admin reads all ...` RLS policies on the ai_learning_* tables.

class PanelAccuracy {
  const PanelAccuracy({
    required this.panelName,
    required this.total,
    required this.confirmed,
  });

  final String panelName;
  final int total;
  final int confirmed;

  double get accuracy => total == 0 ? 0 : confirmed / total;

  /// False positives: the AI flagged the panel but respondents said no.
  int get rejected => total - confirmed;
}

class PartAccuracy {
  const PartAccuracy({
    required this.partName,
    required this.total,
    required this.confirmed,
  });

  final String partName;
  final int total;
  final int confirmed;

  double get accuracy => total == 0 ? 0 : confirmed / total;
}

class SubmissionSummary {
  const SubmissionSummary({
    required this.id,
    required this.respondentName,
    required this.createdAt,
    required this.photoKeys,
    required this.panelCount,
    required this.reviewedCount,
  });

  final String id;
  final String respondentName;
  final DateTime createdAt;
  final List<String> photoKeys;
  final int panelCount;
  final int reviewedCount;
}

class LearningStats {
  const LearningStats({
    required this.totalSubmissions,
    required this.reviewedSubmissions,
    required this.totalPanelReviews,
    required this.confirmedPanelReviews,
    required this.totalPartReviews,
    required this.confirmedPartReviews,
    required this.respondentCount,
    required this.panels,
    required this.parts,
    required this.recent,
  });

  final int totalSubmissions;
  final int reviewedSubmissions;
  final int totalPanelReviews;
  final int confirmedPanelReviews;
  final int totalPartReviews;
  final int confirmedPartReviews;
  final int respondentCount;
  final List<PanelAccuracy> panels;
  final List<PartAccuracy> parts;
  final List<SubmissionSummary> recent;

  double get panelAccuracy =>
      totalPanelReviews == 0 ? 0 : confirmedPanelReviews / totalPanelReviews;

  double get partAccuracy =>
      totalPartReviews == 0 ? 0 : confirmedPartReviews / totalPartReviews;
}

final learningStatsProvider = FutureProvider<LearningStats>((ref) async {
  final db = Supabase.instance.client;

  final submissions = await db
      .from('ai_learning_submissions')
      .select('id, respondent_id, photo_paths, created_at, ai_result')
      .order('created_at', ascending: false)
      .limit(200);

  final panelReviews = await db
      .from('ai_learning_panel_reviews')
      .select('submission_id, panel_name, verdict');

  final partReviews = await db
      .from('ai_learning_part_reviews')
      .select('submission_id, panel_name, part_name, verdict');

  final respondents = await db
      .from('ai_learning_respondents')
      .select('user_id, full_name');

  final names = <String, String>{
    for (final r in (respondents as List))
      if (r is Map) r['user_id'].toString(): (r['full_name'] ?? '').toString(),
  };

  final panelAgg = <String, List<int>>{}; // name -> [total, confirmed]
  for (final r in (panelReviews as List)) {
    if (r is! Map) continue;
    final name = (r['panel_name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final agg = panelAgg.putIfAbsent(name, () => [0, 0]);
    agg[0]++;
    if (r['verdict'] == true) agg[1]++;
  }

  final partAgg = <String, List<int>>{};
  for (final r in (partReviews as List)) {
    if (r is! Map) continue;
    final name = (r['part_name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final agg = partAgg.putIfAbsent(name, () => [0, 0]);
    agg[0]++;
    if (r['verdict'] == true) agg[1]++;
  }

  final reviewedBySubmission = <String, int>{};
  for (final r in [...(panelReviews), ...(partReviews)]) {
    if (r is! Map) continue;
    final id = r['submission_id']?.toString();
    if (id == null) continue;
    reviewedBySubmission[id] = (reviewedBySubmission[id] ?? 0) + 1;
  }

  final recent = <SubmissionSummary>[];
  for (final s in (submissions as List).take(25)) {
    if (s is! Map) continue;
    final id = s['id'].toString();
    final ai = s['ai_result'];
    var panelCount = 0;
    if (ai is Map) {
      final assessment = ai['assessment'];
      final list = assessment is Map
          ? assessment['damaged_panels_detail']
          : ai['damaged_panels_detail'];
      if (list is List) panelCount = list.length;
    }
    recent.add(SubmissionSummary(
      id: id,
      respondentName: names[s['respondent_id'].toString()] ?? 'Respondent',
      createdAt:
          DateTime.tryParse(s['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      photoKeys: (s['photo_paths'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      panelCount: panelCount,
      reviewedCount: reviewedBySubmission[id] ?? 0,
    ));
  }

  int confirmedOf(List r) =>
      r.where((e) => e is Map && e['verdict'] == true).length;

  return LearningStats(
    totalSubmissions: (submissions).length,
    reviewedSubmissions: reviewedBySubmission.length,
    totalPanelReviews: (panelReviews).length,
    confirmedPanelReviews: confirmedOf(panelReviews),
    totalPartReviews: (partReviews).length,
    confirmedPartReviews: confirmedOf(partReviews),
    respondentCount: (respondents).length,
    panels: panelAgg.entries
        .map((e) => PanelAccuracy(
              panelName: e.key,
              total: e.value[0],
              confirmed: e.value[1],
            ))
        .toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy)),
    parts: partAgg.entries
        .map((e) => PartAccuracy(
              partName: e.key,
              total: e.value[0],
              confirmed: e.value[1],
            ))
        .toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy)),
    recent: recent,
  );
});
