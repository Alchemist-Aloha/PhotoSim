import 'package:flutter/material.dart';

import '../models/simulation_state.dart';

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
  Widget build(BuildContext context) => GestureDetector(
    onScaleStart: (_) => focalLength = widget.state.focalLength,
    onScaleUpdate: (details) {
      final state = widget.state;
      if (details.pointerCount > 1) {
        widget.onChanged(
          state.copyWith(
            focalLength: (focalLength * details.scale).clamp(
              SimulationState.minFocalLength,
              SimulationState.maxFocalLength,
            ),
          ),
        );
      } else {
        widget.onChanged(
          state.copyWith(
            azimuth: state.azimuth + details.focalPointDelta.dx * 0.2,
            pitch: state.pitch - details.focalPointDelta.dy * 0.2,
          ),
        );
      }
    },
    child: widget.child,
  );
}
