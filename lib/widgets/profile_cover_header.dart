import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../config/colors.dart';

/// Profile header background: optional cover photo with gradient fallback + scrim.
class ProfileCoverHeader extends StatelessWidget {
  final String? coverUrl;
  final List<Color> fallbackGradient;
  final VoidCallback? onEditCover;
  final Widget child;
  final double minHeight;

  const ProfileCoverHeader({
    super.key,
    required this.coverUrl,
    required this.fallbackGradient,
    required this.child,
    this.onEditCover,
    this.minHeight = 280,
  });

  bool get _hasCover => coverUrl != null && coverUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: _hasCover
                  ? CachedNetworkImage(
                      imageUrl: coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _GradientBackground(colors: fallbackGradient),
                      errorWidget: (_, __, ___) => _GradientBackground(colors: fallbackGradient),
                    )
                  : _GradientBackground(colors: fallbackGradient),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(_hasCover ? 0.35 : 0.15),
                      Colors.black.withOpacity(_hasCover ? 0.62 : 0.42),
                    ],
                  ),
                ),
              ),
            ),
            if (onEditCover != null)
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onEditCover,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _hasCover ? Icons.photo_camera_outlined : Icons.add_photo_alternate_outlined,
                            size: 16,
                            color: Colors.white.withOpacity(0.92),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _hasCover ? 'Edit cover' : 'Add cover',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.92),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientBackground extends StatelessWidget {
  final List<Color> colors;

  const _GradientBackground({required this.colors});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.length >= 3 ? colors : [...colors, JobsyColors.primary],
          stops: colors.length >= 3 ? const [0.0, 0.55, 1.0] : null,
        ),
      ),
    );
  }
}
