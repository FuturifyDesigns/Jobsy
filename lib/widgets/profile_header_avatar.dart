import 'package:flutter/material.dart';
import '../config/colors.dart';

/// Centered profile avatar with edit badge — fixed size so layout never shifts.
class ProfileHeaderAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String fallbackLetter;
  final List<Color> badgeGradient;
  final VoidCallback onTap;

  /// Avatar (r=50) + ring padding + camera badge overflow.
  static const double slotSize = 112;

  const ProfileHeaderAvatar({
    super.key,
    required this.avatarUrl,
    required this.fallbackLetter,
    required this.badgeGradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return Center(
      child: SizedBox(
        width: slotSize,
        height: slotSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Colors.white, Color(0xFFCBD5E1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: JobsyColors.surfaceElevated,
                backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                child: !hasAvatar
                    ? Text(
                        fallbackLetter.isNotEmpty
                            ? fallbackLetter[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      )
                    : null,
              ),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: badgeGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: badgeGradient.first.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps profile header body so children stay horizontally centered on screen.
class ProfileHeaderBody extends StatelessWidget {
  final List<Widget> children;

  const ProfileHeaderBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}
