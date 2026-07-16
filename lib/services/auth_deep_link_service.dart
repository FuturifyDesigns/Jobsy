import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/constants.dart';
import '../config/navigator_key.dart';
import '../config/routes.dart';
import '../services/auth_service.dart';
import '../utils/secure_log.dart';

/// Handles Supabase auth deep links such as `jobsy://reset-password?code=...`.
class AuthDeepLinkService {
  AuthDeepLinkService._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _subscription;
  static bool _pendingPasswordRecovery = false;
  static bool _inRecoveryFlow = false;

  /// True while a password-recovery deep link is being processed.
  static bool get pendingPasswordRecovery => _pendingPasswordRecovery;

  /// True after a recovery link opens until the user finishes resetting.
  static bool get inRecoveryFlow => _inRecoveryFlow;

  /// Returns true once if splash/auth routing should open reset password.
  static bool consumePasswordRecovery() {
    if (!_pendingPasswordRecovery) return false;
    _pendingPasswordRecovery = false;
    return true;
  }

  static void clearRecoveryFlow() {
    _inRecoveryFlow = false;
    _pendingPasswordRecovery = false;
  }

  static Future<void> initialize() async {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      await _handleUri(initialUri);
    }

    await _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object e) => debugPrint('[AuthDeepLink] stream error: $e'),
    );
  }

  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static bool _isLoginCallbackUri(Uri uri) {
    return uri.host == 'login-callback' ||
        uri.path.contains('login-callback');
  }

  static bool _isAuthUri(Uri uri) {
    if (uri.scheme != 'jobsy') return false;
    return uri.queryParameters.containsKey('code') ||
        uri.fragment.contains('access_token') ||
        uri.fragment.contains('error_description') ||
        _isPasswordResetUri(uri) ||
        _isLoginCallbackUri(uri);
  }

  static bool _isPasswordResetUri(Uri uri) {
    return uri.host == 'reset-password' ||
        uri.path.contains('reset-password') ||
        uri.toString().contains('reset-password');
  }

  static Future<void> _handleUri(Uri uri) async {
    if (!_isAuthUri(uri)) return;

    if (_isPasswordResetUri(uri)) {
      _pendingPasswordRecovery = true;
      _inRecoveryFlow = true;
    }

    try {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      if (_isPasswordResetUri(uri)) {
        navigateToResetPassword();
      } else if (_isLoginCallbackUri(uri) ||
          Supabase.instance.client.auth.currentSession != null) {
        await AuthService.finalizeOAuthSession();
        _navigateAfterOAuth();
      }
    } on AuthException catch (e) {
      clearRecoveryFlow();
      secureLog('[AuthDeepLink] Auth error', error: e.message);
    } catch (e) {
      clearRecoveryFlow();
      secureLog('[AuthDeepLink] Error', error: e);
    }
  }

  static void _navigateAfterOAuth() {
    void go() {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        AuthService.routeAfterSignIn(ctx);
      }
    }

    if (navigatorKey.currentContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    } else {
      go();
    }
  }

  static void navigateToResetPassword() {
    _pendingPasswordRecovery = true;
    _inRecoveryFlow = true;

    void pushResetRoute() {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.resetPassword,
        (route) => false,
        arguments: {'fromRecoveryLink': true},
      );
      _pendingPasswordRecovery = false;
    }

    if (navigatorKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => pushResetRoute());
    } else {
      pushResetRoute();
    }
  }
}
