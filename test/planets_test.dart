import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/planets.dart';
import 'package:photosim/models/simulation_state.dart';

const _deg = 180 / 3.141592653589793;

void main() {
  // JPL Horizons, observer 500@399 (geocentric), astrometric ICRF/J2000 RA/Dec
  // and distance at 2026-06-21 19:00 UTC, queried 2026-10-24.
  const horizons = <Planet, (double, double, double)>{
    Planet.mercury: (115.33408, 21.22150, 0.726250),
    Planet.venus: (132.29142, 19.83381, 1.111654),
    Planet.mars: (52.34275, 18.52175, 2.132785),
    Planet.jupiter: (120.02446, 21.01050, 6.150635),
    Planet.saturn: (13.20000, 3.11189, 9.647407),
    Planet.uranus: (60.84438, 20.57433, 20.357910),
    Planet.neptune: (4.19142, 0.33458, 29.932837),
  };

  test('planet positions match JPL Horizons within one arcminute', () {
    final positions = planetPositions(DateTime.utc(2026, 6, 21, 19));
    expect(positions.length, Planet.values.length);
    for (final body in positions) {
      final (ra, dec, distance) = horizons[body.planet]!;
      final deltaRa = ((body.ra * _deg - ra) * 3600).abs();
      final deltaDec = ((body.dec * _deg - dec) * 3600).abs();
      // Light-time is modeled; aberration and relativistic deflection are not, so
      // allow a few arcseconds on top of the VSOP87 truncation.
      expect(
        deltaRa,
        lessThan(60),
        reason: '${body.planet.label} right ascension',
      );
      expect(
        deltaDec,
        lessThan(60),
        reason: '${body.planet.label} declination',
      );
      expect(
        body.distanceAu,
        closeTo(distance, 0.0005),
        reason: '${body.planet.label} geocentric distance',
      );
      expect(body.angularRadius, greaterThan(0));
      expect(body.angularRadius, lessThan(0.01 * 3.141592653589793 / 180));
    }
  });

  test('Venus and Mercury keep plausible elongations and brightness', () {
    for (final iso in [
      DateTime.utc(2025, 3, 15, 6),
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 6, 21, 19),
      DateTime.utc(2027, 9, 2, 12),
    ]) {
      final state = SimulationState(timestamp: iso);
      final sun = state.sky.sun.direction;
      for (final planet in [Planet.mercury, Planet.venus]) {
        final body = state.planets.firstWhere(
          (entry) => entry.planet == planet,
        );
        final direction = state.planetPosition(planet).direction;
        final elongation =
            math.acos(direction.dot(sun).clamp(-1.0, 1.0)) * _deg;
        expect(
          elongation,
          lessThan(planet == Planet.mercury ? 30 : 48),
          reason: '${planet.label} elongation at $iso',
        );
        expect(
          body.distanceAu,
          greaterThan(planet == Planet.mercury ? 0.5 : 0.25),
        );
        expect(body.magnitude, lessThan(6));
      }
    }
  });

  test('planet targets resolve inside the observer frame', () {
    final state = SimulationState(timestamp: DateTime.utc(2026, 6, 21, 19));
    for (final target in CelestialTarget.values) {
      final planet = target.planet;
      if (planet == null) continue;
      final position = state.copyWith(target: target).targetPosition!;
      final direct = state.planetPosition(planet);
      expect(position.azimuth, closeTo(direct.azimuth, 1e-9));
      expect(position.altitude, closeTo(direct.altitude, 1e-9));
      expect(position.distanceKm, greaterThan(0));
      expect(position.direction.length, closeTo(1, 1e-9));
      // Directions are ENU: above the horizon means +Y.
      expect((direct.altitude > 0), direct.direction.y > 0);
    }
  });

  test('planet ephemerides reject dates outside 1900-2100', () {
    expect(() => planetPositions(DateTime.utc(1899)), throwsArgumentError);
    expect(() => planetPositions(DateTime.utc(2101)), throwsArgumentError);
  });
}
