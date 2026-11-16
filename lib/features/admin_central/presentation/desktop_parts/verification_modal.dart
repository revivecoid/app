part of '../master_admin_desktop.dart';

// ─── Verification Modal ───────────────────────────────────────────────────────
//
// This modal used to be a mock: a painted BCA slip, a fake SHA256, a made-up
// "99.4% OCR match" and a reconciler claiming "3 of 3 rules met" over a
// hard-coded Rp 3.575.000. Approving it called overrideJobStatus(job, '4_paid'),
// which moved the job without writing a payment at all — so the invoice stayed
// unpaid, no payment row existed, and nothing recorded who approved what.
//
// It now reads the real invoice and payment rows for the job, shows the proof
// image when one was uploaded, checks the three things an admin actually needs
// to see, and writes through the real RPCs:
//   • payment exists  → admin_review_payment(payment_id, approve|reject, note)
//   • no payment row  → admin_record_manual_payment(job_id, amount, note)

class _VerificationModal extends StatefulWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  final VoidCallback onClose;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  const _VerificationModal(
      {required this.cs,
      required this.job,
      required this.onClose,
      required this.onApprove,
      required this.onReject});

  @override
  State<_VerificationModal> createState() => _VerificationModalState();
}

class _PaymentContext {
  final String? invoiceId;
  final String? invoiceNumber;
  final double? finalCost;
  final String? invoiceStatus;
  final String? paymentId;
  final String? paymentRef;
  final double? paymentAmount;
  final String? paymentMethod;
  final String? paymentStatus;
  final String? proofKey;
  final String? proofUrl;
  final String? reviewNote;

  const _PaymentContext({
    this.invoiceId,
    this.invoiceNumber,
    this.finalCost,
    this.invoiceStatus,
    this.paymentId,
    this.paymentRef,
    this.paymentAmount,
    this.paymentMethod,
    this.paymentStatus,
    this.proofKey,
    this.proofUrl,
    this.reviewNote,
  });

  bool get hasPayment => paymentId != null;
  bool get isReviewable =>
      paymentStatus == 'pending' || paymentStatus == 'awaiting_review';
  bool get isPaid => paymentStatus == 'paid';
  bool get amountMatches =>
      finalCost != null &&
      paymentAmount != null &&
      (finalCost! - paymentAmount!).abs() < 0.5;
}

class _VerificationModalState extends State<_VerificationModal> {
  final _sb = Supabase.instance.client;
  final _noteCtrl = TextEditingController();
  Future<_PaymentContext>? _future;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<_PaymentContext> _load() async {
    Map<String, dynamic>? inv;
    Map<String, dynamic>? pay;
    try {
      inv = await _sb
          .from('invoices')
          .select('id, invoice_number, final_cost, status, payment_method')
          .eq('job_id', widget.job.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      pay = await _sb
          .from('payments')
          .select(
              'id, reference, amount, method, status, proof_file_key, review_note')
          .eq('job_id', widget.job.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (e) {
      debugPrint('[Verification] load failed: $e');
    }

    final proofKey = pay?['proof_file_key'] as String?;
    final proofUrl = (proofKey != null && proofKey.isNotEmpty)
        ? await R2Storage.signedUrl(proofKey)
        : null;

    double? asDouble(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

    return _PaymentContext(
      invoiceId: inv?['id'] as String?,
      invoiceNumber: inv?['invoice_number'] as String?,
      finalCost: asDouble(inv?['final_cost']),
      invoiceStatus: inv?['status'] as String?,
      paymentId: pay?['id'] as String?,
      paymentRef: pay?['reference'] as String?,
      paymentAmount: asDouble(pay?['amount']),
      paymentMethod: pay?['method'] as String?,
      paymentStatus: pay?['status'] as String?,
      proofKey: proofKey,
      proofUrl: proofUrl,
      reviewNote: pay?['review_note'] as String?,
    );
  }

  String get _note => _noteCtrl.text.trim();

  Future<void> _run(Future<void> Function() action, String success,
      Future<void> Function() close) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success),
        backgroundColor: const Color(0xFF059669),
      ));
      await close();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e
          .toString()
          .replaceAll('PostgrestException', '')
          .replaceAll('Exception:', '')
          .trim());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(_PaymentContext ctx) => _run(
      () async {
        if (ctx.isReviewable) {
          await _sb.rpc('admin_review_payment', params: {
            'p_payment_id': ctx.paymentId,
            'p_approve': true,
            'p_note': _note.isEmpty ? null : _note,
          });
        } else if (ctx.isPaid) {
          throw Exception('Pembayaran untuk job ini sudah lunas.');
        } else {
          final amount = ctx.finalCost ?? widget.job.finalPrice;
          if (amount == null || amount <= 0) {
            throw Exception(
                'Tagihan belum diterbitkan. Terbitkan invoice dulu di menu Invoice & Admission.');
          }
          final res = await _sb.rpc('admin_record_manual_payment', params: {
            'p_job_id': widget.job.id,
            'p_amount': amount.round(),
            'p_method': 'manual_transfer',
            'p_reference': null,
            'p_note': _note.isEmpty ? 'Diverifikasi admin' : _note,
          });
          if (res is Map && res['success'] == false) {
            throw Exception('${res['error']}');
          }
        }
      },
      'Pembayaran dicatat. Job masuk tahap pengerjaan.',
      widget.onApprove);

  Future<void> _reject(_PaymentContext ctx) => _run(
      () async {
        if (!ctx.hasPayment) {
          throw Exception(
              'Belum ada pembayaran yang bisa ditolak. Minta pelanggan mengunggah bukti transfer.');
        }
        await _sb.rpc('admin_review_payment', params: {
          'p_payment_id': ctx.paymentId,
          'p_approve': false,
          'p_note': _note.isEmpty ? 'Bukti pembayaran tidak valid.' : _note,
        });
      },
      'Pembayaran ditolak. Pelanggan menerima notifikasi.',
      widget.onReject);

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 960,
              margin: const EdgeInsets.all(24),
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ]),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: cs.surfaceContainerHigh))),
                  child: Row(children: [
                    Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.verified_outlined,
                            color: cs.primary, size: 22)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text('Verifikasi Pembayaran',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface)),
                                const SizedBox(width: 8),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: cs.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(4)),
                                    child: Text('#${widget.job.id}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: cs.primary,
                                            fontFamily: 'monospace'))),
                              ]),
                              Text(
                                  '${widget.job.customerName}  ·  ${widget.job.carIdentity}  ·  ${widget.job.partnerName}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                            ])),
                    IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: cs.onSurfaceVariant),
                        onPressed: widget.onClose),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: FutureBuilder<_PaymentContext>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final ctx = snap.data ?? const _PaymentContext();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: _EvidenceCard(cs: cs, ctx: ctx)),
                                  const SizedBox(width: 24),
                                  Expanded(
                                      child: _ChecksPanel(
                                        cs: cs,
                                        ctx: ctx,
                                        job: widget.job,
                                        noteCtrl: _noteCtrl,
                                      )),
                                ]),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(_error!,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFB91C1C))),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(color: cs.surfaceContainerHigh))),
                  child: FutureBuilder<_PaymentContext>(
                    future: _future,
                    builder: (context, snap) {
                      final ctx = snap.data ?? const _PaymentContext();
                      final approveLabel = ctx.isReviewable
                          ? 'Setujui Pembayaran'
                          : ctx.isPaid
                              ? 'Sudah Lunas'
                              : 'Catat Pembayaran Manual';
                      return Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _reject(ctx),
                              icon: Icon(Icons.close_rounded,
                                  size: 16, color: cs.onSurface),
                              label: Text('Tolak / Minta Ulang',
                                  style: TextStyle(
                                      fontSize: 13, color: cs.onSurface)),
                              style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: cs.outline),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8))),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: (_busy || ctx.isPaid)
                                  ? null
                                  : () => _approve(ctx),
                              icon: _busy
                                  ? SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: cs.onPrimary))
                                  : Icon(Icons.check_rounded,
                                      size: 16, color: cs.onPrimary),
                              label: Text(approveLabel,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onPrimary)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  elevation: 2),
                            ),
                          ]);
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

String _rp(double? v) =>
    v == null ? 'Rp —' : 'Rp ${NumberFormat('#,###', 'id_ID').format(v)}';

class _EvidenceCard extends StatelessWidget {
  final ColorScheme cs;
  final _PaymentContext ctx;
  const _EvidenceCard({required this.cs, required this.ctx});

  List<Widget> _row(String label, String value, {Color? color}) => [
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 12),
                  Flexible(
                      child: Text(value,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: color ?? cs.onSurface,
                              fontFamily: 'monospace'),
                          textAlign: TextAlign.right)),
                ])),
        Divider(height: 1, color: cs.surfaceContainer),
      ];

  @override
  Widget build(BuildContext context) {
    final statusColor = ctx.isPaid
        ? const Color(0xFF059669)
        : ctx.hasPayment
            ? const Color(0xFFB45309)
            : cs.onSurfaceVariant;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('BUKTI PEMBAYARAN',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('TAGIHAN',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(_rp(ctx.finalCost ?? ctx.paymentAmount),
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                  height: 1.0)),
          const SizedBox(height: 12),
          ..._row('No. Invoice', ctx.invoiceNumber ?? 'Belum diterbitkan'),
          ..._row('Status Invoice', ctx.invoiceStatus ?? '—'),
          ..._row('Pembayaran', ctx.paymentStatus ?? 'Belum ada',
              color: statusColor),
          ..._row('Nominal Masuk', _rp(ctx.paymentAmount)),
          ..._row('Metode', ctx.paymentMethod ?? '—'),
          ..._row('Referensi', ctx.paymentRef ?? '—'),
          if (ctx.reviewNote != null)
            ..._row('Catatan Review', ctx.reviewNote!),
        ]),
      ),
      const SizedBox(height: 12),
      if (ctx.proofUrl != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(ctx.proofUrl!,
              height: 240,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    color: cs.surfaceContainerLow,
                    child: Text('Bukti tidak bisa ditampilkan',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  )),
        )
      else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.image_not_supported_outlined,
                size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  ctx.proofKey == null
                      ? 'Belum ada bukti transfer yang diunggah.'
                      : 'Bukti tersimpan (${ctx.proofKey}) tetapi tautannya gagal dibuat.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ]),
        ),
    ]);
  }
}

class _ChecksPanel extends StatelessWidget {
  final ColorScheme cs;
  final _PaymentContext ctx;
  final AdminJobNode job;
  final TextEditingController noteCtrl;
  const _ChecksPanel(
      {required this.cs,
      required this.ctx,
      required this.job,
      required this.noteCtrl});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PEMERIKSAAN',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8)),
      const SizedBox(height: 12),
      _Check(
        cs: cs,
        title: 'Nominal sesuai tagihan',
        subtitle:
            'Tagihan ${_rp(ctx.finalCost)}  ·  Masuk ${_rp(ctx.paymentAmount)}',
        ok: ctx.amountMatches,
        pending: ctx.paymentAmount == null || ctx.finalCost == null,
      ),
      const SizedBox(height: 8),
      _Check(
        cs: cs,
        title: 'Bukti transfer terlampir',
        subtitle: ctx.proofKey ?? 'Tidak ada berkas',
        ok: ctx.proofKey != null && ctx.proofKey!.isNotEmpty,
        pending: !ctx.hasPayment,
      ),
      const SizedBox(height: 8),
      _Check(
        cs: cs,
        title: 'Bengkel sudah ditugaskan',
        subtitle: job.partnerName,
        ok: job.partnerId != null,
        pending: false,
      ),
      const SizedBox(height: 16),
      Text('CATATAN ADMIN (opsional)',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8)),
      const SizedBox(height: 8),
      TextField(
        controller: noteCtrl,
        maxLines: 3,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Alasan bila menolak, atau keterangan pembayaran manual',
          hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        ctx.hasPayment
            ? 'Menyetujui akan menandai pembayaran lunas, invoice lunas, dan job masuk tahap pengerjaan.'
            : 'Belum ada baris pembayaran. Menyetujui akan mencatat pembayaran manual atas nama admin.',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.4),
      ),
    ]);
  }
}

class _Check extends StatelessWidget {
  final ColorScheme cs;
  final String title;
  final String subtitle;
  final bool ok;
  final bool pending;
  const _Check(
      {required this.cs,
      required this.title,
      required this.subtitle,
      required this.ok,
      this.pending = false});

  @override
  Widget build(BuildContext context) {
    final color = pending
        ? cs.onSurfaceVariant
        : ok
            ? const Color(0xFF059669)
            : const Color(0xFFB91C1C);
    final icon = pending
        ? Icons.remove_circle_outline
        : ok
            ? Icons.check_circle_outline
            : Icons.error_outline;
    final badge =
        pending ? 'BELUM ADA' : (ok ? 'COCOK' : 'TIDAK COCOK');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.surfaceContainerHigh)),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4)),
          child: Text(badge,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFamily: 'monospace')),
        ),
      ]),
    );
  }
}
