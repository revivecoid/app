

/// A pure Dart calculation utility for the event-driven slot-booking engine.
class SchedulingEngine {
  /// Calculates the total labor hours based on selected panels and the partner's duration matrix.
  /// 
  /// [selectedPanels] is a list of panel names selected by the user.
  /// [partnerDurationMatrix] is a map of panel_name to repair_duration_hours.
  static double calculateTotalLaborHours({
    required List<String> selectedPanels,
    required Map<String, double> partnerDurationMatrix,
  }) {
    double totalHours = 0.0;
    for (final panel in selectedPanels) {
      // Default to 2.0 hours if a panel is somehow missing from the matrix
      totalHours += partnerDurationMatrix[panel] ?? 2.0;
    }
    return totalHours;
  }

  /// Calculates the total days allocated for a repair job.
  /// 
  /// [totalLaborHours] The sum of base repair durations.
  /// [simultaneousPanelCapacity] The number of panels the workshop can fix concurrently.
  static int calculateTotalDaysAllocated({
    required double totalLaborHours,
    required int simultaneousPanelCapacity,
  }) {
    if (simultaneousPanelCapacity <= 0) {
      simultaneousPanelCapacity = 1; // Prevent division by zero
    }
    
    // Total Days Allocated = Ceiling of (Total Labor Hours / (8 working hours * simultaneous_panel_capacity))
    final double effectiveDailyHours = 8.0 * simultaneousPanelCapacity;
    return (totalLaborHours / effectiveDailyHours).ceil();
  }

  /// Calculates the sequential list of valid working dates skipping holidays and off-days.
  static List<DateTime> calculateWorkingDaysSequence({
    required DateTime startDate,
    required int requiredDays,
    required List<int> standardWorkingDays,
    required List<DateTime> allHolidays,
  }) {
    List<DateTime> sequence = [];
    DateTime currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    
    while (sequence.length < requiredDays) {
      bool isValid = true;
      
      // Check standard working days (1=Mon, 7=Sun)
      if (!standardWorkingDays.contains(currentDate.weekday)) {
        isValid = false;
      } else {
        // Check holidays
        for (final holiday in allHolidays) {
          if (currentDate.year == holiday.year && 
              currentDate.month == holiday.month && 
              currentDate.day == holiday.day) {
            isValid = false;
            break;
          }
        }
      }
      
      if (isValid) {
        sequence.add(currentDate);
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }
    return sequence;
  }

  /// Verifies if a continuous multi-day slot block is valid against daily quotas.
  /// 
  /// [targetDate] The requested start date.
  /// [requiredDays] How many operational days the job requires.
  /// [standardWorkingDays] List of integers 1-7 where 1=Monday.
  /// [blacklistedDates] List of explicitly closed dates and automated holidays.
  /// [guaranteedSlotsPerDay] The maximum allowed booked jobs per day.
  /// [allocatedSlotsCount] A map of existing booking counts per date.
  static bool isSlotAvailable({
    required DateTime targetDate,
    required int requiredDays,
    required List<int> standardWorkingDays,
    required List<DateTime> blacklistedDates,
    required int guaranteedSlotsPerDay,
    required Map<DateTime, int> allocatedSlotsCount,
  }) {
    final sequence = calculateWorkingDaysSequence(
      startDate: targetDate,
      requiredDays: requiredDays,
      standardWorkingDays: standardWorkingDays,
      allHolidays: blacklistedDates,
    );
    
    // Validate that NONE of the days in the calculated sequence exceed the quota
    for (final day in sequence) {
      final count = allocatedSlotsCount[day] ?? 0;
      if (count >= guaranteedSlotsPerDay) {
        return false;
      }
    }

    return true;
  }

  /// Generates a timeline status including parts triage check.
  static Map<String, dynamic> generateBookingStatus({
    required bool requiresPartsSubstitution,
  }) {
    return {
      'status': requiresPartsSubstitution ? 'awaiting_parts_triage' : 'ready_for_scheduling',
      'requiresParts': requiresPartsSubstitution,
    };
  }
}
