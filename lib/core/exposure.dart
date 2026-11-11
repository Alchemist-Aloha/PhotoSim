import 'dart:math' as math;

import '../models/simulation_state.dart';

/// Relative EV response; f/8, 1/125 s, ISO 100 is the renderer's reference.
/// shortcut: artistic radiance reference, calibrate absolute scene luminance before exposure accuracy claims.
double exposureMultiplier(SimulationState state) {
  final manual = state.exposureMode == ExposureMode.manual
      ? (8 * 8 / (state.aperture * state.aperture)) *
            (state.shutterSeconds * 125) *
            (state.iso / 100)
      : 1.0;
  return manual * math.pow(2, state.exposureCompensation);
}

/// Brightest auto-exposure boost; Enhanced visibility may lift night scenes further than Auto.
double autoExposureMaxEv(SimulationState state) =>
    state.exposureMode == ExposureMode.enhanced ? 8 : 4;
