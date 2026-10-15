import 'dart:math' as math;

import 'package:flutter/material.dart';

/// shortcut: illustrative screen-space rain, use world-space particles for physical precipitation.
class RainOverlay extends StatefulWidget {
  const RainOverlay({super.key, this.intensity = 0.6})
    : assert(intensity >= 0 && intensity <= 1);
  final double intensity;
  @override
  State<RainOverlay> createState() => _RainOverlayState();
}

class _RainOverlayState extends State<RainOverlay>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();
  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ClipRect(
      child: CustomPaint(painter: _RainPainter(clock, widget.intensity)),
    ),
  );
}

class _RainPainter extends CustomPainter {
  _RainPainter(this.clock, this.intensity) : super(repaint: clock);
  final Animation<double> clock;
  final double intensity;
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(24);
    final paint = Paint()
      ..color = const Color(0x668FB4CF)
      ..strokeWidth = 1;
    for (var i = 0; i < (266 * intensity).round(); i++) {
      final x = random.nextDouble() * (size.width + 30) - 15;
      final y =
          ((random.nextDouble() + clock.value) % 1) * (size.height + 30) - 15;
      canvas.drawLine(Offset(x, y), Offset(x - 4, y + 14), paint);
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) =>
      oldDelegate.clock != clock || oldDelegate.intensity != intensity;
}
