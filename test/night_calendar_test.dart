import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/night_conditions.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/night_calendar.dart';
import 'package:photosim/ui/time_slider.dart';

import 'night_conditions_test.dart' show forecastFixture;

Future<void> settleCalendar(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(1280, 800),
    const Size(360, 800),
    const Size(844, 390),
  ]) {
    testWidgets('month/week calendar and usable-window preview at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = size.width == 360
          ? 2.0
          : 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return request.url.host == 'api.open-meteo.com'
            ? http.Response(
                forecastFixture(
                  DateTime.utc(2026, 6, 15),
                  clouds: List.filled(384, 20),
                ),
                200,
              )
            : http.Response.bytes(gzip.encode(Uint8List(atlasTileLength)), 200);
      });
      addTearDown(client.close);
      final repository = NightConditionsRepository(
        client,
        now: () => DateTime.utc(2026, 6, 15),
      );
      var week = false;
      DateTime? preview;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  IconButton(
                    tooltip: 'Toggle calendar',
                    onPressed: () => setState(() => week = !week),
                    icon: const Icon(Icons.calendar_view_week),
                  ),
                ],
              ),
              body: NightCalendar(
                state: SimulationState(timestamp: DateTime.utc(2026, 6, 16, 5)),
                weekView: week,
                repository: repository,
                onPreview: (utc) => preview = utc,
              ),
            ),
          ),
        ),
      );
      await settleCalendar(tester);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byKey(const ValueKey('night-2026-06-15')), findsOneWidget);
      expect(calls, 2);
      await tester.tap(find.byTooltip('Toggle calendar'));
      await settleCalendar(tester);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(7));
      expect(calls, 2);
      await tester.ensureVisible(find.text('Preview Galactic core'));
      await tester.tap(find.text('Preview Galactic core'));
      expect(preview, isNotNull);
      expect(preview!.isUtc, isTrue);
      expect(find.textContaining('Modeled zenith: 22.00'), findsOneWidget);
      expect(find.textContaining('Weather-adjusted:'), findsOneWidget);
      expect(
        find.textContaining('Visible Milky Way at 0–30°:'),
        findsOneWidget,
      );
      expect(find.textContaining('low Milky Way'), findsOneWidget);
      expect(find.textContaining('core altitude reach'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'calendar opens as a third workspace without mutating camera/time',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync(
        'photosim-calendar-test-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        directory.deleteSync(recursive: true);
      });
      await tester.pumpWidget(const PhotoSimApp());
      final inspector = tester.widget<CameraInspector>(
        find.byType(CameraInspector),
      );
      final before = inspector.state.copyWith(
        timestamp: DateTime.utc(2026, 6, 16, 5),
        focalLength: 85,
      );
      inspector.onChanged(before);
      await tester.pump();
      await tester.tap(find.text('Calendar'));
      await settleCalendar(tester);
      expect(find.byType(NightCalendar), findsOneWidget);
      expect(find.byType(CameraInspector), findsNothing);
      expect(find.byType(TimeSlider), findsNothing);
      await tester.tap(find.byTooltip('Switch to week view'));
      await settleCalendar(tester);
      expect(
        tester.widget<NightCalendar>(find.byType(NightCalendar)).weekView,
        isTrue,
      );
      expect(find.byTooltip('Switch to month view'), findsOneWidget);
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      final after = tester
          .widget<CameraInspector>(find.byType(CameraInspector))
          .state;
      expect(after.timestamp, before.timestamp);
      expect(after.focalLength, before.focalLength);
      expect(after.location, before.location);
      await tester.tap(find.text('Calendar'));
      await settleCalendar(tester);
      final desired = DateTime.utc(2026, 6, 16, 6);
      tester
          .widget<NightCalendar>(find.byType(NightCalendar))
          .onPreview(desired);
      await tester.pump();
      final preview = tester
          .widget<CameraInspector>(find.byType(CameraInspector))
          .state;
      expect(preview.timestamp, desired);
      expect(preview.timestamp.isUtc, isTrue);
      expect(preview.target, CelestialTarget.galacticCenter);
      expect(preview.focalLength, before.focalLength);
      expect(preview.location, before.location);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'below-horizon core keeps a band rating; distant weather and failed atlas remain unknown',
    (tester) async {
      var weatherCalls = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'api.open-meteo.com') weatherCalls++;
        return http.Response('Unavailable', 404);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NightCalendar(
              state: SimulationState(timestamp: DateTime.utc(2026, 1, 19, 5)),
              weekView: true,
              repository: NightConditionsRepository(
                client,
                now: () => DateTime.utc(2026, 6, 1),
              ),
              onPreview: (_) {},
            ),
          ),
        ),
      );
      await settleCalendar(tester);
      expect(weatherCalls, 0);
      expect(
        find.textContaining('the visible Milky Way band is still rated'),
        findsOneWidget,
      );
      expect(find.text('Preview Galactic core'), findsNothing);
      expect(
        find.textContaining('Visible Milky Way at 0–30°:'),
        findsOneWidget,
      );
      expect(find.textContaining('Astronomy: 0/100'), findsNothing);
      expect(find.textContaining('Sky brightness unavailable'), findsOneWidget);
      expect(find.textContaining('Modeled zenith:'), findsNothing);
      expect(
        find.textContaining('No forecast for this window'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
