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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture extra readme screens', (tester) async {
    final directory = await Directory.systemTemp.createTemp(
      'photosim-showcase-',
    );
    final capture = GlobalKey();
    final state = SimulationState(
      latitude: 37.7306,
      longitude: -119.5738,
      timestamp: DateTime.utc(2026, 6, 13, 7, 30),
      azimuth: 120,
      pitch: 18,
      focalLength: 16,
      showConstellations: true,
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
      await screenshot('night');
      await tester.tap(find.text('Export').last);
      await settle();
      await tester.tap(find.text('Render high-quality preview'));
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await screenshot('export');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await directory.delete(recursive: true);
    }
  });
}
