import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/data/app_session.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  test(
    'camera fill defaults off, validates and survives plans/session recovery',
    () {
      final state = SimulationState(cameraLightStrength: 42);
      final plan = SavedPlan('Torch', state);
      expect(SavedPlan.decode(plan.encode()).state.cameraLightStrength, 42);
      final legacy = jsonDecode(plan.encode()) as Map<String, dynamic>;
      legacy.remove('cameraLightStrength');
      expect(SavedPlan.decode(jsonEncode(legacy)).state.cameraLightStrength, 0);
      final session = AppSession(state: state, cleanComposition: plan.encode());
      expect(AppSession.decode(session.encode()).state.cameraLightStrength, 42);
      expect(state.copyWith(azimuth: 90).cameraLightStrength, 42);
      for (final value in [-1.0, 101.0, double.nan, double.infinity]) {
        expect(
          () => state.copyWith(cameraLightStrength: value),
          throwsArgumentError,
        );
      }
      legacy['cameraLightStrength'] = 'bright';
      expect(() => SavedPlan.decode(jsonEncode(legacy)), throwsFormatException);
    },
  );
  for (final width in [310.0, 390.0]) {
    testWidgets(
      'camera fill slider is live, accessible and disabled for natural imagery at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var state = SimulationState();
        final original = state;
        late StateSetter rebuild;
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) {
                  rebuild = update;
                  return CameraInspector(
                    state: state,
                    expandedSections: const {
                      'Optics': false,
                      'Rendering': true,
                    },
                    onChanged: (next) => update(() => state = next),
                  );
                },
              ),
            ),
          ),
        );
        final slider = find.byKey(const ValueKey('camera-light-strength'));
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Camera light strength'), findsOneWidget);
        tester.widget<Slider>(slider).onChanged!(35);
        await tester.pump();
        expect(state.cameraLightStrength, 35);
        expect(state.timestamp, original.timestamp);
        expect(state.location, original.location);
        expect(state.focalLength, original.focalLength);
        expect(find.text('Camera light: 35%'), findsOneWidget);
        rebuild(() => state = state.copyWith(relitImagery: false));
        await tester.pump();
        expect(tester.widget<Slider>(slider).onChanged, isNull);
        expect(state.cameraLightStrength, 35);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
