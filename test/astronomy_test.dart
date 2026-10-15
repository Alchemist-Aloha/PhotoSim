import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/astronomy.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

Vector3 horizontalDirection(double azimuth, double altitude) {
  final az = azimuth * radians, alt = altitude * radians;
  return Vector3(
    math.sin(az) * math.cos(alt),
    math.sin(alt),
    -math.cos(az) * math.cos(alt),
  );
}

double separation(Vector3 a, Vector3 b) =>
    math.atan2(a.cross(b).length, a.dot(b)) / radians;

void main() {
  final fixtures = jsonDecode(
    File('test/fixtures/horizons.json').readAsStringSync(),
  ) as Map<String, Object?>;
  for (final c
      in (fixtures['cases'] as List<Object?>).cast<Map<String, Object?>>()) {
    test(
      'airless topocentric Horizons reference ${c['utc']} ${c['latitude']}',
      () {
        final sky = calculateSky(
          timestamp: DateTime.parse(c['utc'] as String),
          latitude: (c['latitude'] as num).toDouble(),
          longitude: (c['longitude'] as num).toDouble(),
          elevation: (c['elevation'] as num).toDouble(),
        );
        for (final entry in [('sun', sky.sun, 0.1), ('moon', sky.moon, 0.2)]) {
          final reference = c[entry.$1] as Map<String, Object?>;
          final direction = horizontalDirection(
            (reference['azimuth'] as num).toDouble(),
            (reference['altitude'] as num).toDouble(),
          );
          expect(
            separation(entry.$2.direction, direction),
            lessThan(entry.$3),
            reason: '${entry.$1}: ${entry.$2.azimuth}°, ${entry.$2.altitude}°',
          );
          expect(entry.$2.direction.length, closeTo(1, 1e-12));
          expect(
            separation(
              entry.$2.direction,
              horizontalDirection(entry.$2.azimuth, entry.$2.altitude),
            ),
            lessThan(1e-10),
          );
          expect(entry.$2.azimuth, inInclusiveRange(0, 360));
          expect(entry.$2.altitude, inInclusiveRange(-90, 90));
        }
        expect(
          sky.moonIllumination,
          closeTo(
            ((c['moon'] as Map<String, Object?>)['illumination'] as num)
                .toDouble(),
            0.001,
          ),
        );
        expect(sky.sun.angularRadius / radians, inInclusiveRange(0.25, 0.28));
        expect(sky.moon.angularRadius / radians, inInclusiveRange(0.23, 0.30));
      },
    );
  }

  test('UTC normalization, observer elevation and time update geometry', () {
    final state = SimulationState(
      groundElevation: 1200,
      timestamp: DateTime.utc(2026, 6, 21, 19),
    );
    final sky = state.sky;
    final offset = state.copyWith(
      timestamp: DateTime.parse('2026-06-21T12:00:00-07:00'),
    );
    expect(
      separation(offset.sky.sun.direction, sky.sun.direction),
      lessThan(1e-10),
    );
    expect(
      separation(offset.sky.moon.direction, sky.moon.direction),
      lessThan(1e-10),
    );
    final later = state.copyWith(
      timestamp: state.timestamp.add(const Duration(hours: 1)),
    );
    expect(
      separation(sky.sun.direction, later.sky.sun.direction),
      greaterThan(10),
    );
    expect(
      separation(sky.moon.direction, later.sky.moon.direction),
      greaterThan(10),
    );
    final higher = state.copyWith(groundElevation: 9000).sky;
    expect(higher.moon.distanceKm, isNot(sky.moon.distanceKm));
    expect(
      separation(higher.moon.direction, sky.moon.direction),
      greaterThan(0.0001),
    );
    expect(
      state.copyWith(azimuth: 80, focalLength: 60).sky.sun.azimuth,
      sky.sun.azimuth,
    );
  });

  test('new/full phases and waxing/waning are consistent', () {
    final full = SimulationState(timestamp: DateTime.utc(2024, 3, 25, 7)).sky;
    final waxing = SimulationState(timestamp: DateTime.utc(2024, 3, 20)).sky;
    final waning = SimulationState(timestamp: DateTime.utc(2024, 3, 30)).sky;
    final newMoon = SimulationState(timestamp: DateTime.utc(2024, 4, 8, 18))
        .sky;
    expect(full.moonIllumination, greaterThan(0.999));
    expect(newMoon.moonIllumination, lessThan(0.001));
    expect(waxing.moonWaxing, isTrue);
    expect(waning.moonWaxing, isFalse);
  });

  test('poles, antimeridian and date limits stay finite', () {
    for (final latitude in [-90.0, 90.0]) {
      for (final year in [1900, 2100]) {
        final sky = calculateSky(
          timestamp: DateTime.utc(year),
          latitude: latitude,
          longitude: 180,
          elevation: -400,
        );
        expect(sky.sun.direction.length, closeTo(1, 1e-12));
        expect(sky.moon.direction.length, closeTo(1, 1e-12));
        expect(sky.moonIllumination.isFinite, isTrue);
      }
    }
    final a = calculateSky(
      timestamp: DateTime.utc(2026),
      latitude: 0,
      longitude: -180,
      elevation: 0,
    );
    final b = calculateSky(
      timestamp: DateTime.utc(2026),
      latitude: 0,
      longitude: 180,
      elevation: 0,
    );
    expect(separation(a.sun.direction, b.sun.direction), lessThan(1e-10));
  });

  test('invalid dates and observer inputs are rejected', () {
    for (final year in [1899, 2101]) {
      expect(
        () => SimulationState(timestamp: DateTime.utc(year)),
        throwsArgumentError,
      );
      expect(
        () => calculateSky(
          timestamp: DateTime.utc(year),
          latitude: 0,
          longitude: 0,
          elevation: 0,
        ),
        throwsArgumentError,
      );
    }
    for (final point in [
      (double.nan, 0.0, 0.0),
      (91.0, 0.0, 0.0),
      (0.0, 181.0, 0.0),
      (0.0, 0.0, double.infinity),
      (0.0, 0.0, 10101.0),
    ]) {
      expect(
        () => calculateSky(
          timestamp: DateTime.utc(2026),
          latitude: point.$1,
          longitude: point.$2,
          elevation: point.$3,
        ),
        throwsArgumentError,
      );
    }
  });
}
