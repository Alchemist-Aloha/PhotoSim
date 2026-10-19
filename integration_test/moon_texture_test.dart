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
import 'package:photosim/core/astronomy.dart';
import 'package:photosim/core/night_sky.dart';
import 'package:photosim/render/moon.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real lunar albedo adds GPU surface detail without changing phase geometry',
    (tester) async {
      await scene.Scene.initializeStaticResources();
      final albedo = await scene.Texture2D.fromAsset(
        'assets/moon/lroc_color_2k.jpg',
      );
      final moon = MoonRenderer(albedo);
      final world = scene.Scene()
        ..skybox = scene.Skybox(
          scene.GradientSkySource(
            zenithColor: vm.Vector3(0.002, 0.004, 0.008),
            horizonColor: vm.Vector3(0.002, 0.004, 0.008),
            sunColor: vm.Vector3.zero(),
          ),
        );
      world.add(moon.node);
      final eye = vm.Vector3.zero();
      final camera = scene.PerspectiveCamera(
        position: eye,
        target: vm.Vector3(0, 0, -1),
        fovRadiansY: 1.5 * math.pi / 180,
        fovNear: 0.5,
        fovFar: 50000,
      );
      SkyState pose(DateTime time) {
        final sky = calculateSky(
          timestamp: time,
          latitude: 37.744,
          longitude: -119.59,
          elevation: 1500,
        );
        final pole = ObserverSkyFrame(
          timestamp: time,
          latitude: 37.744,
          longitude: -119.59,
        ).direction(269.9949 * math.pi / 180, 66.5392 * math.pi / 180);
        moon.update(sky, eye, pole);
        camera.target = vm.Vector3(
          sky.moon.direction.x,
          sky.moon.direction.y,
          sky.moon.direction.z,
        );
        return sky;
      }

      final full = pose(DateTime.utc(2026, 6, 30, 7));
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: Transform.flip(
                flipX: true,
                child: scene.SceneView(world, camera: camera),
              ),
            ),
          ),
        ),
      );
      Future<Uint8List> pixels(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
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
            await File('build/validation/$name.png').writeAsBytes(bytes);
          }
          return bytes;
        } finally {
          image.dispose();
        }
      }

      final geometry = moon.node.mesh!.primitives.single.geometry;
      final material =
          moon.node.mesh!.primitives.single.material as scene.UnlitMaterial;
      expect(material.baseColorTexture, same(albedo));
      final textured = img.decodePng(await pixels('moon-textured-full'))!;
      material.baseColorTexture = null;
      final plain = img.decodePng(await pixels('moon-plain-reference'))!;
      final center =
          tester.getCenter(find.byType(scene.SceneView)) -
          tester.getTopLeft(find.byKey(capture));
      final radius =
          full.moon.angularRadius /
          math.tan(camera.fovRadiansY / 2) *
          tester.getSize(find.byType(scene.SceneView)).height /
          2;
      num spread(img.Image image) {
        num low = 255, high = 0;
        for (var y = -radius * 0.4; y <= radius * 0.4; y += 4) {
          for (var x = -radius * 0.4; x <= radius * 0.4; x += 4) {
            final pixel = image.getPixel(
              (center.dx + x).round(),
              (center.dy + y).round(),
            );
            low = math.min(low, pixel.r);
            high = math.max(high, pixel.r);
          }
        }
        return high - low;
      }

      expect(spread(textured), greaterThan(spread(plain) + 8));
      material.baseColorTexture = albedo;
      pose(DateTime.utc(2026, 6, 22, 3));
      final quarter = await pixels('moon-textured-quarter');
      pose(DateTime.utc(2026, 6, 30, 7));
      expect(
        quarter,
        isNot(orderedEquals(await pixels('moon-textured-full-restored'))),
      );
      // Verify the same resident geometry/material/texture survive a date/phase change.
      expect(moon.node.mesh!.primitives.single.geometry, same(geometry));
      expect(moon.node.mesh!.primitives.single.material, same(material));
      expect(material.baseColorTexture, same(albedo));
      await tester.pumpWidget(const SizedBox());
      world.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
