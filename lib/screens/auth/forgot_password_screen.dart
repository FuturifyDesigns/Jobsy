import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../utils/error_messages.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/modern_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
  
  Future<void> _handleSendResetLink() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: AppConstants.authResetPasswordRedirect,
      );
      
      if (mounted) {
        setState(() => _emailSent = true);
      }
    } on AuthException catch (e) {
      if (mounted) {
        await AppDialogs.showError(
          context,
          title: 'Could not send reset link',
          message: friendlyAuthErrorMessage(e),
        );
      }
    } catch (_) {
      if (mounted) {
        await AppDialogs.showError(
          context,
          title: 'Could not send reset link',
          message: 'Please check your connection and try again.',
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
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: JobsyColors.textPrimary, size: 20),
                    onPressed: () => Navigator.pop(context),
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
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: JobsyColors.warning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.lock_reset, color: JobsyColors.warning, size: 28),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      Text(
                        _emailSent ? 'Check your email' : 'Reset Password',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: JobsyColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _emailSent
                            ? 'We sent a password reset link to ${_emailController.text.trim()}. Open the link in your email to set a new password.'
                            : 'Enter your email and we\'ll send you a link to reset your password.',
                        style: const TextStyle(fontSize: 15, color: JobsyColors.textSecondary, height: 1.4),
                      ),
                      
                      if (!_emailSent) ...[
                        const SizedBox(height: 36),
                        
                        JobsyTextField(
                          controller: _emailController,
                          label: 'Email',
                          hint: 'Enter your email',
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          accentColor: JobsyColors.warning,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Email is required';
                            if (AppConstants.validateEmail(value) != null) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        
                        const SizedBox(height: 32),
                        
                        JobsyGradientButton(
                          text: 'Send Reset Link',
                          gradient: const [JobsyColors.warning, Color(0xFFD97706)],
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _handleSendResetLink,
                        ),
                      ] else ...[
                        const SizedBox(height: 32),
                        JobsyGradientButton(
                          text: 'Back to Sign In',
                          gradient: const [JobsyColors.warning, Color(0xFFD97706)],
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            AppRoutes.signin,
                            (route) => false,
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 24),
                      
                      if (!_emailSent)
                        Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              'Back to Sign In',
                              style: TextStyle(fontSize: 14, color: JobsyColors.textSecondary, fontWeight: FontWeight.w600),
                            ),
                          ),
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
