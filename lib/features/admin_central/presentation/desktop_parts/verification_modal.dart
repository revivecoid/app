part of '../master_admin_desktop.dart';

// ─── Verification Modal ───────────────────────────────────────────────────────

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
  State<_VerificationModal> createState() =>
      _VerificationModalState();
}

class _VerificationModalState
    extends State<_VerificationModal> {
  bool _notifyWA = true;
  bool _approving = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final job = widget.job;
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
                  maxHeight:
                      MediaQuery.of(context).size.height *
                          0.9),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color:
                            Colors.black.withValues(alpha: 0.2),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ]),
              child: Column(mainAxisSize: MainAxisSize.min,
                  children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color:
                                  cs.surfaceContainerHigh))),
                  child: Row(children: [
                    Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: cs.primary
                                .withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(8)),
                        child: Icon(Icons.verified_outlined,
                            color: cs.primary, size: 22)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                      Row(children: [
                        Text(
                            'Manual Payment Proof Verification',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface)),
                        const SizedBox(width: 8),
                        Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: cs.surfaceContainerHigh,
                                borderRadius:
                                    BorderRadius.circular(4)),
                            child: Text('#${job.id}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                    fontFamily: 'monospace'))),
                      ]),
                      Text(
                          'Customer: ${job.customerName}  ·  ${job.carIdentity}',
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
                        child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                    Expanded(
                        child:
                            _BcaSlip(cs: cs, job: job)),
                    const SizedBox(width: 24),
                    Expanded(
                        child: _ReconcilerPanel(
                            cs: cs,
                            notifyWA: _notifyWA,
                            onToggle: (v) => setState(
                                () => _notifyWA = v))),
                  ]),
                ))),
                Container(
                  padding: const EdgeInsets.fromLTRB(
                      24, 12, 24, 20),
                  decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(
                              color:
                                  cs.surfaceContainerHigh))),
                  child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.end,
                      children: [
                    OutlinedButton.icon(
                      onPressed: _rejecting
                          ? null
                          : () async {
                              setState(
                                  () => _rejecting = true);
                              await widget.onReject();
                              setState(
                                  () => _rejecting = false);
                            },
                      icon: _rejecting
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onSurface))
                          : Icon(Icons.rule_rounded,
                              size: 16, color: cs.onSurface),
                      label: Text(
                          'Reject / Request Re-upload',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface)),
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cs.outline),
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(8))),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _approving
                          ? null
                          : () async {
                              setState(
                                  () => _approving = true);
                              await widget.onApprove();
                              setState(
                                  () => _approving = false);
                            },
                      icon: _approving
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary))
                          : Icon(Icons.lock_rounded,
                              size: 16, color: cs.onPrimary),
                      label: Text(
                          'Approve Payment & Dispatch to Workshop',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimary)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(8)),
                          elevation: 2),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _BcaSlip extends StatelessWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  const _BcaSlip({required this.cs, required this.job});

  List<Widget> _row(String label, String value,
          {bool hl = false, bool grn = false}) =>
      [
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant)),
              const SizedBox(width: 12),
              Flexible(
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hl
                              ? cs.primary
                              : grn
                                  ? const Color(0xFF059669)
                                  : cs.onSurface,
                          fontFamily: 'monospace'),
                      textAlign: TextAlign.right)),
            ])),
        Divider(height: 1, color: cs.surfaceContainer),
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        Text('UPLOADED SLIP RAW VIEWPORT',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.8)),
        Row(children: [
          Icon(Icons.fingerprint_rounded,
              color: cs.primary, size: 14),
          const SizedBox(width: 4),
          Text('SHA256: a8f9..43c2',
              style: TextStyle(
                  fontSize: 11,
                  color: cs.primary,
                  fontFamily: 'monospace')),
        ]),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  blurRadius: 8)
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFF003087),
                      borderRadius:
                          BorderRadius.circular(4)),
                  child: const Text('BCA',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: -0.5))),
              const SizedBox(width: 8),
              const Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                Text('m-Transfer',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF1e3a5f))),
                Text('BERHASIL / SUCCESS',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                        letterSpacing: 0.5)),
              ]),
            ]),
            Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
              Text('12/09/2026',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace')),
              Text('09:12:04 WIB',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace')),
            ]),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              Text('JUMLAH TRANSFER (TOTAL AMOUNT)',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.8)),
              const SizedBox(height: 4),
              Text(
                  job.finalPrice != null
                      ? 'Rp ${NumberFormat('#,###', 'id_ID').format(job.finalPrice)}'
                      : 'Rp —',
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1c1b1c),
                      height: 1.0)),
              const SizedBox(height: 4),
              const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.check_circle_outline,
                    size: 14,
                    color: Color(0xFF059669)),
                SizedBox(width: 4),
                Text('Admin Fee Included (Rp 0)',
                    style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF059669))),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          ..._row('Dari Rekening:', job.customerName),
          ..._row('Penerima:',
              'PT REVIVE OTOMOTIF\n8830-192-381'),
          ..._row('No. Referensi:', '#${job.id}', hl: true),
          ..._row('Engine Routing:',
              'BCA SWITCHING ENGINE: OK',
              grn: true),
          const SizedBox(height: 12),
          Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
            Row(children: [
              Icon(Icons.document_scanner_outlined,
                  color: cs.primary, size: 16),
              const SizedBox(width: 6),
              Text('Vision OCR Confidence',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ]),
            Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('99.4% Match',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                        fontFamily: 'monospace'))),
          ]),
        ]),
      ),
    ]);
  }
}

class _ReconcilerPanel extends StatelessWidget {
  final ColorScheme cs;
  final bool notifyWA;
  final ValueChanged<bool> onToggle;
  const _ReconcilerPanel(
      {required this.cs,
      required this.notifyWA,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        Text('AUTOMATED RECONCILER DIAGNOSTICS',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.8)),
        _Chip(
            cs: cs,
            label: '3 of 3 Rules Met',
            bgColor: cs.surfaceContainerHigh,
            fgColor: cs.onSurface),
      ]),
      const SizedBox(height: 12),
      _Check(
          cs: cs,
          title: 'Payable Total Match',
          subtitle:
              'System Due: Rp 3.575.000  ·  Slip: Rp 3.575.000',
          badge: 'EXACT MATCH'),
      const SizedBox(height: 8),
      _Check(
          cs: cs,
          title: 'Beneficiary Destination',
          subtitle: 'BCA 8830-192-381  PT Revive Otomotif',
          badge: 'REVIVE ACCT'),
      const SizedBox(height: 8),
      _Check(
          cs: cs,
          title: 'Target Workshop Reservation',
          subtitle: 'Hub Bay 04  ·  Confirmed',
          badge: 'RESERVED'),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color:
                      cs.onSurface.withValues(alpha: 0.06),
                  blurRadius: 4)
            ]),
        child: Row(children: [
          Icon(Icons.chat_bubble_outline_rounded,
              color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
            Text('Customer Notification Bridge',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            Text(
                'Send instant WhatsApp confirmation with digital valet slip',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant)),
          ])),
          Switch(
              value: notifyWA,
              activeThumbColor: cs.primary,
              onChanged: onToggle),
        ]),
      ),
    ]);
  }
}

class _Check extends StatelessWidget {
  final ColorScheme cs;
  final String title, subtitle, badge;
  const _Check(
      {required this.cs,
      required this.title,
      required this.subtitle,
      required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: cs.onSurface.withValues(alpha: 0.04),
                blurRadius: 4)
          ]),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF059669), size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 11, color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(width: 8),
        Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4)),
            child: Text(badge,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                    letterSpacing: 0.5))),
      ]),
    );
  }
}

