import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../models/social_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/social_sign_in_helper.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/social_sign_in_buttons.dart';
import '../../widgets/modern_widgets.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  SocialProvider? _loadingProvider;
  bool _obscurePassword = true;

  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(seconds: 30);

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
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  bool get _isLockedOut =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isLockedOut) {
      final remaining = _lockedUntil!.difference(DateTime.now()).inSeconds;
      await AppDialogs.showError(
        context,
        title: 'Too many attempts',
        message: 'Please wait $remaining seconds before trying again.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      _failedAttempts = 0;
      _lockedUntil = null;

      if (mounted) await AuthService.routeAfterSignIn(context);
    } on AuthException catch (e) {
      _failedAttempts++;
      if (_failedAttempts >= _maxAttempts) {
        _lockedUntil = DateTime.now().add(_lockoutDuration);
        _failedAttempts = 0;
        if (mounted) {
          await AppDialogs.showError(
            context,
            title: 'Too many attempts',
            message:
                'Please wait ${_lockoutDuration.inSeconds} seconds before trying again.',
          );
        }
      } else if (mounted) {
        await AppDialogs.showError(
          context,
          title: 'Sign in failed',
          message: friendlyAuthErrorMessage(e),
        );
      }
    } catch (e) {
      if (mounted) {
        await AppDialogs.showError(
          context,
          title: 'Sign in failed',
          message: friendlyErrorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSocialSignIn(SocialProvider provider) async {
    await SocialSignInHelper.signIn(
      context,
      provider: provider,
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
                    onPressed: _busy
                        ? null
                        : () => Navigator.pushNamedAndRemoveUntil(
                              context,
                              AppRoutes.welcome,
                              (route) => false,
                            ),
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
                          const SizedBox(height: 16),
                          Center(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _accentColor.withOpacity(0.15),
                                    blurRadius: 30,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/logo/logo_full.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'Welcome back',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: JobsyColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sign in with Google or email',
                            style: TextStyle(fontSize: 15, color: JobsyColors.textSecondary),
                          ),
                          const SizedBox(height: 28),
                          if (AuthService.hasSocialLogin) ...[
                            SocialSignInButtons(
                              loadingProvider: _loadingProvider,
                              onProviderTap: _busy ? (_) {} : _handleSocialSignIn,
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
                          const SizedBox(height: 20),
                          JobsyTextField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: 'Enter your password',
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
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () => Navigator.pushNamed(
                                        context,
                                        AppRoutes.forgotPassword,
                                      ),
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _accentColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          JobsyGradientButton(
                            text: 'Sign In',
                            gradient: JobsyColors.brandGradient,
                            isLoading: _isLoading,
                            onPressed: _busy ? null : _handleSignIn,
                          ),
                          const SizedBox(height: 28),
                          Center(
                            child: GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () => Navigator.pushReplacementNamed(
                                        context,
                                        AppRoutes.signup,
                                      ),
                              child: RichText(
                                text: const TextSpan(
                                  text: 'Don\'t have an account? ',
                                  style: TextStyle(
                                      fontSize: 14, color: JobsyColors.textSecondary),
                                  children: [
                                    TextSpan(
                                      text: 'Sign Up',
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
