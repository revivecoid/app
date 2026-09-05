import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../../../../app_router.dart';

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key});

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
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    if (_passwordController.text.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; _successMessage = null; });
    
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      
      setState(() => _successMessage = 'Password updated successfully!');
      
      // Clear the recovery state
      ref.read(passwordRecoveryProvider.notifier).state = false;
      
      // Give the user a moment to read the success message before redirecting
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.go('/');
      });
      
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to update password: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.sleekBlack;
    final bgColor = isDark ? AppColors.sleekBlack : Colors.grey[50];
    final surfaceColor = isDark ? AppColors.surface : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: const ReVAppBar(
        title: Text('Update Password'),
      ),
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
                const Icon(Icons.lock_reset, size: 64, color: AppColors.fireRed),
                const SizedBox(height: 16),
                Text('Secure Your Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('Please enter a new password below.', style: TextStyle(color: AppColors.daysGray), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    color: Colors.red.withValues(alpha: 0.1),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                
                if (_successMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    color: Colors.green.withValues(alpha: 0.1),
                    child: Text(_successMessage!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),

                TextField(
                  controller: _passwordController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'New Password', 
                    labelStyle: const TextStyle(color: AppColors.daysGray),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.daysGray.withValues(alpha: 0.5)))
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password', 
                    labelStyle: const TextStyle(color: AppColors.daysGray),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.daysGray.withValues(alpha: 0.5)))
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
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('SAVE PASSWORD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
