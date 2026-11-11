import 'dart:math' as math;

/// Aerosol optics follow the reference package's five representative types.
enum AerosolType {
  continental(
    'Continental',
    'Mixed dust and pollution',
    1.3,
    (0.94, 0.93, 0.91),
    0.64,
    1.2,
    0.55,
  ),
  maritime(
    'Maritime',
    'Sea-salt haze',
    0.4,
    (0.995, 0.995, 0.99),
    0.72,
    1.0,
    0.7,
  ),
  urban(
    'Urban',
    'Smog and combustion aerosol',
    1.6,
    (0.88, 0.86, 0.82),
    0.62,
    1.0,
    0.5,
  ),
  desert(
    'Desert dust',
    'Coarse mineral dust',
    0.15,
    (0.97, 0.93, 0.84),
    0.7,
    2.6,
    0.08,
  ),
  smoke(
    'Wildfire smoke',
    'Absorbing organic carbon',
    1.85,
    (0.9, 0.84, 0.74),
    0.58,
    2.2,
    0.25,
  );

  const AerosolType(
    this.label,
    this.description,
    this.angstrom,
    this.singleScatteringAlbedo,
    this.asymmetry,
    this.scaleHeightKm,
    this.hygroscopicity,
  );

  final String label, description;
  final double angstrom, asymmetry, scaleHeightKm, hygroscopicity;
  final (double, double, double) singleScatteringAlbedo;
}

typedef Rgb = ({double red, double green, double blue});

/// Aerosol and ozone optics in inverse kilometres, shared by the sky shader and
/// the analytic sunlight/cloud tinting.
class AtmosphereOptics {
  const AtmosphereOptics({
    required this.mieScattering,
    required this.mieAbsorption,
    required this.ozone,
    required this.aerosolHeightKm,
    required this.eccentricity,
  });

  factory AtmosphereOptics.compute({
    AerosolType aerosolType = AerosolType.continental,
    double aerosolOpticalDepth = 0.005,
    double humidity = 40,
    double ozoneColumnDu = 300,
  }) {
    // Hygroscopic growth is capped at 97% RH; optics stay finite at saturation.
    final rh = humidity.clamp(0, 97) / 100;
    final growth = math.pow(1 - rh, -aerosolType.hygroscopicity * 0.8);
    final angstrom = aerosolType.angstrom * (1 - 0.35 * rh);
    final eccentricity = math.min(0.85, aerosolType.asymmetry + 0.08 * rh * rh);
    final beta550 = aerosolOpticalDepth * growth / aerosolType.scaleHeightKm;
    final ssa = [
      aerosolType.singleScatteringAlbedo.$1,
      aerosolType.singleScatteringAlbedo.$2,
      aerosolType.singleScatteringAlbedo.$3,
    ].map((value) => value + (1 - value) * 0.5 * rh).toList();
    const wavelengths = [680.0, 550.0, 440.0];
    final scattering = <double>[];
    final absorption = <double>[];
    for (var i = 0; i < 3; i++) {
      final extinction =
          beta550 * math.pow(wavelengths[i] / 550, -angstrom).toDouble();
      scattering.add(extinction * ssa[i]);
      absorption.add(extinction * (1 - ssa[i]));
    }
    // 1 DU = 2.69e16 molecules/cm²; this is the reference 300 DU profile.
    final ozoneScale = ozoneColumnDu / 300;
    return AtmosphereOptics(
      mieScattering: (
        red: scattering[0],
        green: scattering[1],
        blue: scattering[2],
      ),
      mieAbsorption: (
        red: absorption[0],
        green: absorption[1],
        blue: absorption[2],
      ),
      ozone: (
        red: 0.000650 * ozoneScale,
        green: 0.001881 * ozoneScale,
        blue: 0.000085 * ozoneScale,
      ),
      aerosolHeightKm: aerosolType.scaleHeightKm,
      eccentricity: eccentricity,
    );
  }

  static final standard = AtmosphereOptics.compute();

  final Rgb mieScattering, mieAbsorption, ozone;
  final double aerosolHeightKm, eccentricity;
}
