import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final logisticsJobsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
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
      .select('id, status, customer_id, profiles!repair_jobs_customer_id_fkey(full_name, phone, address), vehicles(make, model, license_plate)')
      .eq('partner_id', partnerId)
      .inFilter('status', ['4_paid', '8_awaiting_delivery'])
      .order('created_at', ascending: true);
      
  return List<Map<String, dynamic>>.from(res);
});

class OpsLogisticsScreen extends ConsumerWidget {
  const OpsLogisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final jobsAsync = ref.watch(logisticsJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logistics & Valet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                  Icon(Icons.local_shipping_outlined, size: 64, color: cs.primary),
                  const SizedBox(height: 16),
                  const Text('No vehicles waiting for pickup or delivery.', style: TextStyle(fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              final isPickup = job['status'] == '4_paid';
              final customer = job['profiles'];
              final vehicle = job['vehicles'];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    context.push('/ops/logistics/intake/${job['id']}');
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        color: isPickup ? Colors.blue.shade100 : Colors.green.shade100,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Icon(isPickup ? Icons.arrow_upward : Icons.arrow_downward, 
                              color: isPickup ? Colors.blue.shade900 : Colors.green.shade900, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              isPickup ? 'NEEDS PICKUP' : 'NEEDS DELIVERY',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isPickup ? Colors.blue.shade900 : Colors.green.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${vehicle?['make']} ${vehicle?['model']} - ${vehicle?['license_plate']}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(customer?['full_name'] ?? 'Unknown'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(child: Text(customer?['address'] ?? 'No address provided')),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  context.push('/ops/logistics/intake/${job['id']}');
                                },
                                icon: Icon(isPickup ? Icons.camera_alt : Icons.check_circle),
                                label: Text(isPickup ? 'Start Pickup Intake' : 'Complete Delivery'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFd10721),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
