import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/page_transitions.dart';
import '../screens/chat/chat_screen.dart';

class MessagingService {
  static final _client = Supabase.instance.client;

  /// Gets an existing conversation for this application, or creates one.
  static Future<Map<String, dynamic>> getOrCreateConversation({
    required String applicationId,
    required String jobId,
    required String employerId,
    required String workerId,
  }) async {
    // 1. Try to find existing conversation for this application
    final existing = await _client
        .from('conversations')
        .select()
        .eq('application_id', applicationId)
        .maybeSingle();

    if (existing != null) return existing;

    // 2. Create a new conversation
    final inserted = await _client
        .from('conversations')
        .insert({
          'application_id': applicationId,
          'job_id': jobId,
          'employer_id': employerId,
          'worker_id': workerId,
        })
        .select()
        .single();

    return inserted;
  }

  /// Ensures a [conversations] row exists (e.g. right after accept) without opening chat.
  static Future<void> ensureConversationExists({
    required String applicationId,
    required String jobId,
    required String employerId,
    required String workerId,
  }) async {
    await getOrCreateConversation(
      applicationId: applicationId,
      jobId: jobId,
      employerId: employerId,
      workerId: workerId,
    );
  }

  /// One-call helper: shows loading, gets/creates conversation, navigates to chat.
  static Future<void> openChat({
    required BuildContext context,
    required String applicationId,
    required String jobId,
    required String jobTitle,
    required String employerId,
    required String workerId,
    required String otherUserName,
    required bool isEmployer,
    String? otherUserAvatar,
  }) async {
    try {
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );

      final conversation = await getOrCreateConversation(
        applicationId: applicationId,
        jobId: jobId,
        employerId: employerId,
        workerId: workerId,
      );
      
      // Try to fetch avatar if not provided
      String? avatar = otherUserAvatar;
      if (avatar == null) {
        try {
          final otherId = isEmployer ? workerId : employerId;
          final profile = await _client
              .from('profiles')
              .select('avatar_url')
              .eq('id', otherId)
              .maybeSingle();
          avatar = profile?['avatar_url'];
        } catch (e) {
          debugPrint('Fetch avatar: $e');
        }
      }

      if (!context.mounted) return;
      Navigator.pop(context); // dismiss loading

      final otherUserId = isEmployer ? workerId : employerId;
      
      Navigator.push(
        context,
        JobsyPageRoute(
          page: ChatScreen(
            conversationId: conversation['id'],
            otherUserName: otherUserName,
            otherUserAvatar: avatar,
            otherUserId: otherUserId,
            jobTitle: jobTitle,
            isEmployer: isEmployer,
          ),
          transition: JobsyTransition.fadeSlide,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open chat. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
