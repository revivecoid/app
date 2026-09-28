import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../app_router.dart';
import '../../../../core/l10n/app_localizations_extension.dart';

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  ConsumerState<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _currentPasswordController = TextEditingController(); // SEC-10
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // SEC-10: check if this is a password-recovery flow (no current password needed)
  bool get _isRecoveryFlow => ref.read(passwordRecoveryProvider);

  Future<void> _updatePassword() async {
    final l = context.l10n;
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = l.passwordNoMatch);
      return;
    }

    // SEC-11 fix: minimum 10 characters
    if (_passwordController.text.length < 10) {
      setState(() => _errorMessage = 'Password minimal 10 karakter');
      return;
    }

    // SEC-11 fix: reject trivially common passwords
    const common = ['password123', '1234567890', 'qwerty12345', 'admin12345'];
    if (common.contains(_passwordController.text.toLowerCase())) {
      setState(() => _errorMessage = 'Password terlalu umum, pilih yang lebih unik');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; _successMessage = null; });

    try {
      // SEC-10 fix: reauthenticate first unless this is a password recovery flow
      if (!_isRecoveryFlow) {
        final email = Supabase.instance.client.auth.currentUser?.email;
        if (email == null || _currentPasswordController.text.isEmpty) {
          setState(() { _isLoading = false; _errorMessage = 'Masukkan password saat ini terlebih dahulu'; });
          return;
        }
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: _currentPasswordController.text,
        );
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      
      setState(() => _successMessage = context.l10n.passwordSuccess);
      
      // Clear the recovery state
      ref.read(passwordRecoveryProvider.notifier).state = false;
      
      // Give the user a moment to read the success message before redirecting
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.go('/');
      });
      
    } on AuthException catch (e) {
      // SEC-13 fix: map auth errors to friendly messages
      final msg = _mapAuthError(e.message);
      setState(() => _errorMessage = msg);
    } catch (e) {
      setState(() => _errorMessage = context.l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(String raw) {
    if (raw.contains('Invalid login credentials') || raw.contains('invalid_credentials')) {
      return 'Password saat ini salah';
    }
    if (raw.contains('Password should be')) return 'Password minimal 10 karakter';
    if (raw.contains('rate limit')) return 'Terlalu banyak percobaan, coba lagi nanti';
    return 'Terjadi kesalahan, coba lagi';
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      Widget inner = Scaffold(
      backgroundColor: cs.surface,
      appBar: ReVAppBar(
        title: Text(context.l10n.passwordUpdateTitle),
        showBackButton: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            margin: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.08), blurRadius: 20)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_reset, size: 64, color: AppColors.fireRed),
                const SizedBox(height: 16),
                Builder(builder: (context) {
                  final l = context.l10n;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(l.passwordSecureAccount, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(l.passwordEnterNew, style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
                  ]);
                }),
                const SizedBox(height: 32),

                // SEC-10 fix: current password field (not shown during recovery flow)
                if (!_isRecoveryFlow) ...[
                  TextField(
                    controller: _currentPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password saat ini',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    color: cs.error.withValues(alpha: 0.1),
                    child: Text(_errorMessage!, style: TextStyle(color: cs.error, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                
                if (_successMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    color: cs.primary.withValues(alpha: 0.1),
                    child: Text(_successMessage!, style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),

                TextField(
                  controller: _passwordController,
                  style: TextStyle(color: cs.onSurface),
                  decoration: InputDecoration(
                    labelText: context.l10n.passwordNew, 
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.outlineVariant))
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  style: TextStyle(color: cs.onSurface),
                  decoration: InputDecoration(
                    labelText: context.l10n.passwordConfirm, 
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.outlineVariant))
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_isLoading || _successMessage != null) ? null : _updatePassword,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed),
                    child: _isLoading 
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: cs.surface, strokeWidth: 2))
                      : Text(context.l10n.passwordSave, style: TextStyle(color: cs.surface, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
      return isDesktop ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: inner)) : inner;
    });
  }
}
