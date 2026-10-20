import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../test/imagery_fixture.dart';
import '../test/terrain_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'camera fill remeters time changes without retaining the previous exposure',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('photosim-fill-');
      final terrain = terrainWebpFixture();
      final preview = imageryFixture(256), detail = imageryFixture(1024);
      final client = MockClient(
        (request) async => http.Response.bytes(
          request.url.host == 'tiles.mapterhorn.com'
              ? terrain
              : request.url.queryParameters['size'] == '256,256'
              ? preview
              : detail,
          200,
        ),
      );
      final capture = GlobalKey();
      final night = DateTime.utc(2026, 6, 30, 7);
      final day = DateTime.utc(2026, 6, 30, 19);
      var state = SimulationState(
        timestamp: night,
        pitch: 85,
        height: 100,
        exposureMode: ExposureMode.automatic,
        showCrosshair: false,
        showGrid: false,
        showLevel: false,
      );
      late StateSetter rebuild;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        client.close();
        await directory.delete(recursive: true);
      });
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
                    httpClient: client,
                    onChanged: (next) => update(() => state = next),
                    onGroundElevationChanged: (location, elevation) => update(
                      () => state = state.copyWith(groundElevation: elevation),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 300 && find.text('Imagery 9/9').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Imagery 9/9'), findsOneWidget);
      final view = tester.widget<scene.SceneView>(find.byType(scene.SceneView));
      final world = view.scene!;
      final camera = view.camera! as scene.PerspectiveCamera;
      world.add(
        scene.Node(
            name: 'Fill probe',
            mesh: scene.Mesh(
              scene.SphereGeometry(radius: 30),
              scene.PhysicallyBasedMaterial()
                ..baseColorFactor = vm.Vector4(0.5, 0.5, 0.5, 1)
                ..roughnessFactor = 1
                ..metallicFactor = 0,
            ),
          )
          ..position =
              camera.position +
              (camera.target - camera.position).normalized() * 300,
      );
      final light = world.root.children
          .singleWhere((node) => node.name == 'Camera light')
          .getComponent<scene.PointLightComponent>()!
          .light;
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      Future<List<double>> brightness() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          final pixels = img.decodePng(bytes)!;
          return [
            for (final point in [
              const Offset(0.15, 0.2),
              const Offset(0.5, 0.5),
            ])
              (() {
                var sum = 0.0;
                for (var y = -3; y <= 3; y++) {
                  for (var x = -3; x <= 3; x++) {
                    final pixel = pixels.getPixel(
                      (pixels.width * point.dx).round() + x,
                      (pixels.height * point.dy).round() + y,
                    );
                    sum += pixel.r + pixel.g + pixel.b;
                  }
                }
                return sum / 49;
              })(),
          ];
        } finally {
          image.dispose();
        }
      }

      final references = <DateTime, List<double>>{};
      for (final time in [night, day]) {
        rebuild(
          () => state = state.copyWith(timestamp: time, cameraLightStrength: 0),
        );
        await settle();
        world.autoExposure.reset();
        await tester.pump(const Duration(milliseconds: 20));
        world.autoExposure
          ..speedUp = 0
          ..speedDown = 0;
        rebuild(() => state = state.copyWith(cameraLightStrength: 50));
        await settle();
        references[time] = await brightness();
      }
      for (final time in [night, day, night]) {
        rebuild(() => state = state.copyWith(timestamp: time));
        await settle();
        final actual = await brightness();
        debugPrint('Fill at $time: $actual; reference ${references[time]}');
        expect(light.intensity, 25000);
        for (var i = 0; i < actual.length; i++) {
          expect(
            actual[i],
            closeTo(references[time]![i], 4),
            reason: 'sky/probe brightness must not depend on the previous time',
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );
}
