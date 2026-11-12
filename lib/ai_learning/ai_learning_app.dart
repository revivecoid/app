import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import 'data/learning_gate.dart';
import 'presentation/auth_screen.dart';
import 'presentation/complete_profile_screen.dart';
import 'presentation/review_screen.dart';
import 'presentation/scan_screen.dart';

class AiLearningApp extends StatelessWidget {
  const AiLearningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 're-V AI Learning',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.fireRed,
          brightness: Brightness.light,
        ),
      ),
      routerConfig: _router,
    );
  }
}

// Every route needs a signed-in account that also has a respondent profile.
// Respondents must register before they can use the app.
final GoRouter _router = GoRouter(
  refreshListenable: learningGate,
  initialLocation: '/',
  redirect: (context, state) {
    final path = state.matchedLocation;
    final onAuth = path == '/auth';
    final onProfile = path == '/complete-profile';

    switch (learningGate.status) {
      case GateStatus.loading:
        return null;
      case GateStatus.signedOut:
      case GateStatus.error:
        return onAuth ? null : '/auth';
      case GateStatus.needsProfile:
        return onProfile ? null : '/complete-profile';
      case GateStatus.ready:
        return (onAuth || onProfile) ? '/' : null;
    }
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ScanScreen()),
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(
      path: '/complete-profile',
      builder: (context, state) => const CompleteProfileScreen(),
    ),
    GoRoute(
      path: '/review',
      builder: (context, state) {
        final args = state.extra as ReviewArgs;
        return ReviewScreen(args: args);
      },
    ),
  ],
);
