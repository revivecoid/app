import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/l10n/app_localizations.dart';
import 'core/providers/locale_provider.dart';
import 'features/shared/services/pricing_matrix.dart';

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

  // 4. Pre-warm the PricingMatrix cache so the first AI estimation request
  //    has no extra latency. Runs in the background — does not block launch.
  PricingMatrix.preload();

  // 5. Run the App inside a ProviderScope (Required by Riverpod for State Management)
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
    final router = ref.watch(appRouterProvider);
    final currentThemeMode = ref.watch(themeModeProvider);
    final currentLocale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 're-V.co.id | Automotive Body Repair Portal',
      debugShowCheckedModeBanner: false,

      // Localizations — EN / ID switchable at runtime
      locale: currentLocale,
      localizationsDelegates: AppL.localizationsDelegates,
      supportedLocales: supportedLocales,

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
