import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/core/terrain_coverage.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';
import 'package:photosim/ui/camera_inspector.dart';

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
          relitImagery: false,
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
                    return Row(
                      children: [
                        Expanded(
                          child: SimulationWorkspace(
                            state: state,
                            onChanged: (value) => setState(() => state = value),
                            onGroundElevationChanged: (location, elevation) {
                              if (state.location == location) {
                                setState(
                                  () => state = state.copyWith(
                                    groundElevation: elevation,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 310,
                          child: CameraInspector(
                            state: state,
                            onChanged: (value) => setState(() => state = value),
                          ),
                        ),
                      ],
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
        expect(find.text('Terrain 9/9'), findsOneWidget);
        expect(find.textContaining('© Mapterhorn'), findsOneWidget);
        expect(find.text('Imagery 9/9'), findsOneWidget);
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
          final nearby = {
            for (final node in world.root.children.where(
              (node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name),
            ))
              node.name: node.mesh!.primitives.single.geometry,
          };
          List<scene.Node> terrainNodes() => world.root.children
              .where((node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name))
              .toList();
          List<String?> counts() => tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .where((text) => text?.contains(' downloaded') ?? false)
              .toList();
          Future<void> waitForCoverage() async {
            await tester.pump(const Duration(milliseconds: 500));
            final expected = terrainCoverage(state).length;
            for (var i = 0; i < 360; i++) {
              if (find
                      .text('Terrain $expected/$expected')
                      .evaluate()
                      .isNotEmpty &&
                  find
                      .text('Imagery $expected/$expected')
                      .evaluate()
                      .isNotEmpty) {
                break;
              }
              await tester.pump(const Duration(milliseconds: 500));
            }
            expect(find.text('Terrain $expected/$expected'), findsOneWidget);
            expect(find.text('Imagery $expected/$expected'), findsOneWidget);
            expect(
              terrainNodes().map((node) => node.name).toSet(),
              terrainCoverage(state).map((tile) => tile.key).toSet(),
            );
            for (final entry in nearby.entries) {
              expect(
                terrainNodes()
                    .singleWhere((node) => node.name == entry.key)
                    .mesh!
                    .primitives
                    .single
                    .geometry,
                same(entry.value),
              );
            }
          }

          rebuild(() => state = state.copyWith(pitch: 0));
          await tester.pump();
          await tester.ensureVisible(find.text('Terrain range'));
          await tester.tap(find.text('Terrain range'));
          await tester.pump(const Duration(milliseconds: 300));
          tester
              .widget<Slider>(find.byKey(const ValueKey('terrain-forward')))
              .onChanged!(20);
          await tester.pump();
          await waitForCoverage();
          final narrowCount = terrainNodes().length;
          expect(narrowCount, greaterThan(9));
          final narrowView = tester.widget<scene.SceneView>(
            find.byType(scene.SceneView),
          );
          expect(
            terrainNodes().any(
              (node) => !node.isVisibleTo(
                narrowView.camera!,
                tester.getSize(find.byType(scene.SceneView)),
              ),
            ),
            isTrue,
          );
          final resident = {
            for (final node in terrainNodes())
              node.name: node.mesh!.primitives.single.geometry,
          };
          final beforeRender = counts();
          // Live inspector changes retain the latest simulation time.
          rebuild(
            () => state = state.copyWith(
              timestamp: state.timestamp.add(const Duration(hours: 1)),
            ),
          );
          await tester.pump();
          final latestUtc = state.timestamp;
          tester
              .widget<Slider>(find.byKey(const ValueKey('terrain-render')))
              .onChanged!(2);
          await tester.pump(const Duration(seconds: 1));
          expect(state.timestamp, latestUtc);
          expect(counts(), beforeRender);
          expect(
            terrainNodes().where((node) => node.visible).length,
            lessThan(resident.length),
          );
          for (final node in terrainNodes()) {
            expect(
              node.mesh!.primitives.single.geometry,
              same(resident[node.name]),
            );
          }
          rebuild(() => state = state.copyWith(focalLength: 8));
          await waitForCoverage();
          expect(
            terrainNodes().map((node) => node.name).toSet(),
            isNot(resident.keys.toSet()),
          );
          rebuild(() => state = state.copyWith(azimuth: 180));
          await waitForCoverage();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('preview-sources')));
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
