import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/ui/map_workspace.dart';
import 'package:photosim/ui/night_calendar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('calendar navigation and real keyless source data', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'photosim-calendar-',
    );
    final captureKey = GlobalKey();
    final stop = Completer<void>();
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> capture(String name) async {
      if (!Platform.isLinux) return;
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
            plans: PlanRepository(Directory('${directory.path}/plans')),
            rasterCache: RasterCache(Directory('${directory.path}/cache')),
          ),
        ),
      );
      await settle();
      final map = tester.widget<MapWorkspace>(find.byType(MapWorkspace));
      final original = map.state;
      await tester.tap(find.text('Calendar'));
      await settle();
      for (
        var i = 0;
        i < 100 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final calendar = tester.widget<NightCalendar>(find.byType(NightCalendar));
      final forecast = await calendar.repository.forecast(
        original.latitude,
        original.longitude,
        abort: stop.future,
      );
      final brightness = await calendar.repository.brightness(
        original.latitude,
        original.longitude,
        abort: stop.future,
      );
      expect(forecast.hours.length, greaterThanOrEqualTo(24));
      expect(forecast.hours.first.utc.isUtc, isTrue);
      expect(brightness, isNotNull);
      expect(brightness!.sqm, inInclusiveRange(0, 22));
      await settle();
      await capture('linux-calendar-month');
      await tester.tap(find.byTooltip('Switch to week view'));
      await settle();
      for (
        var i = 0;
        i < 50 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(ListTile), findsNWidgets(7));
      await capture('linux-calendar-week');
      await tester.tap(find.byTooltip('Switch to month view'));
      await settle();
      final dateButton = find
          .descendant(
            of: find.byType(NightCalendar),
            matching: find.byType(TextButton),
          )
          .first;
      await tester.tap(dateButton);
      await settle();
      Navigator.of(tester.element(find.byType(DatePickerDialog)))
          .pop(DateTime(2026, 6, 15));
      await settle();
      for (
        var i = 0;
        i < 50 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Preview Galactic core'), findsOneWidget);
      await capture('linux-calendar-detail');
      await tester.tap(find.text('Map'));
      await settle();
      final restored = tester
          .widget<MapWorkspace>(find.byType(MapWorkspace))
          .state;
      expect(restored.timestamp, original.timestamp);
      expect(restored.location, original.location);
      expect(restored.focalLength, original.focalLength);
      expect(tester.takeException(), isNull);
    } finally {
      stop.complete();
      await tester.pumpWidget(const SizedBox());
      await settle();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
