import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/render/atmosphere_sky.dart';
import 'package:photosim/render/photography.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'clear sky stays blue until twilight and the low Sun has a red disk',
    (tester) async {
      await scene.Scene.initializeStaticResources();
      final sky = (await AtmosphereSky.load())..sunAngularRadius = 0.00465;
      final world = scene.Scene()..skybox = scene.Skybox(sky);
      final eye = vm.Vector3(0, 2, 0);
      vm.Vector3 direction(double altitude, [double azimuth = 0]) {
        final a = altitude * math.pi / 180, z = azimuth * math.pi / 180;
        return vm.Vector3(
          math.cos(a) * math.sin(z),
          math.sin(a),
          -math.cos(a) * math.cos(z),
        );
      }

      final camera = scene.PerspectiveCamera(
        position: eye,
        target: eye + direction(30),
        fovRadiansY: 5 * math.pi / 180,
        fovNear: 0.5,
        fovFar: 50000,
      );
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: capture,
            child: scene.SceneView(world, camera: camera),
          ),
        ),
      );
      Future<(double, double, double)> sample(
        String name,
        double sunAltitude,
        double viewAltitude,
        double azimuth, {
        int quality = 8,
      }) async {
        sky
          ..sunDirection = direction(sunAltitude)
          ..viewSamples = quality
          ..lightSamples = quality == 12 ? 12 : 8;
        camera.target = eye + direction(viewAltitude, azimuth);
        await tester.pump(const Duration(milliseconds: 500));
        if (world.autoExposure.enabled) {
          for (var frame = 0; frame < 90; frame++) {
            await tester.pump(const Duration(milliseconds: 33));
          }
        }
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          await Directory('build/validation').create(recursive: true);
          await File('build/validation/sky-color-$name.png')
              .writeAsBytes(bytes);
          final decoded = img.decodePng(bytes)!;
          var r = 0.0, g = 0.0, b = 0.0;
          for (var y = -2; y <= 2; y++) {
            for (var x = -2; x <= 2; x++) {
              final pixel = decoded.getPixel(
                decoded.width ~/ 2 + x,
                decoded.height ~/ 2 + y,
              );
              r += pixel.r;
              g += pixel.g;
              b += pixel.b;
            }
          }
          final result = (r / 25, g / 25, b / 25);
          debugPrint('$name: $result');
          return result;
        } finally {
          image.dispose();
        }
      }

      for (final quality in [4, 8, 12]) {
        for (final altitude in [45.0, 30.0, 15.0]) {
          final horizon = await sample(
            'toward-sun-$altitude-q$quality',
            altitude,
            2,
            0,
            quality: quality,
          );
          expect(
            horizon.$3,
            greaterThanOrEqualTo(horizon.$1 * 0.85),
            reason: 'Daytime horizon must remain blue/neutral, not warm haze',
          );
        }
        final golden = await sample(
          'golden-q$quality',
          5,
          2,
          0,
          quality: quality,
        );
        expect(
          golden.$1,
          greaterThan(golden.$3 * 1.2),
          reason: 'The near-Sun horizon should warm naturally at low solar altitude',
        );
        for (final altitude in [45.0, 30.0, 15.0]) {
          final color = await sample(
            'day-$altitude-q$quality',
            altitude,
            30,
            90,
            quality: quality,
          );
          expect(
            color.$3,
            greaterThan(color.$1 * 1.2),
            reason: 'Daytime sky must remain blue',
          );
        }
        final low = await sample('sun-1-q$quality', 1, 1, 0, quality: quality);
        final background = await sample(
          'horizon-1-q$quality',
          1,
          1,
          2,
          quality: quality,
        );
        expect(
          (low.$1 - background.$1).abs() +
              (low.$2 - background.$2).abs() +
              (low.$3 - background.$3).abs(),
          greaterThan(25),
          reason: 'Low Sun must stand out from its aureole',
        );
        expect(
          low.$1,
          greaterThan(low.$2 * 1.08),
          reason: 'Low Sun must stay warm, not clip to a neutral white',
        );
        final limb = await sample(
          'sun-limb-q$quality',
          0,
          0.12,
          0,
          quality: quality,
        );
        final below = await sample(
          'sun-below-q$quality',
          -1,
          0.12,
          0,
          quality: quality,
        );
        expect(
          limb.$1,
          greaterThan(below.$1 + 15),
          reason:
              'Upper limb must remain visible with the center on the horizon',
        );
      }
      sky.observerHeight = 2000;
      final nearHorizonGround = await sample('day-ground-near', 15, -3, 90);
      final downwardGround = await sample('day-ground-down', 15, -30, 90);
      expect(
        (nearHorizonGround.$1 - downwardGround.$1).abs() +
            (nearHorizonGround.$2 - downwardGround.$2).abs() +
            (nearHorizonGround.$3 - downwardGround.$3).abs(),
        greaterThan(20),
        reason: 'Downward views must integrate their own paths, not repeat a flat horizon band',
      );
      sky.observerHeight = 2;
      world.directionalLight = scene.DirectionalLight();
      for (final mode in ExposureMode.values) {
        configurePhotography(world, SimulationState(exposureMode: mode));
        expect(world.autoExposure.enabled, mode != ExposureMode.manual);
        expect(
          world.autoExposure.minEv,
          mode == ExposureMode.enhanced ? 0 : -4,
        );
        expect(world.autoExposure.maxEv, mode == ExposureMode.enhanced ? 8 : 4);
      }
      configurePhotography(world, SimulationState());
      expect(world.autoExposure.enabled, isTrue);
      for (final altitude in [5.0, 1.0, 0.0, -2.0, -6.0]) {
        final color = await sample('enhanced-$altitude', altitude, 45, 90);
        expect(
          color.$3,
          greaterThan(70),
          reason:
              'Enhanced visibility must retain blue sky through civil twilight',
        );
        expect(
          color.$3,
          greaterThan(color.$1 * 1.1),
          reason: 'Warm sunset color must not replace the entire upper sky',
        );
      }
      final night = await sample('enhanced-night', -18, 45, 90);
      expect(
        math.max(night.$1, math.max(night.$2, night.$3)),
        lessThan(5),
        reason: 'Exposure adaptation must not add an artificial daylight floor',
      );
      camera.fovRadiansY = 60 * math.pi / 180;
      await sample('enhanced-sunset-wide', 0, 20, 0);
      await sample('enhanced-twilight-wide', -6, 20, 0);
      configurePhotography(
        world,
        SimulationState(exposureMode: ExposureMode.manual),
      );
      expect(world.autoExposure.enabled, isFalse);
      camera.fovRadiansY = 60 * math.pi / 180;
      await sample('afternoon-wide', 15, 20, 0);
      await sample('sunset-wide', 1, 20, 0);
      await sample('twilight-wide', -6, 20, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
