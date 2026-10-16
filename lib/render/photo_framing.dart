import 'dart:math' as math;
import 'dart:ui';

import '../models/simulation_state.dart';

/// The sensor-sized composition sits inside the full context viewport.
Rect photoRegion(Size viewport, double aspect) {
  if (viewport.isEmpty) return Rect.zero;
  final width = math.min(viewport.width * 0.9, viewport.height * 0.9 * aspect);
  return Rect.fromCenter(
    center: viewport.center(Offset.zero),
    width: width,
    height: width / aspect,
  );
}

/// Expand the context view without changing the lens field inside the photograph.
double previewVerticalFov(SimulationState state, Size viewport) {
  final region = photoRegion(viewport, state.sensorWidth / state.sensorHeight);
  if (region.isEmpty) return state.verticalFov;
  return 2 *
      math.atan(
        math.tan(state.verticalFov / 2) * viewport.height / region.height,
      );
}
