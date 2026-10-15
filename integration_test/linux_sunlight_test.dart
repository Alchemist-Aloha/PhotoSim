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
import 'package:photosim/ui/simulation_workspace.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Linux blue sky, dim red sunrise/sunset and actual edge antialiasing',
    (tester) async {
      var state = SimulationState(height: 100, focalLength: 200);
      final capture = GlobalKey();
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: StatefulBuilder(
                builder: (context, update) {
                  rebuild = update;
                  return SimulationWorkspace(
                    state: state,
                    onChanged: (next) => update(() => state = next),
                  );
                },
              ),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 240 && find.text('Imagery · 9/9 textures').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('Imagery · 9/9 textures'), findsOneWidget);
      final world = tester
          .widget<scene.SceneView>(find.byType(scene.SceneView))
          .scene!;
      final terrain = {
        for (final node in world.root.children.where(
          (node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name),
        ))
          node: node.mesh!.primitives.single.geometry,
      };
      List<String?> counts() => tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where((text) => text?.contains(' downloaded') ?? false)
          .toList();
      final initialCounts = counts();
      DateTime findSun(double altitude, bool rising) {
        var best = DateTime.utc(2026, 6, 21), error = double.infinity;
        for (var minute = 0; minute < 1440; minute++) {
          final time = DateTime.utc(2026, 6, 21).add(Duration(minutes: minute));
          final sun = state.copyWith(timestamp: time).sky.sun;
          if ((sun.azimuth < 180) != rising) continue;
          final delta = (sun.altitude - altitude).abs();
          if (delta < error) {
            best = time;
            error = delta;
          }
        }
        expect(error, lessThan(0.2));
        return best;
      }

      final rise = findSun(1, true),
          set = findSun(1, false),
          day = findSun(30, true);
      Future<img.Image> picture(String name) async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          final bytes = data.buffer.asUint8List();
          await Directory('build/validation').create(recursive: true);
          await File('build/validation/$name.png').writeAsBytes(bytes);
          return img.decodePng(bytes)!;
        } finally {
          image.dispose();
        }
      }

      (double, double, double) diskColor(img.Image image) {
        final center = tester.getCenter(find.byType(scene.SceneView));
        var r = 0.0, g = 0.0, b = 0.0;
        for (var y = -3; y <= 3; y++) {
          for (var x = -3; x <= 3; x++) {
            final pixel = image.getPixel(
              center.dx.toInt() + x,
              center.dy.toInt() + y,
            );
            r += pixel.r;
            g += pixel.g;
            b += pixel.b;
          }
        }
        return (r / 49, g / 49, b / 49);
      }

      final samples = <String, (double, double, double)>{};
      for (final sample in [
        ('sunrise', rise),
        ('sunset', set),
        ('sun-day', day),
      ]) {
        final next = state.copyWith(timestamp: sample.$2);
        final sun = next.sky.sun;
        rebuild(
          () =>
              state = next.copyWith(azimuth: sun.azimuth, pitch: sun.altitude),
        );
        await tester.pump(const Duration(seconds: 1));
        for (final node in world.root.children) {
          node.visible = false;
        }
        await tester.pump(const Duration(milliseconds: 500));
        samples[sample.$1] = diskColor(await picture('linux-${sample.$1}'));
      }
      final daytime = samples['sun-day']!;
      for (final name in ['sunrise', 'sunset']) {
        final low = samples[name]!;
        expect(
          low.$1,
          greaterThan(low.$2 * 1.5),
          reason: '$name should be red: $low',
        );
        expect(
          low.$1 + low.$2 + low.$3,
          lessThan((daytime.$1 + daytime.$2 + daytime.$3) * 0.85),
          reason: '$name should be dimmer: $low vs $daytime',
        );
      }
      rebuild(
        () => state = state.copyWith(
          pitch: 60,
          azimuth: (state.azimuth + 90) % 360,
          focalLength: 24,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final blue = diskColor(await picture('linux-blue-sky'));
      expect(
        blue.$3,
        greaterThan(blue.$1 * 1.2),
        reason: 'Clear sky should be blue: $blue',
      );

      rebuild(
        () => state = state.copyWith(
          azimuth: 0,
          pitch: 0,
          antialiasing: Antialiasing.off,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final camera =
          tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
              as scene.PerspectiveCamera;
      final eye = camera.position;
      final triangle = scene.Node(
        name: 'AA edge fixture',
        mesh: scene.Mesh(
          scene.MeshGeometry.fromArrays(
            positions: Float32List.fromList([
              eye.x - 0.8,
              eye.y - 0.6,
              eye.z - 10,
              eye.x + 0.8,
              eye.y - 0.2,
              eye.z - 10,
              eye.x - 0.3,
              eye.y + 0.8,
              eye.z - 10,
            ]),
            indices: [0, 1, 2],
          ),
          scene.UnlitMaterial(),
        ),
      );
      world.add(triangle);
      void isolate() {
        for (final node in world.root.children) {
          node.visible = node == triangle;
        }
        world.skybox = scene.Skybox(
          scene.GradientSkySource(
            zenithColor: vm.Vector3.zero(),
            horizonColor: vm.Vector3.zero(),
            groundColor: vm.Vector3.zero(),
            sunColor: vm.Vector3.zero(),
          ),
        );
      }

      isolate();
      await tester.pump(const Duration(milliseconds: 500));
      final off = await picture('linux-aa-off');
      rebuild(() => state = state.copyWith(antialiasing: Antialiasing.fxaa));
      await tester.pump(const Duration(milliseconds: 500));
      isolate();
      await tester.pump(const Duration(milliseconds: 500));
      expect(world.effectiveAntiAliasingMode, scene.AntiAliasingMode.fxaa);
      final aa = await picture('linux-aa-fxaa');
      final viewport = tester.getRect(find.byType(scene.SceneView));
      var difference = 0;
      for (var y = viewport.top.toInt(); y < viewport.bottom.toInt(); y++) {
        for (var x = viewport.left.toInt(); x < viewport.right.toInt(); x++) {
          difference +=
              (off.getPixel(x, y).r.toInt() - aa.getPixel(x, y).r.toInt())
                  .abs();
        }
      }
      expect(difference, greaterThan(1000));
      rebuild(() => state = state.copyWith(antialiasing: Antialiasing.msaa));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        world.effectiveAntiAliasingMode,
        scene.Scene.isAntiAliasingModeSupported(scene.AntiAliasingMode.msaa)
            ? scene.AntiAliasingMode.msaa
            : scene.AntiAliasingMode.fxaa,
      );
      expect(counts(), initialCounts);
      for (final entry in terrain.entries) {
        expect(entry.key.mesh!.primitives.single.geometry, same(entry.value));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
