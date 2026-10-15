import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';

void main() {
  final state = SimulationState(
    latitude: -33.86,
    longitude: 151.21,
    azimuth: 271,
    pitch: -12,
    height: 3.2,
    sensor: Sensor.apsC,
    focalLength: 321,
    target: CelestialTarget.galacticCenter,
    relitImagery: true,
    showConstellations: true,
    terrainRings: 2,
    terrainForwardKm: 25,
    terrainRenderKm: 15,
    groundElevation: 90,
    timestamp: DateTime.parse('2026-01-01T20:00:00+08:00'),
  );

  test(
    'versioned JSON preserves the composition, not derived ground elevation',
    () {
      final plan = SavedPlan.decode(
        SavedPlan('Sydney composition', state).encode(),
      );
      expect(plan.name, 'Sydney composition');
      expect(plan.state.latitude, state.latitude);
      expect(plan.state.longitude, state.longitude);
      expect(plan.state.azimuth, state.azimuth);
      expect(plan.state.pitch, state.pitch);
      expect(plan.state.height, state.height);
      expect(plan.state.sensor, state.sensor);
      expect(plan.state.focalLength, state.focalLength);
      expect(plan.state.target, state.target);
      expect(plan.state.relitImagery, state.relitImagery);
      expect(plan.state.showConstellations, isTrue);
      expect(plan.state.terrainRings, 2);
      expect(plan.state.terrainForwardKm, 25);
      expect(plan.state.terrainRenderKm, 15);
      expect(plan.state.timestamp, state.timestamp);
      expect(plan.state.timestamp.isUtc, isTrue);
      expect(plan.state.groundElevation, isNull);
      for (final target in CelestialTarget.values) {
        expect(
          SavedPlan.decode(
            SavedPlan('Target', state.copyWith(target: target)).encode(),
          ).state.target,
          target,
        );
      }
    },
  );

  test('old plans without constellation preference default to off', () {
    final json =
        jsonDecode(SavedPlan('Old', state).encode()) as Map<String, dynamic>;
    json.remove('showConstellations');
    for (final version in [1, 2]) {
      expect(
        SavedPlan.decode(jsonEncode({...json, 'version': version}))
            .state
            .showConstellations,
        isFalse,
      );
    }
  });

  test(
    'legacy plans without terrain ranges keep the original 3×3 defaults',
    () {
      final json = jsonDecode(
        SavedPlan('Old terrain', state).encode(),
      ) as Map<String, Object?>;
      json.remove('terrainRings');
      json.remove('terrainForwardKm');
      json.remove('terrainRenderKm');
      for (final version in [1, 2]) {
        final restored = SavedPlan.decode(
          jsonEncode({...json, 'version': version}),
        ).state;
        expect(restored.terrainRings, 1);
        expect(restored.terrainForwardKm, 0);
        expect(restored.terrainRenderKm, 40);
      }
    },
  );

  test('legacy lens presets do not change saved focal length or sensor', () {
    final json =
        jsonDecode(SavedPlan('Legacy', state).encode()) as Map<String, dynamic>;
    for (final lens in ['wide', 'standard', 'telephoto', 'custom']) {
      final restored = SavedPlan.decode(
        jsonEncode({...json, 'version': 1, 'lens': lens}),
      );
      expect(restored.state.focalLength, state.focalLength);
      expect(restored.state.sensor, state.sensor);
      final encoded = jsonDecode(restored.encode()) as Map<String, Object?>;
      expect(encoded.containsKey('lens'), isFalse);
      expect(encoded['version'], 2);
    }
  });

  test(
    'invalid versions, fields, names and dates are rejected without clamping',
    () {
      final source = jsonDecode(
        SavedPlan('Valid', state).encode(),
      ) as Map<String, Object?>;
      for (final entry in [
        ('version', 3),
        ('version', 1.0),
        ('latitude', 100),
        ('longitude', '151'),
        ('pitch', 90),
        ('azimuth', 360),
        ('height', -1),
        ('sensor', 'unknown'),
        ('target', 'unknown'),
        ('focalLength', 1000),
        ('relitImagery', 1),
        ('showConstellations', 1),
        ('terrainRings', 4),
        ('terrainRings', 1.5),
        ('terrainForwardKm', 41),
        ('terrainForwardKm', '20'),
        ('terrainRenderKm', -1),
        ('name', ''),
        ('name', 'x' * 81),
        ('timestamp', '2026-02-30T00:00:00.000Z'),
        ('timestamp', '2026-01-01T00:00:00+01:00'),
        ('timestamp', '2101-01-01T00:00:00.000Z'),
      ]) {
        expect(
          () => SavedPlan.decode(jsonEncode({...source, entry.$1: entry.$2})),
          throwsFormatException,
        );
      }
      expect(() => SavedPlan.decode('{}'), throwsFormatException);
      expect(() => SavedPlan.decode('[]'), throwsFormatException);
      expect(() => SavedPlan.decode(' ' * 32769), throwsFormatException);
    },
  );

  test(
    'native snapshots reopen through a fresh repository and never overwrite',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-plans-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = PlanRepository(directory);
      final files = await Future.wait(
        List.generate(3, (i) => store.save(SavedPlan('Plan $i', state))),
      );
      expect(files.map((f) => f.path).toSet().length, 3);
      final opened = await PlanRepository(directory).loadAll();
      expect(opened.plans.length, 3);
      expect(opened.unreadable, 0);
      expect(opened.plans.map((p) => p.name).toSet(), {
        'Plan 0',
        'Plan 1',
        'Plan 2',
      });
      expect(
        opened.plans.every(
          (p) => p.state.target == CelestialTarget.galacticCenter,
        ),
        isTrue,
      );
      expect((await directory.list().toList()).whereType<Directory>(), isEmpty);
      final original = await files.first.readAsString();
      await File('${directory.path}/broken.json').writeAsString('{bad');
      await File('${directory.path}/huge.json').writeAsString(' ' * 32769);
      await Directory('${directory.path}/.pending-crash').create();
      final withCorruption = await store.loadAll();
      expect(withCorruption.plans.length, 3);
      expect(withCorruption.unreadable, 2);
      expect(await files.first.readAsString(), original);
      expect(await File('${directory.path}/broken.json').exists(), isTrue);
    },
  );

  test(
    'missing storage is empty; a failed save does not delete existing data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-plans-',
      );
      addTearDown(() => directory.delete(recursive: true));
      expect(
        (await PlanRepository(
          Directory('${directory.path}/missing'),
        ).loadAll()).plans,
        isEmpty,
      );
      final blocker = File('${directory.path}/not-a-directory');
      await blocker.writeAsString('Keep this data');
      final store = PlanRepository(Directory(blocker.path));
      await expectLater(
        store.save(SavedPlan('Plan', state)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await blocker.readAsString(), 'Keep this data');
    },
  );
}
