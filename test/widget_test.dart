import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/core/local_time.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  testWidgets('navigation rail switches workspaces and preserves UTC/camera', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PhotoSimApp());
    final original = tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .state;
    expect(find.byType(NavigationDrawer), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      0,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('3D Preview'),
      ),
    );
    await tester.pump();
    expect(find.byType(FlutterMap), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
    await tester.tap(find.byTooltip('Fullscreen preview'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const ValueKey('local-day-slider')), findsNothing);
    await tester.tap(find.byTooltip('Exit fullscreen preview (Esc)'));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Map'),
      ),
    );
    await tester.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    final current = tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .state;
    expect(current.location, original.location);
    expect(current.timestamp, original.timestamp);
    expect(current.focalLength, original.focalLength);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('timeline adapts to window width without hiding controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1600, 900);
    await tester.pumpWidget(const PhotoSimApp());
    await tester.tap(find.text('3D Preview'));
    await tester.pumpAndSettle();
    for (final width in [800.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      final slider = tester.getRect(
        find.byKey(const ValueKey('local-day-slider')),
      );
      final play = tester.getRect(
        find.byTooltip('Play time (5 simulated minutes per second)'),
      );
      if (width >= 1280) {
        expect(slider.center.dy, closeTo(play.center.dy, 1));
        expect(slider.left, greaterThan(play.right));
      } else {
        expect(slider.top, greaterThanOrEqualTo(play.bottom));
      }
      expect(find.byTooltip('Earlier by one hour'), findsOneWidget);
      expect(find.byTooltip('Later by one hour'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('local editor converts to UTC and applies only on confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PhotoSimApp());
    CameraInspector inspector() =>
        tester.widget<CameraInspector>(find.byType(CameraInspector));
    final original = inspector().state.copyWith(
      timestamp: DateTime.utc(2026, 6, 22, 3),
    );
    inspector().onChanged(original);
    await tester.pump();
    expect(
      find.textContaining('Estimated local: 2026-06-21 20:00 PDT'),
      findsOneWidget,
    );
    await tester.tap(find.text('Edit local: 2026-06-21 20:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local time: 20:00'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(TimePickerDialog)))
        .pop(const TimeOfDay(hour: 21, minute: 30));
    await tester.pumpAndSettle();
    expect(find.text('UTC equivalent: 2026-06-22 04:30 UTC'), findsOneWidget);
    expect(inspector().state.timestamp, original.timestamp);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(inspector().state.timestamp, original.timestamp);
    await tester.tap(find.text('Edit local: 2026-06-21 20:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local date: 2026-06-21'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(DatePickerDialog)))
        .pop(DateTime(2026, 6, 22));
    await tester.pumpAndSettle();
    expect(find.text('UTC equivalent: 2026-06-23 03:00 UTC'), findsOneWidget);
    await tester.tap(find.text('Apply time'));
    await tester.pumpAndSettle();
    expect(inspector().state.timestamp, DateTime.utc(2026, 6, 23, 3));
    expect(inspector().state.location, original.location);
    expect(inspector().state.timestamp.isUtc, isTrue);
    inspector().onChanged(
      original.copyWith(timestamp: DateTime.utc(2100, 12, 31)),
    );
    await tester.pump();
    expect(find.textContaining('Local time unavailable:'), findsOneWidget);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('local-day-slider')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.text('Edit UTC: 2100-12-31 00:00'));
    await tester.pumpAndSettle();
    expect(find.text('Edit UTC (local time unavailable)'), findsOneWidget);
    await tester.tap(find.text('UTC date: 2100-12-31'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(DatePickerDialog)))
        .pop(DateTime(1900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply time'));
    await tester.pumpAndSettle();
    expect(inspector().state.timestamp, DateTime.utc(1900));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'local editor blocks DST gaps and requires a repeated-hour choice',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PhotoSimApp());
      CameraInspector inspector() =>
          tester.widget<CameraInspector>(find.byType(CameraInspector));
      final original = inspector().state.copyWith(
        timestamp: DateTime.utc(2026, 3, 8, 9, 30),
      );
      inspector().onChanged(original);
      await tester.pump();
      await tester.tap(find.text('Edit local: 2026-03-08 01:30'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local time: 01:30'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(TimePickerDialog)))
          .pop(const TimeOfDay(hour: 2, minute: 30));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This local time does not exist'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply time'),
            )
            .onPressed,
        isNull,
      );
      expect(inspector().state.timestamp, original.timestamp);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      inspector().onChanged(
        original.copyWith(timestamp: DateTime.utc(2026, 11, 1, 7, 30)),
      );
      await tester.pump();
      await tester.tap(find.text('Edit local: 2026-11-01 00:30'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local time: 00:30'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(TimePickerDialog)))
          .pop(const TimeOfDay(hour: 1, minute: 30));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This local time occurs twice'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply time'),
            )
            .onPressed,
        isNull,
      );
      tester
          .widget<DropdownButtonFormField<DateTime>>(
            find.byType(DropdownButtonFormField<DateTime>),
          )
          .onChanged!(DateTime.utc(2026, 11, 1, 9, 30));
      await tester.pumpAndSettle();
      expect(find.text('UTC equivalent: 2026-11-01 09:30 UTC'), findsOneWidget);
      await tester.tap(find.text('Apply time'));
      await tester.pumpAndSettle();
      expect(inspector().state.timestamp, DateTime.utc(2026, 11, 1, 9, 30));
      await tester.tap(find.text('Edit local: 2026-11-01 01:30'));
      await tester.pumpAndSettle();
      expect(find.text('UTC equivalent: 2026-11-01 09:30 UTC'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply time'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Use UTC instead (1900–2100)'));
      await tester.pumpAndSettle();
      expect(find.text('Edit simulation time (UTC)'), findsOneWidget);
      expect(find.text('UTC time: 09:30'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('target selection and aiming preserve location and UTC', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final beforeStartup = DateTime.now().toUtc();
    await tester.pumpWidget(const PhotoSimApp());
    final afterStartup = DateTime.now().toUtc();
    SimulationState camera() =>
        tester.widget<CameraInspector>(find.byType(CameraInspector)).state;
    final original = camera();
    expect(original.timestamp.isUtc, isTrue);
    expect(original.timestamp.isBefore(beforeStartup), isFalse);
    expect(original.timestamp.isAfter(afterStartup), isFalse);
    await tester.tap(find.byTooltip('Select astronomical target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galactic center').last);
    await tester.pump();
    expect(camera().target, CelestialTarget.galacticCenter);
    expect(camera().azimuth, original.azimuth);
    await tester.tap(find.byTooltip('Aim at selected target'));
    await tester.pump();
    expect(
      camera().containsDirection(camera().galacticCenter.direction),
      isTrue,
    );
    expect(find.textContaining('Galactic center: inside FOV'), findsOneWidget);
    expect(camera().location, original.location);
    expect(camera().timestamp, original.timestamp);
    await tester.tap(find.byTooltip('Later by one hour'));
    await tester.pump();
    expect(camera().target, CelestialTarget.galacticCenter);
    await tester.tap(find.byTooltip('Select astronomical target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No target').last);
    await tester.pump();
    expect(camera().targetPosition, isNull);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.gps_fixed))
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'shared UTC timeline updates astronomy and respects date bounds',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PhotoSimApp());
      final initialInspector = tester.widget<CameraInspector>(
        find.byType(CameraInspector),
      );
      initialInspector.onChanged(
        initialInspector.state.copyWith(
          timestamp: DateTime.utc(2026, 6, 21, 19),
        ),
      );
      await tester.pump();
      expect(
        find.text(
          'Estimated local: 2026-06-21 12:00 PDT (UTC-07:00) · America/Los_Angeles',
        ),
        findsOneWidget,
      );
      void checkGuides() {
        final state = tester
            .widget<CameraInspector>(find.byType(CameraInspector))
            .state;
        final lines = tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines;
        expect(lines.length, 5);
        final bodies = [state.sky.sun, state.sky.moon, state.galacticCenter];
        final markers = tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers;
        for (var i = 0; i < bodies.length; i++) {
          expect(lines[i + 1].points.first, state.location);
          expect(
            (bearing(state.location, lines[i + 1].points.last) -
                        bodies[i].azimuth +
                        540) %
                    360 -
                180,
            closeTo(0, 1e-7),
          );
          expect(
            lines[i + 1].pattern.segments != null,
            bodies[i].altitude <= 0,
          );
          expect(markers[i].point, lines[i + 1].points.last);
        }
      }

      checkGuides();
      final sunBefore = tester
          .widget<Text>(find.textContaining('Sun az '))
          .data;
      final moonBefore = tester
          .widget<Text>(find.textContaining('Moon az '))
          .data;
      await tester.tap(find.byTooltip('Later by one hour'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.textContaining('Sun az ')).data,
        isNot(sunBefore),
      );
      expect(
        tester.widget<Text>(find.textContaining('Moon az ')).data,
        isNot(moonBefore),
      );
      tester
          .widget<Slider>(find.byKey(const ValueKey('local-day-slider')))
          .onChanged!(360);
      await tester.pump();
      checkGuides();
      expect(
        tester
            .widget<CameraInspector>(find.byType(CameraInspector))
            .state
            .timestamp,
        DateTime.utc(2026, 6, 21, 13),
      );
      for (final entry in [
        (DateTime.utc(1900), 'Earlier by one hour'),
        (DateTime.utc(2100, 12, 31, 23), 'Later by one hour'),
      ]) {
        final inspector = tester.widget<CameraInspector>(
          find.byType(CameraInspector),
        );
        inspector.onChanged(inspector.state.copyWith(timestamp: entry.$1));
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == entry.$2,
                ),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playback pauses for time edits/background and stops at date bounds',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PhotoSimApp());
      SimulationState camera() =>
          tester.widget<CameraInspector>(find.byType(CameraInspector)).state;
      const play = 'Play time (5 simulated minutes per second)';
      final original = camera().timestamp;
      await tester.tap(find.byTooltip(play));
      await tester.pump(const Duration(milliseconds: 600));
      expect(camera().timestamp, original.add(const Duration(minutes: 3)));
      tester
          .widget<CameraInspector>(find.byType(CameraInspector))
          .onChanged(camera().copyWith(focalLength: 50));
      await tester.pump(const Duration(milliseconds: 200));
      expect(camera().timestamp, original.add(const Duration(minutes: 4)));
      await tester.tap(find.byTooltip('Pause time'));
      await tester.pump(const Duration(seconds: 1));
      expect(camera().timestamp, original.add(const Duration(minutes: 4)));
      await tester.tap(find.byTooltip(play));
      await tester.pump(const Duration(milliseconds: 200));
      final sliderDate = camera().timestamp;
      final editedTime = LocalDay(
        localClock(
          timestamp: sliderDate,
          latitude: camera().latitude,
          longitude: camera().longitude,
        ).time!,
      ).utcAt(400);
      tester
          .widget<Slider>(find.byKey(const ValueKey('local-day-slider')))
          .onChanged!(400);
      await tester.pump(const Duration(seconds: 1));
      expect(camera().timestamp, editedTime);
      expect(find.byTooltip(play), findsOneWidget);
      await tester.tap(find.byTooltip(play));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 1));
      expect(camera().timestamp, editedTime);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester
          .widget<CameraInspector>(find.byType(CameraInspector))
          .onChanged(
            camera().copyWith(
              timestamp: DateTime.utc(2100, 12, 31, 23, 58, 30),
            ),
          );
      await tester.pump();
      await tester.tap(find.byTooltip(play));
      await tester.pump(const Duration(milliseconds: 400));
      expect(camera().timestamp, DateTime.utc(2100, 12, 31, 23, 59, 30));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == play,
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Local time unavailable:'), findsOneWidget);
      tester
          .widget<CameraInspector>(find.byType(CameraInspector))
          .onChanged(camera().copyWith(timestamp: original));
      await tester.pump();
      await tester.tap(find.byTooltip(play));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inspector edits the shared sensor and optical model', (
    tester,
  ) async {
    var state = SimulationState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CameraInspector(
              state: state,
              onChanged: (next) => setState(() => state = next),
            ),
          ),
        ),
      ),
    );
    final initialFov = state.horizontalFov;
    expect(find.byType(SegmentedButton<Sensor>), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<Sensor>), findsNothing);
    expect(find.text('Lens'), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider).first).min, 8);
    expect(tester.widget<Slider>(find.byType(Slider).first).max, 600);
    await tester.tap(find.text('APS-C'));
    await tester.pumpAndSettle();
    expect(state.sensor, Sensor.apsC);
    expect(state.horizontalFov, lessThan(initialFov));
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pump();
    expect(state.focalLength, greaterThan(24));
    expect(tester.takeException(), isNull);
  });
}
