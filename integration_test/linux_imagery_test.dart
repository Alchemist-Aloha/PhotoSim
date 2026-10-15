import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Linux anonymous regional/global terrain and imagery preserve geography',
    (tester) async {
      for (final site in [
        (46.58, 7.96, '©swisstopo', 'swiss'),
        (48.86, 2.35, '© IGN · BD ORTHO · Licence Ouverte 2.0', 'ign'),
        (-33.86, 151.21, 'EOxCloudless', 'eox'),
        (39.9, 116.4, 'EOxCloudless', 'beijing'),
      ]) {
        final captureKey = GlobalKey();
        var state = SimulationState(
          latitude: site.$1,
          longitude: site.$2,
          height: 100,
          pitch: -40,
          timestamp: DateTime.utc(2026, 6, 21, site.$4 == 'eox' ? 2 : 12),
        );
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: Scaffold(
              body: RepaintBoundary(
                key: captureKey,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    rebuild = setState;
                    return SimulationWorkspace(
                      state: state,
                      onChanged: (value) => setState(() => state = value),
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
        expect(find.text('Real terrain · 9/9 tiles'), findsOneWidget);
        expect(find.textContaining('© Mapterhorn'), findsOneWidget);
        expect(find.text('Imagery · 9/9 textures'), findsOneWidget);
        expect(find.textContaining(site.$3), findsOneWidget);
        expect(
          find.textContaining('Imagery unavailable or incomplete:'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 500));

        final view = tester.widget<scene.SceneView>(
          find.byType(scene.SceneView),
        );
        final world = view.scene!;
        final geometries = world.root.children
            .where((node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name))
            .map((node) => node.mesh!.primitives.single.geometry)
            .toList();
        expect(geometries, hasLength(9));
        final counters = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .where((text) => text?.contains(' downloaded') ?? false)
            .toList();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final raw = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final viewport = tester
            .getRect(find.byType(scene.SceneView))
            .shift(-tester.getTopLeft(find.byKey(captureKey)));
        final colors = <int>{};
        for (
          var y = viewport.top.toInt() + 8;
          y < viewport.bottom.toInt() - 8;
          y += 8
        ) {
          for (
            var x = viewport.left.toInt() + 8;
            x < viewport.right.toInt() - 8;
            x += 8
          ) {
            final offset = (y * image.width + x) * 4;
            colors.add(
              (raw.getUint8(offset) << 16) |
                  (raw.getUint8(offset + 1) << 8) |
                  raw.getUint8(offset + 2),
            );
          }
        }
        expect(colors.length, greaterThan(100));
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await Directory('build/validation').create(recursive: true);
        await File('build/validation/linux-imagery-${site.$4}.png')
            .writeAsBytes(png.buffer.asUint8List());
        image.dispose();

        rebuild(
          () => state = state.copyWith(
            timestamp: state.timestamp.add(const Duration(hours: 1)),
            focalLength: 50,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.widget<scene.SceneView>(find.byType(scene.SceneView)).scene,
          same(world),
        );
        expect(
          world.root.children
              .where((node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name))
              .map((node) => node.mesh!.primitives.single.geometry),
          orderedEquals(geometries),
        );
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .where((text) => text?.contains(' downloaded') ?? false)
              .toList(),
          counters,
        );
        if (site.$4 == 'swiss') {
          await tester.tap(find.text('© Terrain & imagery sources'));
          await tester.pump(const Duration(milliseconds: 300));
          final credits = tester
              .widget<SelectableText>(find.byType(SelectableText))
              .data!;
          expect(credits, contains('Mapterhorn upstream source credits'));
          expect(credits, contains('COPERNICUS GLO-30'));
          expect(credits, contains('Open Government Licence'));
          await tester.tap(find.text('Close'));
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
