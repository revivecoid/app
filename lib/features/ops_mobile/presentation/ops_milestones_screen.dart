import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final jobMilestonesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, jobId) async {
  final res = await Supabase.instance.client
      .from('job_milestones')
      .select()
      .eq('job_id', jobId)
      .order('created_at', ascending: true);
  return List<Map<String, dynamic>>.from(res);
});

class OpsMilestonesScreen extends ConsumerStatefulWidget {
  final String jobId;
  const OpsMilestonesScreen({super.key, required this.jobId});

  @override
  ConsumerState<OpsMilestonesScreen> createState() => _OpsMilestonesScreenState();
}

class _OpsMilestonesScreenState extends ConsumerState<OpsMilestonesScreen> {
  final List<String> _standardMilestones = [
    'Disassembly',
    'Panel Beating',
    'Putty / Primer',
    'Sanding',
    'Painting',
    'Clear Coat',
    'Polishing',
    'Quality Control',
  ];

  Future<void> _addMilestone(String name) async {
    try {
      await Supabase.instance.client.from('job_milestones').insert({
        'job_id': widget.jobId,
        'milestone_name': name,
        'status': 'completed',
        'completed_by': Supabase.instance.client.auth.currentUser?.id,
        'completed_at': DateTime.now().toIso8601String(),
      });
      ref.invalidate(jobMilestonesProvider(widget.jobId));
    } catch (e) {
      debugPrint('Error adding milestone: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final milestonesAsync = ref.watch(jobMilestonesProvider(widget.jobId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Milestones'),
      ),
      body: milestonesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (milestones) {
          final completedNames = milestones.map((m) => m['milestone_name'] as String).toSet();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _standardMilestones.length,
            itemBuilder: (context, index) {
              final step = _standardMilestones[index];
              final isCompleted = completedNames.contains(step);

              return Card(
                color: isCompleted ? Colors.green.shade50 : null,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isCompleted ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    step,
                    style: TextStyle(
                      fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  trailing: isCompleted
                      ? null
                      : ElevatedButton(
                          onPressed: () => _addMilestone(step),
                          child: const Text('Mark Done'),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
