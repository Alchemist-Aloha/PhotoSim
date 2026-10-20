import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/app_session.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';

List<FrameTiming> timings = [];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Linux profile render timings', (tester) async {
    final directory = await Directory.systemTemp.createTemp('photosim-perf-');
    var state = SimulationState(
      timestamp: DateTime.utc(2026, 6, 21, 19),
      pitch: -8,
      height: 100,
      renderQuality: RenderQuality.balanced,
    );
    final output = StringBuffer();
    try {
      await tester.pumpWidget(
        PhotoSimApp(
          rasterCache: RasterCache(Directory('${directory.path}/cache')),
          initialSession: AppSession(
            state: state,
            cleanComposition: SavedPlan('Performance', state).encode(),
            workspace: 'simulation',
            expandedSections: const {'Optics': false},
          ),
        ),
      );
      for (var i = 0; i < 240; i++) {
        if (find.text('Imagery 9/9').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('Imagery 9/9'), findsOneWidget);
      SchedulerBinding.instance.addTimingsCallback(timings.addAll);
      Future<void> run(
        String label,
        Duration duration,
        Future<void> Function() tick,
      ) async {
        await tester.pump(const Duration(milliseconds: 500));
        timings.clear();
        final end = DateTime.now().add(duration);
        var count = 0;
        while (DateTime.now().isBefore(end)) {
          await tick();
          await Future<void>.delayed(const Duration(milliseconds: 16));
          count++;
        }
        final build =
            timings.map((t) => t.buildDuration.inMicroseconds / 1000).toList()
              ..sort();
        final raster =
            timings.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()
              ..sort();
        double pct(List<double> values, double p) => values.isEmpty
            ? double.nan
            : values[math.min(values.length - 1, (values.length * p).floor())];
        output.writeln(
          '$label frames=${timings.length} loop=$count '
          'build p50=${pct(build, .5).toStringAsFixed(2)} p95=${pct(build, .95).toStringAsFixed(2)} max=${build.isEmpty ? 'n/a' : build.last.toStringAsFixed(2)} | '
          'raster p50=${pct(raster, .5).toStringAsFixed(2)} p95=${pct(raster, .95).toStringAsFixed(2)} max=${raster.isEmpty ? 'n/a' : raster.last.toStringAsFixed(2)}',
        );
      }

      await run('idle', const Duration(seconds: 3), () async {});
      late CameraInspector inspector;
      await run('time-scrub', const Duration(seconds: 4), () async {
        inspector = tester.widget<CameraInspector>(
          find.byType(CameraInspector),
        );
        inspector.onChanged(
          inspector.state.copyWith(
            timestamp: inspector.state.timestamp.add(
              const Duration(minutes: 5),
            ),
          ),
        );
        await tester.pump();
      });
      await tester.tap(
        find.byTooltip('Play time (5 simulated minutes per second)'),
      );
      await run('playback', const Duration(seconds: 4), () async {
        await tester.pump(const Duration(milliseconds: 16));
      });
      await tester.tap(find.byTooltip('Pause time'));
      await tester.pump(const Duration(milliseconds: 300));

      await run('aim-scrub', const Duration(seconds: 4), () async {
        inspector = tester.widget<CameraInspector>(
          find.byType(CameraInspector),
        );
        final next = inspector.state.copyWith(
          azimuth: (inspector.state.azimuth + 7) % 360,
        );
        inspector.onChanged(next);
        await tester.pump();
      });
      inspector = tester.widget<CameraInspector>(find.byType(CameraInspector));
      inspector.onChanged(
        inspector.state.copyWith(renderQuality: RenderQuality.high),
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Imagery 9/9').evaluate().isNotEmpty) break;
      }
      await run('high-idle', const Duration(seconds: 3), () async {});
      await run('high-aim-scrub', const Duration(seconds: 3), () async {
        inspector = tester.widget<CameraInspector>(
          find.byType(CameraInspector),
        );
        inspector.onChanged(
          inspector.state.copyWith(
            azimuth: (inspector.state.azimuth + 7) % 360,
          ),
        );
        await tester.pump();
      });

      // Pure Dart astronomy cost within one frame-sized batch.
      final sample = tester
          .widget<CameraInspector>(find.byType(CameraInspector))
          .state;
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        sample.sky;
      }
      stopwatch.stop();
      output.writeln(
        'astronomy sky: ${(stopwatch.elapsedMicroseconds / 1000).toStringAsFixed(3)} ms/call over 1000 calls',
      );
      stopwatch.reset();
      for (var i = 0; i < 1000; i++) {
        sample.galacticCenter;
      }
      stopwatch.stop();
      output.writeln(
        'galacticCenter frame: ${(stopwatch.elapsedMicroseconds / 1000).toStringAsFixed(3)} ms/call over 1000 calls',
      );

      File('build/validation/render-performance.txt')
          .writeAsStringSync(output.toString());
      debugPrint(output.toString());
      expect(timings, isNotEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      await directory.delete(recursive: true);
    }
  });
}
