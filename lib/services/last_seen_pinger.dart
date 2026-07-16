import 'package:supabase_flutter/supabase_flutter.dart';

/// Event-based last_seen_at ping.
///
/// Call from: app start (after session resolves), conversations list mount,
/// message send. Deliberately NOT called on timer — we want writes to scale
/// with real activity, not real time.
///
/// Cheap: single UPDATE on profiles.last_seen_at. Fire and forget; errors are
/// swallowed because a failed ping is not worth breaking the user flow.
class LastSeenPinger {
  static DateTime? _lastPing;

  /// Safe to call arbitrarily often — throttled to once per minute.
  /// If the user spam-opens screens, we still write at most ~1x/min.
  static Future<void> ping() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    final now = DateTime.now();
    if (_lastPing != null &&
        now.difference(_lastPing!).inSeconds < 60) {
      return;
    }
    _lastPing = now;

    try {
      await client
          .from('profiles')
          .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uid);
    } catch (_) {
      // Swallow — a failed ping is harmless.
    }
  }
}
