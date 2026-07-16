import 'package:flutter/material.dart';
import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../models/social_provider.dart';
import '../../services/auth_service.dart';
import '../../services/privacy_consent_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/social_sign_in_helper.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/social_sign_in_buttons.dart';
import '../../widgets/modern_widgets.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  SocialProvider? _loadingProvider;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedLegal = false;

  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  static const Color _accentColor = JobsyColors.accentLight;

  bool get _busy => _isLoading || _loadingProvider != null;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedLegal) {
      await AppDialogs.showError(
        context,
        title: 'Agreement required',
        message:
            'Please accept the Terms of Service and Privacy Policy to create an account.',
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      await AuthService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
      );

      if (!mounted) return;
      await AppDialogs.showSuccess(
        context,
        title: 'Account Created',
        message: 'Your account has been created. Sign in to continue.',
        buttonLabel: 'Sign In',
      );

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.signin);
      }
    } catch (e) {
      if (!mounted) return;
      await AppDialogs.showError(
        context,
        title: 'Could not create account',
        message: friendlyErrorMessage(e),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSocialSignUp(SocialProvider provider) async {
    if (!_acceptedLegal) {
      await AppDialogs.showError(
        context,
        title: 'Agreement required',
        message:
            'Please accept the Terms of Service and Privacy Policy to continue.',
      );
      return;
    }
    await SocialSignInHelper.signIn(
      context,
      provider: provider,
      fromSignUp: true,
      setLoadingProvider: (p) {
        if (mounted) setState(() => _loadingProvider = p);
      },
    );
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
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: JobsyColors.textPrimary, size: 20),
                    onPressed: _busy ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SlideTransition(
                position: _slideUp,
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          const Text(
                            'Create your account',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: JobsyColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sign up with Google or email',
                            style: TextStyle(fontSize: 15, color: JobsyColors.textSecondary),
                          ),
                          const SizedBox(height: 24),
                          if (AuthService.hasSocialLogin) ...[
                            SocialSignInButtons(
                              loadingProvider: _loadingProvider,
                              onProviderTap: _busy ? (_) {} : _handleSocialSignUp,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(child: Divider(color: JobsyColors.border)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'or',
                                    style: TextStyle(
                                      color: JobsyColors.textTertiary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: JobsyColors.border)),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                          JobsyTextField(
                            controller: _nameController,
                            label: 'Full Name',
                            hint: 'Enter your full name',
                            prefixIcon: Icons.person_outline,
                            accentColor: _accentColor,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Full name is required';
                              }
                              if (value.trim().length < 2) {
                                return 'Name must be at least 2 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          JobsyTextField(
                            controller: _emailController,
                            label: 'Email',
                            hint: 'Enter your email',
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            accentColor: _accentColor,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Email is required';
                              }
                              return AppConstants.validateEmail(value);
                            },
                          ),
                          const SizedBox(height: 18),
                          JobsyTextField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: 'Minimum 6 characters',
                            prefixIcon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            accentColor: _accentColor,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: JobsyColors.textTertiary,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Password is required';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          JobsyTextField(
                            controller: _confirmPasswordController,
                            label: 'Confirm Password',
                            hint: 'Re-enter your password',
                            prefixIcon: Icons.lock_outline,
                            obscureText: _obscureConfirmPassword,
                            accentColor: _accentColor,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: JobsyColors.textTertiary,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                  () => _obscureConfirmPassword = !_obscureConfirmPassword),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _acceptedLegal,
                                  activeColor: _accentColor,
                                  onChanged: _busy
                                      ? null
                                      : (v) => setState(() => _acceptedLegal = v ?? false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Wrap(
                                  children: [
                                    const Text(
                                      'I agree to the ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: JobsyColors.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => PrivacyConsentService.openTerms(),
                                      child: Text(
                                        'Terms',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _accentColor,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    const Text(
                                      ' and ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: JobsyColors.textSecondary,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => PrivacyConsentService.openPrivacyPolicy(),
                                      child: Text(
                                        'Privacy Policy',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _accentColor,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    const Text(
                                      ' (Botswana Data Protection Act, 2024).',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: JobsyColors.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          JobsyGradientButton(
                            text: 'Create Account',
                            gradient: JobsyColors.brandGradient,
                            isLoading: _isLoading,
                            onPressed: _busy ? null : _handleSignup,
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () => Navigator.pushReplacementNamed(
                                        context,
                                        AppRoutes.signin,
                                      ),
                              child: RichText(
                                text: const TextSpan(
                                  text: 'Already have an account? ',
                                  style: TextStyle(
                                      fontSize: 14, color: JobsyColors.textSecondary),
                                  children: [
                                    TextSpan(
                                      text: 'Sign In',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: _accentColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
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
