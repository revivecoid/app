import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';

/// Calls the `list_all_users` RPC which must exist in Supabase with SECURITY DEFINER.
/// Falls back gracefully if not available.
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
  String _search = '';
  String _roleFilter = 'all';
  final _searchCtrl = TextEditingController();

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
      // Try RPC first (requires a SECURITY DEFINER function in Supabase)
      final rpcResult = await _sb.rpc('list_all_users');
      if (rpcResult is List) {
        _users = List<Map<String, dynamic>>.from(rpcResult.map((e) => Map<String, dynamic>.from(e as Map)));
      } else {
        _users = [];
      }
    } catch (rpcErr) {
      // Fallback: build a combined list from partners + repair_jobs customer IDs
      try {
        final partners = await _sb
            .from('partners')
            .select('id, workshop_name, contact_email, is_active, created_at');
        final jobs = await _sb
            .from('repair_jobs')
            .select('customer_id, created_at')
            .order('created_at', ascending: false);

        // Unique customers from repair_jobs
        final seenCustomers = <String>{};
        final customerRows = <Map<String, dynamic>>[];
        for (final j in List<Map<String, dynamic>>.from(jobs)) {
          final cid = j['customer_id']?.toString() ?? '';
          if (cid.isNotEmpty && seenCustomers.add(cid)) {
            customerRows.add({
              'id': cid,
              'display_name': 'Customer',
              'email': cid.substring(0, 8) + '…',
              'role': 'customer',
              'created_at': j['created_at'],
            });
          }
        }

        final partnerRows = List<Map<String, dynamic>>.from(partners).map((p) => {
          'id': p['id'],
          'display_name': p['workshop_name'] ?? 'Partner Workshop',
          'email': p['contact_email'] ?? '',
          'role': 'partner',
          'created_at': p['created_at'],
          'is_active': p['is_active'],
        }).toList();

        _users = [...partnerRows, ...customerRows];
      } catch (e) {
        _error = 'Unable to load users.\n\nTechnical details: $e\n\n'
            'To fix: create a Supabase RPC function named "list_all_users" '
            'with SECURITY DEFINER that selects from auth.users.';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setRole(String userId, String newRole) async {
    try {
      // Try updating via RPC or partners table
      await _sb.from('partners').update({'role': newRole}).eq('id', userId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role updated to $newRole'), backgroundColor: const Color(0xFF059669)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role update requires server-side RPC.\nError: $e'), backgroundColor: const Color(0xFFDC2626)));
      }
    }
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
        // Info banner if using fallback data
        if (!_loading && _error == null && _users.isNotEmpty && _users.any((u) => u['display_name'] == 'Customer'))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.tertiaryContainer.withValues(alpha: 0.5),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: cs.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Showing fallback data. For full auth.users access, create a "list_all_users" RPC in Supabase.',
                style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
              )),
            ]),
          ),
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
            // Role filter
            for (final r in ['all', 'customer', 'partner', 'admin', 'sysadmin'])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: FilterChip(
                  label: Text(r == 'all' ? 'All' : r, style: const TextStyle(fontSize: 11)),
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
            _StatChip(cs: cs, label: 'Partners', value: _users.where((p) => p['role'] == 'partner').length.toString(), color: Colors.orange),
            const SizedBox(width: 12),
            _StatChip(cs: cs, label: 'Admins', value: _users.where((p) => ['admin','sysadmin'].contains(p['role'])).length.toString(), color: AppColors.fireRed),
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
                    onSetRole: (role) => _setRole(_filtered[i]['id'], role),
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
  final void Function(String) onSetRole;
  const _UserRow({required this.cs, required this.theme, required this.profile, required this.onSetRole});

  @override
  Widget build(BuildContext context) {
    final name = (profile['display_name'] ?? profile['full_name'] ?? 'Unknown').toString();
    final email = profile['email']?.toString() ?? '';
    final role = profile['role']?.toString() ?? 'customer';
    final createdAt = profile['created_at']?.toString().substring(0, 10) ?? '';
    final avatarUrl = profile['avatar_url']?.toString();
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join()
        : '?';

    final roleColor = {
      'sysadmin': AppColors.fireRed,
      'admin': Colors.orange,
      'partner': Colors.blue,
      'customer': cs.primary,
    }[role] ?? cs.primary;

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
        ])),
        // Role badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: roleColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: roleColor.withValues(alpha: 0.3))),
          child: Text(role, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: roleColor)),
        ),
        const SizedBox(width: 12),
        Text(createdAt, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        const SizedBox(width: 12),
        // Role change menu
        PopupMenuButton<String>(
          tooltip: 'Change role',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          icon: Icon(Icons.more_vert_rounded, size: 18, color: cs.onSurfaceVariant),
          onSelected: onSetRole,
          itemBuilder: (_) => [
            for (final r in ['customer', 'partner', 'admin', 'sysadmin'])
              PopupMenuItem(value: r, child: Row(children: [
                Icon(Icons.circle, size: 8, color: {
                  'sysadmin': AppColors.fireRed, 'admin': Colors.orange,
                  'partner': Colors.blue, 'customer': cs.primary,
                }[r] ?? cs.primary),
                const SizedBox(width: 8),
                Text(r, style: TextStyle(fontWeight: r == role ? FontWeight.bold : FontWeight.normal)),
              ])),
          ],
        ),
      ]),
    );
  }
}
