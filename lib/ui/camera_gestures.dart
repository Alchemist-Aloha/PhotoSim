import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../models/simulation_state.dart';
import '../render/photo_framing.dart';

/// One finger aims; two fingers change optical focal length without moving the camera.
class CameraGestures extends StatefulWidget {
  const CameraGestures({
    super.key,
    required this.state,
    required this.onChanged,
    required this.child,
  });
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;
  final Widget child;

  @override
  State<CameraGestures> createState() => _CameraGesturesState();
}

class _CameraGesturesState extends State<CameraGestures> {
  double focalLength = 24;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      // Match the displayed field of view, including the outer composition context.
      final degreesPerPixel = bounds.maxHeight > 0
          ? previewVerticalFov(widget.state, bounds.biggest) /
                radians /
                bounds.maxHeight
          : 0.0;
      return GestureDetector(
        onScaleStart: (_) => focalLength = widget.state.focalLength,
        onScaleUpdate: (details) {
          final state = widget.state;
          if (details.pointerCount > 1) {
            widget.onChanged(
              state.copyWith(
                focalLength: (focalLength * details.scale)
                    .clamp(
                      SimulationState.minFocalLength,
                      SimulationState.maxFocalLength,
                    )
                    .roundToDouble(),
              ),
            );
          } else {
            widget.onChanged(
              state.copyWith(
                azimuth:
                    state.azimuth +
                    details.focalPointDelta.dx * degreesPerPixel,
                pitch:
                    state.pitch - details.focalPointDelta.dy * degreesPerPixel,
              ),
            );
          }
        },
        child: widget.child,
      );
    },
  );
}
