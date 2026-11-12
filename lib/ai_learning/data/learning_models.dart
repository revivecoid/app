library;

/// Models for the panels and spare parts the AI returns, as reviewed by respondents.
///
/// Parsing follows the vision-estimation response: structuredData.assessment
/// .damaged_panels_detail[], each with panel_name, panel_severity and
/// spare_parts_needed[] (name, quantity, reason).

class LearningPart {
  const LearningPart({
    required this.name,
    required this.quantity,
    required this.reason,
  });

  final String name;
  final int quantity;
  final String reason;

  factory LearningPart.fromJson(Map<String, dynamic> json) {
    final rawQty = json['quantity'];
    return LearningPart(
      name: (json['name'] ?? '').toString().trim(),
      quantity: rawQty is num ? rawQty.toInt() : 1,
      reason: (json['reason'] ?? '').toString(),
    );
  }
}

class LearningPanel {
  const LearningPanel({
    required this.name,
    required this.severity,
    required this.parts,
  });

  final String name;
  final String? severity;
  final List<LearningPart> parts;
}

/// Extracts unique panels (and unique parts per panel) from a vision-estimation
/// structuredData map. Duplicates are dropped because the review tables have
/// unique keys on (submission, panel) and (submission, panel, part).
List<LearningPanel> parseDamagedPanels(Map<String, dynamic>? structuredData) {
  if (structuredData == null) return const [];

  final assessment = structuredData['assessment'];
  final raw = assessment is Map<String, dynamic>
      ? assessment['damaged_panels_detail']
      : structuredData['damaged_panels_detail'];
  if (raw is! List) return const [];

  final seenPanels = <String>{};
  final panels = <LearningPanel>[];

  for (final item in raw.whereType<Map<String, dynamic>>()) {
    final name = (item['panel_name'] ?? item['panel'] ?? item['name'] ?? '')
        .toString()
        .trim();
    if (name.isEmpty || !seenPanels.add(name)) continue;

    final rawParts = item['spare_parts_needed'];
    final seenParts = <String>{};
    final parts = <LearningPart>[];
    if (rawParts is List) {
      for (final p in rawParts.whereType<Map<String, dynamic>>()) {
        final part = LearningPart.fromJson(p);
        if (part.name.isEmpty || !seenParts.add(part.name)) continue;
        parts.add(part);
      }
    }

    panels.add(LearningPanel(
      name: name,
      severity: item['panel_severity']?.toString(),
      parts: parts,
    ));
  }

  return panels;
}
