import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../ops_access.dart';

class OpsShellScreen extends ConsumerStatefulWidget {
  final Widget child;
  final String activeRoute;

  const OpsShellScreen({super.key, required this.child, required this.activeRoute});

  @override
  ConsumerState<OpsShellScreen> createState() => _OpsShellScreenState();
}

class _OpsShellScreenState extends ConsumerState<OpsShellScreen> {
  /// Index into the CURRENTLY VISIBLE tab list for [route].
  int _selectedIndex(List<OpsTab> tabs, String route) {
    final target = switch (route) {
      final r when r.startsWith('/ops/logistics') => OpsTab.logistics,
      final r when r.startsWith('/ops/settings') => OpsTab.settings,
      _ => OpsTab.floor,
    };
    final idx = tabs.indexOf(target);
    return idx < 0 ? 0 : idx;
  }

  void _onItemTapped(List<OpsTab> tabs, int index) {
    if (index < 0 || index >= tabs.length) return;
    switch (tabs[index]) {
      case OpsTab.floor:
        context.go('/ops/floor');
      case OpsTab.logistics:
        context.go('/ops/logistics');
      case OpsTab.settings:
        context.go('/ops/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // SEC-02: role comes from appMetadata (set by service_role only), not
    // userMetadata, which the account owner can write.
    final role = Supabase.instance.client.auth.currentUser?.appMetadata['role'] as String?;

    // The workshop owner decides whether staff and drivers are restricted to a
    // single job type or can see everything. Until the row loads we show the
    // full set, matching the all_access default.
    final mode = ref.watch(opsViewModeProvider).valueOrNull ?? OpsViewMode.allAccess;
    final tabs = opsTabsFor(mode, role);

    const labels = {
      OpsTab.floor: ('Floor Jobs', Icons.build_circle_outlined),
      OpsTab.logistics: ('Logistics', Icons.local_shipping_outlined),
      OpsTab.settings: ('Settings', Icons.settings_outlined),
    };

    final items = [
      for (final tab in tabs)
        BottomNavigationBarItem(
          icon: Icon(labels[tab]!.$2),
          label: labels[tab]!.$1,
        ),
    ];

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(child: widget.child),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex(tabs, widget.activeRoute),
        onTap: (idx) => _onItemTapped(tabs, idx),
        selectedItemColor: const Color(0xFFd10721), // Re-V Red
        unselectedItemColor: cs.onSurfaceVariant,
        items: items,
      ),
    );
  }
}
