import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ops_access.dart';

class OpsSettingsScreen extends ConsumerWidget {
  const OpsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final mode = ref.watch(opsViewModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          CircleAvatar(
            radius: 40,
            child: Icon(Icons.person, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            user?.email ?? 'Unknown User',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Role: ${user?.appMetadata['role'] ?? 'partner_staff'}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 32),

          // ── Workshop access mode (read-only) ────────────────────────────────
          // Set by the workshop owner in the partner dashboard; shown here so an
          // operator understands why they can or cannot see every job.
          mode.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (value) {
              final allAccess = value == OpsViewMode.allAccess;
              return Card(
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            allAccess ? Icons.visibility_outlined : Icons.badge_outlined,
                            size: 18,
                            color: allAccess ? Colors.green.shade700 : Colors.orange.shade800,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Workshop Access Mode',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        allAccess
                            ? 'Full access — you can see every job in this workshop and '
                              'complete any repair stage, whichever role you hold.'
                            : 'Role-based — you see the jobs and stages for your own role only. '
                              'Your workshop owner controls this.',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Only the workshop owner can change this.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          ElevatedButton.icon(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade100,
              foregroundColor: Colors.red.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
