import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/simulation_state.dart';

/// Composition guides stay outside the export boundary and never intercept aiming.
class PhotographyOverlays extends StatelessWidget {
  const PhotographyOverlays({super.key, required this.state});
  final SimulationState state;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _Guides(state)),
        if (state.showCrosshair)
          const Center(child: Icon(Icons.add, color: Colors.white54, size: 20)),
        if (state.showLevel)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Roll ${state.roll.toStringAsFixed(1)}° · Pitch ${state.pitch.toStringAsFixed(1)}°',
                style: const TextStyle(
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 3)],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Guides extends CustomPainter {
  _Guides(this.state);
  final SimulationState state;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    if (state.showGrid) {
      for (final part in [1 / 3, 2 / 3]) {
        canvas.drawLine(
          Offset(size.width * part, 0),
          Offset(size.width * part, size.height),
          paint,
        );
        canvas.drawLine(
          Offset(0, size.height * part),
          Offset(size.width, size.height * part),
          paint,
        );
      }
    }
    if (state.showLevel) {
      final frame = state.cameraFrame;
      paint.color = state.roll.abs() < 0.5 ? Colors.greenAccent : Colors.amber;
      final h = math.tan(state.horizontalFov / 2),
          v = math.tan(state.verticalFov / 2);
      // The ENU horizontal plane projected into the actual rolled optical frustum.
      if (frame.up.y.abs() > 1e-8) {
        double y(double u) =>
            size.height /
            2 *
            (1 + (frame.forward.y + frame.right.y * u) / frame.up.y / v);
        canvas.drawLine(Offset(0, y(-h)), Offset(size.width, y(h)), paint);
      } else if (frame.right.y.abs() > 1e-8) {
        final x = size.width / 2 * (1 - frame.forward.y / frame.right.y / h);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Guides oldDelegate) => oldDelegate.state != state;
}
