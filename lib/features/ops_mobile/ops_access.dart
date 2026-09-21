import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How a workshop runs its staff and drivers.
///
/// The strict per-role split (staff = self-delivery intake, driver = valet
/// pickup) assumed a customer never changes their mind mid-job. A workshop can
/// now run in [allAccess] so either role can handle any job or stage.
enum OpsViewMode {
  /// Every staff member and driver sees every tab, every job in the workshop,
  /// and may complete any stage photo. This is the database default.
  allAccess,

  /// The previous strict behaviour, restored exactly: staff get self-delivery
  /// intake only, drivers get pickup only, and each stage keeps its own role list.
  originalRole;

  static OpsViewMode fromDb(String? raw) =>
      raw == 'original_role' ? OpsViewMode.originalRole : OpsViewMode.allAccess;

  String get dbValue =>
      this == OpsViewMode.originalRole ? 'original_role' : 'all_access';
}

/// The workshop's ops access mode, read from `partners.ops_view_mode`.
///
/// Workshop members can read their own partner row (the `get_my_partner_id()`
/// read policy matches on the token's partner_id), so this needs no extra RPC.
///
/// On a missing session, missing partner_id, or read error this resolves to
/// [OpsViewMode.allAccess], matching the database default. Both roles already
/// have full RLS access to their workshop's jobs, so this value only decides
/// which tabs and stages the UI surfaces — it is not a permission gate, and
/// failing to the permissive default cannot widen database access.
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

/// Whether [role] may complete a stage whose own role list is [allowedRoles].
///
/// In [OpsViewMode.allAccess] any ops operator may complete any stage. In
/// [OpsViewMode.originalRole] the stage's own [allowedRoles] decides, which is
/// the behaviour that existed before this mode was introduced.
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
  // all_access: every operator gets the full set.
  if (mode == OpsViewMode.allAccess) return OpsTab.values;

  // original_role: only a driver keeps a reduced set (logistics + settings);
  // every other operator already had all three tabs.
  if (role == 'partner_driver') return const [OpsTab.logistics, OpsTab.settings];
  return OpsTab.values;
}

/// Where `/ops` should land [role] under [mode].
String opsHomeRouteFor(OpsViewMode mode, String? role) {
  if (mode == OpsViewMode.allAccess) return '/ops/floor';
  return role == 'partner_driver' ? '/ops/logistics' : '/ops/floor';
}
