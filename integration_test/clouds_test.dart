import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/render/atmosphere_sky.dart';
import 'package:photosim/render/clouds.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'GPU cloud types, coverage, deterministic seed and opaque occlusion',
    (tester) async {
      await scene.Scene.initializeStaticResources();
      final sky = await AtmosphereSky.load();
      final clouds = await CloudRenderer.load();
      var state = SimulationState(
        timestamp: DateTime.utc(2026, 6, 22),
        azimuth: 280,
        pitch: 25,
        cloudAmount: 0,
        cloudSeed: 4721,
      );
      final sun = state.sky.sun;
      sky
        ..sunDirection = vm.Vector3(
          sun.direction.x,
          sun.direction.y,
          sun.direction.z,
        )
        ..sunAngularRadius = sun.angularRadius;
      final world = scene.Scene()..skybox = scene.Skybox(sky);
      world.add(clouds.node);
      final eye = vm.Vector3(0, state.height, 0);
      final frame = state.cameraFrame;
      final camera = scene.PerspectiveCamera(
        position: eye,
        target:
            eye + vm.Vector3(frame.forward.x, frame.forward.y, frame.forward.z),
        fovRadiansY: state.verticalFov,
        fovNear: 0.5,
        fovFar: 50000,
      );
      // A nearby opaque object must remain unmodified by a cloud behind it.
      final occluder = scene.Node(
        name: 'Depth occluder',
        mesh: scene.Mesh(
          scene.SphereGeometry(radius: 28, segments: 32, rings: 16),
          scene.UnlitMaterial()
            ..baseColorFactor = vm.Vector4(0.9, 0.02, 0.03, 1),
        ),
      )..position = eye + (camera.target - eye).normalized() * 300;
      world.add(occluder);
      final capture = GlobalKey();
      clouds.update(state, eye);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: scene.SceneView(world, camera: camera),
            ),
          ),
        ),
      );

      Future<Uint8List> pixels(String name, {double? rangeKm}) async {
        final currentSun = state.sky.sun;
        sky
          ..sunDirection = vm.Vector3(
            currentSun.direction.x,
            currentSun.direction.y,
            currentSun.direction.z,
          )
          ..sunAngularRadius = currentSun.angularRadius
          ..moonDirection = vm.Vector3(
            state.sky.moon.direction.x,
            state.sky.moon.direction.y,
            state.sky.moon.direction.z,
          )
          ..lunarRadiance =
              0.2 * state.sky.moonIllumination * state.sky.moonIllumination;
        final forward = state.cameraFrame.forward;
        camera.target = eye + vm.Vector3(forward.x, forward.y, forward.z);
        clouds.update(state, eye);
        if (rangeKm != null) {
          clouds.material.parameters.setFloat('max_distance', rangeKm);
        }
        await tester.pump(const Duration(milliseconds: 200));
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          if (Platform.isLinux) {
            await Directory('build/validation').create(recursive: true);
            await File('build/validation/clouds-$name.png').writeAsBytes(bytes);
          }
          return bytes;
        } finally {
          image.dispose();
        }
      }

      try {
        final clearBytes = await pixels('clear');
        final clear = img.decodePng(clearBytes)!;
        final samples = <Uint8List>[];
        for (final type in CloudType.values) {
          state = state.copyWith(cloudType: type, cloudAmount: 0.65);
          final bytes = await pixels(type.name);
          final image = img.decodePng(bytes)!;
          var changed = 0;
          for (var y = 0; y < image.height; y += 8) {
            for (var x = 0; x < image.width; x += 8) {
              final a = image.getPixel(x, y), b = clear.getPixel(x, y);
              if ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs() >
                  15) {
                changed++;
              }
            }
          }
          expect(
            changed,
            greaterThan(150),
            reason: '${type.name} must draw cloud structure',
          );
          final center = image.getPixel(image.width ~/ 2, image.height ~/ 2);
          final original = clear.getPixel(clear.width ~/ 2, clear.height ~/ 2);
          expect(
            center.r,
            closeTo(original.r, 2),
            reason: 'Clouds must not paint over foreground geometry',
          );
          expect(center.g, closeTo(original.g, 2));
          expect(center.b, closeTo(original.b, 2));
          for (final other in samples) {
            expect(bytes, isNot(orderedEquals(other)));
          }
          samples.add(bytes);
        }
        state = state.copyWith(cloudType: CloudType.cumulus, cloudAmount: 0.65);
        expect(await pixels('cumulus-restored'), orderedEquals(samples.first));
        state = state.copyWith(cloudSeed: 4722);
        expect(await pixels('randomized'), isNot(orderedEquals(samples.first)));
        state = state.copyWith(cloudAmount: 1);
        final overcast = await pixels('full-amount');
        expect(overcast, isNot(orderedEquals(samples.first)));
        state = state.copyWith(cloudAmount: 0);
        expect(await pixels('zero-restored'), orderedEquals(clearBytes));
        expect(clouds.node.visible, isFalse);
        occluder.visible = false;
        state = state.copyWith(
          cloudType: CloudType.stratus,
          cloudAmount: 1,
          pitch: 0,
        );
        final oldRange = img.decodePng(
          await pixels('horizon-64km', rangeKm: 64),
        )!;
        final farRange = img.decodePng(await pixels('horizon-256km'))!;
        final a = oldRange.getPixel(oldRange.width ~/ 2, oldRange.height ~/ 2);
        final b = farRange.getPixel(farRange.width ~/ 2, farRange.height ~/ 2);
        expect(
          (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs(),
          greaterThan(10),
          reason:
              'Spherical horizon clouds beyond 64 km must be visible at 256 km',
        );

        DateTime timeAtAltitude(DateTime day, bool rising, double altitude) {
          var error = double.infinity;
          var best = day;
          for (var minute = 0; minute < 1440; minute += 5) {
            final time = day.add(Duration(minutes: minute));
            final sun = state.copyWith(timestamp: time).sky.sun;
            if ((sun.azimuth < 180) != rising) continue;
            final next = (sun.altitude - altitude).abs();
            if (next < error) {
              error = next;
              best = time;
            }
          }
          return best;
        }

        for (final sample in [
          ('sunrise', true, 2.0),
          ('sunset', false, 2.0),
          ('after-sunset', false, -1.5),
        ]) {
          final day = DateTime.utc(2026, 6, sample.$2 ? 21 : 22);
          state = state.copyWith(
            timestamp: timeAtAltitude(day, sample.$2, sample.$3),
            cloudType: CloudType.cumulus,
            cloudAmount: 0.65,
            cloudSeed: 4721,
            pitch: 8,
          );
          state = state.copyWith(azimuth: state.sky.sun.azimuth);
          expect(await pixels(sample.$1), isNotEmpty);
        }
        state = state.copyWith(
          timestamp: DateTime.utc(2026, 6, 30, 7),
          cloudType: CloudType.stratus,
          cloudAmount: 1,
          pitch: 25,
        );
        expect(state.sky.sun.altitude, lessThan(-12));
        expect(state.sky.moon.altitude, greaterThan(0));
        final moonlit = img.decodePng(await pixels('night-moonlit'))!;
        expect(clouds.material.parameters.getFloat('daylight'), 0);
        double brightness(img.Image image) {
          var total = 0.0, count = 0;
          for (var y = 0; y < image.height * 0.6; y += 8) {
            for (var x = 0; x < image.width; x += 8) {
              final pixel = image.getPixel(x, y);
              total += (pixel.r + pixel.g + pixel.b) / 3;
              count++;
            }
          }
          return total / count;
        }

        expect(
          brightness(moonlit),
          lessThan(45),
          reason: 'Night clouds must not retain bright daylight fill',
        );
        state = state.copyWith(timestamp: DateTime.utc(2026, 6, 15, 7));
        final moonless = img.decodePng(await pixels('night-moonless'))!;
        expect(brightness(moonless), lessThan(brightness(moonlit)));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        world.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
