import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/constants.dart';
import '../config/env.dart';
import '../config/routes.dart';
import '../models/social_provider.dart';
import '../utils/secure_log.dart';

/// User dismissed the Google sign-in sheet.
class SocialSignInCancelledException implements Exception {}

/// Google Sign-In is not configured in this build.
class SocialSignInNotConfiguredException implements Exception {
  final String message;
  SocialSignInNotConfiguredException(this.message);
}

@Deprecated('Use SocialSignInCancelledException')
typedef GoogleSignInCancelledException = SocialSignInCancelledException;

@Deprecated('Use SocialSignInNotConfiguredException')
typedef GoogleSignInNotConfiguredException = SocialSignInNotConfiguredException;

/// Result of a Google / social sign-in attempt.
class SocialSignInResult {
  final bool accountAlreadyExisted;
  final bool profileComplete;

  const SocialSignInResult({
    required this.accountAlreadyExisted,
    required this.profileComplete,
  });
}

/// Central auth — email, Google, profile bootstrap, routing.
class AuthService {
  AuthService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static bool get hasSocialLogin => availableSocialProviders.isNotEmpty;

  @Deprecated('Use SocialProvider.google.isConfigured')
  static bool get isGoogleSignInAvailable => SocialProvider.google.isConfigured;

  static GoogleSignIn _googleSignIn() {
    final webClientId = Env.googleWebClientId;
    if (webClientId.isEmpty) {
      throw SocialSignInNotConfiguredException(
        'Google Sign-In is not configured yet. Use email sign-in for now.',
      );
    }
    return GoogleSignIn(
      serverClientId: webClientId,
      scopes: const ['email', 'profile'],
    );
  }

  static Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw AuthException('Account could not be created. Please try again.');
    }

    await _createProfileIfNeeded(
      userId: user.id,
      email: email.trim(),
      fullName: fullName.trim(),
    );
  }

  static Future<SocialSignInResult> signInWithSocial(
    SocialProvider provider, {
    bool fromSignUp = false,
  }) async {
    if (provider != SocialProvider.google) {
      return const SocialSignInResult(
        accountAlreadyExisted: false,
        profileComplete: false,
      );
    }
    return signInWithGoogle(fromSignUp: fromSignUp);
  }

  static Future<SocialSignInResult> signInWithGoogle({
    bool fromSignUp = false,
  }) async {
    if (!SocialProvider.google.isConfigured) {
      throw SocialSignInNotConfiguredException(
        'Google Sign-In is not configured in this build yet. Use email instead.',
      );
    }

    final googleSignIn = _googleSignIn();
    await googleSignIn.signOut();

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) throw SocialSignInCancelledException();

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw AuthException('Google Sign-In failed. Please try again.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );

    final user = _client.auth.currentUser;
    if (user == null) {
      throw AuthException('Google Sign-In failed. Please try again.');
    }

    final existingProfile = await _client
        .from('profiles')
        .select('id, is_profile_complete')
        .eq('id', user.id)
        .maybeSingle();

    final accountAlreadyExisted = existingProfile != null;
    final profileComplete =
        existingProfile?['is_profile_complete'] as bool? ?? false;

    await _finalizeSocialSession(
      fallbackEmail: googleUser.email,
      fallbackName: googleUser.displayName,
    );

    return SocialSignInResult(
      accountAlreadyExisted: accountAlreadyExisted,
      profileComplete: profileComplete,
    );
  }

  /// Reserved for future OAuth providers via deep link.
  static Future<void> finalizeOAuthSession() async {
    await _finalizeSocialSession();
  }

  static Future<void> _finalizeSocialSession({
    String? fallbackEmail,
    String? fallbackName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _createProfileIfNeeded(
      userId: user.id,
      email: user.email ?? fallbackEmail ?? '',
      fullName: _resolveDisplayName(user, fallbackName),
    );
  }

  static String _resolveDisplayName(User user, String? fallbackName) {
    final meta = user.userMetadata;
    final fromMeta = meta?['full_name'] ?? meta?['name'];
    if (fromMeta is String && fromMeta.trim().isNotEmpty) return fromMeta.trim();
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      return fallbackName.trim();
    }
    return 'User';
  }

  static Future<void> _createProfileIfNeeded({
    required String userId,
    required String email,
    required String fullName,
  }) async {
    final existing = await _client
        .from('profiles')
        .select('id')
        .eq('id', userId)
        .maybeSingle();

    if (existing != null) return;

    await _client.rpc(
      'create_profile_for_user',
      params: {
        'user_id': userId,
        'user_email': email,
        'user_full_name': fullName.isNotEmpty ? fullName : 'User',
        'user_type': AppConstants.userTypeWorker,
      },
    );
  }

  static Future<void> routeAfterSignIn(BuildContext context) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || !context.mounted) return;

    try {
      await _finalizeSocialSession();

      var profile = await _client
          .from('profiles')
          .select('is_profile_complete, user_type')
          .eq('id', userId)
          .maybeSingle();

      if (!context.mounted) return;

      final isComplete = profile?['is_profile_complete'] as bool? ?? false;
      if (!isComplete) {
        Navigator.pushReplacementNamed(context, AppRoutes.profileSetup);
        return;
      }

      final userType = profile?['user_type'] as String?;
      final route = userType == AppConstants.userTypeEmployer
          ? AppRoutes.employerHome
          : AppRoutes.workerHome;
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    } catch (e) {
      secureLog('Post sign-in routing failed', error: e);
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.profileSetup);
      }
    }
  }

  static Future<void> signOut() async {
    try {
      if (SocialProvider.google.isConfigured) {
        await _googleSignIn().signOut();
      }
    } catch (_) {}
    await _client.auth.signOut();
  }
}
