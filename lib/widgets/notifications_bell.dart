import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../config/page_transitions.dart';
import '../services/notifications_service.dart';
import '../screens/notifications/notifications_screen.dart';

/// Bell icon with a live unread-count badge. Tapping opens the
/// notifications screen with a smooth slide+fade transition.
class NotificationsBell extends StatelessWidget {
  final bool isEmployer;
  final Color? iconColor;

  const NotificationsBell({
    super.key,
    required this.isEmployer,
    this.iconColor,
  });

  Color get _accent =>
      isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationsService.streamUnreadCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return StreamBuilder<int>(
          stream: NotificationsService.streamOtherRoleUnreadCount(isEmployer),
          builder: (context, otherSnapshot) {
            final otherCount = otherSnapshot.data ?? 0;
            return AnimatedPressButton(
              scaleDown: 0.9,
              onPressed: () {
                Navigator.push(
                  context,
                  JobsyPageRoute(
                    page: NotificationsScreen(isEmployer: isEmployer),
                    transition: JobsyTransition.fadeSlide,
                  ),
                );
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: JobsyColors.surfaceLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: count > 0
                        ? _accent.withOpacity(0.35)
                        : JobsyColors.border.withOpacity(0.4),
                    width: 0.7,
                  ),
                  boxShadow: count > 0
                      ? [
                          BoxShadow(
                            color: _accent.withOpacity(0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Icon(
                        count > 0
                            ? Icons.notifications_rounded
                            : Icons.notifications_none_rounded,
                        size: 20,
                        color: iconColor ??
                            (count > 0 ? _accent : JobsyColors.textPrimary),
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: JobsyColors.background,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF4444).withOpacity(0.5),
                                blurRadius: 8,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (otherCount > 0)
                      Positioned(
                        bottom: -1,
                        left: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isEmployer
                                ? JobsyColors.workerPrimary
                                : JobsyColors.employerPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: JobsyColors.background,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
