import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../providers/booking_scheduling_controller.dart';

class BookingSchedulingScreen extends ConsumerWidget {
  final String jobId;

  const BookingSchedulingScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookingSchedulingControllerProvider);
    final controller = ref.read(bookingSchedulingControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: const ReVAppBar(title: Text('Schedule Repair')),
      body: SafeArea(
        child: state.isLoading && state.workshops.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select Workshop', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
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
                          leading: const Icon(Icons.build_circle, size: 40, color: AppColors.sleekBlack),
                          title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${w.address}\n⭐ ${w.rating} • ${w.distanceKm} km away'),
                          trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.fireRed) : null,
                          isThreeLine: true,
                        ),
                      );
                    }).toList(),

                    if (state.selectedWorkshop != null) ...[
                      const SizedBox(height: 32),
                      Text('Select Date', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
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
                                  color: isSelected ? AppColors.fireRed : (isDark ? AppColors.sleekBlack : Colors.white),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isSelected ? AppColors.fireRed : AppColors.daysGray.withValues(alpha: 0.2)),
                                  boxShadow: [
                                    if (isSelected) BoxShadow(color: AppColors.fireRed.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
                                  ]
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _getWeekday(date.weekday),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isWeekend ? AppColors.daysGray : (isSelected ? Colors.white : AppColors.daysGray),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isWeekend ? AppColors.daysGray : (isSelected ? Colors.white : (isDark ? Colors.white : Colors.black)),
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
                        const SizedBox(height: 32),
                        Text('Select Time Slot', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
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
                                color: isSelected ? AppColors.fireRed : (isDark ? Colors.white : Colors.black),
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
                    const SizedBox(height: 100), // padding for bottom bar
                  ],
                ),
              ),
      ),
      bottomNavigationBar: state.selectedSlot != null 
        ? Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1c1b1c) : Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -5))],
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
              child: const Text('Proceed to Checkout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          )
        : null,
    );
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
