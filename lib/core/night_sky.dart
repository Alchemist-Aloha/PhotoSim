import 'dart:convert';
import 'dart:math' as math;

import 'package:astronomia/coord.dart' as coord;
import 'package:astronomia/deltat.dart' as deltat;
import 'package:astronomia/nutation.dart' as nutation;
import 'package:astronomia/precess.dart' as precess;
import 'package:astronomia/sidereal.dart' as sidereal;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'astronomy.dart';
import 'geo.dart';

class Star {
  const Star(this.id, this.ra, this.dec, this.magnitude);
  final int id;

  /// J2000 mean equatorial coordinates, radians.
  final double ra, dec, magnitude;
  Vector3 get direction => Vector3(
    math.cos(dec) * math.cos(ra),
    math.cos(dec) * math.sin(ra),
    math.sin(dec),
  );
}

List<Star> parseStarCatalog(String source) {
  final Object? rows = jsonDecode(source);
  if (rows is! List<Object?> || rows.isEmpty || rows.length > 10000) {
    throw const FormatException('Invalid star catalog');
  }
  return rows
      .map((row) {
        if (row is! List<Object?> || row.length != 4) {
          throw const FormatException('Invalid star row');
        }
        final id = row[0], ra = row[1], dec = row[2], magnitude = row[3];
        if (id is! int ||
            id <= 0 ||
            ra is! num ||
            !ra.isFinite ||
            ra.abs() > 180 ||
            dec is! num ||
            !dec.isFinite ||
            dec.abs() > 90 ||
            magnitude is! num ||
            !magnitude.isFinite ||
            magnitude < -2 ||
            magnitude > 6) {
          throw const FormatException('Invalid star row');
        }
        return Star(id, ra * radians, dec * radians, magnitude.toDouble());
      })
      .toList(growable: false);
}

/// Rigid J2000 -> local sky rotation, shared by stars, Milky Way and targets.
class ObserverSkyFrame {
  ObserverSkyFrame({
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  }) {
    final utc = timestamp.toUtc();
    if (utc.year < 1900 ||
        utc.year > 2100 ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      throw ArgumentError('Invalid sky observer or date (1900–2100)');
    }
    final jd =
        utc.microsecondsSinceEpoch / Duration.microsecondsPerDay + 2440587.5;
    final year =
        utc.year +
        utc.difference(DateTime.utc(utc.year)).inMicroseconds /
            DateTime.utc(utc.year + 1)
                .difference(DateTime.utc(utc.year))
                .inMicroseconds;
    // shortcut: UTC ≈ UT1 and modeled Delta T, matching the Sun/Moon adapter.
    final dt = utc.year < 2010
        ? deltat.interp10A(jd)
        : deltat.polyAfter2000(year);
    final jde = jd + dt / 86400;
    final n = nutation.nutation(jde);
    _meanEps = nutation.meanObliquity(jde);
    _eps = _meanEps + n.dEps;
    _dPsi = n.dPsi;
    _precession = precess.Precessor(2000, 2000 + (jde - 2451545) / 365.25);
    _phi = latitude * radians;
    _sidereal =
        sidereal.mean(jd) * 2 * math.pi / 86400 +
        n.dPsi * math.cos(_eps) +
        longitude * radians;
  }
  late final double _meanEps, _eps, _dPsi, _phi, _sidereal;
  late final precess.Precessor _precession;

  Vector3 direction(double ra, double dec) {
    if (!ra.isFinite || !dec.isFinite || dec.abs() > math.pi / 2) {
      throw ArgumentError('Invalid equatorial coordinates');
    }
    final mean = _precession.precess(ra, dec);
    final ecl = coord.eqToEcl(
      mean.ra,
      mean.dec,
      math.sin(_meanEps),
      math.cos(_meanEps),
    );
    final apparent = coord.eclToEq(
      ecl.lon + _dPsi,
      ecl.lat,
      math.sin(_eps),
      math.cos(_eps),
    );
    final h = _sidereal - apparent.ra;
    final x = math.cos(apparent.dec) * math.cos(h);
    final east = -math.cos(apparent.dec) * math.sin(h);
    final z = math.sin(apparent.dec);
    return Vector3(
      east,
      x * math.cos(_phi) + z * math.sin(_phi),
      x * math.sin(_phi) - z * math.cos(_phi),
    ).normalized();
  }

  CelestialPosition position(double ra, double dec) {
    final d = direction(ra, dec);
    return CelestialPosition(
      math.atan2(d.x, -d.z) / radians % 360,
      math.asin(d.y.clamp(-1.0, 1.0)) / radians,
      double.infinity,
      0,
      d,
    );
  }

  /// Fraction of the visible Galactic equator at 0–30° elevation, by arc length.
  /// A great circle's vertical component is A sin(t); its visible half spans π.
  double get lowMilkyWayFraction {
    final pole = direction(192.85948 * radians, 27.12825 * radians);
    final amplitude = math.sqrt((1 - pole.y * pole.y).clamp(0.0, 1.0));
    return amplitude <= 0.5 ? 1 : 2 * math.asin(0.5 / amplitude) / math.pi;
  }

  /// ICRS position of Sgr A*; not exactly the IAU Galactic-coordinate origin.
  CelestialPosition get galacticCenter =>
      position(266.4051 * radians, -28.936175 * radians);
}

/// Artistic clear-sky visibility, not calibrated sky radiance or exposure.
double nightVisibility(SkyState sky, {bool milkyWay = false}) {
  final darkness = ((-sky.sun.altitude - 6) / 12).clamp(0.0, 1.0);
  final moon =
      sky.moonIllumination * math.max(0, math.sin(sky.moon.altitude * radians));
  return milkyWay
      ? darkness * darkness * math.pow(1 - moon, 2)
      : darkness * (1 - 0.85 * moon);
}
