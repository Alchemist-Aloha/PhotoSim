import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/core/sunlight.dart';
import 'package:photosim/render/atmosphere_sky.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'workspace_navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('water waves move continuously and preserve the sky reflection', (
    tester,
  ) async {
    await scene.Scene.initializeStaticResources();
    final sky = await AtmosphereSky.load();
    final water = await scene.loadFmatMaterial('assets/atmosphere/water.fmat');
    final sun = vm.Vector3(0, 0.05, -1).normalized();
    sky
      ..sunDirection = sun
      ..sunAngularRadius = 0.0047;
    final disk = sunDiskTransmission(math.asin(sun.y) * 180 / math.pi);
    water.parameters
      ..setVec3('sun_direction', sun)
      ..setVec3('sun_color', vm.Vector3(1, 0.4, 0.15))
      ..setVec3('sun_disk_color', vm.Vector3(disk.red, disk.green, disk.blue));
    final world = scene.Scene()
      ..skybox = scene.Skybox(sky)
      ..skyEnvironment = scene.SkyEnvironment(sky, faceResolution: 64)
      ..directionalLight = scene.DirectionalLight(
        direction: -sun,
        color: vm.Vector3(1, 0.4, 0.15),
        intensity: 1,
        castsShadow: false,
      );
    world.add(
      scene.Node(
        mesh: scene.Mesh(
          scene.PlaneGeometry(width: 40000, depth: 40000),
          water,
        ),
      ),
    );
    final camera = scene.PerspectiveCamera(
      position: vm.Vector3(0, 8, 0),
      target: vm.Vector3(0, 0, -100),
      fovRadiansY: 0.6,
      fovNear: 0.5,
      fovFar: 50000,
    );
    final capture = GlobalKey();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: capture,
            child: scene.SceneView(world, camera: camera),
          ),
        ),
      );
      Future<Uint8List> pixels(double seconds, String name) async {
        water.parameters.setFloat('animation_time', seconds);
        await pumpUntilRendered(tester, world);
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          await Directory('build/validation').create(recursive: true);
          await File('build/validation/water-$name.png').writeAsBytes(bytes);
          return bytes;
        } finally {
          image.dispose();
        }
      }

      double waterDifference(
        Uint8List first,
        Uint8List second, {
        double start = 0.5,
        double end = 1,
      }) {
        final a = img.decodePng(first)!, b = img.decodePng(second)!;
        var delta = 0.0, count = 0;
        for (var y = (a.height * start).round(); y < a.height * end; y += 4) {
          for (var x = 0; x < a.width; x += 4) {
            final p = a.getPixel(x, y), q = b.getPixel(x, y);
            delta += (p.r - q.r).abs() + (p.g - q.g).abs() + (p.b - q.b).abs();
            count++;
          }
        }
        return delta / count;
      }

      final initial = await pixels(0, 'sunset');
      final moving = await pixels(15, 'moving');
      expect(waterDifference(initial, moving), greaterThan(1));
      // This narrow band lies just below the horizon, beyond the old wave fade.
      expect(
        waterDifference(initial, moving, start: 0.39, end: 0.44),
        greaterThan(0.3),
      );
      final sunset = img.decodePng(initial)!;
      double peak(double start, double end) {
        var value = 0.0;
        for (
          var y = (sunset.height * start).round();
          y < sunset.height * end;
          y++
        ) {
          for (var x = 0; x < sunset.width; x++) {
            final p = sunset.getPixel(x, y);
            value = math.max(value, p.r * 0.2126 + p.g * 0.7152 + p.b * 0.0722);
          }
        }
        return value;
      }

      expect(peak(0.38, 1), lessThan(peak(0, 0.37)));
      expect(await pixels(0, 'restored'), orderedEquals(initial));
      final before = await pixels(99.9, 'before-100s');
      final middle = await pixels(100.0, 'at-100s');
      final after = await pixels(100.1, 'after-100s');
      final delta = waterDifference(before, middle);
      expect(delta, greaterThan(0));
      expect(waterDifference(middle, after), lessThan(delta * 2 + 0.5));
      water.parameters.setFloat('wave_strength', 0);
      final flat = await pixels(0, 'calm');
      expect(await pixels(15, 'calm-later'), orderedEquals(flat));
      expect(waterDifference(initial, flat), greaterThan(1));
      // With waves disabled, only the reflected deck can change these water pixels.
      water.parameters.setFloat('amount', 0.8);
      final cloudy = await pixels(0, 'cloud-reflection');
      expect(waterDifference(flat, cloudy), greaterThan(1));
      expect(
        waterDifference(cloudy, await pixels(15, 'cloud-reflection-moving')),
        greaterThan(1),
      );
      water.parameters.setFloat('wave_strength', 0.8);
      final reflectedWaves = await pixels(0, 'cloudy-waves');
      expect(waterDifference(reflectedWaves, cloudy), greaterThan(1));
      expect(
        waterDifference(
          reflectedWaves,
          await pixels(15, 'cloudy-waves-moving'),
        ),
        greaterThan(1),
      );
      water.parameters
        ..setFloat('amount', 0)
        ..setFloat('wave_strength', 0);
      expect(await pixels(0, 'clear-reflection-restored'), orderedEquals(flat));
      final highSun = vm.Vector3(0, 1, -1).normalized();
      sky.sunDirection = highSun;
      final highDisk = sunDiskTransmission(45);
      water.parameters
        ..setFloat('wave_strength', 0.8)
        ..setVec3('sun_direction', highSun)
        ..setVec3(
          'sun_disk_color',
          vm.Vector3(highDisk.red, highDisk.green, highDisk.blue),
        );
      for (final altitude in [2000.0, 8000.0]) {
        sky.observerHeight = altitude;
        world.skyEnvironment!.invalidate();
        // Environment re-bakes are time-sliced; wait for every radiance band.
        await pumpUntilRendered(tester, world, frames: 24);
        camera
          ..position = vm.Vector3(0, altitude, 0)
          ..target = vm.Vector3(0, 0, -altitude);
        final aerial = await pixels(0, 'aerial-${altitude.round()}');
        final aerialMoving = await pixels(
          15,
          'aerial-${altitude.round()}-moving',
        );
        expect(
          waterDifference(aerial, aerialMoving, start: 0, end: 1),
          greaterThan(0.02),
          reason: 'Resolved wind patches must not freeze at high altitude',
        );
        water.parameters.setFloat('wave_strength', 0);
        final aerialCalm = await pixels(0, 'aerial-${altitude.round()}-calm');
        expect(
          waterDifference(aerial, aerialCalm, start: 0, end: 1),
          greaterThan(0.5),
          reason: 'Unresolved waves must still soften aerial water reflections',
        );
        ({int area, double peak}) glint(Uint8List bytes) {
          final image = img.decodePng(bytes)!;
          double luminance(int x, int y) {
            final p = image.getPixel(x, y);
            return p.r * 0.2126 + p.g * 0.7152 + p.b * 0.0722;
          }

          final background = luminance(image.width ~/ 4, image.height ~/ 2);
          var area = 0, peak = 0.0;
          for (var y = image.height ~/ 4; y < image.height * 0.75; y++) {
            for (var x = image.width ~/ 4; x < image.width * 0.75; x++) {
              final value = luminance(x, y);
              if (value > background + 12) area++;
              peak = math.max(peak, value);
            }
          }
          return (area: area, peak: peak);
        }

        final roughGlint = glint(aerial), calmGlint = glint(aerialCalm);
        expect(
          roughGlint.area,
          greaterThan(calmGlint.area * 1.25),
          reason: 'Subpixel waves must broaden the solar glint, not sharpen it',
        );
        expect(
          roughGlint.peak,
          lessThan(calmGlint.peak),
          reason: 'Broader glitter must not make the reflection brighter',
        );
        water.parameters.setFloat('wave_strength', 0.8);
      }
      expect(world.environment, isNotNull);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      world.dispose();
    }
  });
}
