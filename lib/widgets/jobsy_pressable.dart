import 'package:flutter/material.dart';

/// Clean tap feedback without Material ink splash (avoids grain on gradients).
class JobsyPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final BorderRadius borderRadius;
  final double pressedOpacity;

  const JobsyPressable({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius = BorderRadius.zero,
    this.pressedOpacity = 0.88,
  });

  @override
  State<JobsyPressable> createState() => _JobsyPressableState();
}

class _JobsyPressableState extends State<JobsyPressable> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _setPressed(true) : null,
      onTapUp: _enabled ? (_) => _setPressed(false) : null,
      onTapCancel: _enabled ? () => _setPressed(false) : null,
      onTap: _enabled ? widget.onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        opacity: !_enabled ? 0.45 : (_pressed ? widget.pressedOpacity : 1.0),
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: widget.child,
        ),
      ),
    );
  }
}
