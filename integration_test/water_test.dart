// Inspect the private scene state without adding production test-only APIs.
// ignore_for_file: avoid_dynamic_calls

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/water/water_repository.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import '../test/terrain_fixture.dart';
import '../test/water_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'static water renders clipped surfaces and shores, reloads and toggles without stale nodes',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-water-scene-',
      );
      final cache = RasterCache(Directory('${directory.path}/cache'));
      final atlas = TileId(10, 942, 614),
          location = TileId(10, 942, 614).point(0.46, 0.46);
      // Polygon coverage must work even when MODIS has no lake pixels.
      final mask = waterFixture(wet: (_, _) => false);
      final polygons = lakeFixture(atlas, [
        [
          // Deliberately angular source geometry exercises rendered Bezier corners.
          for (var i = 0; i <= 8; i++)
            [
              0.46 + 0.055 * math.cos(i % 8 / 8 * math.pi * 2),
              0.46 + 0.055 * math.sin(i % 8 / 8 * math.pi * 2),
            ],
        ],
      ]);
      final land = image.Image(width: 256, height: 256, numChannels: 3);
      image.fill(land, color: image.ColorRgb8(104, 135, 72));
      final landBytes = image.encodePng(land);
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'data-gis.unep-wcmc.org') {
          return http.Response.bytes(polygons, 200);
        }
        if (request.url.queryParameters['LAYERS'] == oceanProvider.layer) {
          return http.Response.bytes(coastFixture(), 200);
        }
        if (request.url.queryParameters['LAYERS'] == waterProvider.layer) {
          return http.Response.bytes(mask, 200);
        }
        if (request.url.host.contains('mapterhorn')) {
          return http.Response('missing', 404);
        }
        if (request.url.host == 's3.amazonaws.com') {
          return http.Response.bytes(
            terrainFixture(
              height: request.url.path.contains('/10/') ? 100 : 101,
            ),
            200,
          );
        }
        return http.Response.bytes(landBytes, 200);
      });
      var state = SimulationState(
        useNasaData: false,
        latitude: location.latitude,
        longitude: location.longitude,
        height: 100,
        fixedElevation: 2000,
        pitch: -80,
        focalLength: 24,
        timestamp: DateTime.utc(2026, 1, 1, 2),
      );
      final capture = GlobalKey();
      late StateSetter rebuild;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        client.close();
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return SimulationWorkspace(
                    state: state,
                    httpClient: client,
                    rasterCache: cache,
                    onChanged: (next) => setState(() => state = next),
                    onGroundElevationChanged: (position, height) {
                      if (position == state.location) {
                        setState(
                          () => state = state.copyWith(groundElevation: height),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      final dynamic workspace = tester.state(find.byType(SimulationWorkspace));
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 400; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (condition()) return;
        }
        fail('Water scene did not finish: ${workspace.waterFailure}');
      }

      await waitFor(
        () =>
            workspace.loading == false &&
            workspace.waterNodes.length == 9 &&
            workspace.imageryLoading == false,
      );
      expect(workspace.error, isNull);
      expect(workspace.waterFailure, isNull);
      expect(find.textContaining(waterAttribution), findsOneWidget);
      final nodes = (workspace.terrainNodes as List<scene.Node>)
          .where((node) => node.name.startsWith('water-'))
          .toList();
      expect(nodes, isNotEmpty);
      expect(
        (workspace.terrainNodes as List<scene.Node>).any(
          (node) => node.name.startsWith('shore-'),
        ),
        isTrue,
      );
      final material =
          nodes.first.mesh!.primitives.single.material
              as scene.PreprocessedMaterial;
      expect(material.parameters.getFloat('roughness'), closeTo(0.025, 1e-6));
      expect(material.parameters.getFloat('wave_strength'), closeTo(0.8, 1e-6));
      expect(material.parameters.getFloat('animation_time'), greaterThan(0));
      expect(
        requests.where(
          (uri) => uri.queryParameters['LAYERS'] == waterProvider.layer,
        ),
        hasLength(1),
      );
      expect(
        requests.any((uri) => uri.host == 'data-gis.unep-wcmc.org'),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = await boundary.toImage();
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/validation').create(recursive: true);
      await File('build/validation/linux-static-water.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      rendered.dispose();
      final corner = atlas.point(0.515, 0.46);
      rebuild(
        () => state = state.copyWith(
          latitude: corner.latitude,
          longitude: corner.longitude,
          fixedElevation: 140,
        ),
      );
      await waitFor(
        () =>
            workspace.loading == false &&
            workspace.waterNodes.length == 9 &&
            workspace.imageryLoading == false,
      );
      await tester.pump(const Duration(seconds: 1));
      final closeup = await boundary.toImage();
      final closeupBytes = await closeup.toByteData(
        format: ui.ImageByteFormat.png,
      );
      await File('build/validation/linux-curved-shore.png')
          .writeAsBytes(closeupBytes!.buffer.asUint8List());
      closeup.dispose();
      // A mesh-resolution change must rebuild water alongside terrain, not lose its carving.
      rebuild(() => state = state.copyWith(renderQuality: RenderQuality.high));
      await waitFor(
        () => workspace.loading == false && workspace.waterNodes.length == 9,
      );
      expect(workspace.waterFailure, isNull);
      rebuild(() => state = state.copyWith(showWater: false));
      await waitFor(() => workspace.loading == false && workspace.loaded == 9);
      expect(workspace.waterNodes, isEmpty);
      expect(find.textContaining(waterAttribution), findsNothing);
      expect(state.groundElevation, closeTo(101, 0.01));
      final before = requests.length;
      rebuild(() => state = state.copyWith(showWater: true));
      await waitFor(
        () => workspace.loading == false && workspace.waterNodes.length == 9,
      );
      expect(workspace.waterFailure, isNull);
      expect(
        requests
            .skip(before)
            .where(
              (uri) => uri.queryParameters['LAYERS'] == waterProvider.layer,
            ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
