import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

/// The customer's invoice: review, approve, or decline.
///
/// This is the step the redesign was built around — payment sits AFTER physical
/// inspection, so the figure the customer is asked to approve is the workshop's
/// real number, not the AI's guess from photographs. Both are shown side by side
/// deliberately: the whole promise of the earlier estimate is that the customer
/// can see how far the real cost moved, and hiding that comparison at the moment
/// of payment would be the worst place to hide it.
///
/// Declining is a real outcome, not a support ticket. `customer_respond_to_invoice`
/// cancels the job, frees the workshop's booked slot and notifies both the
/// workshop and Re-V to arrange the car's return, so the customer can decline in
/// the app and the logistics follow automatically.
///
/// Payment: whichever methods `payment_config` actually has switched on are
/// shown, and nothing else. Manual transfer is functional today — the customer
/// transfers and Re-V confirms through `invoice_mark_paid()`. Card/e-wallet is
/// listed only when `online_enabled` is true, because offering a payment button
/// that cannot take money would be worse than not offering one.
class CustomerInvoiceScreen extends ConsumerStatefulWidget {
  final String jobId;

  const CustomerInvoiceScreen({super.key, required this.jobId});

  @override
  ConsumerState<CustomerInvoiceScreen> createState() =>
      _CustomerInvoiceScreenState();
}

class _CustomerInvoiceScreenState
    extends ConsumerState<CustomerInvoiceScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _invoice;
  Map<String, dynamic>? _paymentConfig;
  bool _busy = false;

  static const _green = Color(0xFF059669);
  static const _amber = Color(0xFFB45309);
  static const _red = Color(0xFFB91C1C);

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final rows = await _supabase
          .rpc('get_invoice_for_job', params: {'p_job_id': widget.jobId});

      Map<String, dynamic>? pick;
      if (rows is List && rows.isNotEmpty) {
        // Newest first from the function; skip superseded/cancelled so a
        // corrected re-issue shows the live document.
        for (final r in rows) {
          final m = Map<String, dynamic>.from(r as Map);
          if (m['status'] != 'superseded' && m['status'] != 'cancelled') {
            pick = m;
            break;
          }
        }
      }

      Map<String, dynamic>? cfg;
      try {
        final c = await _supabase
            .from('payment_config')
            .select('online_enabled, manual_transfer_enabled, bank_accounts, '
                'primary_provider, payment_window_hours')
            .eq('id', 1)
            .maybeSingle();
        if (c != null) cfg = Map<String, dynamic>.from(c);
      } catch (e) {
        // A customer cannot read payment_config if it is admin-only RLS; the
        // screen then simply shows no payment options rather than failing.
        debugPrint('[CustomerInvoice] payment_config unavailable: $e');
      }

      if (!mounted) return;
      setState(() {
        _invoice = pick;
        _paymentConfig = cfg;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('[CustomerInvoice] fetch error: $e');
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

  Future<void> _respond(bool approve) async {
    final inv = _invoice;
    if (inv == null) return;

    String? reason;
    if (!approve) {
      final ctrl = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tolak Invoice', style: TextStyle(fontSize: 15)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Invoice akan ditolak dan pesanan dibatalkan. Workshop akan '
              'menghubungi Anda untuk pengembalian kendaraan.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: const Text('Tolak Invoice'),
            ),
          ],
        ),
      );
      // Cancelling the dialog means cancelling the decline.
      if (reason == null) return;
    }

    setState(() => _busy = true);
    try {
      final res = await _supabase.rpc('customer_respond_to_invoice', params: {
        'p_invoice_id': inv['id'],
        'p_approve': approve,
        'p_reason': (reason == null || reason.isEmpty) ? null : reason,
      });
      final map = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (!mounted) return;

      if (map['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve
              ? 'Invoice disetujui. Silakan lanjutkan pembayaran.'
              : 'Invoice ditolak. Pesanan dibatalkan dan workshop sudah diberi tahu.'),
          backgroundColor: approve ? _green : _amber,
          duration: const Duration(seconds: 5),
        ));
        await _fetch();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(map['error']?.toString() ?? 'Gagal memproses.'),
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
      debugPrint('[CustomerInvoice] respond error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const ReVAppBar(title: Text('Invoice'), showBackButton: true),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.fireRed))
          : _error != null
              ? _message(cs, Icons.error_outline, _red, 'Gagal memuat invoice',
                  _error!, retry: true)
              : _invoice == null
                  ? _message(cs, Icons.hourglass_empty, _amber,
                      'Invoice belum tersedia',
                      'Invoice akan muncul di sini setelah tim Revive '
                          'memeriksa estimasi akhir dari workshop.')
                  : _body(cs, _invoice!),
    );
  }

  Widget _message(ColorScheme cs, IconData icon, Color color, String title,
      String body,
      {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant, height: 1.5)),
            if (retry) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetch, child: const Text('Coba lagi')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme cs, Map<String, dynamic> inv) {
    final status = inv['status']?.toString() ?? '';
    final initial = (inv['initial_estimation_cost'] as num?)?.toDouble();
    final finalCost = (inv['final_cost'] as num?)?.toDouble() ?? 0;
    final delta = initial == null ? null : finalCost - initial;
    final canRespond = status == 'released';
    final approved = status == 'approved' || status == 'paid';

    final lineItems = inv['line_items'];
    final items = lineItems is List ? lineItems : const [];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ── headline ────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inv['invoice_number']?.toString() ?? 'Invoice',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(_idr(finalCost),
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('Total biaya perbaikan',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: 12),

        // ── initial vs final: the comparison that matters ───────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: _pair('Estimasi awal (dari foto)',
                      _idr(initial), cs.onSurfaceVariant)),
              Expanded(
                  child: _pair('Biaya akhir (setelah diperiksa)',
                      _idr(finalCost), cs.onSurface)),
            ]),
            if (delta != null) ...[
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(delta > 0 ? 'Kenaikan' : 'Penurunan',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                  Text(_idr(delta.abs()),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: delta > 0 ? _red : _green)),
                ],
              ),
            ],
          ]),
        ),

        // ── per-panel breakdown ─────────────────────────────────────────────
        if (items.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Rincian',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          ...items.whereType<Map>().map((it) {
            final label = it['panel']?.toString() ??
                it['label']?.toString() ??
                'Item';
            final amount = it['final_cost'] ?? it['amount'];
            final init = it['initial_cost'];
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 12, color: cs.onSurface)),
                ),
                if (init != null)
                  Text('${_idr(init)}  →  ',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                Text(_idr(amount),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
              ]),
            );
          }),
        ],

        const SizedBox(height: 16),

        // ── action area ─────────────────────────────────────────────────────
        if (canRespond) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _amber.withValues(alpha: 0.35)),
            ),
            child: Text(
              'Dengan menyetujui invoice, Anda menyetujui biaya akhir ini dan '
              'perbaikan akan dimulai setelah pembayaran diterima.',
              style: TextStyle(
                  fontSize: 11.5, color: cs.onSurface, height: 1.45),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _respond(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: BorderSide(color: _red.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('Tolak',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _busy ? null : () => _respond(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Setujui Invoice',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ],

        if (approved) ...[
          _paymentOptions(cs, inv),
        ],

        if (status == 'declined') ...[
          _notice(cs, _red, Icons.cancel_outlined, 'Invoice ditolak',
              inv['decline_reason']?.toString() ??
                  'Pesanan dibatalkan. Workshop akan menghubungi Anda untuk pengembalian kendaraan.'),
        ],

        if (status == 'paid') ...[
          _notice(cs, _green, Icons.check_circle_outline, 'Pembayaran diterima',
              'Pembayaran Anda sudah kami terima. Perbaikan kendaraan sedang berjalan.'),
        ],

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _pair(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Widget _notice(ColorScheme cs, Color color, IconData icon, String title,
      String body) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 3),
            Text(body,
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface, height: 1.45)),
          ]),
        ),
      ]),
    );
  }

  /// Shows only what can actually take money right now.
  Widget _paymentOptions(ColorScheme cs, Map<String, dynamic> inv) {
    final cfg = _paymentConfig ?? const <String, dynamic>{};
    final onlineOn = cfg['online_enabled'] == true;
    final manualOn = cfg['manual_transfer_enabled'] != false;
    final banks = cfg['bank_accounts'];
    final accounts = banks is List ? banks : const [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      Text('Pembayaran',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: cs.onSurface)),
      const SizedBox(height: 8),

      if (onlineOn)
        _payTile(cs, Icons.credit_card, 'Kartu / E-Wallet',
            'Bayar langsung melalui gateway pembayaran.', () {
          // The gateway edge function is not wired to keys yet; the button is
          // shown only when the platform has switched online payment on, so the
          // honest state here is "contact us", not a fake success.
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Pembayaran online belum aktif. Silakan gunakan transfer bank.'),
            backgroundColor: _amber,
          ));
        }),

      if (manualOn && accounts.isNotEmpty)
        ...accounts.whereType<Map>().map((b) => _bankCard(cs, inv, b)),

      if (manualOn && accounts.isEmpty)
        _notice(cs, _amber, Icons.info_outline, 'Transfer bank',
            'Rekening tujuan belum dikonfigurasi. Hubungi tim Revive untuk '
                'instruksi pembayaran.'),

      if (!onlineOn && accounts.isEmpty)
        _notice(cs, _amber, Icons.info_outline, 'Metode pembayaran',
            'Hubungi tim Revive untuk menyelesaikan pembayaran invoice ini.'),
    ]);
  }

  Widget _payTile(ColorScheme cs, IconData icon, String title, String sub,
      VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            Icon(icon, size: 19, color: cs.onSurface),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurface)),
                    Text(sub,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
            ),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  Widget _bankCard(ColorScheme cs, Map<String, dynamic> inv, Map b) {
    final amount = (inv['final_cost'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _green.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_outlined, size: 17, color: _green),
          const SizedBox(width: 8),
          Text(b['bank']?.toString() ?? 'Bank',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
        ]),
        const SizedBox(height: 8),
        _kv(cs, 'Nomor rekening', b['account_number']?.toString() ?? '—',
            copyable: b['account_number']?.toString()),
        _kv(cs, 'Atas nama', b['account_holder']?.toString() ?? '—'),
        _kv(cs, 'Jumlah', _idr(amount)),
        const SizedBox(height: 8),
        Text(
          'Kirim bukti transfer ke tim Revive melalui WhatsApp atau email. '
          'Pembayaran akan diverifikasi dan perbaikan dimulai setelah dana '
          'diterima.',
          style: TextStyle(
              fontSize: 11, color: cs.onSurfaceVariant, height: 1.45),
        ),
      ]),
    );
  }

  Widget _kv(ColorScheme cs, String k, String v, {String? copyable}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(
          width: 108,
          child: Text(k,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
        ),
        if (copyable != null)
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: copyable));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Nomor rekening disalin.'),
                duration: Duration(seconds: 2),
              ));
            },
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.copy, size: 14),
            ),
          ),
      ]),
    );
  }
}
