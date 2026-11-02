import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/app_session.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/map_workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture real application showcase screens', (tester) async {
    final directory = await Directory.systemTemp.createTemp(
      'photosim-showcase-',
    );
    final capture = GlobalKey();
    final state = SimulationState(
      timestamp: DateTime.utc(2026, 6, 21, 19),
      azimuth: 70,
      pitch: 10,
      cloudAmount: 0.25,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: PhotoSimApp(
          plans: PlanRepository(Directory('${directory.path}/plans')),
          initialSession: AppSession(
            state: state,
            cleanComposition: SavedPlan('Showcase', state).encode(),
            mapGuideDismissed: true,
            calendarDate: DateTime(2026, 6, 21),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> screenshot(String name) async {
      await settle();
      expect(tester.takeException(), isNull);
      if (Platform.isLinux) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await Directory('website/public/screenshots').create(recursive: true);
          await File('website/public/screenshots/linux-$name.png')
              .writeAsBytes(bytes.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      } else {
        // Give the host time to capture the actual emulator with adb screencap.
        debugPrint('SHOWCASE_READY:$name');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 15)),
        );
      }
    }

    try {
      await settle();
      expect(find.byType(MapWorkspace), findsOneWidget);
      await screenshot('map');
      await tester.tap(find.text('3D Preview').last);
      await settle();
      final export = find.widgetWithText(OutlinedButton, 'Export PNG');
      for (var i = 0; i < 240; i++) {
        if (export.evaluate().isNotEmpty &&
            tester.widget<OutlinedButton>(export).onPressed != null) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(
        find.text('3D rendering is unavailable. The map still works.'),
        findsNothing,
      );
      expect(export, findsOneWidget);
      expect(tester.widget<OutlinedButton>(export).onPressed, isNotNull);
      await screenshot('preview');
      await tester.tap(find.text('Calendar').last);
      await screenshot('calendar');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await directory.delete(recursive: true);
    }
  });
}
