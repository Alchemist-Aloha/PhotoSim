import 'dart:math' as math;

import 'package:astronomia/deltat.dart' as deltat;
import 'package:astronomia/illum.dart' as illum;
import 'package:astronomia/planetposition.dart' as planetposition;

import 'geo.dart' show radians;

const _auKm = 149597870.7;
const _lightTimeDaysPerAu = 0.0057755183;
// Mean obliquity of the ecliptic at J2000.0 (IAU 1976), for ecliptic -> equatorial.
const _j2000Obliquity = 23.439291111 * radians;

/// Naked-eye planets, in orbital order outward from the Sun.
enum Planet {
  mercury('Mercury', planetposition.planetMercury, 2439.7),
  venus('Venus', planetposition.planetVenus, 6051.8),
  mars('Mars', planetposition.planetMars, 3389.5),
  jupiter('Jupiter', planetposition.planetJupiter, 69911),
  saturn('Saturn', planetposition.planetSaturn, 58232),
  uranus('Uranus', planetposition.planetUranus, 25362),
  neptune('Neptune', planetposition.planetNeptune, 24622);

  const Planet(this.label, this.ephemerisIndex, this.radiusKm);
  final String label;
  final int ephemerisIndex;
  final double radiusKm;
}

/// Geocentric position of one planet, valid for the same sky frame as stars.
class PlanetPosition {
  const PlanetPosition({
    required this.planet,
    required this.ra,
    required this.dec,
    required this.distanceAu,
    required this.magnitude,
    required this.angularRadius,
  });

  final Planet planet;

  /// Geocentric J2000 mean equatorial coordinates, radians.
  final double ra, dec;
  final double distanceAu;

  /// Visual magnitude (Saturn ignores ring tilt).
  final double magnitude;
  final double angularRadius;

  double get distanceKm => distanceAu * _auKm;
}

/// Julian Ephemeris Day for a UTC instant, matching the Sun/Moon adapter.
double julianEphemerisDay(DateTime utc) {
  final jd =
      utc.microsecondsSinceEpoch / Duration.microsecondsPerDay + 2440587.5;
  final startOfYear = DateTime.utc(utc.year);
  final year =
      utc.year +
      utc.difference(startOfYear).inMicroseconds /
          DateTime.utc(utc.year + 1).difference(startOfYear).inMicroseconds;
  // shortcut: modeled Delta T and UTC ≈ UT1; use measured Earth orientation for tighter accuracy.
  final deltaT = utc.year < 2010
      ? deltat.interp10A(jd)
      : deltat.polyAfter2000(year);
  return jd + deltaT / 86400;
}

/// Heliocentric VSOP87 positions with light-time iteration, so the planets land
/// in the same J2000 frame that [ObserverSkyFrame] rotates for stars.
List<PlanetPosition> planetPositions(DateTime timestamp) {
  final utc = timestamp.toUtc();
  if (utc.year < 1900 || utc.year > 2100) {
    throw ArgumentError('Planet ephemerides support 1900–2100 only');
  }
  final jde = julianEphemerisDay(utc);
  final earth = planetposition.Planet(planetposition.planetEarth)
      .position2000(jde);
  final earthDistance = earth.range;
  final cosEarthLat = math.cos(earth.lat);
  final earthX = earthDistance * cosEarthLat * math.cos(earth.lon);
  final earthY = earthDistance * cosEarthLat * math.sin(earth.lon);
  final earthZ = earthDistance * math.sin(earth.lat);
  return [
    for (final planet in Planet.values)
      _geocentric(planet, jde, earthDistance, earthX, earthY, earthZ),
  ];
}

PlanetPosition _geocentric(
  Planet planet,
  double jde,
  double earthDistance,
  double earthX,
  double earthY,
  double earthZ,
) {
  // Start at the current instant, then re-evaluate once at the retarded time.
  var lightTime = 0.0;
  late double heliocentric, x, y, z, distance;
  for (var pass = 0; pass < 2; pass++) {
    final position = planetposition.Planet(planet.ephemerisIndex)
        .position2000(jde - lightTime);
    heliocentric = position.range;
    final cosLat = math.cos(position.lat);
    x = heliocentric * cosLat * math.cos(position.lon) - earthX;
    y = heliocentric * cosLat * math.sin(position.lon) - earthY;
    z = heliocentric * math.sin(position.lat) - earthZ;
    distance = math.sqrt(x * x + y * y + z * z);
    lightTime = distance * _lightTimeDaysPerAu;
  }
  final cosE = math.cos(_j2000Obliquity), sinE = math.sin(_j2000Obliquity);
  final equatorialY = y * cosE - z * sinE;
  final equatorialZ = y * sinE + z * cosE;
  final phase = illum.phaseAngle(heliocentric, distance, earthDistance);
  return PlanetPosition(
    planet: planet,
    ra: math.atan2(equatorialY, x) % (2 * math.pi),
    dec: math.asin((equatorialZ / distance).clamp(-1.0, 1.0)),
    distanceAu: distance,
    magnitude: _magnitude(planet, heliocentric, distance, earthDistance, phase),
    angularRadius: math.asin(planet.radiusKm / (distance * _auKm)),
  );
}

double _magnitude(
  Planet planet,
  double heliocentric,
  double distance,
  double earthDistance,
  double phase,
) => switch (planet) {
  Planet.mercury => illum.magnitudeMercury(heliocentric, distance, phase),
  Planet.venus => illum.magnitudeVenus(heliocentric, distance, phase),
  Planet.mars => illum.magnitudeMars(heliocentric, distance, phase),
  Planet.jupiter => illum.magnitudeJupiter(heliocentric, distance),
  // Approximate: the ring contribution needs Saturn-centric geometry, and this
  // value only sizes the marker. Phase and ring tilt stay unmodeled.
  Planet.saturn => -8.88 + 5 * math.log(heliocentric * distance) / math.ln10,
  Planet.uranus => illum.magnitudeUranus(heliocentric, distance),
  Planet.neptune => illum.magnitudeNeptune(heliocentric, distance),
};
