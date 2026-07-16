import 'package:flutter/material.dart';
import '../screens/splash_screen.dart';
import '../screens/welcome_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/signin_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import '../screens/auth/phone_verification_screen.dart';
import '../screens/auth/email_verification_screen.dart';
import '../screens/auth/profile_setup_screen.dart';
import '../screens/employer/employer_home_screen.dart';
import '../screens/worker/worker_home_screen.dart';
import '../screens/worker/external_jobs_screen.dart';
import '../screens/onboarding/onboarding_tutorial_screen.dart';
import '../config/constants.dart';

class AppRoutes {
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String signup = '/signup';
  static const String signin = '/signin';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String phoneVerification = '/phone-verification';
  static const String emailVerification = '/email-verification';
  static const String profileSetup = '/profile-setup';
  static const String employerHome = '/employer-home';
  static const String workerHome = '/worker-home';
  static const String externalJobs = '/external-jobs';
  static const String onboardingTutorial = '/onboarding-tutorial';
  
  static Map<String, WidgetBuilder> get routes => {
    splash: (context) => const SplashScreen(),
    welcome: (context) => const WelcomeScreen(),
    signup: (context) => const SignUpScreen(),
    signin: (context) => const SignInScreen(),
    forgotPassword: (context) => const ForgotPasswordScreen(),
    resetPassword: (context) => const ResetPasswordScreen(),
    phoneVerification: (context) => const PhoneVerificationScreen(),
    emailVerification: (context) => const EmailVerificationScreen(),
    profileSetup: (context) => const ProfileSetupScreen(),
    employerHome: (context) => const EmployerHomeScreen(),
    workerHome: (context) => const WorkerHomeScreen(),
    externalJobs: (context) => const ExternalJobsScreen(),
    onboardingTutorial: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final userType = args is Map ? args['userType'] as String? : null;
      return OnboardingTutorialScreen(
        userType: userType ?? AppConstants.userTypeWorker,
      );
    },
  };
  
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = routes[settings.name];
    if (builder != null) {
      return PageRouteBuilder(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) => builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
      );
    }
    return MaterialPageRoute(builder: (context) => const SplashScreen());
  }
}
