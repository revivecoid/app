part of '../master_admin_desktop.dart';

// ─── Ops Matrix ───────────────────────────────────────────────────────────────

class _OpsMatrixContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;
  final void Function(AdminJobNode) onVerify;

  const _OpsMatrixContent(
      {required this.cs,
      required this.state,
      required this.controller,
      required this.onVerify});

  String _formatRupiah(double amount) {
    final f = NumberFormat('#,###', 'id_ID');
    return 'Rp ${f.format(amount)}';
  }

  @override
  Widget build(BuildContext context) {
    // C-70 fix: apply searchQuery to Ops Matrix (license plate, job ID, customer name)
    final query = state.searchQuery.toLowerCase();
    final filteredJobs = query.isEmpty
        ? state.activeJobs
        : state.activeJobs.where((j) =>
            j.id.toLowerCase().contains(query) ||
            (j.customerName.toLowerCase().contains(query)) ||
            (j.carIdentity.toLowerCase().contains(query)) ||
            (j.partnerName.toLowerCase().contains(query))
          ).toList();

    final pendingJobs = filteredJobs
        .where((j) =>
            j.status == '3_booked' ||
            j.status == '3_inspected')
        .toList();

    final settlementLabel = state.settlementLoading
        ? 'Loading...'
        : _formatRupiah(state.dailySettlementAmount);

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    _Chip(
                        cs: cs,
                        label: 'Master Ops Matrix',
                        bgColor: cs.surfaceContainerHigh,
                        fgColor: cs.primary),
                    const SizedBox(width: 8),
                    Text('BCA / VA Liquidity Gateway Live',
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                      'Active Financial Clearing & Dispatch Matrix',
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                ])),
            const SizedBox(width: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _KpiCard(
                  cs: cs,
                  icon: Icons.account_balance_outlined,
                  label: 'Daily Vault Settlement',
                  value: settlementLabel),
              _KpiCard(
                  cs: cs,
                  icon: Icons.hourglass_top_rounded,
                  label: 'Unreconciled Slips',
                  value: '${pendingJobs.length} Action Required',
                  highlight: pendingJobs.isNotEmpty),
              OutlinedButton.icon(
                onPressed: () {},
                icon: Icon(Icons.history_rounded,
                    size: 16, color: cs.onSurface),
                label: Text('Gateway Audit',
                    style: TextStyle(
                        color: cs.onSurface, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.outline),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          // Filter bar
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color:
                          cs.onSurface.withValues(alpha: 0.04),
                      blurRadius: 8)
                ]),
            child: Row(children: [
              Expanded(
                  child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12),
                decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.filter_list_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text('Status: All Active',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface)),
                ]),
              )),
              const SizedBox(width: 8),
              _Chip(
                  cs: cs,
                  label:
                      '${state.activeJobs.length} jobs',
                  bgColor: cs.surfaceContainerLow,
                  fgColor: cs.onSurfaceVariant),
              const Spacer(),
              const _PulseDot(color: Color(0xFF10b981)),
              const SizedBox(width: 6),
              Text('Live Realtime',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant)),
              const SizedBox(width: 12),
              IconButton(
                  icon: Icon(Icons.download_rounded,
                      color: cs.onSurfaceVariant, size: 20),
                  tooltip: 'Export',
                  onPressed: () {}),
            ]),
          ),
          const SizedBox(height: 16),
          // Table
          Container(
            decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color:
                          cs.onSurface.withValues(alpha: 0.04),
                      blurRadius: 8)
                ]),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Container(
                color: cs.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(children: [
                  _TH(cs: cs, label: 'Job ID', flex: 2),
                  _TH(cs: cs, label: 'Vehicle & Plate', flex: 3),
                  _TH(cs: cs, label: 'Owner', flex: 3),
                  _TH(cs: cs, label: 'Assigned Hub', flex: 3),
                  _TH(cs: cs, label: 'Payment', flex: 2),
                  _TH(
                      cs: cs,
                      label: 'Status',
                      flex: 3),
                  _TH(
                      cs: cs,
                      label: 'Action',
                      flex: 2,
                      right: true),
                ]),
              ),
              if (state.activeJobs.isEmpty && !state.isLoading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 48, color: cs.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text('No active jobs in the pipeline.',
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                  ],
                ),
              ),
            )
              else
                ...filteredJobs.map((j) => _JobRow(
                      cs: cs,
                      job: j,
                      partners: state.partners,
                      onVerify: () => onVerify(j),
                      onOverride: (newStatus) =>
                          controller.overrideJobStatus(
                              j.id, newStatus),
                    )),
              if (state.isLoading)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: cs.primary))),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                color: cs.surfaceContainerLow,
                child: Row(children: [
                  const _PulseDot(
                      color: Color(0xFF10b981)),
                  const SizedBox(width: 6),
                  Text('Realtime sync: ',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant)),
                  Text(
                      state.isLoading
                          ? 'Syncing…'
                          : '${state.activeJobs.length} job(s) live',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                ]),
              ),
            ]),
          ),
        ]);
  }
}

class _JobRow extends StatelessWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  final List<PartnerCrmNode> partners;
  final VoidCallback onVerify;
  final ValueChanged<String> onOverride;

  const _JobRow(
      {required this.cs,
      required this.job,
      required this.partners,
      required this.onVerify,
      required this.onOverride});

  bool get _pending =>
      job.status == '3_inspected';  // C-04 fix: only 3_inspected needs payment review

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: _pending
              ? cs.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          border: Border(
              bottom: BorderSide(
                  color: cs.surfaceContainerHigh, width: 1))),
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 12),
      child: Row(children: [
        // Job ID
        Expanded(
            flex: 2,
            child: Row(children: [
              if (_pending)
                Container(
                    width: 3,
                    height: 20,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius:
                            BorderRadius.circular(2))),
              Expanded(
                  child: Text('#${job.id}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: _pending
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: _pending
                              ? cs.primary
                              : cs.onSurface,
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis)),
            ])),
        // Vehicle
        Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(
                  job.carIdentity.contains('-')
                      ? job.carIdentity
                          .split('-')
                          .first
                          .trim()
                      : job.carIdentity,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              if (job.carIdentity.contains('-'))
                Text(
                    job.carIdentity
                        .split('-')
                        .last
                        .trim(),
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace')),
            ])),
        // Owner
        Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(job.customerName,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              Text('${job.timeElapsedCurrentStage} elapsed',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant)),
            ])),
        // Hub
        Expanded(
            flex: 3,
            child: Row(children: [
              Icon(Icons.warehouse_outlined,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(job.partnerName,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis)),
            ])),
        // Payment
        Expanded(
            flex: 2,
            child: job.finalPrice != null
                ? Text(
                    'Rp ${NumberFormat('#,###', 'id_ID').format(job.finalPrice)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: job.isPaid
                            ? const Color(0xFF059669)
                            : cs.onSurface,
                        fontFamily: 'monospace'))
                : Text('—',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant))),
        // Status
        Expanded(
            flex: 3,
            child: _StatusBadge(cs: cs, status: job.status)),
        // Action
        Expanded(
            flex: 2,
            child: Align(
                alignment: Alignment.centerRight,
                child: _pending
                    ? ElevatedButton.icon(
                        onPressed: onVerify,
                        icon: Icon(Icons.visibility_outlined,
                            size: 14, color: cs.onPrimary),
                        label: Text('Review Slip',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onPrimary)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize
                                .shrinkWrap),
                      )
                    : PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz,
                            color: cs.onSurfaceVariant,
                            size: 18),
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'view',
                            child: Row(children: [
                              Icon(Icons.open_in_new_rounded,
                                  size: 16,
                                  color: cs.onSurface),
                              const SizedBox(width: 10),
                              Text('View Job Details',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'override',
                            child: Row(children: [
                              Icon(
                                  Icons
                                      .swap_horiz_rounded,
                                  size: 16,
                                  color: cs.onSurface),
                              const SizedBox(width: 10),
                              Text('Override Status',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'flag',
                            child: Row(children: [
                              Icon(Icons.flag_outlined,
                                  size: 16,
                                  color: cs.error),
                              const SizedBox(width: 10),
                              Text('Flag / Escalate',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.error)),
                            ]),
                          ),
                        ],
                        onSelected: (val) {
                          switch (val) {
                            case 'view':
                              context.push('/track/${job.id}');
                            case 'override':
                              _showStatusPicker(
                                  context, job, onOverride);
                            case 'flag':
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                    'Job #${job.id} flagged for escalation',
                                    style: TextStyle(
                                        color: cs.onSurface)),
                                backgroundColor:
                                    cs.surfaceContainerHigh,
                              ));
                          }
                        },
                      ))),
      ]),
    );
  }

  void _showStatusPicker(BuildContext context, AdminJobNode job,
      ValueChanged<String> onOverride) {
    final cs = Theme.of(context).colorScheme;
    final statuses = [
      ('2_estimated', 'Estimated'),
      ('3_booked', 'Booked'),
      ('5_admitted', 'Admitted'),
      ('3_inspected', 'Inspected (Invoice Issued)'),
      ('4_paid', 'Paid'),
      ('6_in_progress', 'In Progress'),
      ('7_finished', 'Finished'),
      ('8_awaiting_delivery', 'Awaiting Delivery'),
      ('9_done', 'Done'),
      ('0_cancelled', 'Cancelled'),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerLowest,
        title: Text('Override Status — #${job.id}',
            style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses
              .map((s) => ListTile(
                    leading: Radio<String>(
                      value: s.$1,
                      groupValue: job.status,
                      activeColor: cs.primary,
                      onChanged: (v) {
                        if (v != null) {
                          onOverride(v);
                          Navigator.of(ctx).pop();
                        }
                      },
                    ),
                    title: Text(s.$2,
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface)),
                    subtitle: Text(s.$1,
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                            fontFamily: 'monospace')),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: TextStyle(color: cs.onSurfaceVariant)))
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ColorScheme cs;
  final String status;
  const _StatusBadge({required this.cs, required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    late String label;
    late IconData icon;
    switch (status) {
      case '3_booked':
        bg = cs.primary.withValues(alpha: 0.1);
        fg = cs.primary;
        label = 'Pending Verification';
        icon = Icons.circle;
      case '3_inspected':
        bg = const Color(0xFFf59e0b).withValues(alpha: 0.15);
        fg = const Color(0xFFb45309);
        label = 'AWAITING PAYMENT';
        icon = Icons.receipt_long_outlined;
      case 'overdue':
        bg = cs.secondaryContainer.withValues(alpha: 0.3);
        fg = cs.onSecondaryContainer;
        label = 'PAYMENT OVERDUE';
        icon = Icons.warning_amber_rounded;
      case '6_in_progress':
        bg = const Color(0xFF0ea5e9).withValues(alpha: 0.15);
        fg = const Color(0xFF0369a1);
        label = 'IN PROGRESS';
        icon = Icons.construction_rounded;
      case '4_paid':
      case '5_scheduled':
        bg = const Color(0xFF10b981).withValues(alpha: 0.1);
        fg = const Color(0xFF059669);
        label = status == '4_paid' ? 'PAID' : jobStatusLabel(status).toUpperCase(); // S-08: remove dead '5_scheduled'
        icon = Icons.event_available_rounded;
      default:
        bg = cs.surfaceContainerHigh;
        fg = cs.onSurfaceVariant;
        label = status
            .replaceAll('_', ' ')
            .toUpperCase();
        icon = Icons.radio_button_unchecked;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: fg),
        const SizedBox(width: 4),
        Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: fg),
                overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

