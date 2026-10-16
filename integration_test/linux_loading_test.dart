import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import '../test/imagery_fixture.dart';
import '../test/terrain_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'slow imagery cannot hold terrain loading or start detail early',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-loading-',
      );
      final imagesReady = Completer<void>();
      final preview = imageryFixture(256), detail = imageryFixture(1024);
      var terrainRequests = 0, previewRequests = 0, detailRequests = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'tiles.mapterhorn.com') {
          terrainRequests++;
          return http.Response.bytes(terrainWebpFixture(), 200);
        }
        final size = request.url.queryParameters['size'];
        if (size == '256,256') {
          previewRequests++;
        } else if (size == '1024,1024') {
          detailRequests++;
        } else {
          throw StateError('Unexpected source request: ${request.url}');
        }
        await imagesReady.future;
        return http.Response.bytes(size == '256,256' ? preview : detail, 200);
      });
      addTearDown(() async {
        if (!imagesReady.isCompleted) imagesReady.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        client.close();
        await directory.delete(recursive: true);
      });
      var state = SimulationState(height: 100, pitch: -40);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SimulationWorkspace(
                state: state,
                onChanged: (next) => setState(() => state = next),
                httpClient: client,
                cacheDirectory: directory,
              ),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 200 && find.text('Real terrain · 9/9 tiles').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Real terrain · 9/9 tiles'), findsOneWidget);
      expect(terrainRequests, 9);
      expect(previewRequests, 3);
      expect(detailRequests, 0);
      expect(state.groundElevation, isNotNull);
      final world = tester
          .widget<scene.SceneView>(find.byType(scene.SceneView))
          .scene!;
      final nodes = world.root.children
          .where((node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name))
          .toList();
      final geometry = [
        for (final node in nodes) node.mesh!.primitives.single.geometry,
      ];
      expect(nodes.length, 9);
      imagesReady.complete();
      for (
        var i = 0;
        i < 200 && find.text('Imagery · 9/9 textures').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Imagery · 9/9 textures'), findsOneWidget);
      expect(previewRequests, 9);
      expect(detailRequests, 1);
      expect(terrainRequests, 9);
      for (var i = 0; i < nodes.length; i++) {
        expect(nodes[i].mesh!.primitives.single.geometry, same(geometry[i]));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
