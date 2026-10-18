import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_gestures.dart';

void main() {
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
