import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/data/app_session.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';

AppSession sessionFixture({
  String workspace = 'calendar',
  bool inspectorVisible = false,
}) {
  final state = SimulationState(
    timestamp: DateTime.utc(2026, 6, 16, 5),
    latitude: -33.86,
    longitude: 151.21,
    azimuth: 271,
    pitch: 12,
    roll: 25,
    portrait: true,
    showCrosshair: false,
    showGrid: true,
    showLevel: true,
    exposureMode: ExposureMode.manual,
    iso: 3200,
    shutterSeconds: 20,
    exposureCompensation: 1.5,
    whiteBalance: 4200,
    height: 3,
    sensor: Sensor.apsC,
    focalLength: 85,
    target: CelestialTarget.moon,
    groundElevation: 900,
    fixedElevation: 800,
    relitImagery: false,
    showConstellations: true,
    terrainRings: 2,
    terrainForwardKm: 12,
    terrainRenderKm: 20,
    renderQuality: RenderQuality.high,
    antialiasing: Antialiasing.msaa,
    weather: Weather.rain,
    weatherVisibilityKm: 8,
    weatherLightTransmission: 0.5,
    rainIntensity: 0.6,
    cloudType: CloudType.cirrus,
    cloudAmount: 0.45,
    cloudSeed: 123456,
    depthOfField: true,
    aperture: 2.8,
    focusDistance: 50,
  );
  return AppSession(
    state: state,
    cleanComposition: SavedPlan(
      'Composition',
      state.copyWith(focalLength: 24),
    ).encode(),
    planName: 'Previous plan',
    workspace: workspace,
    inspectorVisible: inspectorVisible,
    timelineExpanded: true,
    calendarWeekView: true,
    mapGuideDismissed: true,
    cleanPreview: false,
    playbackSpeed: 30,
    calendarDate: DateTime.utc(2026, 8, 15),
    mapCenter: const LatLng(-34, 152),
    mapZoom: 16.5,
    expandedSections: {'Optics': true, 'Exposure': false},
  );
}

void main() {
  test('all durable composition and UI settings round-trip without derived elevation', () {
    final original = sessionFixture();
    final restored = AppSession.decode(original.encode());
    expect(restored.encode(), original.encode());
    expect(restored.state.groundElevation, isNull);
    expect(restored.state.timestamp.isUtc, isTrue);
    expect(restored.cleanComposition, original.cleanComposition);
    expect(
      SavedPlan('Composition', restored.state).encode(),
      isNot(restored.cleanComposition),
    );
  });
  test(
    'export workspace round-trips without invalidating session recovery',
    () {
      final session = sessionFixture(workspace: 'export');
      expect(AppSession.decode(session.encode()).workspace, 'export');
    },
  );
  test('older sessions default to visible map guidance', () {
    final json = jsonDecode(sessionFixture().encode()) as Map<String, dynamic>;
    json.remove('mapGuideDismissed');
    expect(AppSession.decode(jsonEncode(json)).mapGuideDismissed, isFalse);
  });
  test(
    'invalid session versions, types, coordinates and preferences are rejected',
    () {
      final json =
          jsonDecode(sessionFixture().encode()) as Map<String, dynamic>;
      for (final change in [
        {'version': 2},
        {'workspace': 'other'},
        {'playbackSpeed': 10},
        {'mapZoom': 19},
        {
          'mapCenter': [91, 0],
        },
        {
          'mapCenter': [0, 181],
        },
        {'inspectorVisible': 'yes'},
        {'mapGuideDismissed': 'yes'},
        {'mapGuideDismissed': null},
        {
          'expandedSections': {'Optics': 1},
        },
        {'calendarDate': '2026-08-15T00:00:00'},
        {'calendarDate': '2040-08-15T00:00:00.000Z'},
        {'composition': <String, Object?>{}},
        {'cleanComposition': <String, Object?>{}},
      ]) {
        expect(
          () => AppSession.decode(jsonEncode({...json, ...change})),
          throwsFormatException,
        );
      }
      expect(
        () => AppSession.decode('x' * (SessionStore.maxBytes + 1)),
        throwsFormatException,
      );
    },
  );
  test('fresh repository restores the last atomic checkpoint; failed writes retain it', () async {
    final dir = await Directory.systemTemp.createTemp('photosim-session-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/session.json');
    final store = SessionStore(file);
    expect((await store.restore()).session, isNull);
    final source = sessionFixture().encode();
    store.save(source);
    expect((await SessionStore(file).restore()).session!.encode(), source);
    await Directory('${file.path}.tmp').create();
    expect(() => store.save(source), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), source);
  });
  test('a missing session directory is a normal first launch', () async {
    final root = await Directory.systemTemp.createTemp(
      'photosim-missing-session-',
    );
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/missing/session.json');
    final restored = await SessionStore(file).restore();
    expect(restored.session, isNull);
    expect(restored.warning, isNull);
    expect(await file.parent.exists(), isFalse);
  });

  test(
    'inaccessible session directories are not treated as missing checkpoints',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'photosim-denied-session-',
      );
      addTearDown(() => root.delete(recursive: true));
      final folder = await Directory('${root.path}/private').create();
      final file = File('${folder.path}/session.json');
      final original = utf8.encode(sessionFixture().encode());
      await file.writeAsBytes(original);
      expect((await Process.run('chmod', ['000', folder.path])).exitCode, 0);
      try {
        if (await file.exists()) {
          markTestSkipped(
            'Directory permission bits are not enforced for this user.',
          );
          return;
        }
        await expectLater(
          SessionStore(file).restore(),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        expect((await Process.run('chmod', ['700', folder.path])).exitCode, 0);
      }
      expect(await file.readAsBytes(), original);
      expect((await folder.list().toList()).map((entry) => entry.uri), [
        file.uri,
      ]);
    },
    skip: !Platform.isLinux,
  );

  test(
    'unreadable and oversized sessions are preserved before starting fresh',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'photosim-bad-session-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/session.json');
      final store = SessionStore(file);
      for (final source in ['not json', 'x' * (SessionStore.maxBytes + 1)]) {
        await file.writeAsString(source);
        final restored = await store.restore();
        expect(restored.session, isNull);
        expect(restored.warning, contains('unreadable'));
        expect(await file.exists(), isFalse);
        final backups = await dir
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList();
        expect(
          await Future.wait(backups.cast<File>().map((f) => f.readAsString())),
          contains(source),
        );
        store.save(sessionFixture().encode());
        expect((await store.restore()).session, isNotNull);
      }
    },
  );
}
