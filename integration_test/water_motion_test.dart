import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
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
    water.parameters
      ..setVec3('sun_direction', sun)
      ..setVec3('sun_color', vm.Vector3(1, 0.4, 0.15));
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
    final capture = GlobalKey();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: capture,
            child: scene.SceneView(
              world,
              camera: scene.PerspectiveCamera(
                position: vm.Vector3(0, 8, 0),
                target: vm.Vector3(0, 0, -100),
                fovRadiansY: 0.6,
                fovNear: 0.5,
                fovFar: 50000,
              ),
            ),
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

      double waterDifference(Uint8List first, Uint8List second) {
        final a = img.decodePng(first)!, b = img.decodePng(second)!;
        var delta = 0.0, count = 0;
        for (var y = a.height ~/ 2; y < a.height; y += 4) {
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
      expect(world.environment, isNotNull);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      world.dispose();
    }
  });
}
