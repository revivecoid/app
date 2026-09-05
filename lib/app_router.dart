import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/rev_app_bar.dart';

// --- IMPORTING ESTABLISHED FEATURE MODULES ---
import 'features/partner_dashboard/presentation/partner_profile_screen.dart';
import 'features/customer_app/home/presentation/customer_landing_screen.dart';
import 'features/customer_app/estimator/presentation/estimator_screen.dart';
import 'features/customer_app/estimator/presentation/diagram_test_screen.dart';
import 'features/customer_app/order/presentation/booking_scheduling_screen.dart';
import 'features/customer_app/order/presentation/checkout_payment_screen.dart';
import 'features/customer_app/tracking/presentation/live_stepper_timeline.dart';
import 'features/customer_app/profile/presentation/customer_profile_screen.dart';
import 'features/customer_app/support/presentation/customer_support_screen.dart';
import 'features/customer_app/notifications/presentation/customer_notifications_screen.dart';
import 'features/customer_app/notifications/presentation/notification_preferences_screen.dart';
import 'features/customer_app/profile/presentation/update_password_screen.dart';
import 'features/admin_central/presentation/master_admin_desktop.dart';
import 'features/admin_central/presentation/admin_partner_profile_screen.dart';
import 'features/admin_central/presentation/admin_job_assignment_screen.dart';
import 'features/partner_dashboard/presentation/partner_dashboard_desktop.dart';
import 'features/partner_dashboard/presentation/partner_registration_screen.dart';
import 'features/partner_dashboard/presentation/schedule_config_screen.dart';
import 'features/partner_dashboard/presentation/panel_duration_config_screen.dart';
import 'features/partner_dashboard/settings/presentation/partner_settings_screen.dart';


// --- IMPORTING CMS SCREENS ---
import 'features/cms/presentation/ai_damage_model_studio_screen.dart';
import 'features/cms/presentation/customer_concierge_nlp_studio_screen.dart';
import 'features/cms/presentation/digital_asset_manager_screen.dart';
import 'features/cms/presentation/frontend_content_studio_screen.dart';
import 'features/cms/presentation/commission_settlement_engine_screen.dart';

// --- RECOVERY STATE PROVIDER ---
final passwordRecoveryProvider = StateProvider<bool>((ref) => false);

// --- SUPABASE AUTH STATE LISTENER FOR GOROUTER ---
class SupabaseAuthRefreshNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  SupabaseAuthRefreshNotifier(Ref ref) {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        ref.read(passwordRecoveryProvider.notifier).state = true;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// --- ROUTER GLOBAL STATE ---
String? _globalReturnToPath;

// --- RIVERPOD ROUTER PROVIDER ---
final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = SupabaseAuthRefreshNotifier(ref);
  
  ref.onDispose(() {
    authNotifier.dispose();
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authNotifier,
    
    // STRICT SECURITY ROLE GUARDS & ROUTING INTERCEPTOR
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggingIn = state.uri.path == '/login';
      final path = state.uri.path;

      // Unauthenticated Guard
      if (session == null) {
        final publicPaths = ['/', '/estimator', '/diagram-test', '/auth/callback', '/partner/register'];
        if (publicPaths.contains(path) || path.startsWith('/auth/')) return null;
        if (!isLoggingIn) {
          final returnTo = Uri.encodeComponent(state.uri.toString());
          _globalReturnToPath = state.uri.toString();
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('returnTo', _globalReturnToPath!);
          } catch (_) {}
          return '/login?returnTo=$returnTo';
        }
        return null;
      }

      // Recovery Guard
      final isRecovering = ref.read(passwordRecoveryProvider);
      if (isRecovering && path != '/update-password') {
        return '/update-password';
      }

      // Read Profile Role — from appMetadata (admin-only, secure) with userMetadata fallback
      final role = (session.user.appMetadata['role'] as String?)
          ?? (session.user.userMetadata?['role'] as String?)
          ?? 'customer';

      // Authenticated Login/Callback Redirect Logic
      if (isLoggingIn || path == '/auth/callback') {
        final queryParamReturnTo = state.uri.queryParameters['returnTo'];
        final decodedQueryParam = queryParamReturnTo != null ? Uri.decodeComponent(queryParamReturnTo) : null;
        
        String? targetPath = decodedQueryParam ?? _globalReturnToPath;
        if (targetPath == null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            targetPath = prefs.getString('returnTo');
            if (targetPath != null) {
              await prefs.remove('returnTo');
            }
          } catch (_) {}
        }
        
        if (role == 'master_admin') return targetPath ?? '/admin-central';
        if (role == 'partner_mechanic') return targetPath ?? '/partner-dashboard';
        return targetPath ?? '/'; 
      } else {
        // If we landed somewhere else unexpectedly right after login (e.g. Supabase fallback to '/'),
        // see if we have a trapped returnTo in SharedPreferences we should be honoring.
        try {
          final prefs = await SharedPreferences.getInstance();
          final trappedPath = prefs.getString('returnTo');
          if (trappedPath != null) {
            await prefs.remove('returnTo');
            if (trappedPath.isNotEmpty) return trappedPath; 
          }
        } catch (_) {}

        // We have securely landed on an authenticated route and are not in a login loop.
        // It is now strictly safe to garbage collect the global return path.
        _globalReturnToPath = null;
      }

      // 1. MASTER ADMIN DOMAIN GUARD
      if (path.startsWith('/admin-central') && role != 'master_admin') {
        return '/'; // Access Denied Intercept
      }

      // 2. PARTNER DOMAIN GUARD
      if (path.startsWith('/partner-dashboard')) {
        if (role != 'partner_mechanic') {
          return '/'; // Access Denied Intercept
        }
        
        // Strict Tenant Verification Guard
        final partnerId = session.user.userMetadata?['partner_id'];
        if (partnerId == null || partnerId.toString().isEmpty) {
          debugPrint('🚨 FATAL: Partner account missing isolated tenant ID payload.');
          return '/login'; 
        }
      }

      return null; // Route permitted
    },

    // 404 FALLBACK ERROR ARCHITECTURE
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 80, color: AppColors.daysGray),
            const SizedBox(height: 24),
            const Text('404 - SECTOR NOT FOUND', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.sleekBlack)),
            const SizedBox(height: 16),
            Text('The route "${state.uri.path}" is unavailable or restricted.', style: const TextStyle(color: AppColors.daysGray)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed),
              child: const Text('RETURN TO BASE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ),

    routes: [
      // --- AUTHENTICATION GATE ---
      GoRoute(
        path: '/login',
        builder: (context, state) => const _GlobalAuthGate(),
      ),

      // --- OAUTH CALLBACK HANDLER ---
      // Supabase redirects here after Google login with ?code= parameter.
      // This screen exchanges the code for a session and redirects to the dashboard.
      GoRoute(
        path: '/auth/callback',
        builder: (context, state) => const _AuthCallbackScreen(),
      ),

      // --- PASSWORD RECOVERY ---
      GoRoute(
        path: '/update-password',
        builder: (context, state) => const UpdatePasswordScreen(),
      ),

      // --- CUSTOMER DOMAIN ---
      GoRoute(
        path: '/',
        builder: (context, state) => const CustomerLandingScreen(), // Public Home Landing
      ),
      GoRoute(
        path: '/partner/register',
        builder: (context, state) => const PartnerRegistrationScreen(),
      ),
      GoRoute(
        path: '/estimator',
        builder: (context, state) => const EstimatorScreen(), // Move estimator here
      ),
      GoRoute(
        path: '/diagram-test',
        builder: (context, state) => const DiagramTestScreen(),
      ),
      GoRoute(
        path: '/booking/schedule/:jobId',
      builder: (context, state) {
        final jobId = state.pathParameters['jobId']!;
        return BookingSchedulingScreen(jobId: jobId);
      },
      ),
      GoRoute(
        path: '/checkout/:jobId',
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          // Provide the missing partnerId required by the earlier constructor
          final partnerId = state.uri.queryParameters['partnerId'] ?? '';
          return CheckoutPaymentScreen(jobId: jobId, partnerId: partnerId);
        },
      ),
      GoRoute(
        path: '/track/:jobId',
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return LiveStepperTimeline(jobId: jobId);
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const CustomerProfileScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => const CustomerSupportScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const CustomerNotificationsScreen(),
      ),
      GoRoute(
        path: '/notification-settings',
        builder: (context, state) => const NotificationPreferencesScreen(),
      ),

      // --- MASTER ADMIN DOMAIN ---
      GoRoute(
        path: '/admin-central',
        builder: (context, state) => const MasterAdminDesktop(),
      ),
      GoRoute(
        path: '/admin-central/assign',
        builder: (context, state) => const AdminJobAssignmentScreen(),
      ),
      GoRoute(
        path: '/admin-central/partner/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return AdminPartnerProfileScreen(partnerId: id);
        },
      ),
      GoRoute(
        path: '/admin-central/cms/ai-damage-model-pricing-rules',
        builder: (context, state) => const AiDamageModelStudioScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/customer-concierge-nlp',
        builder: (context, state) => const CustomerConciergeNlpStudioScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/digital-asset-manager',
        builder: (context, state) => const DigitalAssetManagerScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/frontend-content-studio',
        builder: (context, state) => const FrontendContentStudioScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/commission-settlement-engine',
        builder: (context, state) => const CommissionSettlementEngineScreen(),
      ),

      // --- PARTNER WORKSHOP DOMAIN ---
      GoRoute(
        path: '/partner-dashboard',
        builder: (context, state) => const PartnerDashboardDesktop(),
      ),
      GoRoute(
        path: '/partner-dashboard/profile',
        builder: (context, state) => const PartnerProfileScreen(),
      ),
      GoRoute(
        path: '/partner-dashboard/settings',
        builder: (context, state) => const PartnerSettingsScreen(),
      ),
      GoRoute(
        path: '/partner-dashboard/schedule',
        builder: (context, state) => const ScheduleConfigScreen(),
      ),
      GoRoute(
        path: '/partner-dashboard/quota',
        builder: (context, state) => const PanelDurationConfigScreen(),
      ),

    ],
  );
});

// --- OAUTH CALLBACK SCREEN ---
// Handles Supabase PKCE redirect. Exchanges ?code= for a live session then routes user.
class _AuthCallbackScreen extends StatefulWidget {
  const _AuthCallbackScreen();
  @override
  State<_AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<_AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    if (code != null) {
      try {
        await Supabase.instance.client.auth.exchangeCodeForSession(code);
      } catch (e) {
        debugPrint('OAuth callback error: $e');
      }
    }
    if (mounted) {
      // Respect the returnTo parameter if present, otherwise fall back to global cache, then SharedPreferences
      String? returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'] ?? _globalReturnToPath;
      if (returnTo == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          returnTo = prefs.getString('returnTo');
          if (returnTo != null) {
            await prefs.remove('returnTo');
          }
        } catch (_) {}
      }
      
      if (returnTo != null) {
        context.go(Uri.decodeComponent(returnTo));
      } else {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.sleekBlack,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.fireRed),
            SizedBox(height: 16),
            Text('Authenticating...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

// --- FULLY FUNCTIONAL PRODUCTION AUTH SCREEN (No Dummy Placeholders) ---
class _GlobalAuthGate extends StatefulWidget {
  const _GlobalAuthGate();

  @override
  State<_GlobalAuthGate> createState() => _GlobalAuthGateState();
}

class _GlobalAuthGateState extends State<_GlobalAuthGate> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _isResettingPassword = false;
  bool _registrationSuccess = false;
  bool _resetSuccess = false;
  String? _errorMessage;

  Future<void> _executeResetPassword() async {
    setState(() { _isLoading = true; _errorMessage = null; _resetSuccess = false; });
    try {
      final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
      final queryParam = returnTo != null ? '?returnTo=${Uri.encodeComponent(returnTo)}' : '';
      final redirectTo = Uri.base.origin + '/auth/callback' + queryParam;
      
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: redirectTo,
      );
      setState(() => _resetSuccess = true);
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to send reset link: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeAuth() async {
    setState(() { _isLoading = true; _errorMessage = null; _registrationSuccess = false; _resetSuccess = false; });
    try {
      if (_isRegistering) {
        // Pass redirectTo in sign up for email confirmation redirect
        final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
        final queryParam = returnTo != null ? '?returnTo=${Uri.encodeComponent(returnTo)}' : '';
        final emailRedirectTo = Uri.base.origin + '/auth/callback' + queryParam;

        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          emailRedirectTo: emailRedirectTo,
        );
        setState(() => _registrationSuccess = true);
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      // GoRouter redirect interceptor handles login transition automatically
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Critical Authentication Failure: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeGoogleLogin() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
      final queryParam = returnTo != null ? '?returnTo=${Uri.encodeComponent(returnTo)}' : '';
      final redirectTo = Uri.base.origin + '/auth/callback' + queryParam;
      
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
    } on AuthException catch (e) {
      setState(() { _errorMessage = e.message; _isLoading = false; });
    } catch (e) {
      setState(() { _errorMessage = 'Google Auth Error: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.sleekBlack;
    final bgColor = isDark ? AppColors.sleekBlack : Colors.grey[50];
    final surfaceColor = isDark ? AppColors.surface : Colors.white;

    return Consumer(builder: (context, ref, child) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: ReVAppBar(),
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(32),
              margin: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => context.go('/'),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/revive_logo.png',
                          height: 40,
                          color: isDark ? Colors.white : AppColors.fireRed,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          're-V',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 32,
                            color: isDark ? Colors.white : AppColors.sleekBlack,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Integrated Automotive Digital Platform', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(_isRegistering ? 'Create Account' : 'Secure Login', style: const TextStyle(color: AppColors.daysGray)),
                  const SizedBox(height: 32),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.red.withValues(alpha: 0.1),
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  if (_registrationSuccess)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.green.withValues(alpha: 0.1),
                      child: const Text('Registration successful! Please check your email to verify your account before logging in.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  if (_resetSuccess)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.green.withValues(alpha: 0.1),
                      child: const Text('Password reset link sent! Check your email to securely reset your password.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  TextField(
                    controller: _emailController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'Email Address', 
                      labelStyle: const TextStyle(color: AppColors.daysGray),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.daysGray.withValues(alpha: 0.5)))
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (!_isResettingPassword) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Password', 
                        labelStyle: const TextStyle(color: AppColors.daysGray),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.daysGray.withValues(alpha: 0.5)))
                      ),
                      obscureText: true,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : (_isResettingPassword ? _executeResetPassword : _executeAuth),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed),
                      child: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(_isResettingPassword ? 'SEND RESET LINK' : (_isRegistering ? 'REGISTER' : 'LOGIN'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isResettingPassword) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isResettingPassword = true;
                              _isRegistering = false;
                              _errorMessage = null;
                              _registrationSuccess = false;
                            });
                          },
                          child: Text('Forgot Password?', style: TextStyle(color: textColor.withValues(alpha: 0.7))),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegistering = !_isRegistering;
                              _errorMessage = null;
                              _registrationSuccess = false;
                            });
                          },
                          child: Text(
                            _isRegistering ? 'Login instead' : "Sign Up",
                            style: TextStyle(color: textColor.withValues(alpha: 0.9), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isResettingPassword = false;
                          _errorMessage = null;
                          _resetSuccess = false;
                        });
                      },
                      child: Text('Back to Login', style: TextStyle(color: textColor.withValues(alpha: 0.8))),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR', style: TextStyle(color: AppColors.daysGray, fontWeight: FontWeight.bold)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _executeGoogleLogin,
                      icon: Image.asset('assets/images/google_logo.png', height: 24),
                      label: Text('Continue with Google', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: isDark ? AppColors.daysGray : AppColors.daysGray.withValues(alpha: 0.5), width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        backgroundColor: surfaceColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

