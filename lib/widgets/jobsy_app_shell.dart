import 'package:flutter/material.dart';

import '../config/colors.dart';
import '../widgets/notifications_bell.dart';
import 'jobsy_pressable.dart';

/// Professional app chrome shared by worker & employer home shells.
class JobsyAppBar extends StatelessWidget {
  final Color accentColor;
  final bool isEmployer;
  final String userName;
  final String? avatarUrl;
  final VoidCallback onLeadingPressed;
  final VoidCallback onProfileTap;

  const JobsyAppBar({
    super.key,
    required this.accentColor,
    required this.isEmployer,
    required this.userName,
    this.avatarUrl,
    required this.onLeadingPressed,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = userName.trim().isNotEmpty
        ? userName.trim().split(' ').first
        : (isEmployer ? 'Employer' : 'Worker');
    final displayName =
        firstName.length > 12 ? '${firstName.substring(0, 12)}…' : firstName;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      decoration: BoxDecoration(
        color: JobsyColors.navBarBackground,
        border: Border(
          bottom: BorderSide(color: JobsyColors.border.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: onLeadingPressed,
            icon: const Icon(Icons.logout_rounded, size: 22),
            color: JobsyColors.textSecondary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JOBSY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                    color: accentColor.withValues(alpha: 0.9),
                  ),
                ),
                Text(
                  isEmployer ? 'Employer Portal' : 'Worker Portal',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          NotificationsBell(isEmployer: isEmployer),
          const SizedBox(width: 10),
          JobsyPressable(
            onPressed: onProfileTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              decoration: BoxDecoration(
                color: JobsyColors.surfaceLight,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accentColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: accentColor.withValues(alpha: 0.15),
                    backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                        ? NetworkImage(avatarUrl!)
                        : null,
                    child: avatarUrl == null || avatarUrl!.isEmpty
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    displayName.toUpperCase() == 'ME' ? displayName : displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: JobsyColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class JobsyBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color accentColor;
  final List<BottomNavigationBarItem> items;

  const JobsyBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.accentColor,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JobsyColors.navBarBackground,
        border: Border(
          top: BorderSide(color: JobsyColors.border.withValues(alpha: 0.55)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: accentColor,
          unselectedItemColor: JobsyColors.textTertiary,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          items: items,
        ),
      ),
    );
  }
}

/// Clean list-screen header used on browse / agency views.
class JobsyScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color accentColor;
  final Widget? trailing;

  const JobsyScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.accentColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: JobsyColors.surface,
        border: Border(
          bottom: BorderSide(color: JobsyColors.border.withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 44,
            margin: const EdgeInsets.only(top: 2, right: 14),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: JobsyColors.textPrimary,
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: JobsyColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
