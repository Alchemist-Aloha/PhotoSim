import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/exposure.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/core/terrain_coverage.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/photography_overlays.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  testWidgets(
    'playback speed selection changes UTC rate without changing optics',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PhotoSimApp());
      SimulationState current() =>
          tester.widget<CameraInspector>(find.byType(CameraInspector)).state;
      final original = current();
      await tester.tap(find.byTooltip('Playback speed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min/s'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Play time (30 simulated minutes per second)'),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        current().timestamp.difference(original.timestamp),
        const Duration(minutes: 30),
      );
      expect(current().focalLength, original.focalLength);
      expect(current().location, original.location);
      await tester.tap(find.byTooltip('Pause time'));
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('manual exposure obeys photographic stop ratios, enhanced/auto ignore ISO/shutter', () {
    final state = SimulationState(exposureMode: ExposureMode.manual);
    expect(exposureMultiplier(state), 1);
    expect(exposureMultiplier(state.copyWith(iso: 200)), 2);
    expect(exposureMultiplier(state.copyWith(shutterSeconds: 1 / 250)), 0.5);
    expect(exposureMultiplier(state.copyWith(aperture: 16)), 0.25);
    expect(exposureMultiplier(state.copyWith(exposureCompensation: 1)), 2);
    for (final mode in [ExposureMode.enhanced, ExposureMode.automatic]) {
      expect(
        exposureMultiplier(
          state.copyWith(exposureMode: mode, iso: 25600, shutterSeconds: 30),
        ),
        1,
      );
    }
  });
  test(
    'roll, portrait, target frustum and coverage share the optical frame',
    () {
      final state = SimulationState(pitch: 0);
      final portrait = state.copyWith(portrait: true);
      expect(portrait.horizontalFov, state.verticalFov);
      expect(portrait.verticalFov, state.horizontalFov);
      expect(state.containsDirection(Vector3(0.6, 0, -1)), isTrue);
      expect(portrait.containsDirection(Vector3(0.6, 0, -1)), isFalse);
      expect(portrait.containsDirection(Vector3(0, 0.6, -1)), isTrue);
      final target = state.copyWith(target: CelestialTarget.sun);
      expect(
        target
            .copyWith(
              azimuth: target.sky.sun.azimuth,
              pitch: target.sky.sun.altitude,
            )
            .targetAngularOffset,
        closeTo(0, 1e-5),
      );
      final rolled = state.copyWith(roll: 90);
      expect(rolled.containsDirection(Vector3(0.6, 0, -1)), isFalse);
      expect(rolled.cameraFrame.up.x, closeTo(1, 1e-12));
      expect(rolled.mapFov, closeTo(state.verticalFov, 1e-12));
      for (final roll in [-180.0, -90.0, -25.0, 0.0, 30.0, 90.0, 180.0]) {
        final next = state.copyWith(
          roll: roll,
          portrait: true,
          terrainForwardKm: 40,
        );
        final frame = next.cameraFrame;
        expect(frame.forward.dot(frame.up), closeTo(0, 1e-12));
        expect(frame.right.dot(frame.up), closeTo(0, 1e-12));
        expect(frame.up.length, closeTo(1, 1e-12));
        final tiles = terrainCoverage(next);
        expect(tiles.length, lessThanOrEqualTo(terrainTileBudget));
        expect(tiles.map((tile) => tile.key).toSet().length, tiles.length);
      }
    },
  );
  test(
    'new photography settings persist, validate and retain old plan defaults',
    () {
      final state = SimulationState(
        roll: 30,
        portrait: true,
        showCrosshair: false,
        showGrid: true,
        showLevel: true,
        exposureMode: ExposureMode.manual,
        iso: 800,
        shutterSeconds: 0.5,
        exposureCompensation: -2,
        whiteBalance: 4000,
      );
      final restored = SavedPlan.decode(SavedPlan('Portrait', state).encode())
          .state;
      expect(restored.roll, 30);
      expect(restored.portrait, isTrue);
      expect(restored.showCrosshair, isFalse);
      expect(restored.showGrid, isTrue);
      expect(restored.showLevel, isTrue);
      expect(restored.exposureMode, ExposureMode.manual);
      expect(restored.iso, 800);
      expect(restored.shutterSeconds, 0.5);
      expect(restored.exposureCompensation, -2);
      expect(restored.whiteBalance, 4000);
      final json = jsonDecode(
        SavedPlan('Legacy', state).encode(),
      ) as Map<String, dynamic>;
      for (final key in [
        'roll',
        'portrait',
        'showCrosshair',
        'showGrid',
        'showLevel',
        'exposureMode',
        'iso',
        'shutterSeconds',
        'exposureCompensation',
        'whiteBalance',
      ]) {
        json.remove(key);
      }
      final legacy = SavedPlan.decode(jsonEncode(json)).state;
      expect(legacy.roll, 0);
      expect(legacy.portrait, isFalse);
      expect(legacy.showCrosshair, isTrue);
      expect(legacy.showGrid, isFalse);
      expect(legacy.showLevel, isFalse);
      expect(legacy.exposureMode, ExposureMode.enhanced);
      expect(exposureMultiplier(legacy), 1);
      for (final bad in [
        ('roll', 181),
        ('iso', 49),
        ('iso', 30000),
        ('portrait', 1),
        ('shutterSeconds', 0),
        ('shutterSeconds', 31),
        ('exposureCompensation', 6),
        ('whiteBalance', 1000),
        ('exposureMode', 'bogus'),
      ]) {
        expect(
          () => SavedPlan.decode(jsonEncode({...json, bad.$1: bad.$2})),
          throwsFormatException,
        );
      }
      expect(() => state.copyWith(iso: double.nan), throwsArgumentError);
      expect(() => state.copyWith(roll: double.infinity), throwsArgumentError);
    },
  );
  testWidgets(
    'exposure controls, orientation and composition guides are usable',
    (tester) async {
      var state = SimulationState();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => CameraInspector(
                state: state,
                onChanged: (next) => update(() => state = next),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Portrait'));
      await tester.pumpAndSettle();
      expect(state.portrait, isTrue);
      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exposure'));
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButtonFormField<ExposureMode>>(
            find.byType(DropdownButtonFormField<ExposureMode>),
          )
          .onChanged!(ExposureMode.manual);
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byKey(const ValueKey('iso'))).onChanged!(
        math.log(800 / 50) / math.ln2,
      );
      await tester.pump();
      tester.widget<Slider>(find.byKey(const ValueKey('shutter'))).onChanged!(
        -1,
      );
      await tester.pump();
      expect(state.iso, closeTo(800, 1e-8));
      expect(state.shutterSeconds, 0.5);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: PhotographyOverlays(
              state: state.copyWith(showGrid: true, showLevel: true, roll: 90),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Roll 90.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
