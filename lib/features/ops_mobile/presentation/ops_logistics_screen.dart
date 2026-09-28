import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/session_health.dart';
import '../../../core/widgets/customer_contact_line.dart';
import '../ops_access.dart';

final logisticsJobsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  // Read partner_id from appMetadata directly (SEC-02)
  final partnerId = user.appMetadata['partner_id'] as String?;
  if (partnerId == null || partnerId.isEmpty) return [];

  final mode = await ref.watch(opsViewModeProvider.future);

  // retryOnStaleToken: a future-dated token makes these reads fail with
  // PGRST303; refreshing once recovers without the operator seeing an error.
  final res = await retryOnStaleToken(Supabase.instance.client, () async {
    return Supabase.instance.client
        .from('repair_jobs')
        .select('id, status, delivery_type, customer_id, contact_phone, profiles!repair_jobs_customer_id_fkey(full_name, phone, email), vehicles(make, model, license_plate)')
        .eq('partner_id', partnerId)
        .inFilter('status', ['3_booked', '8_awaiting_delivery'])
        .order('created_at', ascending: true);
  });
      
  final rawJobs = List<Map<String, dynamic>>.from(res);
  return rawJobs.where((job) {
    // Under all_access AND view_all_act_own, logistics also lists self-delivery
    // jobs that are booked, so the valet team can see every job the workshop has
    // (8_awaiting_delivery always shows either way). The two modes are both "see
    // everything"; they differ only in what may be completed.
    if (mode != OpsViewMode.originalRole) return true;
    // original_role: only 3_booked jobs that require a valet pickup.
    if (job['status'] == '3_booked' && job['delivery_type'] != 'pickup') return false;
    return true;
  }).toList();
});

class OpsLogisticsScreen extends ConsumerWidget {
  const OpsLogisticsScreen({super.key});

  /// Opens the correct stage screen based on job status and refreshes on return.
  Future<void> _openStage(
    BuildContext context,
    WidgetRef ref,
    String jobId,
    String customerId,
    String status,
  ) async {
    // C-11 fix: route by status, not hardcoded to intake
    if (status == '8_awaiting_delivery') {
      await context.push('/ops/floor/milestones/$jobId');
    } else {
      // 3_booked → pickup intake
      await context.push('/ops/logistics/intake/$jobId/$customerId');
    }
    if (context.mounted) ref.invalidate(logisticsJobsProvider);
  }

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
              // C-11 fix: isPickup = 3_booked (needs intake), not 4_paid
              final isPickup = job['status'] == '3_booked';
              final isDelivery = job['status'] == '8_awaiting_delivery';
              final customer = job['profiles'];
              final vehicle = job['vehicles'];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    final customerId = job['customer_id']?.toString() ?? '';
                    _openStage(context, ref, job['id'].toString(), customerId, job['status']?.toString() ?? '');
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
                            CustomerContactLine(
                              jobContactPhone: job['contact_phone']?.toString(),
                              profilePhone: customer?['phone']?.toString(),
                              profileEmail: customer?['email']?.toString(),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final customerId = job['customer_id']?.toString() ?? '';
                                  _openStage(context, ref, job['id'].toString(), customerId, job['status']?.toString() ?? '');
                                },
                                icon: Icon(isPickup ? Icons.camera_alt : Icons.check_circle),
                                label: Text(isPickup ? 'Start Pickup Intake' : isDelivery ? 'Complete Delivery' : 'Open'),
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
