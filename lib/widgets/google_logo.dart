import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Official-style multicolor Google "G" mark (24dp).
class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.42;
    const stroke = 3.6;

    void arc(Color color, double start, double sweep) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start,
        sweep,
        false,
        paint,
      );
    }

    arc(const Color(0xFFEA4335), -math.pi / 2, math.pi / 2);
    arc(const Color(0xFFFBBC05), 0, math.pi / 2);
    arc(const Color(0xFF34A853), math.pi / 2, math.pi / 2);
    arc(const Color(0xFF4285F4), math.pi, math.pi / 2);

    final bar = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx - stroke * 0.2, cy - stroke * 0.55, r + stroke, stroke * 1.1),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
