import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/constants.dart';
import '../config/routes.dart';
import '../screens/onboarding/onboarding_tutorial_screen.dart';

/// Tracks whether the first-run product tutorial has been shown.
class OnboardingTutorialService {
  OnboardingTutorialService._();

  static String _keyFor(String userId) => 'onboarding_tutorial_done_$userId';

  static Future<bool> hasCompleted() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFor(userId)) ?? false;
  }

  static Future<void> markCompleted() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFor(userId), true);
  }

  static String homeRouteFor(String userType) {
    return userType == AppConstants.userTypeEmployer
        ? AppRoutes.employerHome
        : AppRoutes.workerHome;
  }

  static Future<void> replay(BuildContext context, String userType) async {
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OnboardingTutorialScreen(
          userType: userType,
          isReplay: true,
        ),
      ),
    );
  }

  /// Opens the tutorial if this signed-in user has not finished it yet.
  static Future<void> maybeShow(BuildContext context) async {
    if (!context.mounted) return;
    if (await hasCompleted()) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('user_type, is_profile_complete')
          .eq('id', userId)
          .maybeSingle();

      if (!context.mounted) return;

      final isComplete = profile?['is_profile_complete'] as bool? ?? false;
      if (!isComplete) return;

      final userType = profile?['user_type'] as String? ?? AppConstants.userTypeWorker;

      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => OnboardingTutorialScreen(userType: userType),
        ),
      );
    } catch (_) {}
  }
}
