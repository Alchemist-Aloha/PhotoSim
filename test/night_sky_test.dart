import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photosim/core/astronomy.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/core/night_sky.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/render/night_sky.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('bundled catalog and licensed brightness map are valid', () {
    final stars = parseStarCatalog(
      File('assets/sky/stars.json').readAsStringSync(),
    );
    expect(stars.length, 5044);
    expect(stars.map((s) => s.id).toSet().length, stars.length);
    final sirius = stars.singleWhere((s) => s.id == 32349);
    expect(sirius.ra / radians, closeTo(101.2872, 1e-5));
    expect(sirius.magnitude, -1.44);
    final map = img.decodePng(
      File('assets/sky/milky_way.png').readAsBytesSync(),
    )!;
    expect(map.width, 1024);
    expect(map.height, 512);
    expect(map.getPixel(245, 338).a, greaterThan(0)); // Galactic center.
    final poleX = ((192.85948 - 180) / 360 * 1024).round();
    final poleY = ((90 - 27.12825) / 180 * 512).round();
    expect(map.getPixel(poleX, poleY).a, 0); // Galactic north pole.
    expect(
      File('assets/sky/LICENSE.txt').readAsStringSync(),
      contains('Olaf Frohn'),
    );
  });

  test('bundled star coordinates match SIMBAD ICRS positions', () {
    final stars = parseStarCatalog(
      File('assets/sky/stars.json').readAsStringSync(),
    );
    // SIMBAD ICRS J2000, queried 2026-10-24 via the TAP service.
    const simbad = <int, (double, double)>{
      32349: (101.287155, -16.716116), // Sirius
      91262: (279.234735, 38.783689), // Vega
      11767: (37.954561, 89.264109), // Polaris
      27989: (88.792939, 7.407064), // Betelgeuse
    };
    for (final entry in simbad.entries) {
      final star = stars.singleWhere((s) => s.id == entry.key);
      expect(
        ((star.ra / radians - entry.value.$1 + 540) % 360 - 180).abs(),
        lessThan(0.002),
        reason: 'HIP ${entry.key} right ascension',
      );
      expect(
        (star.dec / radians - entry.value.$2).abs(),
        lessThan(0.002),
        reason: 'HIP ${entry.key} declination',
      );
    }
  });

  test('Milky Way raster sits on the galactic plane, not merely near it', () {
    final map = img.decodePng(
      File('assets/sky/milky_way.png').readAsBytesSync(),
    )!;
    const poleRa = 192.85948 * radians, poleDec = 27.12825 * radians;
    var lit = 0, nearPlane = 0, sumLatitude = 0.0;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final alpha = map.getPixel(x, y).a.toInt();
        if (alpha == 0) continue;
        lit++;
        // Mesh mapping: u spans RA -180..180, v spans Dec +90..-90.
        final ra = (-180 + (x + 0.5) / map.width * 360) * radians;
        final dec = (90 - (y + 0.5) / map.height * 180) * radians;
        final sinLatitude =
            math.sin(dec) * math.sin(poleDec) +
            math.cos(dec) * math.cos(poleDec) * math.cos(ra - poleRa);
        final latitude = math.asin(sinLatitude.clamp(-1.0, 1.0)) / radians;
        sumLatitude += latitude.abs();
        if (latitude.abs() <= 20) nearPlane++;
      }
    }
    // A misplaced band shows up as lit pixels far from b=0.
    expect(nearPlane / lit, greaterThan(0.98));
    expect(sumLatitude / lit, lessThan(8));
  });

  test('galactic center marker uses the Sgr A* ICRS position', () {
    final frame = ObserverSkyFrame(
      timestamp: DateTime.utc(2026, 6, 21, 9),
      latitude: 37.744,
      longitude: -119.59,
    );
    final center = frame.galacticCenter;
    // SIMBAD: NAME Sgr A* = 266.416817, -29.007825.
    final expected = frame.position(266.416817 * radians, -29.007825 * radians);
    expect(center.azimuth, closeTo(expected.azimuth, 1e-9));
    expect(center.altitude, closeTo(expected.altitude, 1e-9));
    // 4.4' away from the IAU l=b=0 origin the old constant used.
    final legacy = frame.position(266.4051 * radians, -28.936175 * radians);
    final separation =
        math.acos(center.direction.dot(legacy.direction).clamp(-1.0, 1.0)) /
        radians;
    expect(separation * 60, closeTo(4.4, 0.3));
  });

  test('catalog parser rejects malformed and nonphysical rows', () {
    for (final source in [
      '{}',
      '[]',
      'null',
      '[{}]',
      '[[true,0,0,1]]',
      '[[1.5,0,0,1]]',
      '[[1,0,false,1]]',
      '[[1,0,0,null]]',
      '[[1,0,0]]',
      '[[1,181,0,1]]',
      '[[1,0,91,1]]',
      '[[1,0,0,7]]',
      '[[1,"x",0,1]]',
      '[[1,0,0,1e999]]',
    ]) {
      expect(() => parseStarCatalog(source), throwsFormatException);
    }
  });

  final fixtures = jsonDecode(
    File('test/fixtures/sky_rotation.json').readAsStringSync(),
  ) as Map<String, Object?>;
  for (final row
      in (fixtures['cases'] as List<Object?>).cast<Map<String, Object?>>()) {
    test('independent ERFA rotation: ${row['name']}', () {
      final frame = ObserverSkyFrame(
        timestamp: DateTime.parse(row['timestamp'] as String),
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
      );
      final direction = frame.direction(
        (row['ra'] as num) * radians,
        (row['dec'] as num) * radians,
      );
      final values = (row['direction'] as List<Object?>)
          .map((n) => (n as num).toDouble())
          .toList();
      final expected = Vector3(values[0], values[1], values[2]);
      final separation =
          math.acos(direction.dot(expected).clamp(-1.0, 1.0)) / radians;
      expect(separation, lessThan(0.01));
      expect(direction.length, closeTo(1, 1e-12));
      final position = frame.position(
        (row['ra'] as num) * radians,
        (row['dec'] as num) * radians,
      );
      expect(position.altitude, closeTo(row['altitude'] as num, 0.01));
    });
  }

  test('rotation is rigid, advances with sidereal time and handles poles', () {
    final time = DateTime.utc(2026, 6, 21, 9);
    for (final lat in [-90.0, 0.0, 90.0]) {
      final frame = ObserverSkyFrame(
        timestamp: time,
        latitude: lat,
        longitude: 180,
      );
      final x = frame.direction(0, 0),
          y = frame.direction(math.pi / 2, 0),
          z = frame.direction(0, math.pi / 2);
      expect(x.dot(y).abs(), lessThan(1e-12));
      expect(x.cross(y).dot(z), closeTo(1, 1e-12));
    }
    final a = ObserverSkyFrame(
      timestamp: time,
      latitude: 37.744,
      longitude: -119.59,
    ).galacticCenter;
    final b = ObserverSkyFrame(
      timestamp: time.add(const Duration(hours: 1)),
      latitude: 37.744,
      longitude: -119.59,
    ).galacticCenter;
    expect((a.direction - b.direction).length, greaterThan(0.1));
    expect(
      () => ObserverSkyFrame(
        timestamp: DateTime.utc(2101),
        latitude: 0,
        longitude: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () =>
          ObserverSkyFrame(timestamp: time, latitude: double.nan, longitude: 0),
      throwsArgumentError,
    );
  });

  test(
    'rectangular FOV honors pitch, wraparound, sensor, lens and rear plane',
    () {
      final state = SimulationState(azimuth: 359, pitch: 30);
      Vector3 direction(double yaw, double pitch) => Vector3(
        math.sin(yaw * radians) * math.cos(pitch * radians),
        math.sin(pitch * radians),
        -math.cos(yaw * radians) * math.cos(pitch * radians),
      );
      expect(state.containsDirection(direction(359, 30)), isTrue);
      expect(state.containsDirection(direction(1, 30)), isTrue);
      expect(state.containsDirection(direction(179, -30)), isFalse);
      expect(state.containsDirection(direction(359, 70)), isFalse);
      final edge = direction(374, 30);
      expect(state.containsDirection(edge), isTrue);
      expect(state.copyWith(focalLength: 200).containsDirection(edge), isFalse);
      final gc = state.copyWith(target: CelestialTarget.galacticCenter);
      expect(gc.targetPosition!.direction, gc.galacticCenter.direction);
      expect(
        gc.copyWith(sensor: Sensor.apsC).target,
        CelestialTarget.galacticCenter,
      );
    },
  );

  test('batched stellar geometry faces inward and scales with magnitude', () {
    final data = starMesh([
      const Star(1, 0, 0, -1),
      const Star(2, 0, 0, 6),
      const Star(3, 0, math.pi / 2, 1),
    ]);
    expect(data.positions.length, 3 * 9 * 3);
    expect(data.indices.length, 3 * 8 * 3);
    expect(data.positions.every((n) => n.isFinite), isTrue);
    Vector3 p(int index) => Vector3(
      data.positions[index * 3],
      data.positions[index * 3 + 1],
      data.positions[index * 3 + 2],
    );
    final a = p(data.indices[0]),
        b = p(data.indices[1]),
        c = p(data.indices[2]);
    expect((b - a).cross(c - a).dot(a), lessThan(0));
    expect((p(1) - p(0)).length, greaterThan((p(10) - p(9)).length));
    expect(data.colors[0], greaterThan(data.colors[9 * 4]));
  });

  test('twilight and elevated moonlight suppress the night sky', () {
    SkyState sky(double sunAlt, double moonAlt, double phase) => SkyState(
      CelestialPosition(0, sunAlt, 1, 0, Vector3(0, 1, 0)),
      CelestialPosition(0, moonAlt, 1, 0, Vector3(0, 1, 0)),
      phase,
      true,
    );
    expect(nightVisibility(sky(10, -20, 0)), 0);
    expect(nightVisibility(sky(-6, -20, 0)), 0);
    expect(nightVisibility(sky(-18, -20, 0)), 1);
    expect(nightVisibility(sky(-18, 90, 0), milkyWay: true), closeTo(0, 1e-12));
    expect(
      nightVisibility(sky(-18, 90, 0)),
      lessThan(nightVisibility(sky(-18, 90, math.pi))),
    );
    expect(nightVisibility(sky(-12, -20, 0), milkyWay: true), 0.25);
  });
}
