import io
import re

# 1. Update booking_scheduling_controller.dart
path_controller = 'lib/features/customer_app/order/providers/booking_scheduling_controller.dart'
with io.open(path_controller, 'r', encoding='utf-8') as f:
    text_controller = f.read()

# Add supabase import if not there
if "import 'package:supabase_flutter/supabase_flutter.dart';" not in text_controller:
    text_controller = text_controller.replace(
        "import 'package:flutter_riverpod/flutter_riverpod.dart';",
        "import 'package:flutter_riverpod/flutter_riverpod.dart';\nimport 'package:supabase_flutter/supabase_flutter.dart';"
    )

old_init = """  BookingSchedulingController() : super(BookingSchedulingState()) {
    _loadWorkshops();
  }

  Future<void> _loadWorkshops() async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(seconds: 1)); // Simulate network

    final mockWorkshops = [
      WorkshopNode(
        id: 'W-01',
        name: 'Kebon Jeruk Central Bay',
        address: 'Jl. Raya Kebon Jeruk No. 27',
        distanceKm: 2.4,
        rating: 4.8,
      ),
      WorkshopNode(
        id: 'W-02',
        name: 'Auto Shine Puri',
        address: 'Kembangan, Puri Indah',
        distanceKm: 5.1,
        rating: 4.6,
      ),
      WorkshopNode(
        id: 'W-03',
        name: 'Jakarta Selatan Premium Auto',
        address: 'Pondok Indah Arteri',
        distanceKm: 8.9,
        rating: 4.9,
      ),
    ];

    state = state.copyWith(
      isLoading: false,
      workshops: mockWorkshops,
      selectedWorkshop: mockWorkshops.first,
    );
  }"""

new_init = """  BookingSchedulingController() : super(BookingSchedulingState()) {
    _loadWorkshops();
  }

  Future<void> _loadWorkshops() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await Supabase.instance.client.from('partners').select().eq('status', 'active');
      final workshops = (res as List).map((p) => WorkshopNode(
        id: p['id'].toString(),
        name: p['business_name']?.toString() ?? 'Unknown Workshop',
        address: p['address']?.toString() ?? '',
        distanceKm: 2.4, // Mock distance
        rating: 4.8, // Mock rating
      )).toList();

      state = state.copyWith(
        isLoading: false,
        workshops: workshops,
        selectedWorkshop: workshops.isNotEmpty ? workshops.first : null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> assignWorkshopAndDate(String jobId) async {
    if (state.selectedWorkshop == null) return;
    try {
      await Supabase.instance.client.from('repair_jobs').update({
        'partner_id': state.selectedWorkshop!.id,
      }).eq('id', jobId);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }"""

text_controller = text_controller.replace(old_init, new_init)

with io.open(path_controller, 'w', encoding='utf-8') as f:
    f.write(text_controller)

# 2. Update job_stream_controller.dart
path_job_stream = 'lib/features/customer_app/tracking/presentation/job_stream_controller.dart'
with io.open(path_job_stream, 'r', encoding='utf-8') as f:
    text_job_stream = f.read()

old_bypass = """    // --- DEMO MOCK BYPASS ---
    // If the job ID is a mock ID starting with JB-, simulate a live job
    if (_jobId.startsWith('JB-')) {
      _startMockSimulation();
      return;
    }"""

text_job_stream = text_job_stream.replace(old_bypass, "    // Mock bypass removed for production")

with io.open(path_job_stream, 'w', encoding='utf-8') as f:
    f.write(text_job_stream)
