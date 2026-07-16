import '../config/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps notification types to the Jobsy role they belong to.
class NotificationRole {
  NotificationRole._();

  static String label(String role) {
    switch (role) {
      case AppConstants.userTypeEmployer:
        return 'Employer';
      case AppConstants.userTypeWorker:
        return 'Worker';
      default:
        return 'Jobsy';
    }
  }

  static String shortLabel(String role) => label(role);

  /// Push / list prefix, e.g. "[Employer]".
  static String pushPrefix(String role) => '[${label(role)}]';

  /// Infer role from notification type when [target_role] is missing (legacy rows).
  static String? inferFromType(String type) {
    switch (type) {
      case 'new_application':
      case 'worker_withdrew':
        return AppConstants.userTypeEmployer;
      case 'application_accepted':
      case 'application_rejected':
      case 'application_cancelled':
      case 'new_job_posted':
      case 'job_match':
      case 'job_completed':
        return AppConstants.userTypeWorker;
      case 'candidate_match':
        return AppConstants.userTypeEmployer;
      case 'worker_done':
        return AppConstants.userTypeEmployer;
      default:
        return null;
    }
  }

  /// Resolve the role this notification belongs to (DB column → type → conversation).
  static Future<String?> resolve(
    Map<String, dynamic> payload,
    String myId,
  ) async {
    final explicit = payload['target_role'] as String?;
    if (explicit == AppConstants.userTypeEmployer ||
        explicit == AppConstants.userTypeWorker) {
      return explicit;
    }

    final type = payload['type'] as String? ?? '';
    final fromType = inferFromType(type);
    if (fromType != null) return fromType;

    if (type == 'new_message' ||
        type == 'worker_done' ||
        type == 'job_completed' ||
        type == 'new_rating') {
      final conversationId = payload['conversation_id'] as String? ??
          payload['related_conversation_id'] as String?;
      if (conversationId != null && conversationId.isNotEmpty) {
        return _roleFromConversation(conversationId, myId);
      }
    }

    if (type == 're_engagement' || type == 'system') {
      return _currentRole(myId);
    }

    return null;
  }

  static Future<String?> _roleFromConversation(
    String conversationId,
    String myId,
  ) async {
    try {
      final conv = await Supabase.instance.client
          .from('conversations')
          .select('employer_id, worker_id')
          .eq('id', conversationId)
          .maybeSingle();
      if (conv == null) return null;
      if (conv['employer_id'] == myId) return AppConstants.userTypeEmployer;
      if (conv['worker_id'] == myId) return AppConstants.userTypeWorker;
    } catch (_) {}
    return null;
  }

  static Future<String?> _currentRole(String myId) async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('user_type')
          .eq('id', myId)
          .maybeSingle();
      return profile?['user_type'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Role stored on a notification row (in-app list).
  static String? fromRow(Map<String, dynamic> row) {
    final explicit = row['target_role'] as String?;
    if (explicit == AppConstants.userTypeEmployer ||
        explicit == AppConstants.userTypeWorker) {
      return explicit;
    }
    return inferFromType(row['type'] as String? ?? '');
  }
}
