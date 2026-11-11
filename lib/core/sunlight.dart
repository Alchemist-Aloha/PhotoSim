import 'dart:math' as math;

import 'atmosphere.dart';

/// Clear-air Rayleigh scattering coefficients used by the analytic sky shader.
const clearSkyRayleigh = (red: 0.058, green: 0.135, blue: 0.331);

({double red, double green, double blue}) _transmission(
  double altitude,
  AtmosphereOptics optics,
) {
  // Kasten–Young air mass, with the same optical depths as the sky.
  final mass =
      1 /
      (math.sin(altitude * math.pi / 180) +
          0.50572 * math.pow(altitude + 6.07995, -1.6364));
  // Stratospheric ozone has a much shorter grazing path than sea-level air.
  final cosine = math.cos(altitude * math.pi / 180);
  final ozoneMass = 1 / math.sqrt(1 - math.pow(6371 / 6396 * cosine, 2));
  double transmission(double rayleigh, double mie, double ozone) => math.exp(
    -rayleigh * 0.0001 * 8400 * mass -
        mie * optics.aerosolHeightKm * mass -
        ozone * 15 * ozoneMass,
  );
  return (
    red: transmission(
      clearSkyRayleigh.red,
      optics.mieScattering.red + optics.mieAbsorption.red,
      optics.ozone.red,
    ),
    green: transmission(
      clearSkyRayleigh.green,
      optics.mieScattering.green + optics.mieAbsorption.green,
      optics.ozone.green,
    ),
    blue: transmission(
      clearSkyRayleigh.blue,
      optics.mieScattering.blue + optics.mieAbsorption.blue,
      optics.ozone.blue,
    ),
  );
}

/// Absolute disk transmission; keep optical depths in sync with sky.fmat.
Rgb sunDiskTransmission(double altitude, {AtmosphereOptics? optics}) {
  if (!altitude.isFinite || altitude < -90 || altitude > 90) {
    throw ArgumentError.value(altitude, 'altitude');
  }
  final air = optics ?? AtmosphereOptics.standard;
  final elevation = altitude.clamp(-1.0, 90.0);
  final mass =
      1 /
      math.max(
        math.sin(elevation * math.pi / 180) +
            0.50572 * math.pow(elevation + 6.07995, -1.6364),
        0.001,
      );
  double channel(double rayleigh, double mie, double ozone) => math.exp(
    -(rayleigh * 0.1 * 8.4 + mie * air.aerosolHeightKm + ozone * 15) * mass,
  );
  return (
    red: channel(
      clearSkyRayleigh.red,
      air.mieScattering.red + air.mieAbsorption.red,
      air.ozone.red,
    ),
    green: channel(
      clearSkyRayleigh.green,
      air.mieScattering.green + air.mieAbsorption.green,
      air.ozone.green,
    ),
    blue: channel(
      clearSkyRayleigh.blue,
      air.mieScattering.blue + air.mieAbsorption.blue,
      air.ozone.blue,
    ),
  );
}

/// Spectral color of direct sunlight normalized to red.
///
/// [altitude] may dip below the geometric horizon: elevated clouds keep their
/// last red light after ground sunset. The path is clamped at -1° so the color
/// stays finite. Use [sunlight] for ground-level illumination.
({double red, double green, double blue}) sunTransmission(
  double altitude, {
  AtmosphereOptics? optics,
}) {
  if (!altitude.isFinite || altitude < -90 || altitude > 90) {
    throw ArgumentError.value(altitude, 'altitude');
  }
  final light = _transmission(
    altitude.clamp(-1.0, 90.0),
    optics ?? AtmosphereOptics.standard,
  );
  if (light.red <= 0) return (red: 1, green: 0, blue: 0);
  return (red: 1, green: light.green / light.red, blue: light.blue / light.red);
}

/// Approximate RGB extinction, not calibrated irradiance or photographic exposure.
({double intensity, double red, double green, double blue}) sunlight(
  double altitude, {
  AtmosphereOptics? optics,
}) {
  if (!altitude.isFinite || altitude < -90 || altitude > 90) {
    throw ArgumentError.value(altitude, 'altitude');
  }
  if (altitude <= 0) return (intensity: 0, red: 1, green: 0, blue: 0);
  final light = _transmission(altitude, optics ?? AtmosphereOptics.standard);
  // shortcut: fade direct lighting over the last solar diameter, not a refracted limb calculation.
  final limb = (altitude / 0.53).clamp(0.0, 1.0);
  if (light.red <= 0) return (intensity: 0, red: 1, green: 0, blue: 0);
  return (
    intensity: 3 * light.red * limb,
    red: 1,
    green: light.green / light.red,
    blue: light.blue / light.red,
  );
}
