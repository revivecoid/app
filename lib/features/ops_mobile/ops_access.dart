import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How a workshop runs its staff and drivers.
///
/// The strict per-role split (staff = self-delivery intake, driver = valet
/// pickup) assumed a customer never changes their mind mid-job, and a workshop
/// may also want every operator to SEE everything without letting them interfere
/// with another role's production work. Hence three modes.
///
/// VIEW and ACT are separate questions. `opsRoleMayViewStage` decides whether a
/// stage appears; `opsRoleMayActOnStage` decides whether it can be completed. A
/// mode that shows a stage the caller may not complete is exactly right under
/// [viewAllActOwn] — the tile renders as read-only.
///
/// Since 20260921, acting is enforced by the DATABASE, not by these functions:
/// `public.ops_may_act_on_stage(job_id, stage_key)` reads
/// `public.ops_stage_roles` and gates restrictive policies on `job_milestones` /
/// `job_milestone_photos` plus both ops RPCs. These Dart helpers must therefore
/// agree with that table; they exist to render the UI honestly, not to protect
/// anything. A mismatch shows up as a refused write, never as a silent hole.
enum OpsViewMode {
  /// Every staff member and driver sees every tab, every job in the workshop,
  /// and may complete any stage photo. This is the database default.
  allAccess,

  /// Everyone sees every job and every stage, but acting is limited to the
  /// stage's own role list. Added so a driver can be aware of production without
  /// being able to complete a floor stage that belongs to staff or a mechanic.
  viewAllActOwn,

  /// The previous strict behaviour: staff get self-delivery intake only, drivers
  /// get pickup only, and each stage keeps its own role list.
  originalRole;

  static OpsViewMode fromDb(String? raw) => switch (raw) {
        'original_role' => OpsViewMode.originalRole,
        'view_all_act_own' => OpsViewMode.viewAllActOwn,
        // Anything unknown (including NULL) falls back to the DB default rather
        // than to the stricter reading, matching partners.ops_view_mode.
        _ => OpsViewMode.allAccess,
      };

  String get dbValue => switch (this) {
        OpsViewMode.originalRole => 'original_role',
        OpsViewMode.viewAllActOwn => 'view_all_act_own',
        OpsViewMode.allAccess => 'all_access',
      };

  /// Owner-facing label for the workshop settings card.
  String get label => switch (this) {
        OpsViewMode.allAccess => 'Full access',
        OpsViewMode.viewAllActOwn => 'View all, act on their own',
        OpsViewMode.originalRole => 'Strict roles',
      };

  String get description => switch (this) {
        OpsViewMode.allAccess =>
          'Staff and drivers see every job and can complete any stage.',
        OpsViewMode.viewAllActOwn =>
          'Staff and drivers see every job and stage, but can only complete the '
              'stages their role is responsible for.',
        OpsViewMode.originalRole =>
          'Staff handle intake only, drivers handle pickup only, and each stage '
              'stays with its own role.',
      };
}

/// The workshop's ops access mode, read from `partners.ops_view_mode`.
///
/// Workshop members can read their own partner row (the `get_my_partner_id()`
/// read policy matches on the token's partner_id), so this needs no extra RPC.
///
/// On a missing session, missing partner_id, or read error this resolves to
/// [OpsViewMode.allAccess], matching the database default. Since acting is gated
/// server-side, failing to the permissive default cannot widen access — the worst
/// case is a stage tile that the RPC or policy then refuses.
final opsViewModeProvider = FutureProvider.autoDispose<OpsViewMode>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return OpsViewMode.allAccess;

  final partnerId = user.appMetadata['partner_id'] as String?;
  if (partnerId == null || partnerId.isEmpty) return OpsViewMode.allAccess;

  try {
    final row = await Supabase.instance.client
        .from('partners')
        .select('ops_view_mode')
        .eq('id', partnerId)
        .maybeSingle();
    return OpsViewMode.fromDb(row?['ops_view_mode'] as String?);
  } catch (e) {
    debugPrint('[OpsAccess] Could not read ops_view_mode, defaulting to all_access: $e');
    return OpsViewMode.allAccess;
  }
});

/// Roles that may operate inside the ops mobile app at all.
const kOpsOperatorRoles = <String>{
  'partner_staff',
  'partner_driver',
  'partner_mechanic',
  'master_admin',
};

/// Whether [role] should SEE a stage whose own role list is [allowedRoles].
///
/// [OpsViewMode.allAccess] and [OpsViewMode.viewAllActOwn] both show every stage
/// to every operator — that is the whole point of the latter. Only
/// [OpsViewMode.originalRole] hides a stage from a role it does not belong to.
bool opsRoleMayViewStage(
  OpsViewMode mode,
  String? role,
  List<String> allowedRoles,
) {
  if (role == null || role.isEmpty) return false;
  if (!kOpsOperatorRoles.contains(role)) return false;
  if (mode == OpsViewMode.originalRole) return allowedRoles.contains(role);
  return true;
}

/// Whether [role] may COMPLETE a stage whose own role list is [allowedRoles].
///
/// In [OpsViewMode.allAccess] any ops operator may complete any stage. In
/// [OpsViewMode.viewAllActOwn] and [OpsViewMode.originalRole] the stage's own
/// [allowedRoles] decides — the difference between those two is visibility only.
///
/// The database enforces the same rule via `ops_may_act_on_stage()`; this must
/// stay in step with it or the UI will offer taps that are then refused.
bool opsRoleMayActOnStage(
  OpsViewMode mode,
  String? role,
  List<String> allowedRoles,
) {
  if (role == null || role.isEmpty) return false;
  if (mode == OpsViewMode.allAccess) return kOpsOperatorRoles.contains(role);
  return allowedRoles.contains(role);
}

/// The ops tabs [role] sees under [mode].
enum OpsTab { floor, logistics, settings }

List<OpsTab> opsTabsFor(OpsViewMode mode, String? role) {
  // all_access and view_all_act_own both mean "see everything", so both get the
  // full tab set. Only original_role narrows the driver down.
  if (mode != OpsViewMode.originalRole) return OpsTab.values;

  if (role == 'partner_driver') return const [OpsTab.logistics, OpsTab.settings];
  return OpsTab.values;
}

/// Where `/ops` should land [role] under [mode].
String opsHomeRouteFor(OpsViewMode mode, String? role) {
  if (mode != OpsViewMode.originalRole) return '/ops/floor';
  return role == 'partner_driver' ? '/ops/logistics' : '/ops/floor';
}
