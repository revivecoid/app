import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/format/rupiah.dart';
import '../partner_dashboard_controller.dart';

/// The final-estimation form.
///
/// This is the step the workflow was missing entirely: after the car is admitted
/// the workshop prices the *actual* damage, and that figure is what the customer
/// is invoiced for. Before this screen existed the only way to submit a final
/// cost was `partner_issue_invoice(p_job_id, p_final_cost)` — a single number
/// with no record of how it was reached, no sight of what the customer had
/// already been quoted, and no line between "the workshop priced it" and "Re-V
/// released it". The database now separates those two steps
/// (`partner_submit_final_estimation` → `admin_review_invoice` →
/// `admin_release_invoice`); this is the workshop's half.
///
/// Design decisions worth knowing:
///
///  * The initial figures are shown *beside* the editable final ones, per panel,
///    with the delta summed live. A workshop can see exactly how far it is
///    moving the price before it commits, which is the entire reason the initial
///    and final are stored separately rather than overwritten.
///
///  * Panels may be ADDED, not just edited. Stripping the car usually reveals
///    damage the photographs could not see, and forcing the workshop to hide
///    that inside an existing panel's number would make the per-panel record a
///    lie.
///
///  * The final total is computed from the panels rather than being an
///    independent field, so the line items and the total cannot disagree.
class PartnerFinalEstimationDialog extends StatefulWidget {
  final PartnerJobNode job;

  const PartnerFinalEstimationDialog({super.key, required this.job});

  @override
  State<PartnerFinalEstimationDialog> createState() =>
      _PartnerFinalEstimationDialogState();
}

/// One editable row: a panel, what it was quoted at, and what it will cost.
class _PanelRow {
  final String panel;
  final double initialCost;
  final TextEditingController controller;
  final bool addedByWorkshop;

  _PanelRow({
    required this.panel,
    required this.initialCost,
    required this.controller,
    this.addedByWorkshop = false,
  });

  // C-49 fix: digits only, no comma/decimal — use parseRupiah for safe parsing
  double get finalCost {
    final digits = controller.text.trim().replaceAll('.', '').replaceAll(',', '');
    return double.tryParse(digits) ?? 0;
  }

  void dispose() => controller.dispose();
}

class _PartnerFinalEstimationDialogState
    extends State<PartnerFinalEstimationDialog> {
  /// Sentinel for "this panel still holds its quoted price". An empty field
  /// would be ambiguous — it could mean zero, or that the partner has not
  /// reached that row yet — so an untouched row keeps its number.
  final List<_PanelRow> _rows = [];
  final TextEditingController _note = TextEditingController();
  bool _submitting = false;
  String? _error;

  static const _green = Color(0xFF059669);
  static const _amber = Color(0xFFB45309);
  static const _red = Color(0xFFB91C1C);

  @override
  void initState() {
    super.initState();
    for (final p in widget.job.initialPanels) {
      _rows.add(_PanelRow(
        panel: p.panel,
        initialCost: p.initialCost,
        // Pre-filled with the quoted figure: most repairs land on it, and the
        // partner edits only the panels that moved.
        controller: TextEditingController(
          text: p.initialCost > 0 ? p.initialCost.toStringAsFixed(0) : '',
        ),
      ));
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  double get _initialTotal =>
      _rows.fold(0, (sum, r) => sum + r.initialCost);

  double get _finalTotal => _rows.fold(0, (sum, r) => sum + r.finalCost);

  double get _delta => _finalTotal - _initialTotal;

  // S-07 fix: use shared formatRupiah from core/format/rupiah.dart
  String _idr(double v) => v < 0
      ? '-${formatRupiah(v.abs().round())}'
      : formatRupiah(v.round());

  Future<void> _addPanel() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Panel', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama Panel',
            hintText: 'mis. Pintu Depan RH',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      ctrl.dispose();
      return;
    }
    setState(() {
      _rows.add(_PanelRow(
        panel: name,
        initialCost: 0,
        controller: TextEditingController(text: ''),
        addedByWorkshop: true,
      ));
    });
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (_rows.isEmpty) {
      setState(() => _error = 'Tambahkan minimal satu panel.');
      return;
    }
    final zeroRows = _rows.where((r) => r.finalCost <= 0).toList();
    if (zeroRows.isNotEmpty) {
      setState(() => _error =
          'Isi biaya akhir untuk: ${zeroRows.map((r) => r.panel).join(', ')}');
      return;
    }

    setState(() => _submitting = true);
    try {
      // Initial figures travel with the submission so the stored record stands
      // on its own even if the job's assessment is later revised.
      final panels = _rows
          .map((r) => {
                'panel': r.panel,
                'initial_cost': r.initialCost,
                'final_cost': r.finalCost,
                'added_by_workshop': r.addedByWorkshop,
              })
          .toList();

      final result = await Supabase.instance.client.rpc(
        'partner_submit_final_estimation',
        params: {
          'p_job_id': widget.job.id,
          'p_final_cost': _finalTotal,
          'p_panels': panels,
          'p_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        },
      );
      final res = result is Map<String, dynamic> ? result : <String, dynamic>{};

      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Estimasi akhir terkirim (${_idr(_finalTotal)}). '
            'Invoice ${res['invoice_number']} menunggu pemeriksaan admin.',
          ),
          backgroundColor: _green,
          duration: const Duration(seconds: 5),
        ));
      } else {
        setState(() {
          _submitting = false;
          _error = res['error']?.toString() ?? 'Gagal mengirim estimasi akhir.';
        });
      }
    } on PostgrestException catch (e) {
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deltaColor = _delta > 0 ? _red : _green;

    return AlertDialog(
      backgroundColor: cs.surfaceContainerLowest,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(children: [
        const Icon(Icons.fact_check_outlined, color: _green, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Estimasi Akhir',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
              Text(
                '${widget.job.carMake} ${widget.job.carModel} · '
                '${widget.job.licensePlate}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── what the customer was already quoted ────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.photo_camera_back_outlined,
                      size: 15, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Estimasi awal (AI, dari foto): '
                      '${_idr(widget.job.initialEstimationCost ?? _initialTotal)}',
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),

              // ── per-panel rows ──────────────────────────────────────────────
              Row(children: [
                Expanded(
                  flex: 4,
                  child: Text('Panel',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurfaceVariant)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Awal',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text('Akhir',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurfaceVariant)),
                ),
              ]),
              const SizedBox(height: 6),

              ..._rows.map((r) {
                final d = r.finalCost - r.initialCost;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(children: [
                          Flexible(
                            child: Text(
                              r.panel,
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (r.addedByWorkshop)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Tooltip(
                                message:
                                    'Ditemukan saat pemeriksaan fisik, tidak ada di estimasi awal',
                                child: Icon(Icons.add_circle_outline,
                                    size: 12, color: _amber),
                              ),
                            ),
                        ]),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          r.initialCost > 0
                              ? _idr(r.initialCost)
                              : '—',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: r.controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixText: 'Rp ',
                            prefixStyle: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            border: const OutlineInputBorder(),
                            // Tint the field when this panel moved, so the
                            // changed rows are findable at a glance in a long
                            // list.
                            enabledBorder: d != 0
                                ? OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: deltaColor, width: 1.2))
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _submitting ? null : _addPanel,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('Tambah panel',
                      style: TextStyle(fontSize: 12)),
                ),
              ),

              const Divider(height: 20),

              // ── totals ──────────────────────────────────────────────────────
              _totalRow('Total estimasi awal', _idr(_initialTotal),
                  cs.onSurfaceVariant),
              const SizedBox(height: 4),
              _totalRow('Total estimasi akhir', _idr(_finalTotal), cs.onSurface,
                  bold: true),
              const SizedBox(height: 4),
              _totalRow(
                _delta == 0
                    ? 'Selisih'
                    : (_delta > 0 ? 'Kenaikan' : 'Penurunan'),
                _idr(_delta),
                deltaColor,
                bold: true,
              ),

              const SizedBox(height: 14),
              TextField(
                controller: _note,
                maxLines: 2,
                style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                decoration: InputDecoration(
                  labelText: 'Catatan untuk admin (opsional)',
                  hintText: 'mis. kerusakan tambahan di balik bumper',
                  border: const OutlineInputBorder(),
                  labelStyle:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),

              const SizedBox(height: 10),
              Text(
                'Angka ini menjadi invoice yang dikirim ke pelanggan, setelah '
                'diperiksa admin.',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurfaceVariant, height: 1.4),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _red.withValues(alpha: 0.35)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(fontSize: 11.5, color: _red)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text('Batal',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
          ),
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 15),
          label: Text(
            _submitting ? 'Mengirim…' : 'Kirim ke Admin',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _totalRow(String label, String value, Color color,
      {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: bold ? 12.5 : 12,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color)),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 13 : 12,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color)),
      ],
    );
  }
}

/// Opens the form. Single entry point so both the mobile and desktop workshop
/// surfaces render the same thing, the way the old invoice dialog was shared.
void showFinalEstimationDialog(BuildContext context, PartnerJobNode job) {
  showDialog(
    context: context,
    builder: (_) => PartnerFinalEstimationDialog(job: job),
  );
}
