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

/// Camera white-balance gains for a Kelvin setting: the inverse of a Planckian
/// source's linear-sRGB colour, neutral at 6500 K, green fixed at 1 like a raw
/// converter. Planckian xy from Kim et al. (2002), valid 1667–25000 K.
({double red, double green, double blue}) whiteBalanceGain(double kelvin) {
  ({double r, double g, double b}) planck(double t) {
    final x = t <= 4000
        ? -0.2661239e9 / (t * t * t) -
              0.2343589e6 / (t * t) +
              0.8776956e3 / t +
              0.179910
        : -3.0258469e9 / (t * t * t) +
              2.1070379e6 / (t * t) +
              0.2226347e3 / t +
              0.240390;
    final y = t <= 2222
        ? -1.1063814 * x * x * x -
              1.34811020 * x * x +
              2.18555832 * x -
              0.20219683
        : t <= 4000
        ? -0.9549476 * x * x * x -
              1.37418593 * x * x +
              2.09137015 * x -
              0.16748867
        : 3.0817580 * x * x * x -
              5.87338670 * x * x +
              3.75112997 * x -
              0.37001483;
    final cx = x / y, cz = (1 - x - y) / y;
    return (
      r: 3.2406 * cx - 1.5372 - 0.4986 * cz,
      g: -0.9689 * cx + 1.8758 + 0.0415 * cz,
      b: 0.0557 * cx - 0.2040 + 1.0570 * cz,
    );
  }

  final light = planck(kelvin), neutral = planck(6500);
  final green = neutral.g / light.g;
  return (
    red: neutral.r / light.r / green,
    green: 1.0,
    blue: neutral.b / light.b / green,
  );
}
