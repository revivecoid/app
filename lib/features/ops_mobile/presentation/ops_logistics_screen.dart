import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/session_health.dart';
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
        .select('id, status, delivery_type, customer_id, profiles!repair_jobs_customer_id_fkey(full_name, phone, email), vehicles(make, model, license_plate)')
        .eq('partner_id', partnerId)
        .inFilter('status', ['3_booked', '8_awaiting_delivery'])
        .order('created_at', ascending: true);
  });
      
  final rawJobs = List<Map<String, dynamic>>.from(res);
  return rawJobs.where((job) {
    // In all_access logistics also lists self-delivery jobs that are booked, so
    // the valet team can pick up a job the customer switched to pickup-style
    // collection. 8_awaiting_delivery always shows either way.
    if (mode == OpsViewMode.allAccess) return true;
    // original_role: only 3_booked jobs that require a valet pickup.
    if (job['status'] == '3_booked' && job['delivery_type'] != 'pickup') return false;
    return true;
  }).toList();
});

class OpsLogisticsScreen extends ConsumerWidget {
  const OpsLogisticsScreen({super.key});

  /// Opens a stage screen and refreshes this list when it returns.
  ///
  /// The stage screen pops `true` after a successful submit, but this list stays
  /// alive underneath the pushed route — so without awaiting that result its
  /// autoDispose provider never refetches and the completed job stays on screen,
  /// looking exactly like the work was never saved.
  Future<void> _openStage(
    BuildContext context,
    WidgetRef ref,
    String jobId,
    String customerId,
  ) async {
    await context.push('/ops/logistics/intake/$jobId/$customerId');
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
              final isPickup = job['status'] == '4_paid';
              final customer = job['profiles'];
              final vehicle = job['vehicles'];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    final customerId = job['customer_id']?.toString() ?? '';
                    _openStage(context, ref, job['id'].toString(), customerId);
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
                            _ContactRow(
                              phone: customer?['phone']?.toString(),
                              email: customer?['email']?.toString(),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final customerId = job['customer_id']?.toString() ?? '';
                                  _openStage(context, ref, job['id'].toString(), customerId);
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

// ─── Customer contact ─────────────────────────────────────────────────────────

/// The customer's contact detail for the valet.
///
/// `profiles.phone` is optional and currently unset on most accounts, so falling
/// back to email is what keeps this row actionable — otherwise the operator is
/// shown "No phone provided" and has no way to reach anyone. When neither is on
/// file it says so plainly instead of implying the customer has no contact
/// details at all.
///
/// Takes plain strings rather than the embedded row so the card list never has to
/// cast a `dynamic` payload, which would throw while building the list.
class _ContactRow extends StatelessWidget {
  final String? phone;
  final String? email;

  const _ContactRow({this.phone, this.email});

  @override
  Widget build(BuildContext context) {
    final phoneValue = (phone ?? '').trim();
    final emailValue = (email ?? '').trim();
    final contact = phoneValue.isNotEmpty ? phoneValue : emailValue;
    final isPhone = phoneValue.isNotEmpty;

    if (contact.isEmpty) {
      return Row(
        children: [
          Icon(Icons.contact_phone_outlined, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No phone or email on file',
              style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(
          isPhone ? Icons.phone_outlined : Icons.email_outlined,
          size: 16,
          color: Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(contact)),
      ],
    );
  }
}
