import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../partner_dashboard_controller.dart';

/// The single place a workshop job's next action is decided and drawn.
///
/// This used to be duplicated per surface, and the two copies disagreed: the
/// desktop card offered "Issue Invoice" for an admitted job while the mobile card
/// offered a bare "Advance". That Advance called `advanceJobStage` from
/// `5_admitted`, which the old transition map and the old database function both
/// allowed — so on a phone a car could move from the bay into repair before the
/// invoice was issued or the customer had paid. The database now refuses that edge
/// outright, and both cards render this widget, so they cannot drift again.
///
/// Accepted statuses are deliberately grouped by who owes the next move:
///   * 3_booked      -> the workshop admits the vehicle
///   * 5_admitted    -> the workshop prices the repair and issues the invoice
///   * 3_inspected   -> the CUSTOMER pays; the workshop waits
///   * 4_paid        -> the workshop starts the repair
///   * 6_in_progress -> the workshop finishes the work
///   * 8_awaiting_delivery -> ops/driver hands the car over
class PartnerJobActionControl extends StatelessWidget {
  final PartnerJobNode job;
  final PartnerDashboardController controller;
  final Color color;

  /// Mobile sizing. Both branches render the same control, only scaled.
  final bool compact;

  const PartnerJobActionControl({
    super.key,
    required this.job,
    required this.controller,
    required this.color,
    this.compact = false,
  });

  double get _fontSize => compact ? 12 : 11;
  double get _iconSize => compact ? 14 : 13;
  BorderRadius get _radius => BorderRadius.circular(compact ? 8 : 6);
  EdgeInsets get _pad => EdgeInsets.symmetric(horizontal: compact ? 10 : 8);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // In the bay: price the repair. Re-V turns this into the customer's invoice.
    if (job.status == '5_admitted') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF059669),
          foregroundColor: Colors.white,
          padding: _pad,
          shape: RoundedRectangleBorder(borderRadius: _radius),
          elevation: 0,
        ),
        icon: Icon(Icons.receipt_long_outlined, size: _iconSize),
        label: Text('Issue Invoice',
            style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold)),
        onPressed: () => showIssueInvoiceDialog(context, job),
      );
    }

    // Invoiced: the customer has to pay before any work starts, so there is no
    // workshop action to offer. Stated rather than shown as a dead button.
    if (job.status == '3_inspected') {
      return _Gate(
        label: 'Awaiting payment',
        compact: compact,
        radius: _radius,
        fontSize: _fontSize,
        iconSize: _iconSize,
      );
    }

    // Paid: this is the green light. The database accepts 4_paid -> 6_in_progress
    // and nothing else may reach repair, so the workshop starts the work here.
    if (job.status == '4_paid') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF059669),
          foregroundColor: Colors.white,
          padding: _pad,
          shape: RoundedRectangleBorder(borderRadius: _radius),
          elevation: 0,
        ),
        icon: Icon(Icons.play_arrow_rounded, size: _iconSize),
        label: Text('Start Repair',
            style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold)),
        onPressed: () => controller.advanceJobStage(job.id, job.status),
      );
    }

    // Delivered is ops/driver work; a workshop member has nothing to press.
    if (job.status == '8_awaiting_delivery') {
      return _Gate(
        label: 'Awaiting delivery',
        compact: compact,
        radius: _radius,
        fontSize: _fontSize,
        iconSize: _iconSize,
      );
    }

    final admits = job.status == '3_booked';
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: cs.surface,
        padding: _pad,
        shape: RoundedRectangleBorder(borderRadius: _radius),
        elevation: 0,
      ),
      icon: Icon(admits ? Icons.login_rounded : Icons.arrow_forward,
          size: _iconSize),
      label: Text(admits ? 'Admit Vehicle' : 'Advance',
          style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold)),
      onPressed: () => controller.advanceJobStage(job.id, job.status),
    );
  }
}

/// A non-interactive state: the next move belongs to someone else.
class _Gate extends StatelessWidget {
  final String label;
  final bool compact;
  final BorderRadius radius;
  final double fontSize;
  final double iconSize;

  const _Gate({
    required this.label,
    required this.compact,
    required this.radius,
    required this.fontSize,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFB45309);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 8, vertical: compact ? 0 : 4),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: radius,
        border: Border.all(color: amber.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_top_rounded, size: iconSize, color: amber),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: fontSize, fontWeight: FontWeight.bold, color: amber),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a dialog for the partner to report the final inspection cost.
/// Re-V then issues the formal invoice to the customer.
///
/// Shared by both dashboards: a workshop on a phone previously had no way to
/// reach this at all, so an admitted job could only be pushed forward.
void showIssueInvoiceDialog(BuildContext context, PartnerJobNode job) {
  final cs = Theme.of(context).colorScheme;
  final ctrl = TextEditingController();
  bool loading = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: cs.surfaceContainerLowest,
        title: Row(children: [
          const Icon(Icons.receipt_long_outlined, color: Color(0xFF059669), size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Issue Invoice \u2014 ${job.carMake} ${job.carModel}',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the final repair cost based on your physical inspection. '
              'Re-V will issue a formal invoice to the customer for payment approval.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Final Repair Cost (IDR)',
                hintText: 'e.g. 2500000',
                prefixText: 'Rp ',
                border: const OutlineInputBorder(),
                labelStyle: TextStyle(color: cs.onSurfaceVariant),
              ),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: loading ? null : () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: loading
                ? null
                : () async {
                    final raw = ctrl.text.trim().replaceAll(',', '').replaceAll('.', '');
                    final amount = double.tryParse(raw);
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Please enter a valid repair cost.'),
                        backgroundColor: Colors.red,
                      ));
                      return;
                    }
                    setS(() => loading = true);
                    try {
                      final result = await Supabase.instance.client.rpc(
                        'partner_issue_invoice',
                        params: {'p_job_id': job.id, 'p_final_cost': amount},
                      );
                      final response =
                          result is Map<String, dynamic> ? result : <String, dynamic>{};
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (response['success'] == true) {
                        // Dispatch notification to customer
                        await Supabase.instance.client.functions.invoke(
                          'send-notification',
                          body: {
                            'job_id': job.id,
                            'customer_id': response['customer_id'],
                            'new_status': '3_inspected',
                          },
                        );
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Invoice issued: Rp ${amount.toStringAsFixed(0)}. Customer notified via email & WhatsApp.'),
                            backgroundColor: const Color(0xFF059669),
                            duration: const Duration(seconds: 4),
                          ));
                        }
                      } else {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(response['error']?.toString() ??
                                'Failed to issue invoice.'),
                            backgroundColor: Colors.red,
                          ));
                        }
                      }
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      debugPrint('[IssueInvoice] Error: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Error: ${e.toString().replaceAll('PostgrestException', '').trim()}'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
            ),
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Issue Invoice', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
}
