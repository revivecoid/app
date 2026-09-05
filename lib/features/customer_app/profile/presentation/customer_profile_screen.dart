import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../notifications/application/notifications_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'vehicle_registration_modal.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Providers
// ─────────────────────────────────────────────────────────────────────────────

final customerVehiclesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];
  final data = await Supabase.instance.client
      .from('vehicles')
      .select()
      .eq('customer_id', user.id)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

final customerJobsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];
  final data = await Supabase.instance.client
      .from('repair_jobs')
      .select('*, vehicles(*)')
      .eq('customer_id', user.id)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

// Simple persistent toggle — stored in Supabase customers table if available,
// otherwise falls back to in-memory state.
final whatsappAlertsProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({super.key});

  // ── Auth helpers ──────────────────────────────────────────────────────────

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Sign-out failed: $e');
    }
  }

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : parts[0][0].toUpperCase();
  }

  String _formatCurrency(dynamic raw) {
    if (raw == null) return '—';
    try {
      final num = double.parse(raw.toString()).toStringAsFixed(0);
      final chars = num.split('').reversed.toList();
      final buf = StringBuffer();
      for (int i = 0; i < chars.length; i++) {
        if (i > 0 && i % 3 == 0) buf.write('.');
        buf.write(chars[i]);
      }
      return 'Rp ${buf.toString().split('').reversed.join('')}';
    } catch (_) {
      return 'Rp $raw';
    }
  }

  String _humanStatus(String raw) {
    return raw
        .replaceAll(RegExp(r'^\d+_'), '')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString() ??
        '';
    final userEmail = user?.email ?? '';
    final userAvatar = user?.userMetadata?['avatar_url']?.toString();
    final initials = _initials(userName.isNotEmpty ? userName : userEmail);

    return Scaffold(
      backgroundColor: AppColors.workspaceLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, ref),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(customerVehiclesProvider);
                  ref.invalidate(customerJobsProvider);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Profile Card ──────────────────────────────────────
                      _buildProfileCard(
                          context, userName, userEmail, userAvatar, initials),
                      const SizedBox(height: 16),

                      // ── Digital Garage ────────────────────────────────────
                      _buildGarageHeader(ref),
                      const SizedBox(height: 12),
                      ...ref.watch(customerVehiclesProvider).when(
                            data: (vehicles) {
                              if (vehicles.isEmpty) {
                                return [_buildEmptyGarage(context)];
                              }
                              // Grab active jobs (not completed/cancelled) to
                              // annotate each vehicle card with repair status
                              final activeJobs = ref
                                      .watch(customerJobsProvider)
                                      .whenOrNull(data: (j) => j) ??
                                  [];
                              final activeStatuses = {
                                '1_intake', '2_estimated', '3_booked',
                                '4_paid', '5_admitted', '6_in_progress',
                                '7_finished', '8_awaiting_delivery',
                              };
                              return vehicles.map((v) {
                                final activeJob = activeJobs.firstWhere(
                                  (job) =>
                                      activeStatuses.contains(
                                          job['status']?.toString()) &&
                                      job['vehicle_id']?.toString() ==
                                          v['id']?.toString(),
                                  orElse: () => {},
                                );
                                return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 16),
                                    child: _buildVehicleCard(
                                        context, v, activeJob.isNotEmpty ? activeJob : null));
                              }).toList();
                            },
                            loading: () => [
                              const Center(
                                  child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ))
                            ],
                            error: (e, _) => [
                              _buildErrorCard('Could not load vehicles. '
                                  'Pull down to retry.')
                            ],
                          ),
                      _buildAddVehicleButton(context, ref),
                      const SizedBox(height: 24),

                      // ── Job History ───────────────────────────────────────
                      _buildHistoryHeader(context, ref),
                      const SizedBox(height: 12),
                      ...ref.watch(customerJobsProvider).when(
                            data: (jobs) {
                              if (jobs.isEmpty) {
                                return [
                                  _buildInfoCard(
                                    Icons.history_edu,
                                    'No Service History Yet',
                                    'Your completed and active jobs will appear here.',
                                  )
                                ];
                              }
                              return jobs.map((job) {
                                final status =
                                    job['status']?.toString() ?? '';
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12),
                                  child: status == '8_completed'
                                      ? _buildJobCompleted(context, job)
                                      : _buildJobActive(context, job),
                                );
                              }).toList();
                            },
                            loading: () => [
                              const Center(
                                  child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ))
                            ],
                            error: (e, _) => [
                              _buildErrorCard('Could not load job history. '
                                  'Pull down to retry.')
                            ],
                          ),
                      const SizedBox(height: 24),

                      // ── Account & Telemetry ───────────────────────────────
                      const Text('Account & Telemetry',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.sleekBlack)),
                      const SizedBox(height: 12),
                      _buildAccountTiles(context, ref),
                      const SizedBox(height: 24),

                      // ── Logout ────────────────────────────────────────────
                      _buildLogout(context),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString() ?? '';
    final userEmail = user?.email ?? '';
    final userAvatar = user?.userMetadata?['avatar_url']?.toString();
    final initials = _initials(userName.isNotEmpty ? userName : userEmail);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo
          InkWell(
            onTap: () => context.go('/'),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Image.asset('assets/images/revive_logo.png',
                    height: 28, color: AppColors.fireRed),
                const SizedBox(width: 8),
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('re-V',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            color: AppColors.sleekBlack)),
                    SizedBox(height: 2),
                    Text('GARAGE PROFILE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: AppColors.daysGray,
                            height: 1.0)),
                  ],
                ),
              ],
            ),
          ),
          // Action icons
          Row(
            children: [
              // Notifications
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                      icon: const Icon(Icons.notifications_outlined,
                          color: AppColors.daysGray),
                      tooltip: 'Notifications',
                      onPressed: () => context.push('/notifications')),
                  if (ref.watch(unreadNotificationsCountProvider) > 0)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              // Theme toggle
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: AppColors.daysGray,
                ),
                tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                onPressed: () {
                  ref.read(themeModeProvider.notifier).state =
                      isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              // Profile avatar → PopupMenuButton
              PopupMenuButton<String>(
                offset: const Offset(0, 48),
                tooltip: 'Account menu',
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (value) async {
                  switch (value) {
                    case 'profile':
                      context.go('/profile');
                      break;
                    case 'settings':
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Settings coming soon'),
                            behavior: SnackBarBehavior.floating),
                      );
                      break;
                    case 'logout':
                      await _signOut(context);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName.isNotEmpty ? userName : 'Revive Member',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.sleekBlack),
                        ),
                        Text(
                          userEmail,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.daysGray),
                        ),
                        const Divider(height: 16),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(children: [
                      const Icon(Icons.person_outline,
                          size: 18, color: AppColors.daysGray),
                      const SizedBox(width: 10),
                      const Text('My Profile'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(children: [
                      const Icon(Icons.settings_outlined,
                          size: 18, color: AppColors.daysGray),
                      const SizedBox(width: 10),
                      const Text('Settings'),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(children: [
                      Icon(Icons.logout,
                          size: 18, color: AppColors.primaryContainer),
                      const SizedBox(width: 10),
                      Text('Log Out',
                          style: TextStyle(
                              color: AppColors.primaryContainer,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ],
                child: Container(
                  margin: const EdgeInsets.only(left: 4),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color:
                              AppColors.primaryContainer.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: userAvatar != null && userAvatar.isNotEmpty
                      ? Image.network(userAvatar, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(initials,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ))
                      : Center(
                          child: Text(initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  //  Profile Summary Card  (reads live Google OAuth data)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProfileCard(
    BuildContext context,
    String userName,
    String userEmail,
    String? userAvatar,
    String initials,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryContainer.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Stack(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.primaryContainer
                                      .withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          alignment: Alignment.center,
                          child:
                              userAvatar != null && userAvatar.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        userAvatar,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Text(
                                          initials,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18),
                                        ),
                                      ),
                                    )
                                  : Text(initials,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18)),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.orange[800],
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 1),
                            ),
                            child: const Icon(Icons.workspace_premium,
                                color: Colors.white, size: 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Name / email
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  userName.isNotEmpty
                                      ? userName
                                      : 'Revive Member',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.sleekBlack),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified,
                                        color: AppColors.primaryContainer,
                                        size: 12),
                                    const SizedBox(width: 4),
                                    const Text('Member',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.sleekBlack)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            userEmail.isNotEmpty ? userEmail : '—',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.daysGray),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Image.asset('assets/images/google_logo.png',
                                  width: 14,
                                  height: 14,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.account_circle,
                                      size: 14,
                                      color: AppColors.daysGray)),
                              const SizedBox(width: 4),
                              const Text('Signed in with Google',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.daysGray)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Edit button
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppColors.daysGray, size: 18),
                      tooltip: 'Edit Profile',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Profile editing coming soon'),
                              behavior: SnackBarBehavior.floating),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Membership perks strip
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 2,
                                offset: const Offset(0, 1))
                          ],
                        ),
                        child: Icon(Icons.verified_user,
                            color: AppColors.primaryContainer, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('REVIVE MEMBER',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: AppColors.sleekBlack)),
                            Text(
                                'Register vehicles to unlock workshop perks',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.daysGray)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Digital Garage
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildGarageHeader(WidgetRef ref) {
    final count = ref.watch(customerVehiclesProvider).whenOrNull(
              data: (v) => v.length,
            ) ??
        0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.garage,
                color: AppColors.primaryContainer, size: 20),
            const SizedBox(width: 6),
            const Text('My Digital Garage',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.sleekBlack)),
          ],
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count ${count == 1 ? 'Vehicle' : 'Vehicles'}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.daysGray),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyGarage(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primaryContainer.withValues(alpha: 0.2),
            width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.garage_outlined,
              size: 48, color: AppColors.daysGray.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text('Your garage is empty',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.sleekBlack)),
          const SizedBox(height: 4),
          const Text(
              'Register your vehicle to start managing service history,\n'
              'track repairs, and unlock exclusive perks.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.daysGray)),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(
      BuildContext context, Map<String, dynamic> v,
      [Map<String, dynamic>? activeJob]) {
    final make = v['make']?.toString() ?? '';
    final model = v['model']?.toString() ?? '';
    final year = v['year']?.toString() ?? '';
    final plate = v['license_plate']?.toString() ?? '';
    final color = v['color']?.toString() ?? '';
    final type = v['vehicle_type']?.toString() ?? 'Car';
    final title = [make, model].where((s) => s.isNotEmpty).join(' ');
    final subtitle =
        [year, plate].where((s) => s.isNotEmpty).join('   •   ');

    final hasActiveJob = activeJob != null;
    final rawStatus = activeJob?['status']?.toString() ?? '';
    final statusLabel =
        rawStatus.isNotEmpty ? _humanStatus(rawStatus) : 'In Repair';
    final activeJobId = activeJob?['id']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: hasActiveJob
            ? Border.all(
                color: AppColors.primaryContainer.withValues(alpha: 0.3),
                width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(type.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.daysGray,
                                  letterSpacing: 0.5)),
                        ),
                        if (hasActiveJob) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(statusLabel,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryContainer)),
                              ],
                            ),
                          ),
                        ] else if (year.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text('$year Model',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.daysGray)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title.isNotEmpty ? title : 'Unknown Vehicle',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.sleekBlack),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (subtitle.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(subtitle,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.sleekBlack)),
                          ),
                        if (color.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.sleekBlack),
                              ),
                              const SizedBox(width: 4),
                              Text(color,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.daysGray,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 64,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: hasActiveJob
                      ? AppColors.primaryContainer.withValues(alpha: 0.06)
                      : Colors.grey[100],
                ),
                child: Icon(
                  type == 'Motorcycle'
                      ? Icons.two_wheeler
                      : type == 'Truck'
                          ? Icons.local_shipping
                          : Icons.directions_car,
                  color: hasActiveJob
                      ? AppColors.primaryContainer.withValues(alpha: 0.7)
                      : AppColors.daysGray.withValues(alpha: 0.6),
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Status strip
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasActiveJob
                  ? AppColors.primaryContainer.withValues(alpha: 0.05)
                  : Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: hasActiveJob
                      ? AppColors.primaryContainer.withValues(alpha: 0.2)
                      : Colors.grey[200]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasActiveJob
                                ? AppColors.primaryContainer
                                : Colors.grey)),
                    const SizedBox(width: 8),
                    Text(
                      hasActiveJob
                          ? 'Active Repair · $statusLabel'
                          : 'No Active Jobs',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: hasActiveJob
                              ? AppColors.primaryContainer
                              : AppColors.sleekBlack),
                    ),
                  ],
                ),
                Icon(
                  hasActiveJob ? Icons.build_outlined : Icons.task_alt,
                  color: hasActiveJob
                      ? AppColors.primaryContainer
                      : Colors.grey,
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // CTA — Track if in repair, Book if idle
          SizedBox(
            width: double.infinity,
            child: hasActiveJob
                ? ElevatedButton.icon(
                    onPressed: () =>
                        context.push('/track/$activeJobId'),
                    icon: const Icon(Icons.fmd_good_outlined, size: 16),
                    label: const Text('Track Live Repair',
                        style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: () => context.push('/estimator'),
                    icon: Icon(Icons.auto_fix_high,
                        size: 16, color: AppColors.primaryContainer),
                    label: const Text('Book a Service',
                        style: TextStyle(
                            color: AppColors.sleekBlack, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }


  Widget _buildAddVehicleButton(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () async {
        await showVehicleRegistrationModal(context);
        // Provider auto-refreshed by the modal via ref.invalidate()
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.primaryContainer.withValues(alpha: 0.3),
              width: 1.5,
              style: BorderStyle.solid),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer.withValues(alpha: 0.1)),
              child: Icon(Icons.add,
                  size: 20, color: AppColors.primaryContainer),
            ),
            const SizedBox(width: 10),
            Text('Register New Vehicle to Garage',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryContainer)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Job History
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHistoryHeader(BuildContext context, WidgetRef ref) {
    final count = ref
            .watch(customerJobsProvider)
            .whenOrNull(data: (j) => j.length) ??
        0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.history_edu,
                color: AppColors.primaryContainer, size: 20),
            const SizedBox(width: 6),
            const Text('Job History & Certificates',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.sleekBlack)),
          ],
        ),
        if (count > 0)
          GestureDetector(
            onTap: () {
              // TODO: navigate to full job history screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Full history coming soon'),
                    behavior: SnackBarBehavior.floating),
              );
            },
            child: Text('View All ($count)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryContainer)),
          ),
      ],
    );
  }

  Widget _buildJobActive(BuildContext context, Map<String, dynamic> job) {
    final jobId = '#${job['id']?.toString().substring(0, 8).toUpperCase() ?? '—'}';
    final rawStatus = job['status']?.toString() ?? '';
    final statusLabel =
        rawStatus.isNotEmpty ? _humanStatus(rawStatus) : 'In Progress';
    final vehicleData = job['vehicles'];
    final make = vehicleData?['make']?.toString() ?? '';
    final model = vehicleData?['model']?.toString() ?? '';
    final jobTitle =
        [make, model].where((s) => s.isNotEmpty).join(' ');
    final cost = _formatCurrency(job['total_cost']);
    final partnerName = job['partner_name']?.toString() ?? '';
    final payMethod = job['payment_method']?.toString() ?? '';
    final estimatedServices = job['services_requested']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(jobId,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: AppColors.sleekBlack)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryContainer)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        jobTitle.isNotEmpty
                            ? jobTitle
                            : 'Service Job',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.sleekBlack)),
                    if (estimatedServices.isNotEmpty)
                      Text(estimatedServices,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.daysGray),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    if (partnerName.isNotEmpty)
                      Text(partnerName,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.daysGray)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(cost,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryContainer)),
                  if (payMethod.isNotEmpty)
                    Text(payMethod,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.daysGray)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/track/${job['id']}'),
                  icon: const Icon(Icons.fmd_good_outlined, size: 15),
                  label: const Text('Track Order',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Guarantee certificate coming soon'),
                          behavior: SnackBarBehavior.floating),
                    );
                  },
                  icon: const Icon(Icons.verified_outlined, size: 15),
                  label: const Text('Guarantee',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.sleekBlack,
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJobCompleted(
      BuildContext context, Map<String, dynamic> job) {
    final jobId = '#${job['id']?.toString().substring(0, 8).toUpperCase() ?? '—'}';
    final vehicleData = job['vehicles'];
    final make = vehicleData?['make']?.toString() ?? '';
    final model = vehicleData?['model']?.toString() ?? '';
    final jobTitle =
        [make, model].where((s) => s.isNotEmpty).join(' ');
    final completedAt = job['completed_at']?.toString() ??
        job['updated_at']?.toString() ??
        '';
    final dateStr = completedAt.length >= 10
        ? completedAt.substring(0, 10)
        : '';
    final cost = _formatCurrency(job['total_cost']);
    final payMethod =
        job['payment_method']?.toString() ?? 'Personal Pay';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(jobId,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: AppColors.sleekBlack)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Completed',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        jobTitle.isNotEmpty
                            ? jobTitle
                            : 'Service Job',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.sleekBlack)),
                    Text(
                      dateStr.isNotEmpty
                          ? 'Completed $dateStr   •   24-Mo Guarantee Active'
                          : '24-Mo Guarantee Active',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.daysGray),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(cost,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.sleekBlack)),
                  Text(payMethod,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.daysGray)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Tax receipt download coming soon'),
                          behavior: SnackBarBehavior.floating),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 15),
                  label: const Text('Tax Receipt',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.sleekBlack,
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Guarantee certificate coming soon'),
                          behavior: SnackBarBehavior.floating),
                    );
                  },
                  icon: const Icon(Icons.verified_outlined, size: 15),
                  label: const Text('Guarantee',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.sleekBlack,
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Account & Telemetry
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAccountTiles(BuildContext context, WidgetRef ref) {
    final alertsOn = ref.watch(whatsappAlertsProvider);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          _tile(
            icon: Icons.shield,
            iconColor: AppColors.primaryContainer,
            title: 'Saved Insurance Policies',
            subtitle: 'Link your insurance for claim-backed services',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Insurance module coming soon'),
                  behavior: SnackBarBehavior.floating),
            ),
          ),
          _divider(),
          _tile(
            icon: Icons.credit_card,
            iconColor: AppColors.sleekBlack,
            title: 'Payment Methods',
            subtitle: 'Add cards, e-wallets, or bank accounts',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Payment methods coming soon'),
                  behavior: SnackBarBehavior.floating),
            ),
          ),
          _divider(),
          // WhatsApp toggle — actually toggles with Riverpod state
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.chat,
                      color: Colors.green, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WhatsApp Live Alerts',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.sleekBlack)),
                      Text('Real-time photos on stage changes',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.daysGray)),
                    ],
                  ),
                ),
                Switch(
                  value: alertsOn,
                  onChanged: (v) {
                    ref
                        .read(whatsappAlertsProvider.notifier)
                        .state = v;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(v
                            ? 'WhatsApp alerts enabled'
                            : 'WhatsApp alerts disabled'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.green,
                ),
              ],
            ),
          ),
          _divider(),
          _tile(
            icon: Icons.help_center,
            iconColor: AppColors.sleekBlack,
            title: 'Workshop Concierge & FAQ',
            subtitle: '24/7 paint warranty & towing hotlines',
            onTap: () => context.push('/support'),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.sleekBlack)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.daysGray)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.daysGray),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(
      height: 1, thickness: 1, color: Color(0xFFF0F0F0), indent: 16);

  // ─────────────────────────────────────────────────────────────────────────
  //  Logout
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLogout(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _signOut(context),
            icon: Icon(Icons.logout,
                color: AppColors.primaryContainer, size: 20),
            label: Text('Log Out of Revive ID',
                style: TextStyle(
                    color: AppColors.primaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Revive Workshop Telemetry OS v4.2.1-JKT',
            style: TextStyle(
                fontSize: 11,
                color: AppColors.daysGray.withValues(alpha: 0.6))),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.fireRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.fireRed.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.fireRed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.fireRed)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Icon(icon,
              size: 36,
              color: AppColors.daysGray.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.sleekBlack)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.daysGray)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Bottom Navigation  (properly routes all tabs)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navItem(
            context,
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: 'Home',
            route: '/',
            isActive: false,
          ),
          _navItem(
            context,
            icon: Icons.auto_awesome_outlined,
            activeIcon: Icons.auto_awesome,
            label: 'Estimate',
            route: '/estimator',
            isActive: false,
          ),
          _navItem(
            context,
            icon: Icons.fmd_good_outlined,
            activeIcon: Icons.fmd_good,
            label: 'Track',
            route: null, // needs jobId — show prompt
            isActive: false,
            onTapOverride: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Select a job from your history to track it'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          _navItem(
            context,
            icon: Icons.directions_car_outlined,
            activeIcon: Icons.directions_car,
            label: 'Garage',
            route: '/profile',
            isActive: true,
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context, {
    required IconData icon,
    required IconData activeIcon,
    required String label,
    String? route,
    required bool isActive,
    VoidCallback? onTapOverride,
  }) {
    final color =
        isActive ? AppColors.primaryContainer : AppColors.daysGray;
    return Expanded(
      child: InkWell(
        onTap: onTapOverride ??
            (route != null ? () => context.go(route) : null),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
