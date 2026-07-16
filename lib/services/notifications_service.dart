import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/constants.dart';
import '../utils/notification_role.dart';

/// Central service for working with the notifications table.
class NotificationsService {
  static final _client = Supabase.instance.client;

  /// Live stream of the current user's notifications, newest first.
  static Stream<List<Map<String, dynamic>>> streamMine({
    String? roleFilter,
  }) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) {
          if (roleFilter == null) return rows;
          return rows
              .where((r) => NotificationRole.fromRow(r) == roleFilter)
              .toList();
        });
  }

  /// Unread count — all roles (one inbox per user account).
  static Stream<int> streamUnreadCount() {
    return streamMine().map(
      (rows) => rows.where((r) => r['is_read'] == false).length,
    );
  }

  /// Unread count for notifications targeting [role] only.
  static Stream<int> streamUnreadCountForRole(String role) {
    return streamMine(roleFilter: role).map(
      (rows) => rows.where((r) => r['is_read'] == false).length,
    );
  }

  /// Unread count for the opposite role (badge hint on bell).
  static Stream<int> streamOtherRoleUnreadCount(bool isEmployer) {
    final role = isEmployer
        ? AppConstants.userTypeWorker
        : AppConstants.userTypeEmployer;
    return streamUnreadCountForRole(role);
  }

  static Future<void> markAsRead(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('markAsRead error: $e');
    }
  }

  static Future<void> markAllAsRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('markAllAsRead error: $e');
    }
  }

  static Future<void> delete(String notificationId) async {
    try {
      await _client.from('notifications').delete().eq('id', notificationId);
    } catch (e) {
      debugPrint('delete notification error: $e');
    }
  }

  static Future<void> clearAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.from('notifications').delete().eq('user_id', userId);
    } catch (e) {
      debugPrint('clearAll error: $e');
    }
  }
}
