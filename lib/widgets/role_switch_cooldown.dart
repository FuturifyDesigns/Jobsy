import 'dart:async';

import 'package:flutter/material.dart';

import '../config/colors.dart';
import '../services/role_service.dart';

/// Live countdown shown when the user must wait before switching roles again.
class RoleSwitchCooldownDialog extends StatefulWidget {
  final Duration initialRemaining;

  const RoleSwitchCooldownDialog({
    super.key,
    required this.initialRemaining,
  });

  /// Shows a live timer. Returns `true` when the cooldown ends, `false` if dismissed.
  static Future<bool> show(
    BuildContext context, {
    Duration? initialRemaining,
  }) async {
    final remaining =
        initialRemaining ?? await RoleService.getSwitchCooldownRemaining();
    if (remaining == null || remaining <= Duration.zero) return true;
    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => RoleSwitchCooldownDialog(initialRemaining: remaining),
    );
    return result == true;
  }

  @override
  State<RoleSwitchCooldownDialog> createState() =>
      _RoleSwitchCooldownDialogState();
}

class _RoleSwitchCooldownDialogState extends State<RoleSwitchCooldownDialog> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.initialRemaining;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final next = _remaining - const Duration(seconds: 1);
    if (next <= Duration.zero) {
      _timer?.cancel();
      setState(() => _remaining = Duration.zero);
      Navigator.pop(context, true);
      return;
    }
    setState(() => _remaining = next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _remaining.inSeconds.clamp(0, 9999);
    final timeLabel = RoleService.formatSwitchCooldown(_remaining);

    return AlertDialog(
      backgroundColor: JobsyColors.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Please wait',
        style: TextStyle(
          color: JobsyColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: JobsyColors.workerPrimary.withOpacity(0.12),
              border: Border.all(
                color: JobsyColors.workerPrimary.withOpacity(0.35),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              timeLabel,
              style: const TextStyle(
                color: JobsyColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            seconds == 1
                ? 'You can switch roles again in 1 second.'
                : 'You can switch roles again in $seconds seconds.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: JobsyColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
