// lib/core/jobs/repair_stages.dart
//
// The single source of truth for a workshop's repair stages.
//
// It used to live inside `ops_stage_photo_screen.dart`, which was fine while the
// ops app was the only surface that knew about stages. Three surfaces now render
// the same production sequence - the ops field app, the partner dashboard, and
// the customer tracker - and a stage list duplicated per surface is a stage list
// that drifts. `ops_stage_photo_screen.dart` re-exports this file, so the
// existing `import 'ops_stage_photo_screen.dart'` call sites keep working.
//
// ORDER IS PRODUCTION ORDER. `job_milestones` rows carry no sort column; every
// surface derives the sequence from [kOpsStages] and [kBodyPaintStageKeys].

/// Canonical definition of one repair stage.
class OpsStageDefinition {
  /// DB key - `job_milestones.stage_key`, `ops_stage_roles.stage_key`, and the
  /// value `send-notification` switches on. Never rename one of these without a
  /// migration: old rows keep the old string.
  final String stageKey;

  /// English label. Also what older rows stored in `job_milestones.milestone_name`.
  final String label;

  /// Bahasa Indonesia label. The workshop floor reads this one.
  final String labelId;

  /// Shown to the operator inside the stage screen.
  final String instruction;

  /// Photos required before the stage may be submitted. **0 means optional** -
  /// a workshop is not obliged to photograph every step of a repair, and a stage
  /// that cannot be recorded without a camera in hand is a stage that silently
  /// goes unrecorded.
  final int minPhotos;

  /// If non-null, completing the stage also moves the job to this status.
  final String? advancesStatus;

  /// Roles that may complete the stage. `ops_may_act_on_stage()` reads the same
  /// list from `ops_stage_roles`; the two must agree or the UI offers a tap the
  /// database then refuses.
  final List<String> allowedRoles;

  const OpsStageDefinition({
    required this.stageKey,
    required this.label,
    required this.labelId,
    required this.instruction,
    required this.minPhotos,
    this.advancesStatus,
    required this.allowedRoles,
  });

  /// True when this stage may be completed without a photo.
  bool get photoOptional => minPhotos == 0;

  /// Label in the caller's language, following the app's two-tier i18n: anything
  /// that is not Indonesian gets the English label rather than a missing string.
  String labelFor(String languageCode) =>
      languageCode == 'id' ? labelId : label;
}

/// Every stage, in production order.
const kOpsStages = <OpsStageDefinition>[
  OpsStageDefinition(
    stageKey: 'vehicle_intake',
    label: 'Vehicle Intake',
    labelId: 'Penerimaan Kendaraan',
    instruction:
        'Document all 4 sides of the vehicle plus any pre-existing damage before handing over the keys. '
        'Min 2 photos required.',
    minPhotos: 2,
    advancesStatus: '5_admitted',
    allowedRoles: ['partner_staff', 'partner_driver', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'disassembly',
    label: 'Disassembly',
    labelId: 'Bongkar',
    instruction:
        'Bongkar panel yang rusak. Foto bersifat opsional - catat tahap ini walau tanpa foto.',
    minPhotos: 0,
    advancesStatus: '6_in_progress',
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'welding',
    label: 'Welding / Panel Beating',
    labelId: 'Ketok / Las',
    instruction:
        'Perbaikan struktur bodi: ketok panel dan las titik-titik yang diperlukan. Foto opsional.',
    minPhotos: 0,
    advancesStatus: null, // Sub-stage within 6_in_progress; no status change
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'body_filler',
    label: 'Body Filler',
    labelId: 'Dempul',
    instruction: 'Aplikasi dempul pada panel yang sudah diketok. Foto opsional.',
    minPhotos: 0,
    advancesStatus: null,
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'painting',
    label: 'Painting',
    labelId: 'Cat',
    instruction:
        'Pengecatan panel di booth: base coat dan clear coat. Foto opsional.',
    minPhotos: 0,
    advancesStatus: null,
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'polishing',
    label: 'Polishing & Detailing',
    labelId: 'Poles',
    instruction: 'Poles dan detailing panel yang sudah dicat. Foto opsional.',
    minPhotos: 0,
    advancesStatus: null,
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'assembly',
    label: 'Reassembly',
    labelId: 'Pasang',
    instruction:
        'Pasang kembali komponen yang dilepas pada tahap bongkar. Foto opsional.',
    minPhotos: 0,
    advancesStatus: null,
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'qc_finished',
    label: 'Quality Control',
    labelId: 'Kontrol Kualitas',
    instruction:
        'QC sign-off photos. Photograph all repaired areas and complete vehicle - 4 sides minimum.',
    minPhotos: 2,
    advancesStatus: '7_finished',
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'delivery',
    label: 'Delivery / Pickup',
    labelId: 'Serah Terima',
    instruction:
        'Photograph the vehicle being handed to the customer. Include handover proof with customer present if possible.',
    minPhotos: 1,
    advancesStatus: '9_done',
    // Staff are included deliberately: they are the ones who hand the car back to
    // the customer, so excluding them produced a stage the UI offered under
    // all_access and the RPC then refused. `ops_complete_delivery` admits
    // partner_staff too - this list gates the UI, that RPC gates the server, and
    // the two must agree or the button is a dead end.
    allowedRoles: ['partner_staff', 'partner_driver', 'partner_mechanic', 'master_admin'],
  ),
];

/// The six stages the customer sees as "Pengerjaan Bodi & Pengecatan".
///
/// Kept as an explicit key list rather than a slice of [kOpsStages] so that
/// inserting a stage elsewhere cannot silently change what the customer is
/// promised. Everything in here is a progress step, and every one of them is
/// photo-optional.
const kBodyPaintStageKeys = <String>[
  'disassembly',
  'welding',
  'body_filler',
  'painting',
  'polishing',
  'assembly',
];

/// The body & paint stages, resolved once, in production order.
final List<OpsStageDefinition> kBodyPaintStages = List.unmodifiable(
  kBodyPaintStageKeys.map(
    (key) => kOpsStages.firstWhere((s) => s.stageKey == key),
  ),
);

/// Look up a stage by its DB key. Returns null for an unknown key rather than
/// throwing - an old row or a stale deep link is not a crash.
OpsStageDefinition? stageByKey(String key) {
  for (final stage in kOpsStages) {
    if (stage.stageKey == key) return stage;
  }
  return null;
}

/// Position of [stageKey] inside the body & paint sequence, 0-based, or -1 when
/// the stage is not one of the six progress steps.
int bodyPaintIndexOf(String stageKey) => kBodyPaintStageKeys.indexOf(stageKey);

/// Localised label for [stageKey], falling back to the raw key so an unknown
/// stage renders as itself instead of as an empty tile.
String repairStageLabel(String stageKey, String languageCode) =>
    stageByKey(stageKey)?.labelFor(languageCode) ?? stageKey;

/// How far a job has got through one stage, as every surface needs it.
class RepairStageProgress {
  final String stageKey;

  /// `job_milestones.status`; `'completed'` is the only value that means done.
  final String status;

  final DateTime? completedAt;

  /// Photos attached to the milestone. Zero is normal - progress photos are
  /// optional, so this is informational, never a gate.
  final int photoCount;

  const RepairStageProgress({
    required this.stageKey,
    required this.status,
    this.completedAt,
    this.photoCount = 0,
  });

  bool get isComplete => status == 'completed';

  /// Parses one `job_milestones` row. `photoCount` is attached separately
  /// because it comes from a second table.
  factory RepairStageProgress.fromRow(Map<String, dynamic> row) {
    return RepairStageProgress(
      stageKey: row['stage_key']?.toString() ?? '',
      status: row['status']?.toString() ?? '',
      completedAt: DateTime.tryParse(row['completed_at']?.toString() ?? ''),
    );
  }

  RepairStageProgress withPhotoCount(int count) => RepairStageProgress(
        stageKey: stageKey,
        status: status,
        completedAt: completedAt,
        photoCount: count,
      );
}

/// Builds the stage map for a job from its milestone rows, keeping only the six
/// body & paint progress steps.
Map<String, RepairStageProgress> bodyPaintProgressFrom(
  Iterable<Map<String, dynamic>> milestoneRows,
) {
  final out = <String, RepairStageProgress>{};
  for (final row in milestoneRows) {
    final key = row['stage_key']?.toString() ?? '';
    if (!kBodyPaintStageKeys.contains(key)) continue;
    out[key] = RepairStageProgress.fromRow(row);
  }
  return out;
}

/// How many of the six progress steps are done.
int bodyPaintCompletedCount(Map<String, RepairStageProgress> progress) =>
    kBodyPaintStageKeys.where((k) => progress[k]?.isComplete ?? false).length;

/// The next stage the workshop should complete, or null when all six are done.
///
/// This is order-based, not "first incomplete" over a set: a workshop that
/// marks Poles before Cat has genuinely finished both, but the step it should be
/// nudged toward is the earliest one still open.
OpsStageDefinition? nextBodyPaintStage(
  Map<String, RepairStageProgress> progress,
) {
  for (final stage in kBodyPaintStages) {
    if (!(progress[stage.stageKey]?.isComplete ?? false)) return stage;
  }
  return null;
}
