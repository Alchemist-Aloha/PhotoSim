import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/constellations.dart';
import 'package:photosim/core/night_sky.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('bundled catalog covers 88 constellations with two Serpens halves', () {
    final catalog = parseConstellations(
      File('assets/sky/constellations.json').readAsStringSync(),
    );
    expect(catalog.length, 89);
    expect(catalog.map((c) => c.name).toSet().length, 89);
    expect(
      catalog.map((c) => c.name),
      containsAll(['Orion', 'Scorpius', 'Serpens Caput', 'Serpens Cauda']),
    );
    for (final constellation in catalog) {
      expect(constellation.anchor.length, closeTo(1, 1e-12));
      expect(constellation.lines, isNotEmpty);
      for (final line in constellation.lines) {
        expect(line.length, greaterThanOrEqualTo(2));
        expect(
          line.every((p) => p.length.isFinite && (p.length - 1).abs() < 1e-12),
          isTrue,
        );
      }
    }
  });

  test('catalog rejects malformed names, coordinates and figures', () {
    for (final source in [
      '[]',
      '{}',
      '[["",0,0,[[[0,0],[1,1]]]]]',
      '[["Orion",181,0,[[[0,0],[1,1]]]]]',
      '[["Orion",0,0,[]]]',
      '[["Orion",0,0,[[[0,0]]]]]',
      '[["Orion",0,0,[[[0,0],[1,91]]]]]',
      '[["Orion",0,0,[[[0,0],[1,"x"]]]]]',
    ]) {
      expect(() => parseConstellations(source), throwsFormatException);
    }
  });

  test(
    'highlight ribbons face inward and cross the RA seam by the short arc',
    () {
      final data = constellationMesh(
        parseConstellations('[["Seam",180,0,[[[179,0],[-179,0],[179,0]]]]]'),
      );
      expect(data.positions, isNotEmpty);
      expect(data.positions.every((v) => v.isFinite), isTrue);
      Vector3 p(int index) => Vector3(
        data.positions[index * 3],
        data.positions[index * 3 + 1],
        data.positions[index * 3 + 2],
      );
      final a = p(data.indices[0]),
          b = p(data.indices[1]),
          c = p(data.indices[2]);
      expect((b - a).cross(c - a).dot(a), lessThan(0));
      for (var i = 0; i < data.positions.length ~/ 3; i++) {
        expect(p(i).x, lessThan(-39700));
        expect(p(i).length, closeTo(39800, 0.02));
      }
      final duplicates = constellationMesh(
        parseConstellations('[["Same",0,0,[[[0,0],[0,0]]]]]'),
      );
      expect(duplicates.positions, isEmpty);
    },
  );

  test('layer defaults off and survives optical/time/camera changes', () {
    final original = SimulationState();
    expect(original.showConstellations, isFalse);
    final enabled = original.copyWith(showConstellations: true);
    final updated = enabled.copyWith(
      sensor: Sensor.apsC,
      focalLength: 200,
      azimuth: 80,
      latitude: 40,
      timestamp: DateTime.utc(2027),
    );
    expect(updated.showConstellations, isTrue);
    expect(enabled.timestamp, original.timestamp);
    expect(enabled.location, original.location);
    expect(enabled.focalLength, original.focalLength);
    final c = parseConstellations(
      File('assets/sky/constellations.json').readAsStringSync(),
    ).first;
    Vector3 at(DateTime timestamp) {
      final frame = ObserverSkyFrame(
        timestamp: timestamp,
        latitude: 37,
        longitude: -119,
      );
      return frame.direction(
        math.atan2(c.anchor.y, c.anchor.x),
        math.asin(c.anchor.z),
      );
    }

    expect(
      (at(original.timestamp) -
              at(original.timestamp.add(const Duration(hours: 1))))
          .length,
      greaterThan(0.1),
    );
  });
}
