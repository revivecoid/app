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
  List<int> _standardWorkingDays = [1, 2, 3, 4, 5, 6];
  int _simultaneousPanelCapacity = 1;
  int _guaranteedSlotsPerDay = 2;
  List<DateTime> _blacklistedDates = [];
  
  final Map<int, String> _weekdays = {
    1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'
  };

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
          _simultaneousPanelCapacity = response['simultaneous_panel_capacity'] ?? 1;
          _guaranteedSlotsPerDay = response['guaranteed_slots_per_day'] ?? 2;
          
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
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final payload = {
        'partner_id': user.id,
        'standard_working_days': _standardWorkingDays,
        'simultaneous_panel_capacity': _simultaneousPanelCapacity,
        'guaranteed_slots_per_day': _guaranteedSlotsPerDay,
        'blacklisted_dates': _blacklistedDates.map((d) => d.toIso8601String().split('T')[0]).toList(),
      };

      await Supabase.instance.client
          .from('partner_schedules')
          .upsert(payload, onConflict: 'partner_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule configuration saved successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving config: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Workshop Schedule Configuration',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Note: Automated Indonesian Public Holidays are synchronized at the database level and applied globally.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 32),
          
          // Working Days
          Text('Standard Working Days', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.fireRed)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8.0,
            children: _weekdays.entries.map((entry) {
              final isSelected = _standardWorkingDays.contains(entry.key);
              return FilterChip(
                label: Text(entry.value),
                selected: isSelected,
                selectedColor: AppColors.fireRed,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _standardWorkingDays.add(entry.key);
                    } else {
                      _standardWorkingDays.remove(entry.key);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          // Capacities
          Text('Capacity Thresholds', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.fireRed)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStepperCard(
                  title: 'Simultaneous Panels',
                  subtitle: 'How many panels can you fix at the same time?',
                  value: _simultaneousPanelCapacity,
                  onIncrement: () => setState(() => _simultaneousPanelCapacity++),
                  onDecrement: () => setState(() {
                    if (_simultaneousPanelCapacity > 1) _simultaneousPanelCapacity--;
                  }),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStepperCard(
                  title: 'Guaranteed Daily Slots',
                  subtitle: 'Reserved unit intake quota per day.',
                  value: _guaranteedSlotsPerDay,
                  onIncrement: () => setState(() => _guaranteedSlotsPerDay++),
                  onDecrement: () => setState(() {
                    if (_guaranteedSlotsPerDay > 0) _guaranteedSlotsPerDay--;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Interactive Calendar
          Text('Calendar & Exceptions', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.fireRed)),
          const SizedBox(height: 8),
          const Text('Tap any working day below to mark it as a day off, or tap a red day off to restore it to a working day.', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          _InteractiveMonthCalendar(
            standardWorkingDays: _standardWorkingDays,
            blacklistedDates: _blacklistedDates,
            onToggleDate: (date) {
              setState(() {
                final normalized = DateTime(date.year, date.month, date.day);
                final exists = _blacklistedDates.any((d) => d.year == normalized.year && d.month == normalized.month && d.day == normalized.day);
                if (exists) {
                  _blacklistedDates.removeWhere((d) => d.year == normalized.year && d.month == normalized.month && d.day == normalized.day);
                } else {
                  _blacklistedDates.add(normalized);
                }
              });
            },
          ),

          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saveConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.fireRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Schedule Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperCard({
    required String title,
    required String subtitle,
    required int value,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onDecrement,
                icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
              ),
              Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.fireRed)),
              IconButton(
                onPressed: onIncrement,
                icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InteractiveMonthCalendar extends StatefulWidget {
  final List<int> standardWorkingDays;
  final List<DateTime> blacklistedDates;
  final Function(DateTime) onToggleDate;

  const _InteractiveMonthCalendar({
    required this.standardWorkingDays,
    required this.blacklistedDates,
    required this.onToggleDate,
  });

  @override
  State<_InteractiveMonthCalendar> createState() => _InteractiveMonthCalendarState();
}

class _InteractiveMonthCalendarState extends State<_InteractiveMonthCalendar> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  void _nextMonth() => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1));
  void _prevMonth() => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1));

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    final firstDayOffset = _currentMonth.weekday % 7; // Sunday = 0
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white), onPressed: _prevMonth),
              Text(
                '${_getMonthName(_currentMonth.month)} ${_currentMonth.year}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white), onPressed: _nextMonth),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((w) => Text(w, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))).toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.2,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: daysInMonth + firstDayOffset,
            itemBuilder: (context, index) {
              if (index < firstDayOffset) return const SizedBox.shrink();
              final day = index - firstDayOffset + 1;
              final date = DateTime(_currentMonth.year, _currentMonth.month, day);
              
              // 1 = Mon, 7 = Sun. Convert to match _standardWorkingDays (1-7 scale usually)
              final isStandardWorkingDay = widget.standardWorkingDays.contains(date.weekday);
              final isBlacklisted = widget.blacklistedDates.any((d) => d.year == date.year && d.month == date.month && d.day == date.day);
              final isPast = date.isBefore(today);

              Color bgColor = Colors.transparent;
              Color textColor = Colors.white;
              
              if (isPast) {
                textColor = Colors.white24;
              } else if (isBlacklisted) {
                bgColor = AppColors.fireRed.withValues(alpha: 0.2);
                textColor = AppColors.fireRed;
              } else if (!isStandardWorkingDay) {
                bgColor = Colors.white10;
                textColor = Colors.white54;
              } else {
                bgColor = Colors.green.withValues(alpha: 0.2);
                textColor = Colors.green;
              }

              return InkWell(
                onTap: isPast ? null : () => widget.onToggleDate(date),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: isBlacklisted ? Border.all(color: AppColors.fireRed) : null,
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.square, color: Colors.green, size: 12), SizedBox(width: 4), Text('Working Day', style: TextStyle(color: Colors.white70, fontSize: 12)),
              SizedBox(width: 16),
              Icon(Icons.square, color: AppColors.fireRed, size: 12), SizedBox(width: 4), Text('Day Off', style: TextStyle(color: Colors.white70, fontSize: 12)),
              SizedBox(width: 16),
              Icon(Icons.square, color: Colors.grey, size: 12), SizedBox(width: 4), Text('Standard Weekend', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          )
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
