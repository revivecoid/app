import 'package:flutter/material.dart';

import '../partner_dashboard_controller.dart';
import 'partner_final_estimation_dialog.dart';

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

    // In the bay: price the repair. This submits the final estimation, which the
    // database turns into a draft invoice for Re-V to check and release — the
    // workshop no longer issues the invoice itself.
    if (job.status == '5_admitted') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF059669),
          foregroundColor: Colors.white,
          padding: _pad,
          shape: RoundedRectangleBorder(borderRadius: _radius),
          elevation: 0,
        ),
        icon: Icon(Icons.fact_check_outlined, size: _iconSize),
        label: Text('Final Estimate',
            style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold)),
        onPressed: () => showFinalEstimationDialog(context, job),
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
