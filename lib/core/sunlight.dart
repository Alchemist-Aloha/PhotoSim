import 'dart:math' as math;

/// Clear-air Rayleigh scattering coefficients used by the analytic sky shader.
const clearSkyRayleigh = (red: 0.058, green: 0.135, blue: 0.331);
const clearSkyMie = 0.002;

/// Approximate RGB extinction, not calibrated irradiance or photographic exposure.
({double intensity, double red, double green, double blue}) sunlight(
  double altitude,
) {
  if (!altitude.isFinite || altitude < -90 || altitude > 90) {
    throw ArgumentError.value(altitude, 'altitude');
  }
  if (altitude <= 0) return (intensity: 0, red: 1, green: 0, blue: 0);
  // Kasten–Young air mass, with the same clear-air optical depths as the sky.
  final mass =
      1 /
      (math.sin(altitude * math.pi / 180) +
          0.50572 * math.pow(altitude + 6.07995, -1.6364));
  double transmission(double rayleigh, double mie) => math.exp(
    -(rayleigh * 0.0001 * 8400 + 2 * clearSkyMie * mie * 0.000434 * 1250) *
        mass,
  );
  final red = transmission(clearSkyRayleigh.red, 0.69);
  final green = transmission(clearSkyRayleigh.green, 0.73);
  final blue = transmission(clearSkyRayleigh.blue, 0.81);
  // shortcut: fade direct lighting over the last solar diameter, not a refracted limb calculation.
  final limb = (altitude / 0.53).clamp(0.0, 1.0);
  return (
    intensity: 3 * red * limb,
    red: 1,
    green: green / red,
    blue: blue / red,
  );
}
