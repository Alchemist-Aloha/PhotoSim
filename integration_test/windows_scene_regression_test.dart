import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/app_session.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';

import 'workspace_navigation.dart';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await const MethodChannel('photosim/window')
        .invokeMethod<void>('enableAccessibilityForTest');
    // Let the engine's semantics-enabled notification reach the binding before
    // testWidgets records its initial semantics handle count.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  testWidgets('Windows real terrain and workspace transitions with semantics', (
    tester,
  ) async {
    final output = Directory('build/validation/windows/real-scene').absolute;
    await output.create(recursive: true);
    final cache = RasterCache(Directory('${output.path}/cache'));
    await cache.initialize();
    final state = SimulationState(
      timestamp: DateTime.utc(2026, 10, 22, 16, 15),
      azimuth: 51.43978743640224,
      pitch: 8,
      showConstellations: false,
      terrainRenderKm: 40,
    );
    final capture = GlobalKey();
    addTearDown(() async {
      await const MethodChannel('photosim/window')
          .invokeMethod<void>('fullscreen', false);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: PhotoSimApp(
          rasterCache: cache,
          plans: PlanRepository(Directory('${output.path}/plans')),
          initialSession: AppSession(
            state: state,
            cleanComposition: SavedPlan('Composition', state).encode(),
          ),
        ),
      ),
    );
    Future<void> waitForScene(String stage) async {
      final watch = Stopwatch()..start();
      var lastReport = -1;
      while (watch.elapsed < const Duration(minutes: 3)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final views = find.byType(scene.SceneView);
        final world = views.evaluate().isEmpty
            ? null
            : tester.widget<scene.SceneView>(views).scene;
        final labels = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .where(
              (text) =>
                  text.startsWith('Terrain ') || text.startsWith('Imagery '),
            )
            .join(' / ');
        if (watch.elapsed.inSeconds ~/ 5 != lastReport) {
          lastReport = watch.elapsed.inSeconds ~/ 5;
          final progress =
              '$stage: $labels; frames=${world?.renderStats.frameCount}\n';
          debugPrint(progress);
          await File('${output.path}/progress.log')
              .writeAsString(progress, mode: FileMode.append);
        }
        if (find.text('Terrain 9/9').evaluate().isNotEmpty &&
            find.text('Imagery 9/9').evaluate().isNotEmpty &&
            world != null &&
            world.renderStats.frameCount > 20) {
          return;
        }
      }
      fail('$stage did not finish loading real terrain and imagery');
    }

    await openWorkspace(tester, '3D Preview');
    await waitForScene('first 3D entry');
    // ExpansionTile animates its slider anchors through zero opacity, the
    // transition implicated in Flutter's orphaned traversal-node regression.
    for (final section in ['Optics', 'Position & orientation']) {
      for (var toggle = 0; toggle < 2; toggle++) {
        await tester.tap(find.text(section));
        await tester.pump();
        for (var frame = 0; frame < 15; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }
    }
    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.byTooltip('Toggle camera inspector'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Toggle camera inspector'));
      await tester.pump(const Duration(milliseconds: 300));
      await openWorkspace(tester, 'Map');
      await openWorkspace(tester, '3D Preview');
      await waitForScene('3D re-entry $visit');
    }
    await tester.tap(find.byTooltip('Fullscreen preview'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Exit fullscreen preview (Esc)'));
    await tester.pump(const Duration(milliseconds: 500));
    await waitForScene('fullscreen restore');
    final world = tester
        .widget<scene.SceneView>(find.byType(scene.SceneView))
        .scene!;
    final frames = world.renderStats.frameCount;
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(world.renderStats.frameCount, greaterThan(frames));
    expect(tester.takeException(), isNull);
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('${output.path}/loaded.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }, skip: !Platform.isWindows);
}
