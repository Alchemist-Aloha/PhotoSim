import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/app_session.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux timeline preview and unsaved-plan protection', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'photosim-planning-ui-',
    );
    final store = PlanRepository(Directory('${directory.path}/plans'));
    final checkpoint = SessionStore(File('${directory.path}/session.json'));
    final captureKey = GlobalKey();
    Future<void> capture(String name) async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/validation').create(recursive: true);
      await File('build/validation/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: PhotoSimApp(
            plans: store,
            sessionStore: checkpoint,
            rasterCache: RasterCache(Directory('${directory.path}/cache')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      CameraInspector inspector() =>
          tester.widget<CameraInspector>(find.byType(CameraInspector));
      final destination = inspector().state.copyWith(focalLength: 85);
      await store.save(SavedPlan('Morning plan', destination));
      final original = inspector().state.copyWith(
        timestamp: DateTime.utc(2026, 6, 22, 3),
      );
      inspector().onChanged(original);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Estimated local: 2026-06-21 20:00 PDT'),
        findsOneWidget,
      );
      await capture('linux-planning-timeline');
      await tester.tap(find.text('Edit local: 2026-06-21 20:00'));
      await tester.pumpAndSettle();
      expect(find.text('Edit local shooting time'), findsOneWidget);
      await tester.tap(find.text('Local time: 20:00'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(TimePickerDialog)))
          .pop(const TimeOfDay(hour: 21, minute: 30));
      await tester.pumpAndSettle();
      expect(find.text('UTC equivalent: 2026-06-22 04:30 UTC'), findsOneWidget);
      await capture('linux-planning-local-editor');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(inspector().state.timestamp, original.timestamp);
      await tester.tap(find.byTooltip('Photography plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morning plan'));
      await tester.pumpAndSettle();
      await capture('linux-planning-unsaved');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        'Evening plan',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(inspector().state.focalLength, destination.focalLength);
      expect(find.text('Saved · Morning plan'), findsOneWidget);
      final restored = await store.loadAll();
      expect(restored.plans.length, 2);
      expect(
        restored.plans
            .singleWhere((plan) => plan.name == 'Evening plan')
            .state
            .timestamp,
        original.timestamp,
      );
      if (Platform.isLinux) {
        final planFile = (await store.directory.list().toList())
            .whereType<File>()
            .first;
        final beforeFailure = inspector().state;
        final moved = beforeFailure.copyWith(
          latitude: beforeFailure.latitude + 0.001,
        );
        inspector().onChanged(moved);
        await tester.pumpAndSettle();
        expect(find.text('Camera moved'), findsOneWidget);
        expect(
          (await Process.run('chmod', ['000', store.directory.path])).exitCode,
          0,
        );
        try {
          if (!await planFile.exists()) {
            await tester.tap(find.byTooltip('Photography plans'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Open plan'));
            await tester.pumpAndSettle();
            expect(find.text('Camera moved'), findsNothing);
            expect(
              find.textContaining('Check storage space and folder permissions'),
              findsOneWidget,
            );
            expect(inspector().state, same(moved));
            await capture('linux-plan-error-feedback');
          } else {
            debugPrint(
              'Permission-denial phase skipped: directory access remains available to this user.',
            );
          }
        } finally {
          expect(
            (await Process.run('chmod', [
              '700',
              store.directory.path,
            ])).exitCode,
            0,
          );
        }
        expect((await store.loadAll()).plans.length, 2);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final previousCheckpoint = checkpoint.file.readAsStringSync();
      final blocked = Directory('${checkpoint.file.path}.tmp')..createSync();
      final beforeCheckpointFailure = inspector().state;
      final edited = beforeCheckpointFailure.copyWith(
        latitude: beforeCheckpointFailure.latitude + 0.001,
        focalLength: 135,
      );
      inspector().onChanged(edited);
      await tester.pump();
      expect(find.text('Camera moved'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Camera moved'), findsNothing);
      expect(
        find.textContaining('Session could not be saved. Check storage'),
        findsOneWidget,
      );
      expect(inspector().state, same(edited));
      expect(checkpoint.file.readAsStringSync(), previousCheckpoint);
      await capture('linux-session-error-feedback');
      blocked.deleteSync();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Session recovery warning'), findsNothing);
      expect(
        SavedPlan(
          'Session',
          AppSession.decode(checkpoint.file.readAsStringSync()).state,
        ).encode(),
        SavedPlan('Session', edited).encode(),
      );
      expect(inspector().state, same(edited));
      expect((await store.loadAll()).plans.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await directory.delete(recursive: true);
    }
  });
}
