import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'idle rendering is bounded without changing pixels or active refresh',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('photosim-idle-');
      final terrain = terrainWebpFixture(), imagery = imageryFixture(256);
      final client = MockClient(
        (request) async => http.Response.bytes(
          request.url.host == 'tiles.mapterhorn.com' ? terrain : imagery,
          200,
        ),
      );
      final capture = GlobalKey();
      var state = SimulationState(
        timestamp: DateTime.utc(2026, 6, 21, 19),
        height: 100,
        pitch: -15,
        cloudType: CloudType.cumulonimbus,
        cloudAmount: 0.1355,
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
      for (var i = 0; i < 400; i++) {
        if (find.text('Imagery 9/9').evaluate().isNotEmpty &&
            tester
                    .widget<OutlinedButton>(
                      find.widgetWithText(OutlinedButton, 'Export PNG'),
                    )
                    .onPressed !=
                null) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Imagery 9/9'), findsOneWidget);
      final world = tester
          .widget<scene.SceneView>(find.byType(scene.SceneView))
          .scene!;
      Future<int> fingerprint() async {
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var hash = 0;
          for (final byte in data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          )) {
            hash = (hash * 31 + byte) & 0x1fffffffffffff;
          }
          return hash;
        } finally {
          image.dispose();
        }
      }

      Future<double> idleFps() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        final start = world.renderStats.frameCount;
        final watch = Stopwatch()..start();
        await Future<void>.delayed(const Duration(seconds: 2));
        return (world.renderStats.frameCount - start) /
            (watch.elapsedMicroseconds / 1e6);
      }

      final results = <String, Object>{};
      for (final quality in [RenderQuality.balanced, RenderQuality.high]) {
        rebuild(() => state = state.copyWith(renderQuality: quality));
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.text('Imagery 9/9').evaluate().isNotEmpty) break;
        }
        final fps = await idleFps();
        expect(fps, 0);
        // The live test binding itself drives frames; inspect app tickers instead.
        expect(SchedulerBinding.instance.transientCallbackCount, 0);
        expect(
          TickerMode.valuesOf(tester.element(find.byType(scene.SceneView)))
              .enabled,
          isFalse,
        );
        results['${quality.name}IdleFps'] = fps;
        results['${quality.name}IdleTickers'] =
            SchedulerBinding.instance.transientCallbackCount;
        final hash = await fingerprint();
        results['${quality.name}RgbaHash'] = hash;
        final start = world.renderStats.frameCount;
        final watch = Stopwatch()..start();
        while (watch.elapsed < const Duration(seconds: 2)) {
          rebuild(
            () => state = state.copyWith(azimuth: (state.azimuth + 1) % 360),
          );
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        final activeFps =
            (world.renderStats.frameCount - start) /
            (watch.elapsedMicroseconds / 1e6);
        results['${quality.name}ActiveFps'] = activeFps;
        expect(
          activeFps,
          greaterThan(5),
          reason:
              'Camera edits must resume rendering above the former idle cap',
        );
        rebuild(() => state = state.copyWith(azimuth: 0));
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(await fingerprint(), hash);
      }
      rebuild(
        () => state = state.copyWith(weather: Weather.rain, rainIntensity: 0.6),
      );
      final rainFps = await idleFps();
      expect(
        rainFps,
        0,
        reason: 'Animated rain must reuse the static 3D layer',
      );
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
      results['rainIdleSceneFps'] = rainFps;
      await Directory('build/validation').create(recursive: true);
      const path = 'build/validation/idle-render-after.json';
      await File(path)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(results));
      debugPrint('Idle render measurement: $results');
      expect(tester.takeException(), isNull);
    },
  );
}
