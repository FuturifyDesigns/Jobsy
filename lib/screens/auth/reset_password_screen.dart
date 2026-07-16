import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/colors.dart';
import '../../config/routes.dart';
import '../../services/auth_deep_link_service.dart';
import '../../utils/error_messages.dart';
import '../../widgets/modern_widgets.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _currentPassword;
  bool _fromRecoveryLink = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _currentPassword = args?['currentPassword'];
    _fromRecoveryLink = args?['fromRecoveryLink'] == true;
  }
  
  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
  
  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text),
      );
      
      if (mounted) {
        AuthDeepLinkService.clearRecoveryFlow();
        await Supabase.instance.client.auth.signOut();
        
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: JobsyColors.surfaceLight,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: JobsyColors.success.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: JobsyColors.success, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Password Updated',
                  style: TextStyle(color: JobsyColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            content: const Text(
              'Your password has been updated. Sign in with your new password.',
              style: TextStyle(fontSize: 15, color: JobsyColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamedAndRemoveUntil(context, AppRoutes.signin, (route) => false);
                },
                child: const Text('Sign In',
                  style: TextStyle(color: JobsyColors.success, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyAuthErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password update failed. Please try again.'),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  if (!_fromRecoveryLink)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: JobsyColors.textPrimary, size: 20),
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context, AppRoutes.signin, (route) => false),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: JobsyColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.vpn_key, color: JobsyColors.success, size: 28),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      Text(
                        _fromRecoveryLink ? 'Set New Password' : 'New Password',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                          color: JobsyColors.textPrimary, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _fromRecoveryLink
                            ? 'Choose a new password for your account.'
                            : 'Create a strong new password for your account.',
                        style: const TextStyle(fontSize: 15, color: JobsyColors.textSecondary, height: 1.4),
                      ),
                      
                      const SizedBox(height: 36),
                      
                      JobsyTextField(
                        controller: _newPasswordController,
                        label: 'New Password',
                        hint: 'Minimum 6 characters',
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscureNew,
                        accentColor: JobsyColors.success,
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: JobsyColors.textTertiary, size: 20),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Password is required';
                          if (value.length < 6) return 'Must be at least 6 characters';
                          if (!_fromRecoveryLink &&
                              _currentPassword != null &&
                              value == _currentPassword) {
                            return 'New password must be different';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 20),
                      
                      JobsyTextField(
                        controller: _confirmPasswordController,
                        label: 'Confirm New Password',
                        hint: 'Re-enter your new password',
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscureConfirm,
                        accentColor: JobsyColors.success,
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: JobsyColors.textTertiary, size: 20),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Please confirm password';
                          if (value != _newPasswordController.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 32),
                      
                      JobsyGradientButton(
                        text: 'Update Password',
                        gradient: const [JobsyColors.success, Color(0xFF059669)],
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _handleResetPassword,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
