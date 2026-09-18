import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final floorJobsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  // Read partner_id from appMetadata directly (SEC-02, avoids extra RLS hop)
  final partnerId = user.appMetadata['partner_id'] as String?;
  if (partnerId == null || partnerId.isEmpty) return [];

  // Do NOT join profiles here — staff RLS now allows reading customer profiles
  // via the "Partners can read customer profiles for their jobs" policy,
  // but we keep the query minimal and join only vehicles to reduce RLS surface.
  final res = await Supabase.instance.client
      .from('repair_jobs')
      .select('id, status, customer_id, vehicles(make, model, license_plate)')
      .eq('partner_id', partnerId)
      .inFilter('status', ['5_admitted', '6_in_progress', '7_finished'])
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
                  const Text('No active jobs in bay.', style: TextStyle(fontSize: 16)),
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
              final status = job['status'] as String? ?? '';
              final statusLabel = status.replaceAll(RegExp(r'^\d+_'), '').replaceAll('_', ' ').toUpperCase();
              final statusColor = status == '5_admitted'
                  ? Colors.blue.shade700
                  : status == '7_finished'
                      ? Colors.green.shade700
                      : Colors.orange.shade700;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child: Icon(Icons.directions_car, color: Colors.orange.shade900),
                  ),
                  title: Text('${vehicle?['make']} ${vehicle?['model']}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vehicle?['license_plate'] ?? ''),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(statusLabel,
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                      ),
                    ],
                  ),
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
