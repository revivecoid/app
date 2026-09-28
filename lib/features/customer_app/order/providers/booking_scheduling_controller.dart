// [FUTURE FEATURE] Customer Workshop Selection
// This provider, model, and controller are preserved for when the customer-facing
// workshop picker (BookingSchedulingScreen) is re-enabled. Do not delete.
// See: booking_scheduling_screen.dart (commented-out _BookingSchedulingScreenLive)
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkshopNode {
  final String id;
  final String name;
  final String address;
  final double distanceKm;
  final double rating;

  WorkshopNode({
    required this.id,
    required this.name,
    required this.address,
    required this.distanceKm,
    required this.rating,
  });
}

class BookingSchedulingState {
  final bool isLoading;
  final String? errorMessage;
  final List<WorkshopNode> workshops;
  final WorkshopNode? selectedWorkshop;
  final DateTime? selectedDate;
  final List<String> availableSlots;
  final String? selectedSlot;

  BookingSchedulingState({
    this.isLoading = false,
    this.errorMessage,
    this.workshops = const [],
    this.selectedWorkshop,
    this.selectedDate,
    this.availableSlots = const [],
    this.selectedSlot,
  });

  BookingSchedulingState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<WorkshopNode>? workshops,
    WorkshopNode? selectedWorkshop,
    DateTime? selectedDate,
    List<String>? availableSlots,
    String? selectedSlot,
  }) {
    return BookingSchedulingState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      workshops: workshops ?? this.workshops,
      selectedWorkshop: selectedWorkshop ?? this.selectedWorkshop,
      selectedDate: selectedDate ?? this.selectedDate,
      availableSlots: availableSlots ?? this.availableSlots,
      selectedSlot: selectedSlot ?? this.selectedSlot,
    );
  }
}

class BookingSchedulingController extends StateNotifier<BookingSchedulingState> {
  BookingSchedulingController() : super(BookingSchedulingState()) {
    _fetchWorkshops();
  }

  // BIZ-12 fix: dummy workshops removed from production bundle
  // This screen/controller is not connected to any route or real data source.
  // Replace _fetchWorkshops with a real Supabase query when the feature is built.
  Future<void> _fetchWorkshops() async {
    state = state.copyWith(isLoading: false, workshops: []);
    // TODO: query public.partners when booking-by-workshop feature is implemented
  }

  void selectWorkshop(WorkshopNode workshop) {
    state = state.copyWith(selectedWorkshop: workshop, selectedDate: null, selectedSlot: null, availableSlots: []);
  }

  void selectDate(DateTime date) {
    // Generate dummy slots for the date
    final slots = ['09:00 AM', '11:00 AM', '01:00 PM', '03:00 PM'];
    // Randomly remove a slot to simulate booked
    if (date.day % 2 == 0) {
      slots.removeAt(1);
    }
    state = state.copyWith(selectedDate: date, availableSlots: slots, selectedSlot: null);
  }

  void selectSlot(String slot) {
    state = state.copyWith(selectedSlot: slot);
  }
}

final bookingSchedulingControllerProvider = StateNotifierProvider.autoDispose<BookingSchedulingController, BookingSchedulingState>((ref) {
  return BookingSchedulingController();
});
