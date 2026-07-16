import 'package:flutter/material.dart';

import '../config/env.dart';

/// Google is the only social login provider enabled for now.
enum SocialProvider {
  google,
}

extension SocialProviderX on SocialProvider {
  String get label => 'Google';

  String get buttonLabel => 'Continue with Google';

  IconData get icon => Icons.g_mobiledata_rounded;

  Color get brandColor => const Color(0xFF4285F4);

  Color get foregroundColor => const Color(0xFF1F1F1F);

  Color get backgroundColor => Colors.white;

  /// Native Google Sign-In completes in-app (no browser redirect).
  bool get usesNativeFlow => true;

  bool get isConfigured => Env.googleWebClientId.isNotEmpty;

  bool get isAvailable => true;
}

List<SocialProvider> get availableSocialProviders => SocialProvider.values;
