import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final floorJobsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];
  
  final profile = await Supabase.instance.client
      .from('profiles')
      .select('partner_id')
      .eq('id', user.id)
      .single();
      
  final partnerId = profile['partner_id'];
  if (partnerId == null) return [];

  final res = await Supabase.instance.client
      .from('repair_jobs')
      .select('id, status, vehicles(make, model, license_plate)')
      .eq('partner_id', partnerId)
      .eq('status', '6_in_progress')
      .order('created_at', ascending: true);
      
  return List<Map<String, dynamic>>.from(res);
});

class OpsFloorScreen extends ConsumerWidget {
  const OpsFloorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final jobsAsync = ref.watch(floorJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workshop Floor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: jobsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (jobs) {
          if (jobs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.build_circle_outlined, size: 64, color: cs.primary),
                  const SizedBox(height: 16),
                  const Text('No active floor jobs yet.', style: TextStyle(fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              final vehicle = job['vehicles'];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child: Icon(Icons.directions_car, color: Colors.orange.shade900),
                  ),
                  title: Text('${vehicle?['make']} ${vehicle?['model']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(vehicle?['license_plate'] ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/ops/floor/milestones/${job['id']}');
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
