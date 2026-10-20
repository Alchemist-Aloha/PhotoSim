import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/core/camera_movement.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/wasd_navigation.dart';

void main() {
  test(
    'WASD follows terrain while preserving heading, pitch and height offset',
    () {
      final state = SimulationState(
        groundElevation: 1200,
        height: 1.7,
        azimuth: 90,
        pitch: 85,
        roll: 80,
      );
      final moved = moveCamera(state, 30, 0);
      expect(bearing(state.location, moved.location), closeTo(90, 1e-7));
      expect(
        const Distance().as(LengthUnit.Meter, state.location, moved.location),
        closeTo(30, 0.1),
      );
      expect(moved.fixedElevation, isNull);
      expect(moved.cameraElevation, isNull);
      expect(moved.height, state.height);
      expect(moved.pitch, state.pitch);
      expect(moved.roll, state.roll);
      expect(moved.timestamp, state.timestamp);
      expect(moved.copyWith(groundElevation: 1400).cameraElevation, 1401.7);
      expect(moved.copyWith(groundElevation: 800).cameraElevation, 801.7);
      expect(
        moved.copyWith(groundElevation: 1400).sky.moon.distanceKm,
        isNot(moved.copyWith(groundElevation: 800).sky.moon.distanceKm),
      );
      final forward = moveCamera(state.copyWith(pitch: -85), 30, 0);
      expect(forward.location, moved.location);
      expect(
        bearing(state.location, moveCamera(state, 0, 30).location),
        closeTo(180, 1e-7),
      );
      expect(
        bearing(state.location, moveCamera(state, -30, 0).location),
        closeTo(270, 1e-7),
      );
      expect(
        (bearing(state.location, moveCamera(state, 0, -30).location) + 180) %
                360 -
            180,
        closeTo(0, 1e-7),
      );
      expect(moved.copyWith(height: 2).fixedElevation, isNull);
      expect(moved.copyWith(latitude: 40).fixedElevation, isNull);
      expect(moved.copyWith(clearFixedElevation: true).fixedElevation, isNull);
      expect(moveCamera(SimulationState(), 30, 0).fixedElevation, isNull);
      expect(identical(moveCamera(state, 0, 0), state), isTrue);
      expect(() => moveCamera(state, double.nan, 0), throwsArgumentError);
      expect(() => moveCamera(state, 0, double.infinity), throwsArgumentError);
    },
  );
  test('WASD releases legacy elevation overrides; height offsets persist', () {
    final state = SimulationState(groundElevation: 500, fixedElevation: 501.7);
    final restored = SavedPlan.decode(SavedPlan('Walk', state).encode()).state;
    expect(restored.cameraElevation, state.cameraElevation);
    expect(restored.groundElevation, isNull);
    final moved = moveCamera(restored, 10, 0);
    expect(moved.fixedElevation, isNull);
    expect(moved.copyWith(groundElevation: 600).cameraElevation, 601.7);
    final walkedPlan = SavedPlan.decode(SavedPlan('Walked', moved).encode())
        .state;
    expect(walkedPlan.fixedElevation, isNull);
    expect(walkedPlan.height, 1.7);
    final json =
        jsonDecode(SavedPlan('Walk', state).encode()) as Map<String, Object?>;
    json.remove('fixedElevation');
    expect(SavedPlan.decode(jsonEncode(json)).state.fixedElevation, isNull);
    for (final value in ['high', -12001, 10101]) {
      expect(
        () => SavedPlan.decode(jsonEncode({...json, 'fixedElevation': value})),
        throwsFormatException,
      );
    }
    expect(
      () => state.copyWith(fixedElevation: double.nan),
      throwsArgumentError,
    );
    final wrapped = moveCamera(
      SimulationState(longitude: 179.9999, groundElevation: 0, azimuth: 90),
      30,
      0,
    );
    expect(wrapped.longitude, lessThan(0));
    final polar = moveCamera(
      SimulationState(latitude: 85.05112878, groundElevation: 0),
      30,
      0,
    );
    expect(polar.latitude, lessThanOrEqualTo(85.05112878));
  });
  test('resident frame transform agrees with direct WGS84 projection, including the dateline', () {
    for (final origin in [
      const LatLng(37.744, -119.59),
      const LatLng(85, 179.9999),
      const LatLng(-85, -179.9999),
    ]) {
      final old = LocalFrame(origin);
      final next = LocalFrame(destination(origin, 65, 300));
      final point = destination(origin, 120, 2000);
      final transformed = next
          .transformFrom(old)
          .transformed3(old.project(point, 1250));
      final expected = next.project(point, 1250);
      expect((transformed - expected).length, lessThan(1e-6));
    }
  });
  testWidgets(
    'held WASD normalizes diagonals and stops for focus/lifecycle/disposal',
    (tester) async {
      var forward = 0.0, right = 0.0;
      final textFocus = FocusNode();
      addTearDown(textFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: textFocus),
                Expanded(
                  child: WasdNavigation(
                    enabled: true,
                    onMove: (f, r) {
                      forward += f;
                      right += r;
                    },
                    child: const ColoredBox(
                      key: ValueKey('view'),
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      await tester.tap(find.byKey(const ValueKey('view')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      await frames(5);
      expect(forward, closeTo(10, 0.01));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      final before = forward;
      await frames(5);
      expect(forward - before, closeTo(10 / math.sqrt(2), 0.01));
      expect(right, closeTo(10 / math.sqrt(2), 0.01));
      textFocus.requestFocus();
      await tester.pump();
      final stopped = forward;
      await frames(5);
      expect(forward, stopped);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.enterText(find.byType(TextField), 'wasd');
      expect(forward, stopped);
      await tester.tap(find.byKey(const ValueKey('view')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      await frames(2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final inactive = forward;
      await frames(5);
      expect(forward, inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await frames(5);
      expect(forward, inactive);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
