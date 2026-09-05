import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for the Job Status Notifier
final jobStatusProvider = StateNotifierProvider<JobStatusNotifier, AsyncValue<String?>>((ref) {
  return JobStatusNotifier(Supabase.instance.client);
});

/// Strict StateNotifier managing the 9-stage business model sequence.
class JobStatusNotifier extends StateNotifier<AsyncValue<String?>> {
  final SupabaseClient _supabase;

  JobStatusNotifier(this._supabase) : super(const AsyncValue.data(null));

  // The locked 9-stage sequence dictated by the system design specification
  static const List<String> _validStages = [
    '1_intake',
    '2_estimated',
    '3_booked',
    '4_paid',
    '5_admitted',
    '6_in_progress',
    '7_finished',
    '8_awaiting_delivery',
    '9_done'
  ];

  /// Loads the current status for a specific repair job
  Future<void> fetchCurrentStatus(String jobId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _supabase
          .from('repair_jobs')
          .select('status')
          .eq('id', jobId)
          .single();
          
      state = AsyncValue.data(response['status'] as String);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Advances the status to the next logical step in the sequence.
  /// Enforces sequential movement using strict validation and optimistic locking on the DB.
  Future<void> advanceStatus(String jobId, String currentStatus) async {
    final currentIndex = _validStages.indexOf(currentStatus);
    
    if (currentIndex == -1 || currentIndex >= _validStages.length - 1) {
      state = AsyncValue.error(
        Exception("Cannot advance from terminal or invalid state: $currentStatus"), 
        StackTrace.current
      );
      return;
    }

    final nextStatus = _validStages[currentIndex + 1];
    state = const AsyncValue.loading();

    try {
      // Execute explicit row update with constraint
      final response = await _supabase
          .from('repair_jobs')
          .update({'status': nextStatus})
          .eq('id', jobId)
          .eq('status', currentStatus) // Optimistic locking constraint
          .select();

      if (response.isEmpty) {
         throw Exception("Database update rejected. Status may have been modified by another process.");
      }

      state = AsyncValue.data(nextStatus);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}
