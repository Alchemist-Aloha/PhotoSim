import 'dart:math' as math;

import '../models/simulation_state.dart';
import 'geo.dart';

/// Horizontal motion follows azimuth, independent of pitch, roll and focal length.
SimulationState moveCamera(
  SimulationState state,
  double forwardMeters,
  double rightMeters,
) {
  final distance = math.sqrt(
    forwardMeters * forwardMeters + rightMeters * rightMeters,
  );
  if (!distance.isFinite) throw ArgumentError('Movement must be finite');
  final elevation = state.cameraElevation;
  if (distance == 0 || elevation == null) return state;
  final direction =
      state.azimuth + math.atan2(rightMeters, forwardMeters) / radians;
  final next = destination(state.location, direction, distance);
  return state.copyWith(
    latitude: next.latitude.clamp(-85.05112878, 85.05112878),
    longitude: next.longitude,
    fixedElevation: elevation,
  );
}
