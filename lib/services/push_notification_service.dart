import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/colors.dart';

/// Top-level handler for background messages (must be top-level function).
/// Called when the app is terminated or in the background and a DATA message
/// (not notification-type) arrives from FCM.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] Background message: ${message.messageId}');
  // The notification is shown automatically by FCM for notification-type
  // messages. For data-only messages we'd show a local notification here,
  // but our Edge Function sends notification-type payloads, so this is
  // mostly a no-op safety net.
}

/// Manages FCM token registration, foreground notification display,
/// and tap-to-navigate handling.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService _instance = PushNotificationService._();
  static PushNotificationService get instance => _instance;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Callback set by the app to handle notification taps.
  /// Receives a Map<String, dynamic> payload with keys like
  /// 'type', 'conversation_id', 'job_id', 'application_id'.
  void Function(Map<String, dynamic> payload)? onNotificationTap;

  bool _initialized = false;

  // ─────────────────────────────────────────────────────────────────────
  // INITIALIZATION
  // ─────────────────────────────────────────────────────────────────────

  /// Call once from main() after Firebase.initializeApp().
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission (Android 13+ needs POST_NOTIFICATIONS runtime)
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // Set up local notifications for foreground display
    await _setupLocalNotifications();

    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification tap from terminated state
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTap(initialMessage);
      });
    }

    // Get and save token
    await _saveTokenToSupabase();

    // Listen for token refreshes
    _fcm.onTokenRefresh.listen((token) {
      _updateTokenInSupabase(token);
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // LOCAL NOTIFICATIONS SETUP (foreground display)
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _setupLocalNotifications() async {
    // Channel id must match MainActivity + AndroidManifest + Edge Function.
    final androidChannel = AndroidNotificationChannel(
      'jobsy_default_v4',
      'Jobsy Notifications',
      description: 'Job updates, messages, and activity from Jobsy',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: const RawResourceAndroidNotificationSound('soundreality_notification'),
    );

    // Create the channel on Android
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          try {
            final data = jsonDecode(details.payload!) as Map<String, dynamic>;
            onNotificationTap?.call(data);
          } catch (e) {
            debugPrint('[FCM] Failed to parse notification payload: $e');
          }
        }
      },
    );

    final iosPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // FOREGROUND MESSAGE HANDLING
  // ─────────────────────────────────────────────────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] Foreground message: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    // Show as a local notification so the user sees it
    _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'Jobsy',
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'jobsy_default_v4',
          'Jobsy Notifications',
          channelDescription: 'Job updates, messages, and activity from Jobsy',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: JobsyColors.employerPrimary,
          enableVibration: true,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('soundreality_notification'),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // NOTIFICATION TAP HANDLING
  // ─────────────────────────────────────────────────────────────────────

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM] Notification tapped: ${message.data}');
    onNotificationTap?.call(message.data);
  }

  // ─────────────────────────────────────────────────────────────────────
  // FCM TOKEN → SUPABASE
  // ─────────────────────────────────────────────────────────────────────

  /// Get the FCM token and save it to the user's profile in Supabase.
  Future<void> _saveTokenToSupabase() async {
    try {
      final token = await _fcm.getToken();
      if (token == null) {
        debugPrint('[FCM] No token available');
        return;
      }
      debugPrint('[FCM] Token: ${token.substring(0, 20)}...');
      await _updateTokenInSupabase(token);
    } catch (e) {
      debugPrint('[FCM] Error getting token: $e');
    }
  }

  Future<void> _updateTokenInSupabase(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.from('profiles').update({
        'fcm_token': token,
        'device_platform': Platform.isAndroid ? 'android' : 'ios',
      }).eq('id', userId);

      debugPrint('[FCM] Token saved to Supabase');
    } catch (e) {
      debugPrint('[FCM] Error saving token: $e');
    }
  }

  /// Call on sign-out to clear the token so the user stops receiving pushes.
  Future<void> clearToken() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.from('profiles').update({
        'fcm_token': null,
      }).eq('id', userId);

      await _fcm.deleteToken();
      debugPrint('[FCM] Token cleared');
    } catch (e) {
      debugPrint('[FCM] Error clearing token: $e');
    }
  }

  /// Re-register token after sign-in (call from auth state listener).
  Future<void> onSignIn() async {
    await _saveTokenToSupabase();
  }
}
