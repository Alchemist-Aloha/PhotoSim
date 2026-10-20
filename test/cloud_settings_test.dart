import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/render/clouds.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  test('cloud distance and elevated twilight colors remain bounded', () {
    expect(cloudRenderDistanceKm, 256);
    final day = cloudSunColor(45, 2);
    final low = cloudSunColor(2, 2);
    final afterSunset = cloudSunColor(-2, 8);
    expect(low.green, lessThan(day.green));
    expect(low.blue, lessThan(day.blue));
    expect(afterSunset.green, greaterThan(0));
    expect(afterSunset.blue, greaterThan(0));
    for (final altitude in [-90.0, -6.0, -2.0, 0.0, 5.0, 45.0, 90.0]) {
      for (final height in [0.0, 2.0, 8.0, 30.0]) {
        final color = cloudSunColor(altitude, height);
        for (final channel in [color.red, color.green, color.blue]) {
          expect(channel.isFinite, isTrue);
          expect(channel, inInclusiveRange(0, 1));
        }
      }
    }
  });
  test(
    'cloud settings round-trip, preserve composition, and migrate old plans',
    () {
      final original = SimulationState(
        timestamp: DateTime.utc(2026, 6, 21, 19),
      );
      for (final type in CloudType.values) {
        final state = original.copyWith(
          cloudType: type,
          cloudAmount: 0.63,
          cloudSeed: 123456,
        );
        final restored = SavedPlan.decode(
          SavedPlan('Cloud study', state).encode(),
        ).state;
        expect(restored.cloudType, type);
        expect(restored.cloudAmount, 0.63);
        expect(restored.cloudSeed, 123456);
        expect(restored.location, original.location);
        expect(restored.focalLength, original.focalLength);
        expect(restored.timestamp, original.timestamp);
        expect(state.copyWith(focalLength: 85).cloudSeed, 123456);
        expect(state.atmosphericEffects, isTrue);
        final layer = cloudLayer(type);
        expect(layer.base, greaterThan(0));
        expect(layer.thickness, greaterThan(0));
        expect(layer.extinction, greaterThan(0));
        expect(cloudLightTransmission(state), inInclusiveRange(0, 1));
      }
      for (final weather in Weather.values) {
        final state = original.copyWith(weather: weather);
        expect(state.cloudType, weather.cloudType);
        expect(state.cloudAmount, weather.cloudAmount);
        final json = jsonDecode(
          SavedPlan('Legacy', state).encode(),
        ) as Map<String, dynamic>;
        for (final key in ['cloudType', 'cloudAmount', 'cloudSeed']) {
          json.remove(key);
        }
        final legacy = SavedPlan.decode(jsonEncode(json)).state;
        expect(legacy.cloudType, weather.cloudType);
        expect(legacy.cloudAmount, weather.cloudAmount);
        expect(legacy.cloudSeed, 0);
      }
      expect(cloudLightTransmission(original), 1);
    },
  );

  test('cloud settings reject invalid values at construction and decoding', () {
    for (final amount in [-0.01, 1.01, double.nan, double.infinity]) {
      expect(() => SimulationState(cloudAmount: amount), throwsArgumentError);
    }
    for (final seed in [-1, 0x80000000]) {
      expect(() => SimulationState(cloudSeed: seed), throwsArgumentError);
    }
    final json = jsonDecode(
      SavedPlan('Validation', SimulationState()).encode(),
    ) as Map<String, dynamic>;
    for (final change in [
      {'cloudType': 'unknown'},
      {'cloudType': null},
      {'cloudAmount': null},
      {'cloudAmount': -0.1},
      {'cloudAmount': 1.1},
      {'cloudAmount': 'half'},
      {'cloudSeed': -1},
      {'cloudSeed': 1.5},
      {'cloudSeed': 0x80000000},
      {'cloudSeed': null},
    ]) {
      expect(
        () => SavedPlan.decode(jsonEncode({...json, ...change})),
        throwsFormatException,
      );
    }
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets(
      'cloud controls select type, amount and randomize at text scale $scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(310, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var state = SimulationState(timestamp: DateTime.utc(2026, 6, 21, 19));
        final original = state;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => CameraInspector(
                  state: state,
                  expandedSections: const {'Optics': false, 'Weather': true},
                  onChanged: (next) => update(() => state = next),
                ),
              ),
            ),
          ),
        );
        final typeField = find.byType(DropdownButtonFormField<CloudType>);
        final inspectorScroll = find
            .descendant(
              of: find.byType(CameraInspector),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          typeField,
          200,
          scrollable: inspectorScroll,
        );
        await tester.pumpAndSettle();
        tester.widget<DropdownButtonFormField<CloudType>>(typeField).onChanged!(
          CloudType.cirrus,
        );
        await tester.pumpAndSettle();
        expect(state.cloudType, CloudType.cirrus);
        expect(state.cloudAmount, 0);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Randomize clouds'),
              )
              .onPressed,
          isNull,
        );
        tester
            .widget<Slider>(find.byKey(const ValueKey('Cloud amount')))
            .onChanged!(65);
        await tester.pumpAndSettle();
        expect(state.cloudAmount, 0.65);
        await tester.ensureVisible(find.text('Randomize clouds'));
        await tester.pumpAndSettle();
        final before = state.cloudSeed;
        await tester.tap(find.text('Randomize clouds'));
        await tester.pumpAndSettle();
        expect(state.cloudSeed, isNot(before));
        expect(state.cloudType, CloudType.cirrus);
        expect(state.cloudAmount, 0.65);
        expect(state.location, original.location);
        expect(state.timestamp, original.timestamp);
        expect(state.focalLength, original.focalLength);
        tester
            .widget<Slider>(find.byKey(const ValueKey('Cloud amount')))
            .onChanged!(0);
        await tester.pumpAndSettle();
        expect(state.cloudAmount, 0);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
