import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../config/constants.dart';
import '../services/role_service.dart';

/// Full-screen overlay while switching roles or showing success.
class RoleSwitchOverlay extends StatefulWidget {
  final String targetRole;
  final bool success;

  const RoleSwitchOverlay({
    super.key,
    required this.targetRole,
    this.success = false,
  });

  /// Shows loading overlay (does not block — call [dismiss] when done).
  static void showLoading(BuildContext context, String targetRole) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.82),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => RoleSwitchOverlay(targetRole: targetRole),
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  static void dismiss(BuildContext context) {
    if (!context.mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  static Future<void> showSuccess(BuildContext context, String targetRole) async {
    if (!context.mounted) return;
    dismiss(context);

    // Do not await showGeneralDialog — its future only completes on pop, which
    // would freeze the app until we navigate. Show briefly, then dismiss.
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.82),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) =>
          RoleSwitchOverlay(targetRole: targetRole, success: true),
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.elasticOut),
            ),
            child: child,
          ),
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 850));
    dismiss(context);
  }

  @override
  State<RoleSwitchOverlay> createState() => _RoleSwitchOverlayState();
}

class _RoleSwitchOverlayState extends State<RoleSwitchOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (!widget.success) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmployer = widget.targetRole == AppConstants.userTypeEmployer;
    final accent = isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;
    final label = RoleService.roleLabel(widget.targetRole);

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 36),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          decoration: BoxDecoration(
            color: JobsyColors.surfaceLight,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.25),
                blurRadius: 32,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.success)
                Icon(Icons.check_circle_rounded, color: accent, size: 56)
              else
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    return SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: accent.withOpacity(0.55 + _pulse.value * 0.45),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 20),
              Text(
                widget.success ? 'You are now $label' : 'Switching to $label…',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JobsyColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.success
                    ? 'Your ${label.toLowerCase()} data is saved and ready.'
                    : 'Saving your profile and loading your dashboard',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JobsyColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
