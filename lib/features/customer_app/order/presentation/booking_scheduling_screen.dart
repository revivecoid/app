import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../providers/booking_scheduling_controller.dart';

class BookingSchedulingScreen extends ConsumerWidget {
  final String jobId;

  BookingSchedulingScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookingSchedulingControllerProvider);
    final controller = ref.read(bookingSchedulingControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      Widget inner = Scaffold(
      appBar: ReVAppBar(title: Text('Schedule Repair')),
      body: SafeArea(
        child: state.isLoading && state.workshops.isEmpty
            ? Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select Workshop', style: Theme.of(context).textTheme.titleLarge),
                    SizedBox(height: 16),
                    ...state.workshops.map((w) {
                      final isSelected = state.selectedWorkshop?.id == w.id;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: isSelected ? AppColors.fireRed : Colors.transparent, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          onTap: () => controller.selectWorkshop(w),
                          leading: Icon(Icons.build_circle, size: 40, color: AppColors.sleekBlack),
                          title: Text(w.name, style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${w.address}\n⭐ ${w.rating} • ${w.distanceKm} km away'),
                          trailing: isSelected ? Icon(Icons.check_circle, color: AppColors.fireRed) : null,
                          isThreeLine: true,
                        ),
                      );
                    }).toList(),

                    if (state.selectedWorkshop != null) ...[
                      SizedBox(height: 32),
                      Text('Select Date', style: Theme.of(context).textTheme.titleLarge),
                      SizedBox(height: 16),
                      SizedBox(
                        height: 90,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: 14,
                          itemBuilder: (context, index) {
                            final date = DateTime.now().add(Duration(days: index + 1)); // start tomorrow
                            final isSelected = state.selectedDate?.day == date.day && state.selectedDate?.month == date.month;
                            final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
                            
                            return GestureDetector(
                              onTap: isWeekend ? null : () => controller.selectDate(date),
                              child: Container(
                                width: 70,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.fireRed : (isDark ? AppColors.sleekBlack : Theme.of(context).colorScheme.surface),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isSelected ? AppColors.fireRed : AppColors.daysGray.withValues(alpha: 0.2)),
                                  boxShadow: [
                                    if (isSelected) BoxShadow(color: AppColors.fireRed.withValues(alpha: 0.3), blurRadius: 8, offset: Offset(0, 4))
                                  ]
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _getWeekday(date.weekday),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isWeekend ? AppColors.daysGray : (isSelected ? Theme.of(context).colorScheme.surface : AppColors.daysGray),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isWeekend ? AppColors.daysGray : (isSelected ? Theme.of(context).colorScheme.surface : (isDark ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.onSurface)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      if (state.selectedDate != null) ...[
                        SizedBox(height: 32),
                        Text('Select Time Slot', style: Theme.of(context).textTheme.titleLarge),
                        SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: state.availableSlots.map((slot) {
                            final isSelected = state.selectedSlot == slot;
                            return ChoiceChip(
                              label: Text(slot),
                              selected: isSelected,
                              selectedColor: AppColors.fireRed.withValues(alpha: 0.1),
                              labelStyle: TextStyle(
                                color: isSelected ? AppColors.fireRed : (isDark ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.onSurface),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              side: BorderSide(color: isSelected ? AppColors.fireRed : AppColors.daysGray.withValues(alpha: 0.3)),
                              onSelected: (selected) {
                                if (selected) controller.selectSlot(slot);
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                    SizedBox(height: 100), // padding for bottom bar
                  ],
                ),
              ),
      ),
      bottomNavigationBar: state.selectedSlot != null 
        ? Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF1c1b1c) : Theme.of(context).colorScheme.surface,
              boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1), blurRadius: 10, offset: Offset(0, -5))],
            ),
            child: ElevatedButton(
              onPressed: () {
                final dummyJobId = 'JB-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
                context.push('/checkout/$dummyJobId?partnerId=${state.selectedWorkshop!.id}');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.fireRed,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Proceed to Checkout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.surface)),
            ),
          )
        : null,
    );
      return isDesktop ? Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 800), child: inner)) : inner;
    });
  }

  String _getWeekday(int weekday) {
    switch (weekday) {
      case 1: return 'MON';
      case 2: return 'TUE';
      case 3: return 'WED';
      case 4: return 'THU';
      case 5: return 'FRI';
      case 6: return 'SAT';
      case 7: return 'SUN';
      default: return '';
    }
  }
}
