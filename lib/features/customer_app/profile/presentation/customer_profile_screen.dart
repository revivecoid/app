import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../notifications/application/notifications_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../core/widgets/app_settings_sheet.dart';
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

/// Fetches the current user's row from the profiles table.
/// Used to show DB-saved name/phone and to pre-populate the edit form.
final customerProfileDataProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  return await Supabase.instance.client
      .from('profiles')
      .select('full_name, email, phone')
      .eq('id', user.id)
      .maybeSingle();
});

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

  void _showSettingsPanel(BuildContext context, WidgetRef ref) =>
      AppSettingsSheet.show(context);

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

    // Resolve display name: DB profiles.full_name first, then Google metadata
    final profileAsync = ref.watch(customerProfileDataProvider);
    final dbProfile = profileAsync.whenOrNull(data: (d) => d);
    final dbName = dbProfile?['full_name']?.toString().trim() ?? '';
    final googleName = user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString() ?? '';
    final userName = dbName.isNotEmpty ? dbName : googleName;

    final userEmail = user?.email ?? '';
    final userAvatar = user?.userMetadata?['avatar_url']?.toString();
    final initials = _initials(userName.isNotEmpty ? userName : userEmail);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                          context, ref, userName, userEmail, userAvatar, initials,
                          phone: dbProfile?['phone']?.toString() ?? ''),
                      SizedBox(height: 16), if (user?.appMetadata?['role'] == 'partner_staff' || user?.appMetadata?['role'] == 'partner_driver' || user?.userMetadata?['role'] == 'partner_staff' || user?.userMetadata?['role'] == 'partner_driver' || user?.appMetadata?['role'] == 'partner_mechanic' || user?.userMetadata?['role'] == 'partner_mechanic') Padding(padding: const EdgeInsets.only(bottom: 16), child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), ), onPressed: () => GoRouter.of(context).go('/ops'), icon: const Icon(Icons.rocket_launch), label: const Text('Open Workshop Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), ), ),

                      // ── Digital Garage ────────────────────────────────────
                      _buildGarageHeader(context, ref),
                      SizedBox(height: 12),
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
                              Center(
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
                      SizedBox(height: 24),

                      // ── Job History ───────────────────────────────────────
                      _buildHistoryHeader(context, ref),
                      SizedBox(height: 12),
                      ...ref.watch(customerJobsProvider).when(
                            data: (jobs) {
                              if (jobs.isEmpty) {
                                return [
                                  _buildInfoCard(context, 
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
                              Center(
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
                      SizedBox(height: 24),

                      // ── Account & Telemetry ───────────────────────────────
                      Text(AppL.of(context)!.profileAccountTelemetry,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface)),
                      SizedBox(height: 12),
                      _buildAccountTiles(context, ref),
                      SizedBox(height: 24),

                      // ── Logout ────────────────────────────────────────────
                      _buildLogout(context),
                      SizedBox(height: 32),
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
  //  Edit Profile Sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _showEditProfileSheet(
    BuildContext context,
    WidgetRef ref,
    String currentName,
    String currentPhone,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        initialName: currentName,
        initialPhone: currentPhone,
        onSaved: () => ref.invalidate(customerProfileDataProvider),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = Supabase.instance.client.auth.currentUser;
    // Consistent name resolution: DB first, then Google metadata
    final dbProfile = ref.watch(customerProfileDataProvider).whenOrNull(data: (d) => d);
    final dbName = dbProfile?['full_name']?.toString().trim() ?? '';
    final googleName = user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString() ?? '';
    final userName = dbName.isNotEmpty ? dbName : googleName;
    final userEmail = user?.email ?? '';
    final userAvatar = user?.userMetadata?['avatar_url']?.toString();
    final initials = _initials(userName.isNotEmpty ? userName : userEmail);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
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
                SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('re-V',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            color: Theme.of(context).colorScheme.onSurface)),
                    SizedBox(height: 2),
                    Text('GARAGE PROFILE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      icon: Icon(Icons.notifications_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              // Theme toggle
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      AppSettingsSheet.show(context);
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
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface),
                        ),
                        Text(
                          userEmail,
                          style: TextStyle(
                              fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        Divider(height: 16),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(children: [
                      Icon(Icons.person_outline,
                          size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(width: 10),
                      Text(AppL.of(context)!.profileTitle),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(children: [
                      Icon(Icons.settings_outlined,
                          size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(width: 10),
                      Text(AppL.of(context)!.settings),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(children: [
                      Icon(Icons.logout,
                          size: 18, color: AppColors.primaryContainer),
                      SizedBox(width: 10),
                      Text(AppL.of(context)!.logout,
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
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.surface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ))
                      : Center(
                          child: Text(initials,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.surface,
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
    WidgetRef ref,
    String userName,
    String userEmail,
    String? userAvatar,
    String initials, {
    String phone = '',
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                                          style: TextStyle(
                                              color: Theme.of(context).colorScheme.surface,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18),
                                        ),
                                      ),
                                    )
                                  : Text(initials,
                                      style: TextStyle(
                                          color: Theme.of(context).colorScheme.surface,
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
                                  Border.all(color: Theme.of(context).colorScheme.surface, width: 1),
                            ),
                            child: Icon(Icons.workspace_premium,
                                color: Theme.of(context).colorScheme.surface, size: 10),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: 12),
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
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified,
                                        color: AppColors.primaryContainer,
                                        size: 12),
                                    SizedBox(width: 4),
                                    Text(AppL.of(context)!.profileMember,
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.onSurface)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 2),
                          Text(
                            userEmail.isNotEmpty ? userEmail : '—',
                            style: TextStyle(
                                fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Image.asset('assets/images/google_logo.png',
                                  width: 14,
                                  height: 14,
                                  errorBuilder: (_, __, ___) => Icon(
                                      Icons.account_circle,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              SizedBox(width: 4),
                              Text(AppL.of(context)!.profileSignedInGoogle,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Edit button — opens real profile edit sheet
                    IconButton(
                      icon: Icon(Icons.edit_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                      tooltip: 'Edit Profile',
                      onPressed: () => _showEditProfileSheet(context, ref, userName, phone),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                // Membership perks strip
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
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
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppL.of(context)!.profileReviveMember,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: Theme.of(context).colorScheme.onSurface)),
                            Text(AppL.of(context)!.profileMemberPerks,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

  Widget _buildGarageHeader(BuildContext context, WidgetRef ref) {
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
            SizedBox(width: 6),
            Text(AppL.of(context)!.profileGarageTitle,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count ${count == 1 ? 'Vehicle' : 'Vehicles'}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        color: Theme.of(context).colorScheme.surface,
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
              size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          SizedBox(height: 12),
          Text(AppL.of(context)!.profileGarageEmpty,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          SizedBox(height: 4),
          Text(AppL.of(context)!.profileGarageEmptyDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
        color: Theme.of(context).colorScheme.surface,
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
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(type.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  letterSpacing: 0.5)),
                        ),
                        if (hasActiveJob) ...[
                          SizedBox(width: 6),
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
                                SizedBox(width: 4),
                                Text(statusLabel,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryContainer)),
                              ],
                            ),
                          ),
                        ] else if (year.isNotEmpty) ...[
                          SizedBox(width: 6),
                          Text('$year Model',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      title.isNotEmpty ? title : 'Unknown Vehicle',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 4),
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
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(subtitle,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface)),
                          ),
                        if (color.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(context).colorScheme.onSurface),
                              ),
                              SizedBox(width: 4),
                              Text(color,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  size: 32,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
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
                    SizedBox(width: 8),
                    Text(
                      hasActiveJob
                          ? 'Active Repair · $statusLabel'
                          : 'No Active Jobs',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: hasActiveJob
                              ? AppColors.primaryContainer
                              : Theme.of(context).colorScheme.onSurface),
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
          SizedBox(height: 12),
          // CTA — Track if in repair, Book if idle
          SizedBox(
            width: double.infinity,
            child: hasActiveJob
                ? ElevatedButton.icon(
                    onPressed: () =>
                        context.push('/track/$activeJobId'),
                    icon: Icon(Icons.fmd_good_outlined, size: 16),
                    label: Text(AppL.of(context)!.profileTrackLive,
                        style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.surface,
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
                    label: Text(AppL.of(context)!.profileBookService,
                            style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
          color: Theme.of(context).colorScheme.surface,
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
            SizedBox(width: 10),
            Text(AppL.of(context)!.profileRegisterVehicle,
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
            SizedBox(width: 6),
            Text(AppL.of(context)!.profileJobHistory,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
        if (count > 0)
          GestureDetector(
            onTap: () {
              // TODO: navigate to full job history screen
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(AppL.of(context)!.profileHistoryComing),
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
        color: Theme.of(context).colorScheme.surface,
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
                            style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface)),
                        SizedBox(width: 6),
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
                    SizedBox(height: 4),
                    Text(
                        jobTitle.isNotEmpty
                            ? jobTitle
                            : 'Service Job',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface)),
                    if (estimatedServices.isNotEmpty)
                      Text(estimatedServices,
                          style: TextStyle(
                              fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    if (partnerName.isNotEmpty)
                      Text(partnerName,
                          style: TextStyle(
                              fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                        style: TextStyle(
                            fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/track/${job['id']}'),
                  icon: Icon(Icons.fmd_good_outlined, size: 15),
                  label: Text(AppL.of(context)!.profileTrackOrder,
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              SizedBox(width: 8),
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
                  icon: Icon(Icons.verified_outlined, size: 15),
                  label: Text('Guarantee',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
        color: Theme.of(context).colorScheme.surface,
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
                            style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface)),
                        SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(AppL.of(context)!.profileCompleted,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green)),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                        jobTitle.isNotEmpty
                            ? jobTitle
                            : 'Service Job',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface)),
                    Text(
                      dateStr.isNotEmpty
                          ? 'Completed $dateStr   •   24-Mo Guarantee Active'
                          : '24-Mo Guarantee Active',
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
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
                          color: Theme.of(context).colorScheme.onSurface)),
                  Text(payMethod,
                      style: TextStyle(
                          fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          SizedBox(height: 12),
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
                  icon: Icon(Icons.receipt_long_outlined, size: 15),
                  label: Text('Tax Receipt',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              SizedBox(width: 8),
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
                  icon: Icon(Icons.verified_outlined, size: 15),
                  label: Text('Guarantee',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
    // ignore: unused_local_variable
    final alertsOn = ref.watch(whatsappAlertsProvider);
    final user = Supabase.instance.client.auth.currentUser;
    final role = (user?.appMetadata['role'] as String?)
        ?? (user?.userMetadata?['role'] as String?)
        ?? 'customer';
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
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
          // ── Role-specific portal shortcut ────────────────────────────
          if (role == 'master_admin') ...[
            _tile(context,
              icon: Icons.admin_panel_settings_outlined,
              iconColor: AppColors.fireRed,
              title: 'Admin Panel',
              subtitle: 'Open the Revive Ops Core management console',
              onTap: () => context.go('/admin-central'),
            ),
            _divider(),
          ] else if (role == 'partner_mechanic') ...[
            _tile(context,
              icon: Icons.storefront_outlined,
              iconColor: AppColors.primaryContainer,
              title: 'Partner Dashboard',
              subtitle: 'Manage your workshop, jobs & schedule',
              onTap: () => context.go('/partner-dashboard'),
            ),
            _divider(),
          ],
          _tile(context,
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
          _tile(context,
            icon: Icons.credit_card,
            iconColor: cs.onSurface,
            title: 'Payment Methods',
            subtitle: 'Add cards, e-wallets, or bank accounts',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Payment methods coming soon'),
                  behavior: SnackBarBehavior.floating),
            ),
          ),
          _divider(),
          _tile(context,
            icon: Icons.notifications_active_outlined,
            iconColor: AppColors.fireRed,
            title: 'Pengaturan Notifikasi',
            subtitle: 'In-app, Email & WhatsApp booking updates',
            onTap: () => context.push('/notification-settings'),
          ),
          _divider(),
          _tile(context,
            icon: Icons.help_center,
            iconColor: cs.onSurface,
            title: 'Workshop Concierge & FAQ',
            subtitle: '24/7 paint warranty & towing hotlines',
            onTap: () => context.push('/support'),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, {
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
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
            label: Text(AppL.of(context)!.profileLogOut,
                style: TextStyle(
                    color: AppColors.primaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 1,
            ),
          ),
        ),
        SizedBox(height: 12),
        Text(AppL.of(context)!.profileTelemetryVersion,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
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
          Icon(Icons.error_outline,
              color: AppColors.fireRed, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 13, color: AppColors.fireRed)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
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
                SnackBar(
                  content:
                      Text(AppL.of(context)!.profileSelectJob),
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
        isActive ? AppColors.primaryContainer : Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTapOverride ??
            (route != null ? () => context.go(route) : null),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 24),
            SizedBox(height: 2),
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



// _____________________________________________________________________________
//  Edit Profile Sheet
// _____________________________________________________________________________

class _EditProfileSheet extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final VoidCallback onSaved;

  const _EditProfileSheet({
    required this.initialName,
    required this.initialPhone,
    required this.onSaved,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.initialName);
    _phoneCtrl = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Full name cannot be empty.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      await Supabase.instance.client.from('profiles').upsert({
        'id':        user.id,
        'full_name': name,
        'phone':     _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'email':     user.email ?? '',
        'role':      (user.appMetadata['role'] as String?) ?? 'customer',
      });
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Profile updated successfully'),
          ]),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Save failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.person_outline, color: AppColors.primaryContainer, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
          ]),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              labelText: 'Full Name',
              hintText: 'Enter your full name',
              prefixIcon: Icon(Icons.badge_outlined, color: cs.onSurfaceVariant, size: 20),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primaryContainer, width: 2)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              labelText: 'Phone Number',
              hintText: '+62 8xx xxxx xxxx (optional)',
              prefixIcon: Icon(Icons.phone_outlined, color: cs.onSurfaceVariant, size: 20),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primaryContainer, width: 2)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

