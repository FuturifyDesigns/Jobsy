import 'package:flutter/material.dart';
import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../config/page_transitions.dart';
import '../../services/notifications_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/notification_navigation.dart';
import '../../utils/notification_role.dart';

/// Full notifications screen — shows alerts for both roles on one account.
class NotificationsScreen extends StatefulWidget {
  final bool isEmployer;

  const NotificationsScreen({super.key, required this.isEmployer});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// null = all roles
  String? _roleFilter;

  bool get isEmployer => widget.isEmployer;

  Color get _accent =>
      isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;

  List<Color> get _gradient =>
      isEmployer ? JobsyColors.employerGradient : JobsyColors.workerGradient;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      appBar: AppBar(
        backgroundColor: JobsyColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: JobsyColors.textPrimary,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Color(0xFFE2E8F0),
              Color(0xFF94A3B8),
              Color(0xFFE2E8F0),
            ],
            stops: [0.0, 0.5, 1.0],
          ).createShader(bounds),
          child: const Text(
            'Notifications',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all read',
            onPressed: () async {
              await NotificationsService.markAllAsRead();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All notifications marked as read'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          PopupMenuButton<String>(
            color: JobsyColors.surfaceLight,
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: JobsyColors.border.withOpacity(0.4),
                width: 0.6,
              ),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded,
                        size: 18, color: Color(0xFFEF4444)),
                    SizedBox(width: 10),
                    Text('Clear all',
                        style: TextStyle(color: JobsyColors.textPrimary)),
                  ],
                ),
              ),
            ],
            onSelected: (v) async {
              if (v == 'clear') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: JobsyColors.surfaceLight,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    title: const Text(
                      'Clear all notifications?',
                      style: TextStyle(
                        color: JobsyColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    content: const Text(
                      'This cannot be undone.',
                      style: TextStyle(
                        color: JobsyColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          foregroundColor: JobsyColors.textSecondary,
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Clear',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await NotificationsService.clearAll();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All notifications cleared'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _RoleFilterBar(
              accent: _accent,
              roleFilter: _roleFilter,
              onChanged: (value) => setState(() => _roleFilter = value),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: NotificationsService.streamMine(roleFilter: _roleFilter),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildError(friendlyStreamError(snapshot.error));
                }
                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: _accent),
                  );
                }
                final notifications = snapshot.data!;
                if (notifications.isEmpty) {
                  return _buildEmpty();
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final n = notifications[index];
                    return AnimatedListItem(
                      index: index,
                      child: _NotificationTile(
                        notification: n,
                        accent: _accent,
                        gradient: _gradient,
                        onTap: () => _handleTap(context, n),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: JobsyColors.textTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load notifications',
              style: TextStyle(
                color: JobsyColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              err,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: JobsyColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: JobsyColors.surfaceLight,
                border: Border.all(
                  color: _accent.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 42,
                color: _accent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "You're all caught up",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: JobsyColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'New messages and updates from both Worker and Employer modes appear here.',
              style: TextStyle(
                fontSize: 14,
                color: JobsyColors.textTertiary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(
      BuildContext context, Map<String, dynamic> notification) async {
    final id = notification['id']?.toString();
    if (id != null && notification['is_read'] == false) {
      NotificationsService.markAsRead(id);
    }

    final payload = <String, dynamic>{
      'type': notification['type'] as String? ?? '',
      if (notification['target_role'] != null)
        'target_role': notification['target_role'].toString(),
      if (notification['related_conversation_id'] != null)
        'conversation_id': notification['related_conversation_id'].toString(),
      if (notification['related_job_id'] != null)
        'job_id': notification['related_job_id'].toString(),
      if (notification['related_application_id'] != null)
        'application_id': notification['related_application_id'].toString(),
    };

    await navigateFromNotification(payload, context: context);
  }
}

class _RoleFilterBar extends StatelessWidget {
  final Color accent;
  final String? roleFilter;
  final ValueChanged<String?> onChanged;

  const _RoleFilterBar({
    required this.accent,
    required this.roleFilter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('All', null),
          const SizedBox(width: 8),
          _chip('Worker', AppConstants.userTypeWorker),
          const SizedBox(width: 8),
          _chip('Employer', AppConstants.userTypeEmployer),
        ],
      ),
    );
  }

  Widget _chip(String label, String? value) {
    final selected = roleFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onChanged(value),
      selectedColor: accent.withOpacity(0.22),
      checkmarkColor: accent,
      labelStyle: TextStyle(
        color: selected ? accent : JobsyColors.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
      ),
      side: BorderSide(
        color: selected ? accent.withOpacity(0.45) : JobsyColors.border.withOpacity(0.4),
      ),
      backgroundColor: JobsyColors.surfaceLight,
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  final Color accent;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.accent,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification['is_read'] == true;
    final type = notification['type'] as String? ?? '';
    final id = notification['id'].toString();
    final icon = _iconFor(type);
    final tint = _tintFor(type);
    final title = notification['title']?.toString() ?? '';
    final body = notification['body']?.toString() ?? '';
    final time = _formatTime(notification['created_at']?.toString());
    final notifRole = NotificationRole.fromRow(notification);

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFEF4444).withOpacity(0.4),
            width: 0.7,
          ),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFFEF4444),
        ),
      ),
      onDismissed: (_) {
        NotificationsService.delete(id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: AnimatedPressButton(
        onPressed: onTap,
        scaleDown: 0.98,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isRead
                  ? [
                      JobsyColors.surfaceLight.withOpacity(0.7),
                      JobsyColors.surface,
                    ]
                  : [
                      JobsyColors.surfaceLight,
                      JobsyColors.surface,
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead
                  ? JobsyColors.border.withOpacity(0.35)
                  : tint.withOpacity(0.32),
              width: 0.7,
            ),
            boxShadow: isRead
                ? null
                : [
                    BoxShadow(
                      color: tint.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: tint.withOpacity(0.3),
                    width: 0.7,
                  ),
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight:
                                  isRead ? FontWeight.w600 : FontWeight.w700,
                              color: JobsyColors.textPrimary,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (notifRole != null) ...[
                          const SizedBox(width: 6),
                          _RoleChip(role: notifRole),
                        ],
                        if (!isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tint,
                              boxShadow: [
                                BoxShadow(
                                  color: tint.withOpacity(0.5),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: JobsyColors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: JobsyColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'new_message':
        return Icons.chat_bubble_rounded;
      case 'new_application':
        return Icons.person_add_alt_1_rounded;
      case 'application_accepted':
        return Icons.check_circle_rounded;
      case 'application_rejected':
        return Icons.cancel_rounded;
      case 'application_cancelled':
        return Icons.block_rounded;
      case 'worker_withdrew':
        return Icons.person_remove_rounded;
      case 'worker_done':
      case 'job_completed':
        return Icons.task_alt_rounded;
      case 'new_rating':
        return Icons.star_rounded;
      case 'new_job_posted':
      case 'job_match':
        return Icons.work_rounded;
      case 'candidate_match':
        return Icons.people_alt_rounded;
      case 'job_update':
        return Icons.work_rounded;
      case 'system':
        return Icons.info_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _tintFor(String type) {
    switch (type) {
      case 'new_message':
        return accent;
      case 'new_application':
        return JobsyColors.employerPrimary;
      case 'application_accepted':
        return const Color(0xFF10B981);
      case 'application_rejected':
        return const Color(0xFFEF4444);
      case 'application_cancelled':
        return const Color(0xFFF59E0B);
      case 'worker_withdrew':
        return JobsyColors.employerPrimary;
      case 'worker_done':
      case 'job_completed':
        return const Color(0xFF10B981);
      case 'new_rating':
        return const Color(0xFFF59E0B);
      case 'new_job_posted':
      case 'job_match':
        return JobsyColors.workerPrimary;
      case 'candidate_match':
        return JobsyColors.employerPrimary;
      case 'job_update':
        return const Color(0xFFF59E0B);
      case 'system':
        return JobsyColors.textSecondary;
      default:
        return accent;
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final date = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }
}

class _RoleChip extends StatelessWidget {
  final String role;

  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final isEmployer = role == AppConstants.userTypeEmployer;
    final color =
        isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35), width: 0.6),
      ),
      child: Text(
        NotificationRole.shortLabel(role),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
