import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';

/// Admin User Accounts — calls `list_all_users` and `set_user_role` RPCs
class AdminUserAccountsScreen extends ConsumerStatefulWidget {
  const AdminUserAccountsScreen({super.key});
  @override
  ConsumerState<AdminUserAccountsScreen> createState() => _AdminUserAccountsState();
}

class _AdminUserAccountsState extends ConsumerState<AdminUserAccountsScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _partners = []; // For assigning staff/driver to a workshop
  String _search = '';
  String _roleFilter = 'all';
  final _searchCtrl = TextEditingController();

  static const _allRoles = ['customer', 'partner_mechanic', 'partner_staff', 'partner_driver', 'master_admin'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rpcResult = await _sb.rpc('list_all_users');
      if (rpcResult is List) {
        _users = List<Map<String, dynamic>>.from(rpcResult.map((e) => Map<String, dynamic>.from(e as Map)));
      } else {
        _users = [];
      }

      // Also load partners for the role-change dialog
      try {
        final partnerRes = await _sb
            .from('partners')
            .select('id, shop_name, entity_name, workshop_name, is_active')
            .eq('is_active', true)
            .order('shop_name');
        _partners = List<Map<String, dynamic>>.from(partnerRes);
      } catch (_) {
        _partners = [];
      }
    } catch (rpcErr) {
      _error = 'Unable to load users.\n\nTechnical details: $rpcErr\n\n'
          'Ensure the "list_all_users" RPC exists in Supabase (migration 20260916).';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setRole(String userId, String currentRole, String newRole) async {
    // If assigning staff/driver, we need to pick a partner workshop
    String? partnerId;
    if (newRole == 'partner_staff' || newRole == 'partner_driver') {
      partnerId = await _showPartnerPickerDialog(newRole);
      if (partnerId == null) return; // User cancelled
    }

    // If promoting to partner_mechanic, we also need a partner_id
    // but that's handled separately via the partner approval flow.
    // For now, allow admin to assign partner_mechanic if a partner is selected.
    if (newRole == 'partner_mechanic') {
      partnerId = await _showPartnerPickerDialog(newRole);
      if (partnerId == null) return;
    }

    try {
      final result = await _sb.rpc('set_user_role', params: {
        'target_user_id': userId,
        'new_role': newRole,
        if (partnerId != null) 'new_partner_id': partnerId,
      });

      final Map<String, dynamic> response = result is Map<String, dynamic> ? result : {};
      final success = response['success'] == true;

      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Role updated: ${response['email'] ?? userId} → $newRole'
              : 'Failed: ${response['error'] ?? 'Unknown error'}'),
          backgroundColor: success ? const Color(0xFF059669) : const Color(0xFFDC2626),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          backgroundColor: const Color(0xFFDC2626),
          content: Text('Role update failed: $e'),
        ));
      }
    }
  }

  Future<String?> _showPartnerPickerDialog(String targetRole) async {
    if (_partners.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No active partners found. Create a partner workshop first.'),
          backgroundColor: Color(0xFFDC2626),
        ));
      }
      return null;
    }

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final roleName = targetRole == 'partner_driver' ? 'Driver' :
                         targetRole == 'partner_staff' ? 'Staff' : 'Partner Owner';
        return AlertDialog(
          title: Text('Assign $roleName to Workshop'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select the workshop this user will be assigned to:',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 16),
                ..._partners.map((p) {
                  final name = p['workshop_name'] ?? p['entity_name'] ?? p['shop_name'] ?? 'Unknown';
                  return ListTile(
                    leading: const Icon(Icons.store, size: 20),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(p['id'].toString().substring(0, 8), style: const TextStyle(fontSize: 10)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    onTap: () => Navigator.pop(ctx, p['id'].toString()),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _users;
    if (_roleFilter != 'all') list = list.where((p) => p['role'] == _roleFilter).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((p) =>
        (p['display_name'] ?? p['full_name'] ?? '').toString().toLowerCase().contains(q) ||
        (p['email'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    return list;
  }

  String _roleBadgeLabel(String role) {
    switch (role) {
      case 'master_admin': return 'Admin';
      case 'partner_mechanic': return 'Partner';
      case 'partner_staff': return 'Staff';
      case 'partner_driver': return 'Driver';
      case 'customer': return 'Customer';
      default: return role;
    }
  }

  Color _roleColor(String role, ColorScheme cs) {
    switch (role) {
      case 'master_admin': return AppColors.fireRed;
      case 'partner_mechanic': return Colors.blue;
      case 'partner_staff': return Colors.orange;
      case 'partner_driver': return Colors.teal;
      case 'customer': return cs.primary;
      default: return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ReVAppBar(
        showBackButton: true,
        title: Text('User Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurface)),
      ),
      body: Column(children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
          ),
          child: Row(children: [
            // Search
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF18191C) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: 'Search by name or email...'),
                    onChanged: (v) => setState(() => _search = v),
                  )),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            // Role filter chips — now using actual DB roles
            for (final r in ['all', ..._allRoles])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: FilterChip(
                  label: Text(r == 'all' ? 'All' : _roleBadgeLabel(r), style: const TextStyle(fontSize: 11)),
                  selected: _roleFilter == r,
                  onSelected: (_) => setState(() => _roleFilter = r),
                  selectedColor: AppColors.primaryContainer.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.primaryContainer,
                  side: BorderSide(color: _roleFilter == r ? AppColors.primaryContainer.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            const SizedBox(width: 12),
            IconButton(icon: Icon(Icons.refresh_rounded, size: 18, color: cs.onSurfaceVariant), onPressed: _load),
          ]),
        ),
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: cs.surfaceContainerLowest,
          child: Row(children: [
            _StatChip(cs: cs, label: 'Total', value: _users.length.toString(), color: cs.primary),
            const SizedBox(width: 12),
            _StatChip(cs: cs, label: 'Customers', value: _users.where((p) => p['role'] == 'customer').length.toString(), color: cs.secondary),
            const SizedBox(width: 12),
            _StatChip(cs: cs, label: 'Partners', value: _users.where((p) => p['role'] == 'partner_mechanic').length.toString(), color: Colors.blue),
            const SizedBox(width: 12),
            _StatChip(cs: cs, label: 'Staff', value: _users.where((p) => p['role'] == 'partner_staff').length.toString(), color: Colors.orange),
            const SizedBox(width: 12),
            _StatChip(cs: cs, label: 'Drivers', value: _users.where((p) => p['role'] == 'partner_driver').length.toString(), color: Colors.teal),
            const SizedBox(width: 12),
            _StatChip(cs: cs, label: 'Admins', value: _users.where((p) => p['role'] == 'master_admin').length.toString(), color: AppColors.fireRed),
            const Spacer(),
            Text('Showing ${_filtered.length} of ${_users.length}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        ),
        // List
        Expanded(child: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline_rounded, size: 48, color: cs.error),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 12), textAlign: TextAlign.center),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ]))
            : _filtered.isEmpty
              ? Center(child: Text('No users found', style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _UserRow(
                    cs: cs,
                    theme: theme,
                    profile: _filtered[i],
                    roleBadgeLabel: _roleBadgeLabel,
                    roleColor: _roleColor,
                    allRoles: _allRoles,
                    onSetRole: (role) => _setRole(_filtered[i]['id'], _filtered[i]['role'] ?? 'customer', role),
                  ),
                ),
        ),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final ColorScheme cs;
  final String label, value;
  final Color color;
  const _StatChip({required this.cs, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text('$value $label', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
  ]);
}

class _UserRow extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final Map<String, dynamic> profile;
  final String Function(String) roleBadgeLabel;
  final Color Function(String, ColorScheme) roleColor;
  final List<String> allRoles;
  final void Function(String) onSetRole;
  const _UserRow({
    required this.cs,
    required this.theme,
    required this.profile,
    required this.roleBadgeLabel,
    required this.roleColor,
    required this.allRoles,
    required this.onSetRole,
  });

  @override
  Widget build(BuildContext context) {
    final name = (profile['display_name'] ?? profile['full_name'] ?? 'Unknown').toString();
    final email = profile['email']?.toString() ?? '';
    final role = profile['role']?.toString() ?? 'customer';
    final createdAt = profile['created_at']?.toString().substring(0, 10) ?? '';
    final lastSignIn = profile['last_sign_in_at']?.toString();
    final partnerName = profile['partner_name']?.toString();
    final avatarUrl = profile['avatar_url']?.toString();
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join()
        : '?';

    final badgeColor = roleColor(role, cs);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: avatarUrl != null && avatarUrl.isNotEmpty
              ? Image.network(avatarUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(child: Text(initials,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))))
              : Center(child: Text(initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
        ),
        const SizedBox(width: 14),
        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
          Text(email, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          if (partnerName != null && partnerName.isNotEmpty)
            Text('Workshop: $partnerName', style: TextStyle(fontSize: 10, color: badgeColor, fontWeight: FontWeight.w500)),
        ])),
        // Role badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: badgeColor.withValues(alpha: 0.3))),
          child: Text(roleBadgeLabel(role), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: badgeColor)),
        ),
        const SizedBox(width: 12),
        // Last sign in
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Joined $createdAt', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            if (lastSignIn != null)
              Text('Last seen ${lastSignIn.substring(0, 10)}', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ),
        const SizedBox(width: 12),
        // Role change menu
        PopupMenuButton<String>(
          tooltip: 'Change role',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          icon: Icon(Icons.more_vert_rounded, size: 18, color: cs.onSurfaceVariant),
          onSelected: onSetRole,
          itemBuilder: (_) => [
            for (final r in allRoles)
              PopupMenuItem(value: r, child: Row(children: [
                Icon(Icons.circle, size: 8, color: roleColor(r, cs)),
                const SizedBox(width: 8),
                Text(roleBadgeLabel(r), style: TextStyle(
                  fontWeight: r == role ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                )),
                if (r == role) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check, size: 14, color: roleColor(r, cs)),
                ],
              ])),
          ],
        ),
      ]),
    );
  }
}
