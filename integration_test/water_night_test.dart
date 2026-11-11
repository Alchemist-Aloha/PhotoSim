import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/render/atmosphere_sky.dart';
import 'package:photosim/render/moon.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'workspace_navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('night water stays as dark as the sky and reflects the Moon', (
    tester,
  ) async {
    await scene.Scene.initializeStaticResources();
    final sky = await AtmosphereSky.load();
    final water = await scene.loadFmatMaterial('assets/atmosphere/water.fmat');
    final sun = vm.Vector3(0, -0.4, 1).normalized();
    final moon = vm.Vector3(0, 0.12, -1).normalized();
    sky
      ..sunDirection = sun
      ..moonDirection = moon
      ..lunarRadiance = 0.2 * moonlightScale;
    water.parameters
      ..setVec3('sun_direction', sun)
      ..setVec3('moon_direction', moon)
      ..setFloat('lunar_radius', 0.0045)
      ..setFloat('animation_time', 3);
    final world = scene.Scene()
      ..skybox = scene.Skybox(sky)
      ..skyEnvironment = scene.SkyEnvironment(sky, faceResolution: 64)
      // Resolve the moonlit scene the way enhanced exposure does at night.
      ..exposure = 256;
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
      Future<img.Image> render(String name, double moonBrightness) async {
        water.parameters.setVec3(
          'moon_disk_color',
          vm.Vector3(1, 0.95, 0.85) * moonBrightness,
        );
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
          return img.decodePng(bytes)!;
        } finally {
          image.dispose();
        }
      }

      double luminance(
        img.Image image,
        double x0,
        double x1,
        double y0,
        double y1,
      ) {
        var total = 0.0, count = 0;
        for (
          var y = (image.height * y0).round();
          y < image.height * y1;
          y += 2
        ) {
          for (
            var x = (image.width * x0).round();
            x < image.width * x1;
            x += 2
          ) {
            final p = image.getPixel(x, y);
            total += p.r * 0.2126 + p.g * 0.7152 + p.b * 0.0722;
            count++;
          }
        }
        return total / count;
      }

      final dark = await render('night-moonless-disk', 0);
      final lit = await render('night-moonlit', 0.15);
      // Away from the Moon's path, water reflects the sky; it must not glow above it.
      final skyBand = luminance(dark, 0, 0.3, 0.3, 0.45);
      final waterBand = luminance(dark, 0, 0.3, 0.6, 0.95);
      expect(
        waterBand,
        lessThanOrEqualTo(skyBand * 1.1 + 2),
        reason:
            'Night water must not be brighter than the sky ($waterBand vs $skyBand)',
      );
      final path = luminance(lit, 0.47, 0.53, 0.40, 0.58);
      final beside = luminance(lit, 0.2, 0.3, 0.40, 0.58);
      expect(
        path,
        greaterThan(beside + 5),
        reason: 'The Moon must leave a glitter path ($path vs $beside)',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      world.dispose();
    }
  });
}
