import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/page_transitions.dart';
import '../config/routes.dart';
import '../config/navigator_key.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/employer/job_applications_screen.dart';
import '../utils/notification_role.dart';
import '../utils/notification_role_switch.dart';

/// Routes the user to the screen that matches a notification payload.
/// Switches role first when the notification targets a different mode.
Future<void> navigateFromNotification(
  Map<String, dynamic> payload, {
  BuildContext? context,
}) async {
  final client = Supabase.instance.client;
  final myId = client.auth.currentUser?.id;
  if (myId == null) return;

  final type = payload['type'] as String? ?? '';
  final conversationId = payload['conversation_id'] as String? ??
      payload['related_conversation_id'] as String?;
  final jobId = payload['job_id'] as String? ??
      payload['related_job_id'] as String?;

  try {
    final targetRole = await NotificationRole.resolve(payload, myId);
    if (targetRole != null) {
      await ensureRoleForNotification(targetRole, context: context);
    }

    if (type == 'new_message' ||
        type == 'worker_done' ||
        type == 'job_completed' ||
        type == 'new_rating') {
      if (conversationId != null && conversationId.isNotEmpty) {
        await openChatFromNotification(conversationId, myId);
        return;
      }
    }

    if (type == 'new_application' || type == 'worker_withdrew') {
      if (jobId != null && jobId.isNotEmpty) {
        await _openEmployerJobApplications(jobId);
        return;
      }
      await _goHome(isEmployer: true);
      return;
    }

    if (type == 'application_accepted' ||
        type == 'application_rejected' ||
        type == 'application_cancelled') {
      await _goHome(isEmployer: false, initialTab: 1);
      return;
    }

    if (type == 'new_job_posted' || type == 'job_match') {
      await _goHome(isEmployer: false, initialTab: 0);
      return;
    }

    if (type == 'candidate_match') {
      if (jobId != null && jobId.isNotEmpty) {
        await _openEmployerJobApplications(jobId);
        return;
      }
      await _goHome(isEmployer: true);
      return;
    }

    if (type == 're_engagement') {
      final profile = await client
          .from('profiles')
          .select('user_type')
          .eq('id', myId)
          .maybeSingle();
      await _goHome(isEmployer: profile?['user_type'] == 'employer');
      return;
    }

    final profile = await client
        .from('profiles')
        .select('user_type')
        .eq('id', myId)
        .maybeSingle();
    await _goHome(isEmployer: profile?['user_type'] == 'employer');
  } catch (e) {
    debugPrint('[NotificationNav] Error: $e');
  }
}

Future<void> openChatFromNotification(String conversationId, String myId) async {
  final client = Supabase.instance.client;

  final conv = await client
      .from('conversations')
      .select('*, job:jobs(title)')
      .eq('id', conversationId)
      .maybeSingle();
  if (conv == null) return;

  final isEmployer = conv['employer_id'] == myId;
  final otherId = isEmployer ? conv['worker_id'] : conv['employer_id'];

  final profile = await client
      .from('profiles')
      .select('full_name, avatar_url')
      .eq('id', otherId)
      .maybeSingle();

  final jobTitle = (conv['job'] as Map?)?['title']?.toString() ?? 'Job';
  final homeRoute = isEmployer ? AppRoutes.employerHome : AppRoutes.workerHome;

  navigatorKey.currentState?.pushNamedAndRemoveUntil(
    homeRoute,
    (route) => false,
  );

  await Future.delayed(const Duration(milliseconds: 300));

  navigatorKey.currentState?.push(
    JobsyPageRoute(
      page: ChatScreen(
        conversationId: conversationId,
        otherUserName: profile?['full_name'] ?? 'User',
        otherUserAvatar: profile?['avatar_url']?.toString(),
        otherUserId: otherId,
        jobTitle: jobTitle,
        isEmployer: isEmployer,
      ),
      transition: JobsyTransition.fadeSlide,
    ),
  );
}

Future<void> _openEmployerJobApplications(String jobId) async {
  final client = Supabase.instance.client;
  final job = await client
      .from('jobs')
      .select('id, title')
      .eq('id', jobId)
      .maybeSingle();
  if (job == null) return;

  navigatorKey.currentState?.pushNamedAndRemoveUntil(
    AppRoutes.employerHome,
    (route) => false,
  );

  await Future.delayed(const Duration(milliseconds: 300));

  navigatorKey.currentState?.push(
    JobsyPageRoute(
      page: JobApplicationsScreen(
        jobId: jobId,
        jobTitle: job['title']?.toString() ?? 'Job',
      ),
      transition: JobsyTransition.fadeSlide,
    ),
  );
}

Future<void> _goHome({required bool isEmployer, int initialTab = 0}) async {
  final route = isEmployer ? AppRoutes.employerHome : AppRoutes.workerHome;
  navigatorKey.currentState?.pushNamedAndRemoveUntil(
    route,
    (route) => false,
    arguments: {'initialTab': initialTab},
  );
}
