import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  // 1. Ensure Flutter engine is fully initialized before async network bindings run
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set URL strategy to Path to prevent go_router from crashing on Supabase auth hash fragments
  usePathUrlStrategy();

  // 2. Load environment variables securely from the local filesystem
  await dotenv.load(fileName: ".env");

  // 3. Initialize Supabase Connection mapping to the production schema via strict environment pointers
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 4. Run the App inside a ProviderScope (Required by Riverpod for State Management)
  runApp(
    const ProviderScope(
      child: ReVApp(),
    ),
  );
}


class ReVApp extends ConsumerWidget {
  const ReVApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read our routing configurations executing strict role guards
    final router = ref.watch(appRouterProvider);
    final currentThemeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 're-V.co.id | Automotive Body Repair Portal',
      debugShowCheckedModeBanner: false,
      
      // Theme Configuration strictly mapped to re-V Brand Identity
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: currentThemeMode,

      // Enable Web Mouse Dragging for Carousels
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      
      // Hook Flutter directly into our GoRouter instance
      routerConfig: router,
    );
  }
}

