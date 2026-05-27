/// TotpRing — razor-thin circular progress ring for TOTP countdown (§10)
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../config/colors.dart';

class TotpRing extends StatelessWidget {
  final double progress; // 0.0 → 1.0 (remaining time / period)
  final double size;
  final double strokeWidth;
  final Widget? child;

  const TotpRing({
    super.key,
    required this.progress,
    this.size = 200,
    this.strokeWidth = 1.5, // Razor-thin as specified
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress, strokeWidth: strokeWidth),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;

  const _RingPainter({required this.progress, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth;

    // Background ring
    final bgPaint = Paint()
      ..color = SFColors.borderSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc — starts at top (-π/2), sweeps clockwise
    final progPaint = Paint()
      ..color = progress < 0.25
          ? SFColors.danger
          : SFColors.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,               // Start at 12 o'clock
      2 * pi * progress,     // Arc length
      false,
      progPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
