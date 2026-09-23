import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

/// The admin half of the invoice flow, plus the admission step Re-V owns.
///
/// Two jobs live here because they are the same person's queue at the same
/// moment in the workflow:
///
///   1. ADMISSION (Case 1) — when Re-V receives the car rather than the
///      workshop, an admin has to record that. Before this screen there was no
///      action for it at all; the only route to `5_admitted` was a raw status
///      override in a dropdown, which notified nobody and left no trace of who
///      received the vehicle. `admin_admit_vehicle()` is that missing step.
///
///   2. INVOICE CHECK + RELEASE — the workshop's final estimation produces a
///      DRAFT invoice. Nothing reaches the customer until an admin checks it and
///      then releases it. Those are deliberately two separate presses: checking
///      says "these figures are sane", releasing says "send this to the customer
///      and start their payment clock". Collapsing them into one would remove
///      the only human gate between a workshop's own number and the customer's
///      bill.
///
/// Release is also what moves the job to `3_inspected`, and the database does
/// that inside `admin_release_invoice()` — not here — so the invoice state and
/// the job state cannot drift apart if a request fails midway.
class AdminInvoiceReviewScreen extends ConsumerStatefulWidget {
  const AdminInvoiceReviewScreen({super.key});

  @override
  ConsumerState<AdminInvoiceReviewScreen> createState() =>
      _AdminInvoiceReviewScreenState();
}

class _AdminInvoiceReviewScreenState
    extends ConsumerState<AdminInvoiceReviewScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _awaitingAdmission = [];
  final Set<String> _busy = {};

  static const _amber = Color(0xFFB45309);
  static const _green = Color(0xFF059669);
  static const _red = Color(0xFFB91C1C);

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      // Everything an admin still has to act on, plus recently released ones so
      // the queue does not look empty the moment it is worked through.
      final invoices = await _supabase
          .from('invoices')
          .select('''
            id, invoice_number, status, initial_estimation_cost, final_cost,
            line_items, created_at, released_at, expires_at, admin_note,
            job_id, partner_id,
            partners:partner_id (shop_name),
            repair_jobs:job_id (
              id, status, customer_id,
              vehicles:vehicle_id (make, model, license_plate),
              profiles:customer_id (full_name, phone)
            )
          ''')
          .inFilter('status',
              ['draft', 'awaiting_release', 'released', 'approved', 'declined'])
          .order('created_at', ascending: false)
          .limit(100);

      // Case 1: booked jobs nobody has received yet.
      final booked = await _supabase
          .from('repair_jobs')
          .select('''
            id, status, created_at, service_area, delivery_type, contact_phone,
            vehicles:vehicle_id (make, model, license_plate),
            profiles:customer_id (full_name, phone),
            partners:partner_id (shop_name)
          ''')
          .eq('status', '3_booked')
          .order('created_at', ascending: true)
          .limit(100);

      if (!mounted) return;
      setState(() {
        _invoices = List<Map<String, dynamic>>.from(invoices);
        _awaitingAdmission = List<Map<String, dynamic>>.from(booked);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('[InvoiceReview] fetch error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _idr(dynamic v) {
    final d = (v as num?)?.toDouble() ?? 0;
    final s = d.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return 'Rp ${buf.toString()}';
  }

  Future<void> _run(String key, String fn, Map<String, dynamic> params,
      String successMsg) async {
    setState(() => _busy.add(key));
    try {
      final res = await _supabase.rpc(fn, params: params);
      final map = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (!mounted) return;
      if (map['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMsg),
          backgroundColor: _green,
        ));
        await _fetch();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(map['error']?.toString() ?? 'Action failed.'),
          backgroundColor: _red,
        ));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: _red),
        );
      }
    } catch (e) {
      debugPrint('[InvoiceReview] $fn error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _sendBack(Map<String, dynamic> inv) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kembalikan ke Workshop',
            style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Alasan',
            hintText: 'mis. biaya panel belum sesuai',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Kembalikan'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await _run('back:${inv['id']}', 'admin_review_invoice', {
      'p_invoice_id': inv['id'],
      'p_action': 'send_back',
      'p_note': reason,
    }, 'Invoice dikembalikan ke workshop.');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: const ReVAppBar(
          title: Text('Invoice & Admission'),
          showBackButton: true,
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.fireRed))
            : _error != null
                ? _errorView(cs)
                : Column(
                    children: [
                      Container(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                        child: TabBar(
                          labelColor: AppColors.fireRed,
                          unselectedLabelColor: cs.onSurfaceVariant,
                          indicatorColor: AppColors.fireRed,
                          tabs: [
                            Tab(
                              text: 'Invoices (${_invoices.where((i) => _needsAction(i)).length})',
                            ),
                            Tab(
                              text: 'Admission (${_awaitingAdmission.length})',
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            RefreshIndicator(
                              onRefresh: _fetch,
                              color: AppColors.fireRed,
                              child: _invoiceList(cs),
                            ),
                            RefreshIndicator(
                              onRefresh: _fetch,
                              color: AppColors.fireRed,
                              child: _admissionList(cs),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  bool _needsAction(Map<String, dynamic> inv) =>
      inv['status'] == 'draft' || inv['status'] == 'awaiting_release';

  Widget _errorView(ColorScheme cs) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _red, size: 36),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );

  // ── invoices ───────────────────────────────────────────────────────────────

  Widget _invoiceList(ColorScheme cs) {
    if (_invoices.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Icon(Icons.receipt_long_outlined, size: 40, color: cs.onSurfaceVariant),
        const SizedBox(height: 10),
        Center(
          child: Text('Tidak ada invoice.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ),
      ]);
    }

    final pending = _invoices.where(_needsAction).toList();
    final done = _invoices.where((i) => !_needsAction(i)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (pending.isNotEmpty) ...[
          _sectionLabel('PERLU TINDAKAN', cs),
          ...pending.map((i) => _invoiceCard(i, cs)),
          const SizedBox(height: 8),
        ],
        if (done.isNotEmpty) ...[
          _sectionLabel('RIWAYAT', cs),
          ...done.map((i) => _invoiceCard(i, cs)),
        ],
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: cs.onSurfaceVariant)),
      );

  Widget _invoiceCard(Map<String, dynamic> inv, ColorScheme cs) {
    final job = inv['repair_jobs'] as Map<String, dynamic>? ?? {};
    final veh = job['vehicles'] as Map<String, dynamic>? ?? {};
    final cust = job['profiles'] as Map<String, dynamic>? ?? {};
    final partner = inv['partners'] as Map<String, dynamic>? ?? {};

    final status = inv['status']?.toString() ?? '';
    final initial = (inv['initial_estimation_cost'] as num?)?.toDouble();
    final finalCost = (inv['final_cost'] as num?)?.toDouble() ?? 0;
    final delta = initial == null ? null : finalCost - initial;
    final busyCheck = _busy.contains('check:${inv['id']}');
    final busyRelease = _busy.contains('release:${inv['id']}');
    final busyBack = _busy.contains('back:${inv['id']}');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _needsAction(inv)
              ? _amber.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${inv['invoice_number']} · ${veh['make'] ?? '?'} ${veh['model'] ?? ''}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface),
            ),
          ),
          _statusChip(status),
        ]),
        const SizedBox(height: 6),
        Text(
          '${veh['license_plate'] ?? 'No plate'} · ${cust['full_name'] ?? 'Unknown'}'
          '${cust['phone'] != null ? ' · ${cust['phone']}' : ''}',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        Text('Workshop: ${partner['shop_name'] ?? '—'}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(
              child: _money('Estimasi awal', _idr(initial), cs.onSurfaceVariant)),
          Expanded(
              child: _money('Estimasi akhir', _idr(finalCost), cs.onSurface)),
          Expanded(
            child: _money(
              delta == null
                  ? 'Selisih'
                  : (delta > 0 ? 'Kenaikan' : 'Penurunan'),
              delta == null ? '—' : _idr(delta),
              delta == null
                  ? cs.onSurfaceVariant
                  : (delta > 0 ? _red : _green),
            ),
          ),
        ]),

        if (inv['admin_note'] != null) ...[
          const SizedBox(height: 8),
          Text('Catatan: ${inv['admin_note']}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],

        const SizedBox(height: 12),
        Row(children: [
          if (status == 'draft')
            ElevatedButton.icon(
              onPressed: busyCheck
                  ? null
                  : () => _run(
                        'check:${inv['id']}',
                        'admin_review_invoice',
                        {'p_invoice_id': inv['id'], 'p_action': 'check'},
                        'Invoice diperiksa. Siap dirilis ke pelanggan.',
                      ),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _amber, foregroundColor: Colors.white),
              icon: busyCheck
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.fact_check_outlined, size: 15),
              label: const Text('Periksa',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          if (status == 'awaiting_release') ...[
            ElevatedButton.icon(
              onPressed: busyRelease
                  ? null
                  : () => _run(
                        'release:${inv['id']}',
                        'admin_release_invoice',
                        {'p_invoice_id': inv['id']},
                        'Invoice dirilis. Pelanggan diberi tahu.',
                      ),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white),
              icon: busyRelease
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 15),
              label: const Text('Rilis ke Pelanggan',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: busyBack ? null : () => _sendBack(inv),
              icon: const Icon(Icons.undo, size: 15, color: _amber),
              label: const Text('Kembalikan',
                  style: TextStyle(fontSize: 12, color: _amber)),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _money(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Widget _statusChip(String status) {
    final (color, label) = switch (status) {
      'draft' => (_amber, 'DRAFT'),
      'awaiting_release' => (_amber, 'SIAP RILIS'),
      'released' => (const Color(0xFF1D4ED8), 'MENUNGGU PELANGGAN'),
      'approved' => (_green, 'DISETUJUI'),
      'declined' => (_red, 'DITOLAK'),
      'paid' => (_green, 'DIBAYAR'),
      _ => (Colors.grey, status.toUpperCase()),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.bold, color: color)),
    );
  }

  // ── admission ──────────────────────────────────────────────────────────────

  Widget _admissionList(ColorScheme cs) {
    if (_awaitingAdmission.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Icon(Icons.directions_car_outlined,
            size: 40, color: cs.onSurfaceVariant),
        const SizedBox(height: 10),
        Center(
          child: Text('Tidak ada kendaraan menunggu penerimaan.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionLabel('MENUNGGU PENERIMAAN (CASE 1 · DITERIMA REVIVE)', cs),
        ..._awaitingAdmission.map((job) => _admissionCard(job, cs)),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _admissionCard(Map<String, dynamic> job, ColorScheme cs) {
    final veh = job['vehicles'] as Map<String, dynamic>? ?? {};
    final cust = job['profiles'] as Map<String, dynamic>? ?? {};
    final partner = job['partners'] as Map<String, dynamic>? ?? {};
    final busy = _busy.contains('admit:${job['id']}');
    final isPickup = job['delivery_type'] == 'pickup';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${veh['make'] ?? '?'} ${veh['model'] ?? ''} · ${veh['license_plate'] ?? ''}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: cs.onSurface)),
        const SizedBox(height: 5),
        Text('${cust['full_name'] ?? 'Unknown'}'
            '${cust['phone'] != null ? ' · ${cust['phone']}' : ''}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        Text(
          '${isPickup ? 'Jemput (valet pickup)' : 'Antar sendiri'}'
          '${job['contact_phone'] != null ? ' · ${job['contact_phone']}' : ''}',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        Text('Workshop tujuan: ${partner['shop_name'] ?? 'Belum ditugaskan'}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: busy
              ? null
              : () => _run(
                    'admit:${job['id']}',
                    'admin_admit_vehicle',
                    {'p_job_id': job['id']},
                    'Kendaraan diterima. Workshop & pelanggan diberi tahu.',
                  ),
          style: ElevatedButton.styleFrom(
              backgroundColor: _green, foregroundColor: Colors.white),
          icon: busy
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.login_rounded, size: 15),
          label: const Text('Terima Kendaraan',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
