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

  Future<void> _fetchWorkshops() async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(milliseconds: 800)); // Simulate network
    
    final dummyWorkshops = [
      WorkshopNode(
        id: 'ws_1',
        name: 'Revive HQ Workshop',
        address: 'Jl. Sudirman No. 12, Jakarta',
        distanceKm: 2.4,
        rating: 4.8,
      ),
      WorkshopNode(
        id: 'ws_2',
        name: 'Auto Fix Elite',
        address: 'Jl. Gatot Subroto No. 45, Jakarta',
        distanceKm: 4.1,
        rating: 4.5,
      ),
      WorkshopNode(
        id: 'ws_3',
        name: 'Bengkel Cepat Pratama',
        address: 'Jl. Rasuna Said No. 9, Jakarta',
        distanceKm: 5.8,
        rating: 4.2,
      ),
    ];

    state = state.copyWith(
      isLoading: false,
      workshops: dummyWorkshops,
    );
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
