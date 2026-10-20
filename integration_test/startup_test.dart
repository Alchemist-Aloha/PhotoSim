import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/terrain/terrain_provider.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import '../test/imagery_fixture.dart';
import '../test/terrain_fixture.dart';

class DelayedCache extends RasterCache {
  DelayedCache(super.directory, this.ready);
  final Future<void> ready;
  Future<void>? initialization;

  @override
  Future<void> initialize() =>
      initialization ??= ready.then((_) => super.initialize());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'scene bypasses indexing; center imagery bypasses slow neighbors',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-startup-',
      );
      final indexReady = Completer<void>(), neighborsReady = Completer<void>();
      final cache = DelayedCache(directory, indexReady.future);
      var state = SimulationState(
        height: 100,
        pitch: -40,
        showConstellations: false,
      );
      final center = TerrainProvider.mapterhorn.request(
        TileId.at(state.location),
      );
      final terrain = terrainWebpFixture();
      final preview = imageryFixture(256), detail = imageryFixture(1024);
      var terrainRequests = 0, previewRequests = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'tiles.mapterhorn.com') {
          terrainRequests++;
          if (request.url != center) await neighborsReady.future;
          return http.Response.bytes(terrain, 200);
        }
        final isPreview = request.url.queryParameters['size'] == '256,256';
        if (isPreview) previewRequests++;
        return http.Response.bytes(isPreview ? preview : detail, 200);
      });
      addTearDown(() async {
        if (!indexReady.isCompleted) indexReady.complete();
        if (!neighborsReady.isCompleted) neighborsReady.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        client.close();
        await directory.delete(recursive: true);
      });
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return SimulationWorkspace(
                  state: state,
                  rasterCache: cache,
                  httpClient: client,
                  onChanged: (next) => setState(() => state = next),
                  onGroundElevationChanged: (location, elevation) {
                    if (state.location == location) {
                      setState(
                        () =>
                            state = state.copyWith(groundElevation: elevation),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ),
      );
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 300 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(ready(), isTrue);
      }

      scene.Scene? world;
      await until(() {
        final views = find.byType(scene.SceneView);
        if (views.evaluate().isEmpty) return false;
        world = tester.widget<scene.SceneView>(views).scene!;
        return world!.renderStats.frameCount > 0;
      });
      expect(indexReady.isCompleted, isFalse);
      expect(terrainRequests, 0);
      final sky = world!.root.children.singleWhere(
        (node) => node.name == 'Night sky',
      );
      expect(
        sky.children.any((node) => node.name == 'Constellations'),
        isFalse,
      );

      indexReady.complete();
      await until(() => previewRequests > 0);
      expect(neighborsReady.isCompleted, isFalse);
      expect(find.text('Terrain 9/9'), findsNothing);
      expect(state.groundElevation, isNotNull);
      neighborsReady.complete();
      await until(() => find.text('Imagery 9/9').evaluate().isNotEmpty);
      expect(previewRequests, 9); // No duplicate center preview.

      update(() => state = state.copyWith(showConstellations: true));
      await until(
        () => sky.children.any((node) => node.name == 'Constellations'),
      );
      final guides = sky.children.singleWhere(
        (node) => node.name == 'Constellations',
      );
      await tester.pump();
      expect(guides.visible, isTrue);
      update(() => state = state.copyWith(showConstellations: false));
      await tester.pump();
      expect(guides.visible, isFalse);
      update(() => state = state.copyWith(showConstellations: true));
      await tester.pump();
      expect(
        sky.children.where((node) => node.name == 'Constellations').single,
        same(guides),
      );
      expect(guides.visible, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
