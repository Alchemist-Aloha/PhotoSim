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
import 'package:photosim/render/celestial_material.dart';
import 'package:photosim/ui/simulation_workspace.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'sky lighting and aerial perspective affect GPU pixels without reloading terrain',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-atmosphere-',
      );
      final capture = GlobalKey();
      var state = SimulationState(
        timestamp: DateTime.utc(2026, 6, 21, 19),
        pitch: -15,
        height: 100,
        showCrosshair: false,
        showGrid: false,
        showLevel: false,
      );
      late StateSetter rebuild;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: capture,
                child: StatefulBuilder(
                  builder: (context, update) {
                    rebuild = update;
                    return SimulationWorkspace(
                      state: state,
                      cacheDirectory: directory,
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
          i < 240 && find.text('Imagery 9/9').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.text('Imagery 9/9'), findsOneWidget);
        final world = tester
            .widget<scene.SceneView>(find.byType(scene.SceneView))
            .scene!;
        final nodes = world.root.children
            .where((node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name))
            .toList();
        final geometries = [
          for (final node in nodes) node.mesh!.primitives.single.geometry,
        ];
        List<String?> counts() => tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .where((text) => text?.contains(' downloaded') ?? false)
            .toList();
        final initialCounts = counts();
        Future<void> settleLighting() async {
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
        }

        Future<Uint8List> pixels([String? name]) async {
          debugPrint('Atmosphere capture: ${name ?? 'celestial probe'}');
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
            if (name != null && Platform.isLinux) {
              await Directory('build/validation').create(recursive: true);
              await File('build/validation/atmosphere-$name.png')
                  .writeAsBytes(bytes);
            }
            return bytes;
          } finally {
            image.dispose();
          }
        }

        await settleLighting();
        expect(world.skyEnvironment!.source, same(world.skybox!.source));
        expect(
          world.skyEnvironment!.refresh,
          scene.SkyEnvironmentRefresh.manual,
        );
        expect(world.skyEnvironment!.faceResolution, 64);
        expect(world.environment, isNotNull);
        expect(world.fog.enabled, isTrue);
        expect(world.fog.skyColorInfluence, 1);
        expect(
          world.fog.density,
          closeTo(scene.Fog.visibilityDensity(100000), 1e-12),
        );
        final hazed = await pixels('haze');
        world.fog.enabled = false;
        await tester.pump(const Duration(milliseconds: 100));
        final unhazed = await pixels('no-haze');
        expect(hazed, isNot(orderedEquals(unhazed)));
        world.directionalLight!.intensity = 0;
        await tester.pump(const Duration(milliseconds: 100));
        final skyLit = await pixels('sky-lit');
        world.environmentIntensity = 0;
        await tester.pump(const Duration(milliseconds: 100));
        expect(await pixels('no-sky-light'), isNot(orderedEquals(skyLit)));
        world.environmentIntensity = 1;

        // Terrestrial range fog must not attenuate the Moon/stars at proxy mesh distances.
        final camera =
            tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
                as scene.PerspectiveCamera;
        final forward = (camera.target - camera.position).normalized();
        final probe = scene.Node(
          name: 'Celestial fog probe',
          mesh: scene.Mesh(
            scene.SphereGeometry(radius: 2),
            CelestialMaterial()..baseColorFactor = vm.Vector4(1, 0, 0, 1),
          ),
        )..position = camera.position + forward * 20;
        world.add(probe);
        await tester.pump(const Duration(milliseconds: 100));
        final beforeFog = img.decodePng(await pixels())!;
        world.fog
          ..enabled = true
          ..density = 1;
        await tester.pump(const Duration(milliseconds: 100));
        final afterFog = img.decodePng(await pixels())!;
        final viewRect = tester.getRect(find.byType(scene.SceneView));
        final origin = tester.getTopLeft(find.byKey(capture));
        final point = viewRect.center - origin;
        final a = beforeFog.getPixel(point.dx.round(), point.dy.round());
        final b = afterFog.getPixel(point.dx.round(), point.dy.round());
        expect(a.r, greaterThan(a.g + 20));
        expect(b.r, closeTo(a.r, 1));
        expect(b.g, closeTo(a.g, 1));
        expect(b.b, closeTo(a.b, 1));
        world.remove(probe);

        final oldEnvironment = world.environment;
        rebuild(
          () => state = state.copyWith(
            timestamp: state.timestamp.add(const Duration(hours: 6)),
          ),
        );
        await settleLighting();
        expect(world.environment, isNot(same(oldEnvironment)));
        await pixels('evening');
        rebuild(
          () => state = state.copyWith(
            weather: Weather.cloudy,
            weatherLightTransmission: 0.5,
            renderQuality: RenderQuality.performance,
          ),
        );
        await settleLighting();
        expect(world.skyEnvironment!.source, same(world.skybox!.source));
        expect(world.skyEnvironment!.source, isA<scene.GradientSkySource>());
        expect(world.skyEnvironment!.faceResolution, 32);
        await pixels('overcast');
        rebuild(
          () => state = state.copyWith(
            weather: Weather.clear,
            relitImagery: false,
          ),
        );
        await settleLighting();
        expect(world.fog.enabled, isFalse);
        expect(world.fog.skyColorInfluence, 0);
        expect(
          (nodes.first.mesh!.primitives.single.material as scene.UnlitMaterial)
              .displayReferred,
          isTrue,
        );
        expect(counts(), initialCounts);
        for (var i = 0; i < nodes.length; i++) {
          expect(
            nodes[i].mesh!.primitives.single.geometry,
            same(geometries[i]),
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await directory.delete(recursive: true);
      }
    },
  );
}
