import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../app_router.dart';

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  UpdatePasswordScreen({super.key});

  @override
  ConsumerState<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  Future<void> _updatePassword() async {
    final l = AppL.of(context)!;
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = l.passwordNoMatch);
      return;
    }

    if (_passwordController.text.length < 6) {
      setState(() => _errorMessage = l.passwordTooShort);
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; _successMessage = null; });
    
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      
      setState(() => _successMessage = AppL.of(context)!.passwordSuccess);
      
      // Clear the recovery state
      ref.read(passwordRecoveryProvider.notifier).state = false;
      
      // Give the user a moment to read the success message before redirecting
      Future.delayed(Duration(seconds: 2), () {
        if (mounted) context.go('/');
      });
      
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = '${AppL.of(context)!.somethingWentWrong} $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      Widget inner = Scaffold(
      backgroundColor: cs.surface,
      appBar: ReVAppBar(
        title: Text(AppL.of(context)!.passwordUpdateTitle),
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
                Icon(Icons.lock_reset, size: 64, color: AppColors.fireRed),
                SizedBox(height: 16),
                Builder(builder: (context) {
                  final l = AppL.of(context)!;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(l.passwordSecureAccount, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface), textAlign: TextAlign.center),
                    SizedBox(height: 8),
                    Text(l.passwordEnterNew, style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
                  ]);
                }),
                SizedBox(height: 32),
                
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
                    labelText: AppL.of(context)!.passwordNew, 
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.outlineVariant))
                  ),
                  obscureText: true,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  style: TextStyle(color: cs.onSurface),
                  decoration: InputDecoration(
                    labelText: AppL.of(context)!.passwordConfirm, 
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.outlineVariant))
                  ),
                  obscureText: true,
                ),
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_isLoading || _successMessage != null) ? null : _updatePassword,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed),
                    child: _isLoading 
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: cs.surface, strokeWidth: 2))
                      : Text(AppL.of(context)!.passwordSave, style: TextStyle(color: cs.surface, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
      return isDesktop ? Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 800), child: inner)) : inner;
    });
  }
}
