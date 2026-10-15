import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/sunlight.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';

void main() {
  test('clear-air sunlight dims and reddens toward either horizon', () {
    final low = sunlight(1), noon = sunlight(60);
    expect(low.intensity, lessThan(noon.intensity / 3));
    expect(low.green, lessThan(0.2));
    expect(low.blue, lessThan(low.green));
    expect(noon.green, greaterThan(0.9));
    expect(noon.blue, greaterThan(0.7));
    var last = sunlight(0);
    for (final altitude in [0.01, 0.1, 0.5, 1.0, 5.0, 15.0, 45.0, 90.0]) {
      final current = sunlight(altitude);
      expect(current.intensity, greaterThan(last.intensity));
      expect(current.green, greaterThan(last.green));
      expect(current.blue, greaterThan(last.blue));
      last = current;
    }
    expect(sunlight(-10).intensity, 0);
    expect(sunlight(0.00001).intensity, lessThan(0.001));
    for (final altitude in [double.nan, double.infinity, -91.0, 91.0]) {
      expect(() => sunlight(altitude), throwsArgumentError);
    }
  });

  test('AA persists independently of quality; legacy plans enable FXAA', () {
    final state = SimulationState();
    expect(state.antialiasing, Antialiasing.fxaa);
    for (final mode in Antialiasing.values) {
      final changed = state.copyWith(antialiasing: mode);
      expect(changed.timestamp, state.timestamp);
      expect(changed.location, state.location);
      expect(changed.renderQuality, state.renderQuality);
      expect(
        SavedPlan.decode(SavedPlan('AA', changed).encode()).state.antialiasing,
        mode,
      );
    }
    final json =
        jsonDecode(SavedPlan('Old', state).encode()) as Map<String, dynamic>;
    json.remove('antialiasing');
    expect(
      SavedPlan.decode(jsonEncode(json)).state.antialiasing,
      Antialiasing.fxaa,
    );
    expect(
      () => SavedPlan.decode(jsonEncode({...json, 'antialiasing': 'invalid'})),
      throwsFormatException,
    );
  });
}
