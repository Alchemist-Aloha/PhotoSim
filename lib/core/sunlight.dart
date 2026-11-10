import 'dart:math' as math;

/// Clear-air Rayleigh scattering coefficients used by the analytic sky shader.
const clearSkyRayleigh = (red: 0.058, green: 0.135, blue: 0.331);
// Low aerosol loading for the clear-sky baseline; avoid a broad warm daytime aureole.
const clearSkyMie = 0.0005;
// RGB ozone absorption per km at peak density; 10–40 km triangular layer.
const clearSkyOzone = (red: 0.000650, green: 0.001881, blue: 0.000085);

({double red, double green, double blue}) _transmission(double altitude) {
  // Kasten–Young air mass, with the same clear-air optical depths as the sky.
  final mass =
      1 /
      (math.sin(altitude * math.pi / 180) +
          0.50572 * math.pow(altitude + 6.07995, -1.6364));
  // Stratospheric ozone has a much shorter grazing path than sea-level air.
  final cosine = math.cos(altitude * math.pi / 180);
  final ozoneMass = 1 / math.sqrt(1 - math.pow(6371 / 6396 * cosine, 2));
  double transmission(double rayleigh, double mie, double ozone) => math.exp(
    -(rayleigh * 0.0001 * 8400 + 2 * clearSkyMie * mie * 0.000434 * 1250) *
            mass -
        ozone * 15 * ozoneMass,
  );
  return (
    red: transmission(clearSkyRayleigh.red, 0.69, clearSkyOzone.red),
    green: transmission(clearSkyRayleigh.green, 0.73, clearSkyOzone.green),
    blue: transmission(clearSkyRayleigh.blue, 0.81, clearSkyOzone.blue),
  );
}

/// Spectral color of direct sunlight normalized to red.
///
/// [altitude] may dip below the geometric horizon: elevated clouds keep their
/// last red light after ground sunset. The path is clamped at -1° so the color
/// stays finite. Use [sunlight] for ground-level illumination.
({double red, double green, double blue}) sunTransmission(double altitude) {
  if (!altitude.isFinite || altitude < -90 || altitude > 90) {
    throw ArgumentError.value(altitude, 'altitude');
  }
  final light = _transmission(altitude.clamp(-1.0, 90.0));
  return (red: 1, green: light.green / light.red, blue: light.blue / light.red);
}

/// Approximate RGB extinction, not calibrated irradiance or photographic exposure.
({double intensity, double red, double green, double blue}) sunlight(
  double altitude,
) {
  if (!altitude.isFinite || altitude < -90 || altitude > 90) {
    throw ArgumentError.value(altitude, 'altitude');
  }
  if (altitude <= 0) return (intensity: 0, red: 1, green: 0, blue: 0);
  final light = _transmission(altitude);
  // shortcut: fade direct lighting over the last solar diameter, not a refracted limb calculation.
  final limb = (altitude / 0.53).clamp(0.0, 1.0);
  return (
    intensity: 3 * light.red * limb,
    red: 1,
    green: light.green / light.red,
    blue: light.blue / light.red,
  );
}
