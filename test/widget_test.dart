import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/ui/time_slider.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  testWidgets(
    'shared UTC timeline updates astronomy and respects date bounds',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PhotoSimApp());
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
        expect(lines.length, 3);
        final bodies = [state.sky.sun, state.sky.moon];
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
          .widget<Slider>(find.byKey(const ValueKey('utc-day-slider')))
          .onChanged!(360);
      await tester.pump();
      checkGuides();
      expect(
        tester
            .widget<CameraInspector>(find.byType(CameraInspector))
            .state
            .timestamp,
        DateTime.utc(2026, 6, 21, 6),
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
      tester
          .widget<Slider>(find.byKey(const ValueKey('utc-day-slider')))
          .onChanged!(400);
      await tester.pump(const Duration(seconds: 1));
      expect(camera().timestamp, DateTime.utc(2026, 6, 21, 6, 40));
      expect(find.byTooltip(play), findsOneWidget);
      await tester.tap(find.byTooltip(play));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 1));
      expect(camera().timestamp, DateTime.utc(2026, 6, 21, 6, 40));
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

  testWidgets(
    'day slider rounds minutes, preserves state and stays inside endpoint dates',
    (tester) async {
      var state = SimulationState(
        timestamp: DateTime.utc(1900),
        groundElevation: 1200,
        relitImagery: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => TimeSlider(
                state: state,
                onChanged: (next) => setState(() => state = next),
              ),
            ),
          ),
        ),
      );
      Slider slider() =>
          tester.widget<Slider>(find.byKey(const ValueKey('utc-day-slider')));
      expect(slider().semanticFormatterCallback!(59.6), '01:00 UTC');
      for (final value in [0.0, 59.6, 720.0, 1439.0]) {
        slider().onChanged!(value);
        await tester.pump();
        expect(
          state.timestamp,
          DateTime.utc(1900).add(Duration(minutes: value.round())),
        );
        expect(state.timestamp.isUtc, isTrue);
        expect(state.groundElevation, 1200);
        expect(state.relitImagery, isTrue);
        expect(state.latitude, 37.744);
      }
      state = state.copyWith(timestamp: DateTime.utc(2100, 12, 31, 23, 59, 59));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeSlider(state: state, onChanged: (next) => state = next),
          ),
        ),
      );
      expect(slider().value, 1439);
      slider().onChanged!(1439);
      expect(state.timestamp, DateTime.utc(2100, 12, 31, 23, 59));
      slider().onChanged!(0);
      expect(state.timestamp, DateTime.utc(2100, 12, 31));
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
    await tester.tap(find.text('Full-frame'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APS-C').last);
    await tester.pumpAndSettle();
    expect(state.sensor, Sensor.apsC);
    expect(state.horizontalFov, lessThan(initialFov));
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pump();
    expect(state.focalLength, greaterThan(24));
    expect(tester.takeException(), isNull);
  });
}
