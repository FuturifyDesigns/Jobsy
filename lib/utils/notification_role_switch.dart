import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../config/constants.dart';
import '../config/navigator_key.dart';
import '../services/role_service.dart';
import '../widgets/role_switch_overlay.dart';
import 'notification_role.dart';

/// Switches to [targetRole] when needed before opening notification content.
/// Shows the same loading/success overlay as manual role switching (no confirm).
Future<void> ensureRoleForNotification(
  String targetRole, {
  BuildContext? context,
}) async {
  final current = await RoleService.getCurrentRole();
  if (current == targetRole) return;

  final ctx = context ?? navigatorKey.currentContext;
  if (ctx != null && ctx.mounted) {
    RoleSwitchOverlay.showLoading(ctx, targetRole);
  }

  try {
    await RoleService.switchRoleServer(targetRole);
    if (ctx != null && ctx.mounted) {
      await RoleSwitchOverlay.showSuccess(ctx, targetRole);
    }
  } on RoleSwitchException catch (e) {
    if (ctx != null && ctx.mounted) {
      RoleSwitchOverlay.dismiss(ctx);
      if (RoleService.isSwitchCooldownError(e.message)) {
        await RoleService.showSwitchCooldownIfNeeded(ctx);
      } else {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              '${e.message} Opening in ${NotificationRole.label(await RoleService.getCurrentRole() ?? targetRole)} mode.',
            ),
            backgroundColor: JobsyColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  } catch (e) {
    if (ctx != null && ctx.mounted) {
      RoleSwitchOverlay.dismiss(ctx);
    }
  }
}
