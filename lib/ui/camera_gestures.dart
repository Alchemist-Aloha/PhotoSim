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

  /// Aiming and zooming accumulate from the gesture origin. A pointer delivers
  /// several events per frame while the parent only rebuilds once, so composing
  /// each event onto [widget.state] kept just the last delta: a high-polling-rate
  /// mouse, or a GPU-bound frame rate, moved the camera a fraction of the cursor.
  SimulationState? origin;
  var drag = Offset.zero;

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
        onScaleStart: (_) {
          focalLength = widget.state.focalLength;
          origin = widget.state;
          drag = Offset.zero;
        },
        onScaleEnd: (_) {
          origin = null;
          drag = Offset.zero;
        },
        onScaleUpdate: (details) {
          final base = origin ??= widget.state;
          if (details.pointerCount == 1) drag += details.focalPointDelta;
          final next = base.copyWith(
            azimuth: base.azimuth + drag.dx * degreesPerPixel,
            pitch: base.pitch - drag.dy * degreesPerPixel,
            focalLength: details.pointerCount > 1
                ? (focalLength * details.scale)
                      .clamp(
                        SimulationState.minFocalLength,
                        SimulationState.maxFocalLength,
                      )
                      .roundToDouble()
                : null,
          );
          widget.onChanged(next);
        },
        child: widget.child,
      );
    },
  );
}
