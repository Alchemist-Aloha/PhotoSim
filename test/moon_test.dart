import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/astronomy.dart';
import 'package:photosim/render/moon.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

SkyState sky(
  double fraction,
  double moonAltitude, {
  double sunAltitude = -20,
}) => SkyState(
  CelestialPosition(0, sunAltitude, 150000000, 0.005, Vector3(0, 0, -1)),
  CelestialPosition(180, moonAltitude, 384000, 0.005, Vector3(0, 0, 1)),
  math.acos(2 * fraction - 1),
  true,
);

void main() {
  test(
    'Lambert illumination masks the dark hemisphere without black shading',
    () {
      final normals = Float32List.fromList([
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        -1,
      ]);
      expect(moonColors(normals, Vector3(0, 0, 1)), [
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        0,
        1,
        1,
        1,
        0,
        1,
        1,
        1,
        0,
      ]);
      final crescent = moonColors(normals, Vector3(1, 0, -1).normalized());
      expect(crescent[3], 0);
      expect(crescent[7], closeTo(1 / math.sqrt(2), 1e-7));
      final tilted = moonColors(normals, Vector3(0, 1, 0));
      expect(tilted[7], 0);
      expect(tilted[11], 1);
    },
  );

  test('visible illuminated area matches phase geometry and limb rotation', () {
    for (final phase in [
      0.0,
      math.pi / 3,
      math.pi / 2,
      2 * math.pi / 3,
      math.pi,
    ]) {
      for (final rotation in [0.0, 1.2]) {
        final light = Vector3(
          math.sin(phase) * math.cos(rotation),
          math.sin(phase) * math.sin(rotation),
          math.cos(phase),
        );
        var lit = 0, count = 0;
        for (var y = -99; y <= 99; y += 2) {
          for (var x = -99; x <= 99; x += 2) {
            final xx = x / 100, yy = y / 100;
            if (xx * xx + yy * yy > 1) continue;
            final normal = Float32List.fromList([
              xx,
              yy,
              math.sqrt(1 - xx * xx - yy * yy),
            ]);
            if (moonColors(normal, light)[3] > 1e-6) lit++;
            count++;
          }
        }
        expect(lit / count, closeTo((1 + math.cos(phase)) / 2, 0.01));
      }
    }
  });

  test('Moon-to-Sun vector preserves observer phase angle', () {
    final s = calculateSky(
      timestamp: DateTime.utc(2026, 6, 22, 3),
      latitude: 37.744,
      longitude: -119.59,
      elevation: 1200,
    );
    expect(s.moonToSunDirection.length, closeTo(1, 1e-12));
    expect(
      (-s.moon.direction).dot(s.moonToSunDirection),
      closeTo(math.cos(s.moonPhaseAngle), 1e-12),
    );
  });

  test('moonlight varies with phase, elevation and darkness', () {
    final full = moonlightIntensity(sky(1, 90));
    expect(full, closeTo(0.03, 1e-12));
    expect(moonlightIntensity(sky(0.5, 90)), closeTo(full / 4, 1e-12));
    expect(moonlightIntensity(sky(1, 30)), closeTo(full / 2, 1e-12));
    expect(moonlightIntensity(sky(0, 90)), 0);
    expect(moonlightIntensity(sky(1, -10)), 0);
    expect(moonlightIntensity(sky(1, 90, sunAltitude: 1)), 0);
    expect(
      moonlightIntensity(sky(1, 90, sunAltitude: -3)),
      closeTo(full / 2, 1e-12),
    );
  });
}
