import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

// ─── Provider: load job + estimation data ─────────────────────────────────────

final _bookingJobProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, jobId) async {
  final res = await Supabase.instance.client
      .from('repair_jobs')
      .select('id, status, initial_estimation_cost, estimation_result, vehicles(make, model, year, license_plate)')
      .eq('id', jobId)
      .maybeSingle();
  return res != null ? Map<String, dynamic>.from(res) : null;
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class BookingSchedulingScreen extends ConsumerStatefulWidget {
  final String jobId;
  const BookingSchedulingScreen({super.key, required this.jobId});

  @override
  ConsumerState<BookingSchedulingScreen> createState() =>
      _BookingSchedulingScreenState();
}

class _BookingSchedulingScreenState
    extends ConsumerState<BookingSchedulingScreen> {
  final _sb = Supabase.instance.client;

  DateTime? _selectedDate;
  String _deliveryType = 'self_deliver'; // 'self_deliver' | 'pickup'
  bool _isBooking = false;
  String? _error;
  String? _dateError;

  // ── Date availability check ───────────────────────────────────────────────
  Future<bool> _checkDateAvailable(DateTime date) async {
    try {
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final weekday = date.weekday; // 1=Mon … 7=Sun

      final schedules = await _sb.from('partner_schedules').select();
      int totalCapacity = 0;
      for (final s in schedules) {
        final blacklisted = List<dynamic>.from(s['blacklisted_dates'] ?? []);
        final holidays = List<dynamic>.from(s['automated_holidays'] ?? []);
        final workdays = List<dynamic>.from(s['standard_working_days'] ?? []);
        final cap = (s['guaranteed_slots_per_day'] as num?)?.toInt() ?? 2;

        if (!blacklisted.contains(dateStr) &&
            !holidays.contains(dateStr) &&
            workdays.contains(weekday)) {
          totalCapacity += cap;
        }
      }

      if (totalCapacity == 0) return false;

      final count = await _sb
          .from('repair_jobs')
          .select('id')
          .gte('scheduled_date', '${dateStr}T00:00:00Z')
          .lte('scheduled_date', '${dateStr}T23:59:59Z')
          .inFilter('status', [
            '3_booked', '4_paid', '5_admitted',
            '6_in_progress', '7_finished', '8_awaiting_delivery'
          ])
          .count();

      return count.count < totalCapacity;
    } catch (e) {
      debugPrint('[Booking] Date check error: $e');
      return true; // Fail open — server validates atomically via book_slot RPC
    }
  }

  // ── Confirm booking ───────────────────────────────────────────────────────
  Future<void> _confirmBooking() async {
    if (_selectedDate == null) {
      setState(() => _dateError = 'Please select a preferred date.');
      return;
    }

    setState(() {
      _isBooking = true;
      _error = null;
      _dateError = null;
    });

    try {
      // book_slot RPC: atomic capacity check + books slot + advances 2_estimated → 3_booked
      await _sb.rpc('book_slot', params: {
        'p_job_id': widget.jobId,
        'p_delivery_type': _deliveryType,
        'p_scheduled_date': _selectedDate!.toIso8601String(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Booking confirmed! Drop off your vehicle on the selected date. '
            'We\'ll notify you once inspection is complete.'),
        backgroundColor: Color(0xFF059669),
        duration: Duration(seconds: 4),
      ));

      context.go('/');
    } catch (e) {
      debugPrint('[Booking] Error: $e');
      setState(() {
        _error = e
            .toString()
            .replaceAll('PostgrestException', '')
            .replaceAll('Exception:', '')
            .trim();
        _isBooking = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(_bookingJobProvider(widget.jobId));
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      Widget inner = Scaffold(
        appBar: ReVAppBar(
          title: const Text('Review Estimate & Book'),
          showBackButton: true,
        ),
        body: jobAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.fireRed)),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (job) {
            if (job == null) {
              return const Center(child: Text('Estimation not found.'));
            }

            final vehicle =
                job['vehicles'] as Map<String, dynamic>? ?? {};
            final estimatedCost =
                (job['initial_estimation_cost'] as num?)?.toDouble() ?? 0.0;
            final estimationResult =
                job['estimation_result'] as Map<String, dynamic>?;

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Vehicle header ──────────────────────────────────
                        _VehicleHeader(vehicle: vehicle, cs: cs),
                        const SizedBox(height: 20),

                        // ── Estimation summary (collapsible) ────────────────
                        _EstimationSummary(
                          estimatedCost: estimatedCost,
                          estimationResult: estimationResult,
                          cs: cs,
                        ),
                        const SizedBox(height: 24),

                        // ── Delivery type ───────────────────────────────────
                        Text('How will you deliver your vehicle?',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: cs.onSurface)),
                        const SizedBox(height: 10),
                        _DeliverySelector(
                          selected: _deliveryType,
                          onChanged: (v) => setState(() => _deliveryType = v),
                          cs: cs,
                        ),
                        const SizedBox(height: 24),

                        // ── Date picker ─────────────────────────────────────
                        Text('Select Preferred Admission Date',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: cs.onSurface)),
                        const SizedBox(height: 4),
                        Text(
                          'This is your preferred date — the workshop will confirm on arrival.',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        _BookingCalendar(
                          selectedDate: _selectedDate,
                          onDaySelected: (day) async {
                            final available =
                                await _checkDateAvailable(day);
                            setState(() {
                              if (available) {
                                _selectedDate = day;
                                _dateError = null;
                              } else {
                                _dateError =
                                    'No available slots on ${DateFormat('d MMMM yyyy').format(day)}. '
                                    'Please choose another date.';
                              }
                            });
                          },
                          cs: cs,
                        ),
                        if (_dateError != null) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 14, color: Colors.orange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_dateError!,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.orange)),
                            ),
                          ]),
                        ],
                        if (_selectedDate != null) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.check_circle_outline,
                                size: 14, color: Color(0xFF059669)),
                            const SizedBox(width: 6),
                            Text(
                              'Selected: ${DateFormat('EEEE, d MMMM yyyy').format(_selectedDate!)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669)),
                            ),
                          ]),
                        ],

                        // ── Important notice ────────────────────────────────
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: cs.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'The cost shown is an AI estimate based on your photos. '
                                  'After your vehicle is admitted, our technician will perform a thorough inspection '
                                  'and Re-V will issue your official invoice. '
                                  'Payment is only required after you review and approve the final invoice.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                      height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              Icon(Icons.error_outline,
                                  size: 16, color: cs.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: cs.onErrorContainer,
                                          fontSize: 12))),
                            ]),
                          ),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),

                // ── Sticky confirm button ───────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    boxShadow: [
                      BoxShadow(
                          color: cs.onSurface.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, -3)),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_isBooking || _selectedDate == null)
                              ? null
                              : _confirmBooking,
                      icon: _isBooking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.calendar_month_outlined,
                              size: 18),
                      label: Text(
                        _isBooking
                            ? 'Confirming…'
                            : _selectedDate == null
                                ? 'Select a Date to Confirm'
                                : 'Confirm Booking — ${DateFormat('d MMM').format(_selectedDate!)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.fireRed,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            cs.onSurface.withValues(alpha: 0.12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

      return isDesktop
          ? Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: inner))
          : inner;
    });
  }
}

// ─── Vehicle Header ───────────────────────────────────────────────────────────
class _VehicleHeader extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final ColorScheme cs;
  const _VehicleHeader({required this.vehicle, required this.cs});

  @override
  Widget build(BuildContext context) {
    final make = vehicle['make']?.toString() ?? '';
    final model = vehicle['model']?.toString() ?? '';
    final year = vehicle['year']?.toString() ?? '';
    final plate = vehicle['license_plate']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: AppColors.fireRed.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: const Icon(Icons.directions_car,
              color: AppColors.fireRed, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$make $model',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: cs.onSurface)),
                Text(
                    [if (year.isNotEmpty) year, if (plate.isNotEmpty) plate]
                        .join(' · '),
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
        ),
      ]),
    );
  }
}

// ─── Estimation Summary ───────────────────────────────────────────────────────
class _EstimationSummary extends StatefulWidget {
  final double estimatedCost;
  final Map<String, dynamic>? estimationResult;
  final ColorScheme cs;

  const _EstimationSummary({
    required this.estimatedCost,
    required this.estimationResult,
    required this.cs,
  });

  @override
  State<_EstimationSummary> createState() => _EstimationSummaryState();
}

class _EstimationSummaryState extends State<_EstimationSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final result = widget.estimationResult;
    final panels =
        result?['assessment']?['damaged_panels_detail'] as List? ?? [];
    final severity =
        result?['assessment']?['severity_classification'] as String? ?? '—';
    final model =
        result?['analysis_metadata']?['engine_processed'] as String? ?? '—';
    final fmt = NumberFormat('#,###', 'id_ID');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.fireRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.fireRed.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        // ── Header (always visible) ─────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.fireRed, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI Damage Estimate',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(
                          _expanded
                              ? 'Tap to collapse'
                              : 'Tap to see full breakdown',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Rp ${fmt.format(widget.estimatedCost)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.fireRed)),
                Text('AI estimate',
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant)),
              ]),
              const SizedBox(width: 8),
              Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: cs.onSurfaceVariant),
            ]),
          ),
        ),

        // ── Breakdown (expandable) ──────────────────────────────────────────
        if (_expanded) ...[
          Divider(
              height: 1,
              color: AppColors.fireRed.withValues(alpha: 0.2)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    _Tag('Severity: ${severity.toUpperCase()}',
                        Colors.orange),
                    _Tag('Model: $model', cs.primary),
                    _Tag('${panels.length} panel(s)', Colors.grey),
                  ]),
                  const SizedBox(height: 12),

                  // Panel rows
                  if (panels.isEmpty)
                    Text('No panel detail available.',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant))
                  else
                    ...panels.map((p) {
                      final panel = p as Map<String, dynamic>;
                      final name =
                          panel['panel_name']?.toString() ?? '—';
                      final sev =
                          panel['panel_severity']?.toString() ?? '—';
                      final cost =
                          (panel['calculated_cost'] as num?)
                                  ?.toDouble() ??
                              0;
                      final needsReplace =
                          panel['requires_replacement'] == true;
                      final scratches =
                          panel['scratches_found'] as int? ?? 0;
                      final dents =
                          panel['dents_found'] as int? ?? 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: cs.onSurface)),
                                  const SizedBox(height: 4),
                                  Wrap(spacing: 6, children: [
                                    _Tag(sev.toUpperCase(),
                                        _sevColor(sev)),
                                    if (needsReplace)
                                      _Tag('REPLACE', Colors.red),
                                    if (scratches > 0)
                                      _Tag('$scratches scratch${scratches > 1 ? 'es' : ''}',
                                          Colors.grey),
                                    if (dents > 0)
                                      _Tag('$dents dent${dents > 1 ? 's' : ''}',
                                          Colors.blueGrey),
                                  ]),
                                ]),
                          ),
                          const SizedBox(width: 12),
                          Text('Rp ${fmt.format(cost)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.fireRed)),
                        ]),
                      );
                    }),

                  // Disclaimer
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 14, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'AI estimate only. Final cost is set by the workshop technician '
                              'after physical inspection and issued as an official invoice by Re-V.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade800,
                                  height: 1.4),
                            ),
                          ),
                        ]),
                  ),
                ]),
          ),
        ],
      ]),
    );
  }

  Color _sevColor(String sev) {
    switch (sev.toLowerCase()) {
      case 'ringan': return Colors.green;
      case 'sedang': return Colors.orange;
      case 'berat':  return Colors.red;
      default:       return Colors.grey;
    }
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color)),
    );
  }
}

// ─── Delivery Selector ────────────────────────────────────────────────────────
class _DeliverySelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final ColorScheme cs;

  const _DeliverySelector(
      {required this.selected,
      required this.onChanged,
      required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: _DeliveryOption(
        value: 'self_deliver',
        selected: selected,
        icon: Icons.directions_car_outlined,
        label: 'Self Drop-off',
        subtitle: 'I will bring the vehicle',
        onTap: onChanged,
        cs: cs,
      )),
      const SizedBox(width: 12),
      Expanded(
          child: _DeliveryOption(
        value: 'pickup',
        selected: selected,
        icon: Icons.local_shipping_outlined,
        label: 'Valet Pickup',
        subtitle: 'Driver picks up from me',
        onTap: onChanged,
        cs: cs,
      )),
    ]);
  }
}

class _DeliveryOption extends StatelessWidget {
  final String value, selected, label, subtitle;
  final IconData icon;
  final ValueChanged<String> onTap;
  final ColorScheme cs;

  const _DeliveryOption({
    required this.value,
    required this.selected,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = value == selected;
    return InkWell(
      onTap: () => onTap(value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.fireRed.withValues(alpha: 0.08)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isActive
                  ? AppColors.fireRed
                  : cs.outlineVariant.withValues(alpha: 0.5),
              width: isActive ? 1.5 : 1),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  color: isActive
                      ? AppColors.fireRed
                      : cs.onSurfaceVariant,
                  size: 22),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isActive
                          ? AppColors.fireRed
                          : cs.onSurface)),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant)),
            ]),
      ),
    );
  }
}

// ─── Calendar ─────────────────────────────────────────────────────────────────
class _BookingCalendar extends StatelessWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDaySelected;
  final ColorScheme cs;

  const _BookingCalendar({
    required this.selectedDate,
    required this.onDaySelected,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: TableCalendar(
        firstDay: now.add(const Duration(days: 1)),
        lastDay: now.add(const Duration(days: 60)),
        focusedDay:
            selectedDate ?? now.add(const Duration(days: 1)),
        selectedDayPredicate: (day) =>
            selectedDate != null && isSameDay(day, selectedDate!),
        enabledDayPredicate: (day) =>
            day.weekday != DateTime.sunday,
        onDaySelected: (selected, focused) =>
            onDaySelected(selected),
        calendarStyle: CalendarStyle(
          selectedDecoration: const BoxDecoration(
              color: AppColors.fireRed, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(
              color: AppColors.fireRed.withValues(alpha: 0.2),
              shape: BoxShape.circle),
          disabledTextStyle: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.25)),
          weekendTextStyle:
              TextStyle(color: cs.onSurfaceVariant),
          defaultTextStyle: TextStyle(color: cs.onSurface),
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
              fontSize: 14),
          leftChevronIcon:
              Icon(Icons.chevron_left, color: cs.onSurface),
          rightChevronIcon:
              Icon(Icons.chevron_right, color: cs.onSurface),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.bold),
          weekendStyle: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
