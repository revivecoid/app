part of '../master_admin_desktop.dart';

// ─── Top Header ───────────────────────────────────────────────────────────────

class _TopHeader extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final WidgetRef ref;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;

  const _TopHeader(
      {required this.cs,
      required this.state,
      required this.ref,
      required this.searchCtrl,
      required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;
    // Role display label
    final roleLabel = state.adminRole
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty
            ? ''
            : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return Container(
      height: 64,
      color: cs.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        // Search
        Expanded(
          flex: 3,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.search_rounded,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                controller: searchCtrl,
                onChanged: onSearch,
                style:
                    TextStyle(fontSize: 14, color: cs.onSurface),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText:
                      'Search VIN, license plate, or order ID...',
                  hintStyle: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 14),
                  isDense: true,
                  suffixIcon: searchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            searchCtrl.clear();
                            onSearch('');
                          },
                          child: Icon(Icons.close,
                              size: 16,
                              color: cs.onSurfaceVariant))
                      : null,
                ),
              )),
            ]),
          ),
        ),
        const SizedBox(width: 24),
        // Live node
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const _PulseDot(color: Color(0xFF10b981)),
            const SizedBox(width: 6),
            Text('NODE 04: LIVE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
          ]),
        ),
        const SizedBox(width: 8),
        // Notifications
        Stack(children: [
          IconButton(
              icon: Icon(Icons.notifications_outlined,
                  color: cs.onSurface),
              onPressed: () {}),
          Positioned(
              top: 8,
              right: 8,
              child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: cs.surfaceContainerLowest,
                          width: 1.5)))),
        ]),
        // Theme toggle
        IconButton(
          icon: Icon(
              isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              color: cs.onSurface),
          tooltip: 'Toggle Theme',
          onPressed: () =>
              ref.read(themeModeProvider.notifier).setTheme(isDark ? ThemeMode.light : ThemeMode.dark),
        ),
        const SizedBox(width: 8),
        // Admin identity — clickable
        InkWell(
          onTap: () => _showAdminProfileSheet(context, state, cs),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(children: [
              Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(state.adminName,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            height: 1.2)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(state.adminLevel == 'sysadmin' ? 'System Administrator' : 'Administrator',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              height: 1.2)),
                      if (state.adminLevel == 'sysadmin') ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3)),
                          child: Text('SYS',
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ]),
                  ]),
              const SizedBox(width: 10),
              Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: cs.primary, shape: BoxShape.circle),
                  child: Icon(Icons.person_rounded,
                      color: cs.onPrimary, size: 18)),
            ]),
          ),
        ),
      ]),
    );
  }

  void _showAdminProfileSheet(
      BuildContext context, AdminDashboardState state, ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 56,
              height: 56,
              decoration:
                  BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              child: Icon(Icons.person_rounded, color: cs.onPrimary, size: 30)),
          const SizedBox(height: 12),
          Text(state.adminName,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(
              state.adminLevel == 'sysadmin'
                  ? 'System Administrator'
                  : 'Administrator',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          if (state.adminLevel == 'sysadmin') ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('SYSADMIN ACCESS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                      letterSpacing: 1)),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.hub_outlined,
                color: cs.onSurfaceVariant, size: 20),
            title: Text('Active Hub',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            trailing: Text(state.activeHubName,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            dense: true,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: Icon(Icons.logout, color: cs.error, size: 18),
            label: Text('Sign Out',
                style:
                    TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
            onPressed: () async {
              Navigator.pop(context);
              await Supabase.instance.client.auth.signOut();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

