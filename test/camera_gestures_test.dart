import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_gestures.dart';

void main() {
  testWidgets('aiming adapts to zoom, sensor and viewport size', (
    tester,
  ) async {
    Future<SimulationState> aim(
      double focal,
      Size size, {
      Sensor sensor = Sensor.fullFrame,
      bool portrait = false,
    }) async {
      var state = SimulationState(
        azimuth: 180,
        pitch: 0,
        focalLength: focal,
        sensor: sensor,
        portrait: portrait,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: StatefulBuilder(
                builder: (context, setState) => CameraGestures(
                  state: state,
                  onChanged: (next) => setState(() => state = next),
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        final detector = tester.widget<GestureDetector>(
          find.descendant(
            of: find.byType(CameraGestures),
            matching: find.byType(GestureDetector),
          ),
        );
        detector.onScaleUpdate!(
          ScaleUpdateDetails(
            focalPointDelta: Offset(size.width / 800, -size.height / 600),
            pointerCount: 1,
          ),
        );
        await tester.pump();
      }
      return state;
    }

    final wide = await aim(24, const Size(800, 600));
    final zoomed = await aim(600, const Size(800, 600));
    expect(zoomed.azimuth - 180, greaterThan(0));
    expect(zoomed.azimuth - 180, lessThan(0.1));
    expect(wide.azimuth - 180, greaterThan((zoomed.azimuth - 180) * 10));
    expect(zoomed.pitch, closeTo(zoomed.azimuth - 180, 1e-10));
    final smaller = await aim(600, const Size(400, 300));
    expect(smaller.azimuth, closeTo(zoomed.azimuth, 1e-10));
    expect(smaller.pitch, closeTo(zoomed.pitch, 1e-10));
    final cropped = await aim(600, const Size(800, 600), sensor: Sensor.apsC);
    expect(cropped.azimuth - 180, lessThan(zoomed.azimuth - 180));
    final portrait = await aim(600, const Size(800, 600), portrait: true);
    expect(portrait.pitch, greaterThan(zoomed.pitch));
  });

  testWidgets(
    'touch aiming and pinch zoom preserve position and recover after cancellation',
    (tester) async {
      var state = SimulationState(timestamp: DateTime.utc(2026, 6, 21));
      final original = state;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => CameraGestures(
              state: state,
              onChanged: (next) => setState(() => state = next),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(CameraGestures), const Offset(80, -30));
      await tester.pump();
      expect(state.azimuth, greaterThan(original.azimuth));
      expect(state.pitch, greaterThan(original.pitch));
      final beforePinch = state;
      final left = await tester.startGesture(
        const Offset(300, 300),
        pointer: 1,
      );
      final right = await tester.startGesture(
        const Offset(500, 300),
        pointer: 2,
      );
      await left.moveTo(const Offset(250, 300));
      await right.moveTo(const Offset(550, 300));
      await tester.pump();
      await left.moveTo(const Offset(200, 300));
      await right.moveTo(const Offset(600, 300));
      await tester.pump();
      expect(state.focalLength, greaterThan(beforePinch.focalLength));
      expect(state.azimuth, beforePinch.azimuth);
      expect(state.pitch, beforePinch.pitch);
      await left.cancel();
      await right.cancel();
      final afterCancel = state;
      await tester.drag(find.byType(CameraGestures), const Offset(-60, 20));
      await tester.pump();
      expect(state.azimuth, isNot(afterCancel.azimuth));
      expect(state.focalLength, afterCancel.focalLength);
      expect(state.location, original.location);
      expect(state.timestamp, original.timestamp);
      final detector = tester.widget<GestureDetector>(
        find.descendant(
          of: find.byType(CameraGestures),
          matching: find.byType(GestureDetector),
        ),
      );
      detector.onScaleStart!(ScaleStartDetails());
      detector.onScaleUpdate!(
        ScaleUpdateDetails(scale: 1.037, pointerCount: 2),
      );
      await tester.pump();
      expect(
        state.focalLength,
        (afterCancel.focalLength * 1.037).roundToDouble(),
      );
      expect(state.focalLength % 1, 0);
      detector.onScaleStart!(ScaleStartDetails());
      detector.onScaleUpdate!(ScaleUpdateDetails(scale: 100, pointerCount: 2));
      await tester.pump();
      expect(state.focalLength, 600);
      detector.onScaleStart!(ScaleStartDetails());
      detector.onScaleUpdate!(
        ScaleUpdateDetails(scale: 0.001, pointerCount: 2),
      );
      await tester.pump();
      expect(state.focalLength, 8);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
