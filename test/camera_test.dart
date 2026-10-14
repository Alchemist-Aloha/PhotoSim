import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/models/simulation_state.dart';

void main() {
  test('physical optics match full-frame 50 mm reference', () {
    final state = SimulationState(focalLength: 50);
    expect(state.horizontalFov * 180 / math.pi, closeTo(39.59775, 0.0001));
    expect(state.verticalFov * 180 / math.pi, closeTo(26.99147, 0.0001));
    expect(
      math.tan(state.horizontalFov / 2) / math.tan(state.verticalFov / 2),
      closeTo(state.sensor.width / state.sensor.height, 1e-12),
    );
    expect(
      state.copyWith(sensor: Sensor.apsC).horizontalFov,
      lessThan(state.horizontalFov),
    );
  });

  test('updates preserve location, UTC time and optical zoom position', () {
    final original = SimulationState(timestamp: DateTime.utc(2026, 1, 2));
    final updated = original.copyWith(azimuth: -10, pitch: 90, focalLength: 50);
    expect(updated.azimuth, 350);
    expect(updated.pitch, 85);
    expect(updated.latitude, original.latitude);
    expect(updated.longitude, original.longitude);
    expect(updated.timestamp, original.timestamp);
    expect(updated.timestamp.isUtc, isTrue);
    expect(original.focalLength, 24);
  });

  test('focal length uses one range and sensor changes preserve it', () {
    final state = SimulationState(focalLength: 200);
    expect(state.copyWith(sensor: Sensor.apsC).focalLength, 200);
    expect(state.copyWith(focalLength: 0).focalLength, 8);
    expect(state.copyWith(focalLength: 1000).focalLength, 600);
    expect(SimulationState(focalLength: 8).focalLength, 8);
    expect(SimulationState(focalLength: 600).focalLength, 600);
    expect(() => SimulationState(focalLength: 7), throwsArgumentError);
    expect(() => SimulationState(focalLength: 601), throwsArgumentError);
  });

  test(
    'ground elevation is retained for optics/time but invalidated by movement',
    () {
      final state = SimulationState(groundElevation: 1234.5);
      expect(state.copyWith(focalLength: 50).groundElevation, 1234.5);
      expect(
        state.copyWith(timestamp: DateTime.utc(2027)).groundElevation,
        1234.5,
      );
      expect(state.copyWith(latitude: 38).groundElevation, isNull);
      expect(state.copyWith(longitude: -120).groundElevation, isNull);
      expect(
        () => SimulationState(groundElevation: double.nan),
        throwsArgumentError,
      );
    },
  );

  test(
    'imagery relighting preference survives unrelated camera/time updates',
    () {
      final state = SimulationState().copyWith(relitImagery: true);
      expect(state.copyWith(focalLength: 50).relitImagery, isTrue);
      expect(
        state.copyWith(timestamp: DateTime.utc(2027)).relitImagery,
        isTrue,
      );
    },
  );

  test('invalid boundary inputs are rejected in release mode too', () {
    expect(() => SimulationState(latitude: double.nan), throwsArgumentError);
    expect(() => SimulationState(longitude: 181), throwsArgumentError);
    expect(() => SimulationState(height: -1), throwsArgumentError);
    expect(() => SimulationState(focalLength: 0), throwsArgumentError);
    expect(
      () => SimulationState(focalLength: double.infinity),
      throwsArgumentError,
    );
  });
}
