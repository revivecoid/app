import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class OpsShellScreen extends ConsumerStatefulWidget {
  final Widget child;
  final String activeRoute;

  const OpsShellScreen({super.key, required this.child, required this.activeRoute});

  @override
  ConsumerState<OpsShellScreen> createState() => _OpsShellScreenState();
}

class _OpsShellScreenState extends ConsumerState<OpsShellScreen> {
  int _getSelectedIndex() {
    if (widget.activeRoute.startsWith('/ops/logistics')) return 1;
    if (widget.activeRoute.startsWith('/ops/settings')) return 2;
    return 0; // /ops/floor
  }

  void _onItemTapped(int index) {
    if (index == 0) context.go('/ops/floor');
    if (index == 1) context.go('/ops/logistics');
    if (index == 2) context.go('/ops/settings');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final role = Supabase.instance.client.auth.currentUser?.userMetadata?['role'] as String? ?? 'partner_staff';
    final isDriver = role == 'partner_driver';
    
    // For drivers, we only show Logistics and Settings
    final items = isDriver 
      ? [
          const BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), label: 'Logistics'),
          const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ]
      : [
          const BottomNavigationBarItem(icon: Icon(Icons.build_circle_outlined), label: 'Floor Jobs'),
          const BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), label: 'Logistics'),
          const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ];

    // Compute active index taking role into account
    int activeIdx = _getSelectedIndex();
    if (isDriver) {
      activeIdx = widget.activeRoute.startsWith('/ops/settings') ? 1 : 0;
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(child: widget.child),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: activeIdx,
        onTap: (idx) {
          if (isDriver) {
             if (idx == 0) context.go('/ops/logistics');
             if (idx == 1) context.go('/ops/settings');
          } else {
             _onItemTapped(idx);
          }
        },
        selectedItemColor: const Color(0xFFd10721), // Re-V Red
        unselectedItemColor: cs.onSurfaceVariant,
        items: items,
      ),
    );
  }
}
