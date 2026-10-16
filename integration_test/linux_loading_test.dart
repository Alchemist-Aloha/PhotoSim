import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import '../test/imagery_fixture.dart';
import '../test/terrain_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'slow imagery cannot block meshes; storage settings trim without rebuilding',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-loading-',
      );
      final cache = RasterCache(
        Directory('${directory.path}/photosim'),
        settingsFile: File('${directory.path}/cache-settings.json'),
      );
      await cache.initialize();
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
              builder: (context, setState) => Row(
                children: [
                  Expanded(
                    child: SimulationWorkspace(
                      state: state,
                      onChanged: (next) => setState(() => state = next),
                      httpClient: client,
                      rasterCache: cache,
                    ),
                  ),
                  SizedBox(
                    width: 310,
                    child: CameraInspector(
                      state: state,
                      onChanged: (next) => setState(() => state = next),
                      rasterCache: cache,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 200 && find.text('Terrain 9/9').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Terrain 9/9'), findsOneWidget);
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
        i < 200 && find.text('Imagery 9/9').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Imagery 9/9'), findsOneWidget);
      expect(previewRequests, 9);
      expect(detailRequests, 1);
      expect(terrainRequests, 9);
      final viewRect = tester.getRect(find.byType(scene.SceneView));
      expect(viewRect, tester.getRect(find.byType(SimulationWorkspace)));
      for (final key in ['preview-actions', 'preview-info']) {
        final panel = tester.getRect(find.byKey(ValueKey(key)));
        expect(panel.left, greaterThanOrEqualTo(viewRect.left));
        expect(panel.top, greaterThanOrEqualTo(viewRect.top));
        expect(panel.right, lessThanOrEqualTo(viewRect.right));
        expect(panel.bottom, lessThanOrEqualTo(viewRect.bottom));
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preview-actions')),
          matching: find.byIcon(Icons.straighten),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preview-actions')),
          matching: find.byIcon(Icons.auto_awesome),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preview-actions')),
          matching: find.byTooltip(
            'Click preview · Drag to aim · WASD: 30 m/s, follows terrain',
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('preview-actions'))).width,
        lessThanOrEqualTo(540),
      );
      final terrainStatus = tester.getRect(
        find.byKey(const ValueKey('terrain-status')),
      );
      final imageryStatus = tester.getRect(
        find.byKey(const ValueKey('imagery-status')),
      );
      expect(terrainStatus.top, lessThan(viewRect.top + 48));
      expect(imageryStatus.top, terrainStatus.top);
      expect(terrainStatus.overlaps(imageryStatus), isFalse);
      final credit = tester.widget<Text>(
        find.byKey(const ValueKey('preview-credit')),
      );
      expect(credit.maxLines, 1);
      expect(credit.overflow, TextOverflow.ellipsis);
      expect(
        tester.getRect(find.byKey(const ValueKey('preview-info'))).bottom,
        viewRect.bottom,
      );
      expect(find.text('Terrain 9/9'), findsOneWidget);
      expect(find.text('Imagery 9/9'), findsOneWidget);
      for (var i = 0; i < nodes.length; i++) {
        expect(nodes[i].mesh!.primitives.single.geometry, same(geometry[i]));
      }
      Future<List<FileSystemEntity>> files() => cache.directory
          .list(recursive: true, followLinks: false)
          .where((file) => file is File)
          .toList();
      expect(
        (await files()).where((file) => file.path.endsWith('.png')),
        hasLength(19),
      );
      final inspectorScroll = find.descendant(
        of: find.byKey(const PageStorageKey('scene-inspector')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Storage'),
        300,
        scrollable: inspectorScroll,
      );
      await tester.tap(find.text('Storage'));
      await tester.pump(const Duration(milliseconds: 400));
      final field = find.byKey(const PageStorageKey('cache-limit'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '0');
      await tester.ensureVisible(find.text('Apply cache limit'));
      await tester.tap(find.text('Apply cache limit'));
      for (
        var i = 0;
        i < 100 && find.text('Cache limit saved.').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Cache limit saved.'), findsOneWidget);
      expect(cache.limitMiB, 0);
      expect(await files(), isEmpty);
      final reopened = RasterCache(
        cache.directory,
        settingsFile: cache.settingsFile,
      );
      await reopened.initialize();
      expect(reopened.limitMiB, 0);
      for (var i = 0; i < nodes.length; i++) {
        expect(nodes[i].mesh!.primitives.single.geometry, same(geometry[i]));
      }
      expect(find.text('Imagery 9/9'), findsOneWidget);
      expect(terrainRequests, 9);
      expect(previewRequests, 9);
      expect(detailRequests, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
