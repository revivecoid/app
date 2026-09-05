import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';

class ScheduleConfigScreen extends ConsumerStatefulWidget {
  const ScheduleConfigScreen({super.key});

  @override
  ConsumerState<ScheduleConfigScreen> createState() => _ScheduleConfigScreenState();
}

class _ScheduleConfigScreenState extends ConsumerState<ScheduleConfigScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<int> _standardWorkingDays = [1, 2, 3, 4, 5, 6];
  int _simultaneousPanelCapacity = 18;
  int _guaranteedSlotsPerDay = 6;
  bool _fastTrackEnabled = false;
  List<DateTime> _blacklistedDates = [];

  final Map<int, String> _weekdays = {
    1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'
  };

  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _loadScheduleConfig();
  }

  Future<void> _loadScheduleConfig() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final response = await Supabase.instance.client
          .from('partner_schedules')
          .select()
          .eq('partner_id', user.id)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _standardWorkingDays = List<int>.from(response['standard_working_days'] ?? [1,2,3,4,5,6]);
          _simultaneousPanelCapacity = response['simultaneous_panel_capacity'] ?? 18;
          _guaranteedSlotsPerDay = response['guaranteed_slots_per_day'] ?? 6;
          _fastTrackEnabled = response['fast_track_enabled'] ?? false;
          if (response['blacklisted_dates'] != null) {
            _blacklistedDates = (response['blacklisted_dates'] as List)
                .map((d) => DateTime.parse(d.toString()))
                .toList();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading config: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      await Supabase.instance.client
          .from('partner_schedules')
          .upsert({
            'partner_id': user.id,
            'standard_working_days': _standardWorkingDays,
            'simultaneous_panel_capacity': _simultaneousPanelCapacity,
            'guaranteed_slots_per_day': _guaranteedSlotsPerDay,
            'fast_track_enabled': _fastTrackEnabled,
            'blacklisted_dates': _blacklistedDates
                .map((d) => d.toIso8601String().split('T')[0])
                .toList(),
          }, onConflict: 'partner_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule configuration saved.'),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving config: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _isBlacklisted(DateTime date) =>
      _blacklistedDates.any((d) =>
          d.year == date.year && d.month == date.month && d.day == date.day);

  void _toggleDate(DateTime date) {
    setState(() {
      final norm = DateTime(date.year, date.month, date.day);
      if (_isBlacklisted(norm)) {
        _blacklistedDates.removeWhere(
            (d) => d.year == norm.year && d.month == norm.month && d.day == norm.day);
      } else {
        _blacklistedDates.add(norm);
      }
    });
  }

  void _nextMonth() => setState(() =>
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1));
  void _prevMonth() => setState(() =>
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.fireRed));
    }

    final cardBg = isDark ? AppColors.surfaceContainerLow : Colors.white;
    final cardBorder = isDark ? AppColors.outlineVariant : Colors.black12;
    final subtitleColor = isDark ? AppColors.onSurfaceVariant : Colors.black54;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.fireRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.calendar_month, color: AppColors.fireRed, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Workshop Capacity & Operating Calendar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.statusSuccess.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.statusSuccess.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6,
                                decoration: const BoxDecoration(color: AppColors.statusSuccess, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              const Text('ENGINE SYNCED',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.statusSuccess)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configure simultaneous throughput and blackout dates. AI auto-dispatch respects dynamic panel ceilings and partner blackout windows.',
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Three stat cards ────────────────────────────────────────
          LayoutBuilder(builder: (ctx, constraints) {
            final isWide = constraints.maxWidth > 600;
            final cards = [
              _buildCapacityCard(
                isDark: isDark, cardBg: cardBg, cardBorder: cardBorder, subtitleColor: subtitleColor,
                icon: Icons.speed, iconColor: AppColors.fireRed,
                label: 'SIMULTANEOUS INTAKE',
                value: _simultaneousPanelCapacity,
                unit: 'Panels/Day',
                stepperLabel: 'Panel Ceiling',
                onDecrement: () => setState(() { if (_simultaneousPanelCapacity > 1) _simultaneousPanelCapacity--; }),
                onIncrement: () => setState(() => _simultaneousPanelCapacity++),
              ),
              _buildCapacityCard(
                isDark: isDark, cardBg: cardBg, cardBorder: cardBorder, subtitleColor: subtitleColor,
                icon: Icons.verified_user_outlined, iconColor: Colors.orange,
                label: 'INSURER GUARANTEE',
                value: _guaranteedSlotsPerDay,
                unit: 'Slots/Day',
                stepperLabel: 'Panel Ceiling',
                onDecrement: () => setState(() { if (_guaranteedSlotsPerDay > 0) _guaranteedSlotsPerDay--; }),
                onIncrement: () => setState(() => _guaranteedSlotsPerDay++),
              ),
              _buildFastTrackCard(
                isDark: isDark, cardBg: cardBg, cardBorder: cardBorder, subtitleColor: subtitleColor,
                enabled: _fastTrackEnabled,
                onToggle: (v) => setState(() => _fastTrackEnabled = v),
              ),
            ];

            return isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[1]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[2]),
                    ],
                  )
                : Column(children: [
                    cards[0],
                    const SizedBox(height: 12),
                    cards[1],
                    const SizedBox(height: 12),
                    cards[2],
                  ]);
          }),
          const SizedBox(height: 32),

          // ── Working Days Row ────────────────────────────────────────
          Text('Standard Working Days',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                  color: AppColors.fireRed, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: _weekdays.entries.map((entry) {
              final isSelected = _standardWorkingDays.contains(entry.key);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSelected) {
                    _standardWorkingDays.remove(entry.key);
                  } else {
                    _standardWorkingDays.add(entry.key);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.fireRed : (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.fireRed : (isDark ? AppColors.outlineVariant : Colors.black12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        const Icon(Icons.check, color: Colors.white, size: 13),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : (isDark ? AppColors.onSurfaceVariant : Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          // ── Calendar ────────────────────────────────────────────────
          _buildCalendar(isDark: isDark, cardBg: cardBg, cardBorder: cardBorder, subtitleColor: subtitleColor),

          const SizedBox(height: 32),

          // ── Save Button ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.fireRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Schedule Configuration',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityCard({
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color subtitleColor,
    required IconData icon,
    required Color iconColor,
    required String label,
    required int value,
    required String unit,
    required String stepperLabel,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: subtitleColor, letterSpacing: 0.6)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$value',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.fireRed)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(unit,
                    style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (value / (value + 5)).clamp(0.0, 1.0),
            backgroundColor: AppColors.fireRed.withValues(alpha: 0.1),
            color: AppColors.fireRed,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stepperBtn(Icons.remove, onDecrement, isDark),
              Expanded(
                child: Center(
                  child: Text(stepperLabel,
                      style: TextStyle(fontSize: 11, color: subtitleColor)),
                ),
              ),
              _stepperBtn(Icons.add, onIncrement, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFastTrackCard({
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color subtitleColor,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enabled ? AppColors.fireRed.withValues(alpha: 0.4) : cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: AppColors.fireRed, size: 16),
              const SizedBox(width: 6),
              Text('FAST-TRACK MODE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: subtitleColor, letterSpacing: 0.6)),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Express 24h',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.fireRed)),
          const SizedBox(height: 4),
          Text('Priority bypass for minor dent & spot cures.',
              style: TextStyle(fontSize: 11, color: subtitleColor)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: enabled
                      ? AppColors.fireRed.withValues(alpha: 0.1)
                      : (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  enabled ? 'ACTIVE' : 'INACTIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: enabled ? AppColors.fireRed : subtitleColor,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onToggle,
                activeColor: AppColors.fireRed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceContainerLow : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isDark ? AppColors.outlineVariant : Colors.black12),
        ),
        child: Icon(icon, size: 16,
            color: isDark ? AppColors.onSurfaceVariant : Colors.black54),
      ),
    );
  }

  Widget _buildCalendar({
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color subtitleColor,
  }) {
    final daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    // Start on Monday (weekday 1), offset = weekday-1 (Mon=0..Sun=6)
    final firstDayOffset = (_currentMonth.weekday - 1) % 7;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final monthName = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ][_currentMonth.month - 1];

    // Detect if it's a "peak" month (Jun-Aug in this context)
    final isPeakMonth = [6, 7, 8].contains(_currentMonth.month);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Calendar header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: AppColors.fireRed, size: 16),
                const SizedBox(width: 8),
                Text(
                  '$monthName ${_currentMonth.year}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.onSurface : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                if (isPeakMonth)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentWarning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.accentWarning.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Peak Cycle',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentWarning)),
                  ),
                const Spacer(),
                // Legend
                _calLegend(Colors.green, 'Working Day'),
                const SizedBox(width: 12),
                _calLegend(AppColors.fireRed, 'Day Off / Closed'),
                const SizedBox(width: 12),
                _calLegend(Colors.orange, 'National Holiday'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  iconSize: 20,
                  color: isDark ? AppColors.onSurface : Colors.black54,
                  onPressed: _prevMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  iconSize: 20,
                  color: isDark ? AppColors.onSurface : Colors.black54,
                  onPressed: _nextMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cardBorder),

          // Weekday headers (Mon–Sun)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((w) {
                return Expanded(
                  child: Center(
                    child: Text(w,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: (w == 'Sun')
                              ? AppColors.fireRed.withValues(alpha: 0.8)
                              : subtitleColor,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),

          // Calendar grid
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.05,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: daysInMonth + firstDayOffset,
              itemBuilder: (context, index) {
                if (index < firstDayOffset) return const SizedBox.shrink();
                final day = index - firstDayOffset + 1;
                final date = DateTime(_currentMonth.year, _currentMonth.month, day);
                final isToday = date == today;
                final isPast = date.isBefore(today);
                final isBlacklisted = _isBlacklisted(date);
                final isStandardWorkingDay = _standardWorkingDays.contains(date.weekday);
                final isSunday = date.weekday == 7;

                Color bgColor;
                Color textColor;
                Color? dotColor;
                String? statusLabel;

                if (isBlacklisted) {
                  bgColor = AppColors.fireRed.withValues(alpha: 0.12);
                  textColor = AppColors.fireRed;
                  dotColor = AppColors.fireRed;
                  statusLabel = 'OFF';
                } else if (!isStandardWorkingDay) {
                  bgColor = (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100);
                  textColor = isSunday ? AppColors.fireRed.withValues(alpha: 0.5) : subtitleColor;
                  dotColor = null;
                } else {
                  bgColor = Colors.green.withValues(alpha: isDark ? 0.12 : 0.08);
                  textColor = isPast
                      ? (isDark ? Colors.white24 : Colors.black26)
                      : (isDark ? AppColors.onSurface : Colors.black87);
                  dotColor = Colors.green;
                }

                return GestureDetector(
                  onTap: isPast ? null : () => _toggleDate(date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(6),
                      border: isToday
                          ? Border.all(color: AppColors.fireRed, width: 1.5)
                          : (isBlacklisted
                              ? Border.all(color: AppColors.fireRed.withValues(alpha: 0.4))
                              : null),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (dotColor != null)
                              Container(
                                width: 5, height: 5,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                              ),
                            Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                        if (statusLabel != null)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.fireRed,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              statusLabel,
                              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          )
                        else if (isStandardWorkingDay && !isPast && dotColor != null)
                          Text(
                            '${_guaranteedSlotsPerDay}/${_simultaneousPanelCapacity}',
                            style: TextStyle(fontSize: 8, color: subtitleColor),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Tap hint
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Tap any working day to mark as day-off, or tap a red day to restore.',
              style: TextStyle(fontSize: 11, color: subtitleColor),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _calLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
