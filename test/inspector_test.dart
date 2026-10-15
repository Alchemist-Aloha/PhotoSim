import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  test(
    'weather overrides validate, persist and reset only on preset changes',
    () {
      final state = SimulationState(
        weather: Weather.rain,
        weatherVisibilityKm: 5,
        weatherLightTransmission: 0.8,
        rainIntensity: 0.2,
      );
      final restored = SavedPlan.decode(
        SavedPlan('Custom rain', state).encode(),
      ).state;
      expect(restored.weatherVisibilityKm, 5);
      expect(restored.weatherLightTransmission, 0.8);
      expect(restored.rainIntensity, 0.2);
      final moved = restored.copyWith(azimuth: 90);
      expect(moved.weatherVisibilityKm, 5);
      expect(moved.copyWith(weather: Weather.rain).rainIntensity, 0.2);
      final fog = moved.copyWith(weather: Weather.fog);
      expect(fog.weatherVisibilityKm, Weather.fog.visibilityKm);
      expect(fog.weatherLightTransmission, Weather.fog.lightTransmission);
      expect(fog.rainIntensity, 0);
      expect(fog.timestamp, state.timestamp);
      expect(fog.location, state.location);
      expect(SimulationState().relitImagery, isTrue);
      expect(
        SavedPlan.decode(
          SavedPlan('Natural', state.copyWith(relitImagery: false)).encode(),
        ).state.relitImagery,
        isFalse,
      );
      final json = jsonDecode(
        SavedPlan('Legacy', state).encode(),
      ) as Map<String, dynamic>;
      for (final key in [
        'weatherVisibilityKm',
        'weatherLightTransmission',
        'rainIntensity',
      ]) {
        json.remove(key);
      }
      final legacy = SavedPlan.decode(jsonEncode(json)).state;
      expect(legacy.weatherVisibilityKm, Weather.rain.visibilityKm);
      expect(legacy.weatherLightTransmission, Weather.rain.lightTransmission);
      expect(legacy.rainIntensity, Weather.rain.rainIntensity);
      for (final entry in [
        ('weatherVisibilityKm', 0),
        ('weatherVisibilityKm', 101),
        ('weatherLightTransmission', -0.1),
        ('weatherLightTransmission', 1.1),
        ('rainIntensity', -1),
        ('rainIntensity', 2),
        ('rainIntensity', 'heavy'),
      ]) {
        expect(
          () => SavedPlan.decode(jsonEncode({...json, entry.$1: entry.$2})),
          throwsFormatException,
        );
      }
      expect(
        () => state.copyWith(weatherVisibilityKm: double.nan),
        throwsArgumentError,
      );
      expect(
        () => state.copyWith(weatherLightTransmission: double.infinity),
        throwsArgumentError,
      );
      expect(
        () => state.copyWith(rainIntensity: double.nan),
        throwsArgumentError,
      );
      expect(
        state.copyWith(weather: Weather.clear).atmosphericEffects,
        isFalse,
      );
      expect(
        state
            .copyWith(weather: Weather.clear, weatherVisibilityKm: 1)
            .atmosphericEffects,
        isTrue,
      );
    },
  );

  testWidgets(
    'collapsible panel edits weather, remembers expansion and preserves camera state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(310, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      expect(find.byType(ExpansionTile), findsNWidgets(6));
      expect(find.byKey(const ValueKey('Focal length')), findsOneWidget);
      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('Focal length')), findsNothing);
      await tester.tap(find.text('Weather'));
      await tester.pumpAndSettle();
      final preset = find.byType(DropdownButtonFormField<Weather>);
      tester.widget<DropdownButtonFormField<Weather>>(preset).onChanged!(
        Weather.rain,
      );
      await tester.pumpAndSettle();
      for (final edit in [
        ('Visibility', 4.0),
        ('Light transmission', 65.0),
        ('Rain intensity', 25.0),
      ]) {
        tester.widget<Slider>(find.byKey(ValueKey(edit.$1))).onChanged!(
          edit.$2,
        );
        await tester.pump();
      }
      expect(state.weatherVisibilityKm, 4);
      expect(state.weatherLightTransmission, 0.65);
      expect(state.rainIntensity, 0.25);
      expect(state.timestamp, original.timestamp);
      expect(state.location, original.location);
      expect(state.focalLength, original.focalLength);
      await tester.ensureVisible(find.text('Weather'));
      await tester.tap(find.text('Weather'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('Visibility')), findsNothing);
      await tester.tap(find.text('Weather'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Slider>(find.byKey(const ValueKey('Visibility'))).value,
        4,
      );
      await tester.ensureVisible(find.text('Reset weather parameters'));
      await tester.tap(find.text('Reset weather parameters'));
      await tester.pumpAndSettle();
      expect(state.weatherVisibilityKm, Weather.rain.visibilityKm);
      expect(state.rainIntensity, Weather.rain.rainIntensity);
      tester.widget<DropdownButtonFormField<Weather>>(preset).onChanged!(
        Weather.clear,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('Rain intensity')), findsNothing);
      expect(state.weatherLightTransmission, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
