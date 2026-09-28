// lib/core/format/rupiah.dart
//
// Satu-satunya implementasi format rupiah (S-07, UX-06).
// Pakai ini di semua layar — hapus implementasi lokal lainnya.
//
// Contoh:
//   formatRupiah(2500000)  → 'Rp 2.500.000'
//   formatRupiah(null)     → '—'
//   formatRupiah(0)        → 'Rp 0'

import 'package:intl/intl.dart';

final _fmt = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

/// Format integer rupiah. Null → '—'.
String formatRupiah(num? amount) {
  if (amount == null) return '—';
  // C-72: server rounds, client just formats — no floor/truncate
  return _fmt.format(amount.round());
}

/// Parse input rupiah dari keyboard (hanya digit).
/// '2.500.000' → 2500000
/// '2500000'   → 2500000
/// '2500000,00'→ null (koma tidak valid — tampilkan error)
/// Returns null bila input tidak valid.
int? parseRupiah(String input) {
  // Hapus spasi dan simbol Rp
  final cleaned = input.trim().replaceAll('Rp', '').replaceAll(' ', '');

  // Jika ada koma → invalid (C-49: mencegah 2500000,00 → 250000000)
  if (cleaned.contains(',')) return null;

  // Hapus titik (pemisah ribuan Indonesia)
  final digits = cleaned.replaceAll('.', '');

  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}
