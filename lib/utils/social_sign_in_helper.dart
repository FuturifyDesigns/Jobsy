import 'package:flutter/material.dart';

import '../models/social_provider.dart';
import '../services/auth_service.dart';
import '../utils/error_messages.dart';
import '../widgets/app_dialogs.dart';

/// Shared handler for Google sign-in taps.
class SocialSignInHelper {
  SocialSignInHelper._();

  static Future<void> signIn(
    BuildContext context, {
    required SocialProvider provider,
    required void Function(SocialProvider? loading) setLoadingProvider,
    bool fromSignUp = false,
  }) async {
    setLoadingProvider(provider);
    try {
      final result = await AuthService.signInWithSocial(
        provider,
        fromSignUp: fromSignUp,
      );

      if (!context.mounted || !provider.usesNativeFlow) return;

      if (fromSignUp && result.accountAlreadyExisted) {
        await AppDialogs.showSuccess(
          context,
          title: 'Account already exists',
          message: result.profileComplete
              ? 'This Google account is already registered. Signing you in now.'
              : 'This Google account is already registered. Let\'s finish your profile.',
          buttonLabel: 'Continue',
        );
      }

      if (context.mounted) {
        await AuthService.routeAfterSignIn(context);
      }
    } on SocialSignInCancelledException {
      // User dismissed native picker — no dialog.
    } catch (e) {
      if (context.mounted) {
        await AppDialogs.showError(
          context,
          title: '${provider.label} sign-in failed',
          message: friendlyErrorMessage(e),
        );
      }
    } finally {
      setLoadingProvider(null);
    }
  }
}
