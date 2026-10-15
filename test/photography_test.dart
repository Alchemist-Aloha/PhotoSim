import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/rain_overlay.dart';

void main() {
  test('photography settings roundtrip, validate and keep legacy defaults', () {
    final original = SimulationState(
      weather: Weather.rain,
      renderQuality: RenderQuality.high,
      depthOfField: true,
      aperture: 1.4,
      focusDistance: 3,
    );
    final restored = SavedPlan.decode(SavedPlan('Rain', original).encode())
        .state;
    expect(restored.weather, Weather.rain);
    expect(restored.renderQuality, RenderQuality.high);
    expect(restored.depthOfField, isTrue);
    expect(restored.aperture, 1.4);
    expect(restored.focusDistance, 3);
    final json = jsonDecode(
      SavedPlan('Legacy', original).encode(),
    ) as Map<String, Object?>;
    for (final key in [
      'weather',
      'renderQuality',
      'depthOfField',
      'aperture',
      'focusDistance',
    ]) {
      json.remove(key);
    }
    final legacy = SavedPlan.decode(jsonEncode(json)).state;
    expect(legacy.weather, Weather.clear);
    expect(legacy.renderQuality, RenderQuality.balanced);
    expect(legacy.depthOfField, isFalse);
    expect(legacy.aperture, 8);
    expect(legacy.focusDistance, 1000);
    for (final entry in [
      ('weather', 'snow'),
      ('renderQuality', 'ultra'),
      ('depthOfField', 1),
      ('aperture', 0),
      ('aperture', 23),
      ('focusDistance', 0.5),
      ('focusDistance', 1000001),
    ]) {
      expect(
        () => SavedPlan.decode(jsonEncode({...json, entry.$1: entry.$2})),
        throwsFormatException,
      );
    }
    expect(() => original.copyWith(aperture: double.nan), throwsArgumentError);
    expect(
      () => original.copyWith(focusDistance: double.infinity),
      throwsArgumentError,
    );
    final changed = original.copyWith(weather: Weather.fog, aperture: 16);
    expect(changed.timestamp, original.timestamp);
    expect(changed.location, original.location);
    expect(changed.focusDistance, 3);
    for (final weather in Weather.values) {
      expect(weather.lightTransmission, inInclusiveRange(0, 1));
    }
  });

  testWidgets(
    'DOF controls set aperture/focus without changing optics or UTC',
    (tester) async {
      var state = SimulationState();
      final original = state;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => CameraInspector(
                state: state,
                onChanged: (next) => update(() => state = next),
              ),
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('Depth of field'), 200);
      await tester.tap(find.text('Depth of field'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(SwitchListTile), 200);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(state.depthOfField, isTrue);
      final aperture = tester
          .widgetList<Slider>(find.byType(Slider))
          .singleWhere((slider) => slider.label == 'Aperture (f-number)');
      aperture.onChanged!(2.8);
      await tester.pump();
      tester
          .widget<Slider>(find.byKey(const ValueKey('focus-distance')))
          .onChanged!(2);
      await tester.pump();
      expect(state.aperture, 2.8);
      expect(state.focusDistance, 100);
      expect(state.focalLength, original.focalLength);
      expect(state.timestamp, original.timestamp);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'illustrative rain paints, ignores gestures and disposes its clock',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(width: 400, height: 300, child: RainOverlay()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(RainOverlay),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
