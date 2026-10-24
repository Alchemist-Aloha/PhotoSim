import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/export_panel.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import '../test/imagery_fixture.dart';
import '../test/terrain_fixture.dart';
import 'workspace_navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'export tab renders real high-resolution pixels and saves exactly the preview',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-export-tab-',
      );
      final terrain = terrainWebpFixture();
      final imagery = imageryFixture(256);
      final client = MockClient(
        (request) async => http.Response.bytes(
          request.url.host == 'tiles.mapterhorn.com' ? terrain : imagery,
          200,
        ),
      );
      final capture = GlobalKey();
      var exportMode = true;
      var state = SimulationState(
        timestamp: DateTime.utc(2026, 6, 21, 19),
        height: 100,
        pitch: -20,
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
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: StatefulBuilder(
                builder: (context, update) {
                  rebuild = update;
                  return SimulationWorkspace(
                    state: state,
                    exportMode: exportMode,
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
      ExportPanel panel() =>
          tester.widget<ExportPanel>(find.byType(ExportPanel));
      Future<void> until(bool Function() condition) async {
        for (var i = 0; i < 400 && !condition(); i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(condition(), isTrue);
      }

      await until(() => panel().ready);
      final world = tester
          .widget<scene.SceneView>(find.byType(scene.SceneView))
          .scene!;
      await pumpUntilRendered(tester, world, frames: 2);
      final sourceSize = tester.getSize(find.byType(scene.SceneView));
      await tester.tap(find.text('Render high-quality preview'));
      await until(() => panel().bytes != null && !panel().busy);
      final bytes = panel().bytes!;
      final decoded = img.decodePng(bytes)!;
      expect(decoded.width, greaterThan(sourceSize.width));
      expect(decoded.width / decoded.height, closeTo(1.5, 0.005));
      expect(panel().width, decoded.width);
      expect(panel().height, decoded.height);
      expect(panel().prompt.text, contains('2026-06-21T19:00:00.000Z'));
      expect(panel().prompt.text, contains('sourceCredits'));
      // A sky/terrain image has more than just a flat background and a credit strip.
      final colors = <int>{};
      for (var y = 0; y < decoded.height * 0.75; y += 20) {
        for (var x = 0; x < decoded.width; x += 20) {
          final p = decoded.getPixel(x, y);
          colors.add((p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt());
        }
      }
      expect(colors.length, greaterThan(10));
      final frames = world.renderStats.frameCount;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(
        world.renderStats.frameCount,
        frames,
        reason: 'Do not keep rendering behind a completed static export',
      );
      await Directory('build/validation').create(recursive: true);
      final screen =
          await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final png = (await screen.toByteData(format: ui.ImageByteFormat.png))!;
        await File('build/validation/linux-export-tab.png')
            .writeAsBytes(png.buffer.asUint8List());
      } finally {
        screen.dispose();
      }
      await tester.ensureVisible(find.text('Save PNG'));
      await tester.tap(find.text('Save PNG'));
      await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
      final path = '${directory.path}/render.png';
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        path,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Save PNG'),
        ),
      );
      await until(() => !panel().busy);
      expect(await File(path).readAsBytes(), bytes);
      await tester.ensureVisible(
        find.byKey(const ValueKey('enhancement-prompt')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('enhancement-prompt')),
        'Edited capture prompt',
      );
      await tester.ensureVisible(find.text('Copy prompt'));
      await tester.tap(find.text('Copy prompt'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))!.text,
        'Edited capture prompt',
      );
      rebuild(() => exportMode = false);
      await tester.pump();
      expect(
        tester.widget<scene.SceneView>(find.byType(scene.SceneView)).scene,
        same(world),
      );
      rebuild(() {
        exportMode = true;
        state = state.copyWith(focalLength: 35);
      });
      await tester.pump();
      expect(panel().stale, isTrue);
      expect(panel().prompt.text, 'Edited capture prompt');
      await tester.ensureVisible(find.text('Re-render preview & reset prompt'));
      await tester.tap(find.text('Re-render preview & reset prompt'));
      await until(() => !panel().busy && !panel().stale);
      expect(panel().prompt.text, contains('"focalLength": 35.0'));
      expect(tester.takeException(), isNull);
    },
  );
}
