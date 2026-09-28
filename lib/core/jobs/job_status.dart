// lib/core/jobs/job_status.dart
//
// Satu-satunya definisi status job — generated dari job_statuses table.
// Gunakan konstanta ini, jangan literal string di tempat lain.
// S-01, S-08, L-08, L-12, C-29, C-36, C-52

class JobStatus {
  final String code;
  final int sortOrder;
  final String labelId;    // Bahasa Indonesia
  final String labelEn;
  final bool isTerminal;
  final bool countsForCapacity;
  final bool customerCanCancel;
  final bool visibleToCustomer;

  const JobStatus({
    required this.code,
    required this.sortOrder,
    required this.labelId,
    required this.labelEn,
    this.isTerminal = false,
    this.countsForCapacity = false,
    this.customerCanCancel = false,
    this.visibleToCustomer = true,
  });

  @override
  String toString() => code;
  @override
  bool operator ==(Object other) => other is JobStatus && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

// ── Canonical list (mirrors job_statuses table) ──────────────────────────────
// Sort order is business flow order, NOT lexicographic.

const kJobStatusCancelled = JobStatus(
  code: '0_cancelled', sortOrder: 0,
  labelId: 'Dibatalkan', labelEn: 'Cancelled',
  isTerminal: true, customerCanCancel: false,
);
const kJobStatusEstimated = JobStatus(
  code: '2_estimated', sortOrder: 10,
  labelId: 'Estimasi Selesai', labelEn: 'Estimated',
  customerCanCancel: true,
);
const kJobStatusBooked = JobStatus(
  code: '3_booked', sortOrder: 20,
  labelId: 'Dijadwalkan', labelEn: 'Booked',
  countsForCapacity: true, customerCanCancel: true,
);
const kJobStatusAdmitted = JobStatus(
  code: '5_admitted', sortOrder: 30,
  labelId: 'Kendaraan Masuk', labelEn: 'Admitted',
  countsForCapacity: true,
);
const kJobStatusInspected = JobStatus(
  code: '3_inspected', sortOrder: 40,
  labelId: 'Inspeksi Selesai', labelEn: 'Inspected',
  countsForCapacity: true,
);
const kJobStatusPaid = JobStatus(
  code: '4_paid', sortOrder: 50,
  labelId: 'Pembayaran Dikonfirmasi', labelEn: 'Payment Confirmed',
  countsForCapacity: true,
);
const kJobStatusInProgress = JobStatus(
  code: '6_in_progress', sortOrder: 60,
  labelId: 'Dalam Pengerjaan', labelEn: 'In Progress',
  countsForCapacity: true,
);
const kJobStatusFinished = JobStatus(
  code: '7_finished', sortOrder: 70,
  labelId: 'Selesai Dikerjakan', labelEn: 'Finished',
  countsForCapacity: true,
);
const kJobStatusAwaitingDelivery = JobStatus(
  code: '8_awaiting_delivery', sortOrder: 80,
  labelId: 'Menunggu Pengantaran', labelEn: 'Awaiting Delivery',
  countsForCapacity: true,
);
const kJobStatusDone = JobStatus(
  code: '9_done', sortOrder: 90,
  labelId: 'Selesai', labelEn: 'Done',
  isTerminal: true,
);

/// Ordered list — use this for progress bars, sorting, index lookup.
const kJobStatusAll = [
  kJobStatusCancelled,
  kJobStatusEstimated,
  kJobStatusBooked,
  kJobStatusAdmitted,
  kJobStatusInspected,
  kJobStatusPaid,
  kJobStatusInProgress,
  kJobStatusFinished,
  kJobStatusAwaitingDelivery,
  kJobStatusDone,
];

/// Active (non-terminal, visible to customer) — for progress bar / garage.
const kJobStatusActive = [
  kJobStatusEstimated,
  kJobStatusBooked,
  kJobStatusAdmitted,
  kJobStatusInspected,
  kJobStatusPaid,
  kJobStatusInProgress,
  kJobStatusFinished,
  kJobStatusAwaitingDelivery,
];

/// Status that appear on the partner board (not terminal, not cancelled).
const kJobStatusPartnerBoard = [
  kJobStatusBooked,
  kJobStatusAdmitted,
  kJobStatusInspected,
  kJobStatusPaid,
  kJobStatusInProgress,
  kJobStatusFinished,
  kJobStatusAwaitingDelivery,
];

/// Ops floor — vehicles physically in the workshop.
const kJobStatusFloor = [
  kJobStatusBooked,    // self_deliver intake
  kJobStatusAdmitted,
  kJobStatusInspected,
  kJobStatusPaid,      // C-12 fix: 4_paid must show on floor
  kJobStatusInProgress,
  kJobStatusFinished,
];

/// Find by code. Returns null for unknown codes (safer than throwing).
JobStatus? jobStatusFromCode(String? code) {
  if (code == null) return null;
  try {
    return kJobStatusAll.firstWhere((s) => s.code == code);
  } catch (_) {
    return null;
  }
}

/// Sort order for a status code. Unknown → 999 (goes to end).
int jobStatusSortOrder(String? code) =>
    jobStatusFromCode(code)?.sortOrder ?? 999;

/// Label in Bahasa Indonesia for a status code.
String jobStatusLabel(String? code, {bool english = false}) {
  final s = jobStatusFromCode(code);
  if (s == null) return code ?? '—';
  return english ? s.labelEn : s.labelId;
}

/// True if status code is paid (has a payment record) — C-29.
bool jobStatusIsPaid(String? code) {
  if (code == null) return false;
  return const [
    '4_paid', '6_in_progress', '7_finished', '8_awaiting_delivery', '9_done'
  ].contains(code);
}

/// Progress (0.0–1.0) for the customer progress bar.
double jobStatusProgress(String? code) {
  final s = jobStatusFromCode(code);
  if (s == null || s.isTerminal && s.code == '0_cancelled') return 0.0;
  // Use sort_order of active statuses only
  const active = kJobStatusActive;
  final idx = active.indexWhere((x) => x.code == code);
  if (idx < 0) return 0.0;
  return (idx + 1) / active.length;
}
