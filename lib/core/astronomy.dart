import 'dart:math' as math;

import 'package:astronomia/coord.dart' as coord;
import 'package:astronomia/deltat.dart' as deltat;
import 'package:astronomia/globe.dart' as globe;
import 'package:astronomia/moonposition.dart' as moonposition;
import 'package:astronomia/nutation.dart' as nutation;
import 'package:astronomia/sidereal.dart' as sidereal;
import 'package:astronomia/solar.dart' as solar;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'geo.dart';

const _auKm = 149597870.7;

class CelestialPosition {
  const CelestialPosition(
    this.azimuth,
    this.altitude,
    this.distanceKm,
    this.angularRadius,
    this.direction,
  );

  /// Airless topocentric center, degrees clockwise from north and above horizontal.
  final double azimuth, altitude;
  final double distanceKm, angularRadius;

  /// Renderer axes: east +X, up +Y, north −Z.
  final Vector3 direction;
}

class SkyState {
  const SkyState(this.sun, this.moon, this.moonPhaseAngle, this.moonWaxing);
  final CelestialPosition sun, moon;

  /// Radians: zero at full Moon, pi at new Moon.
  final double moonPhaseAngle;
  final bool moonWaxing;
  double get moonIllumination => (1 + math.cos(moonPhaseAngle)) / 2;
}

/// Offline Meeus ephemerides. Elevation is meters above the reference ellipsoid.
SkyState calculateSky({
  required DateTime timestamp,
  required double latitude,
  required double longitude,
  required double elevation,
}) {
  final utc = timestamp.toUtc();
  if (utc.year < 1900 ||
      utc.year > 2100 ||
      !latitude.isFinite ||
      latitude.abs() > 90 ||
      !longitude.isFinite ||
      longitude.abs() > 180 ||
      !elevation.isFinite ||
      elevation < -12000 ||
      elevation > 10100) {
    throw ArgumentError('Invalid astronomical observer or date (1900–2100)');
  }
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
  final jde = jd + deltaT / 86400;
  final n = nutation.nutation(jde);
  final eps = nutation.meanObliquity(jde) + n.dEps;
  final sunEq = solar.apparentEquatorial(jde);
  final sunDistance = solar.radius((jde - 2451545) / 36525) * _auKm;
  final moonEcl = moonposition.position(jde);
  final moonEq = coord.eclToEq(
    moonEcl.lon + n.dPsi,
    moonEcl.lat,
    math.sin(eps),
    math.cos(eps),
  );
  final phi = latitude * radians;
  final rho = globe.parallaxConstants(
    phi,
    elevation,
    er: 6378.137,
    fl: 1 / 298.257223563,
  );
  final localSidereal =
      sidereal.mean(jd) * 2 * math.pi / 86400 +
      n.dPsi * math.cos(eps) +
      longitude * radians;

  CelestialPosition observe(
    ({double ra, double dec}) eq,
    double distance,
    double radius,
  ) {
    final h = localSidereal - eq.ra;
    // Subtract the WGS84 observer before rotating into ENU: includes lunar parallax.
    final x =
        distance * math.cos(eq.dec) * math.cos(h) - 6378.137 * rho.rhoCosPrime;
    final y = -distance * math.cos(eq.dec) * math.sin(h);
    final z = distance * math.sin(eq.dec) - 6378.137 * rho.rhsSinPhiPrime;
    final north = z * math.cos(phi) - x * math.sin(phi);
    final up = z * math.sin(phi) + x * math.cos(phi);
    final direction = Vector3(y, up, -north);
    final topocentricDistance = direction.length;
    direction.scale(1 / topocentricDistance);
    return CelestialPosition(
      (math.atan2(y, north) / radians) % 360,
      math.atan2(up, math.sqrt(y * y + north * north)) / radians,
      topocentricDistance,
      math.asin(radius / topocentricDistance),
      direction,
    );
  }

  final sun = observe(sunEq, sunDistance, 695700);
  final moon = observe(moonEq, moonEcl.delta, 1737.4);
  final lightDirection =
      (sun.direction * sun.distanceKm - moon.direction * moon.distanceKm)
          .normalized();
  final phase = math.acos(
    (-moon.direction).dot(lightDirection).clamp(-1.0, 1.0),
  );
  final elongation =
      (moonEcl.lon +
          n.dPsi -
          solar.apparentLongitude((jde - 2451545) / 36525)) %
      (2 * math.pi);
  return SkyState(sun, moon, phase, elongation < math.pi);
}
