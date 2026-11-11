import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/atmosphere.dart';
import 'package:photosim/core/sunlight.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';

void main() {
  test('humidity grows hygroscopic haze and desert dust absorbs blue', () {
    final dry = AtmosphereOptics.compute(humidity: 20);
    final humid = AtmosphereOptics.compute(humidity: 90);
    expect(humid.mieScattering.green, greaterThan(dry.mieScattering.green * 2));
    final desert = AtmosphereOptics.compute(
      aerosolType: AerosolType.desert,
      humidity: 20,
    );
    final continental = AtmosphereOptics.compute(humidity: 20);
    expect(
      desert.mieAbsorption.blue / desert.mieAbsorption.red,
      greaterThan(
        continental.mieAbsorption.blue / continental.mieAbsorption.red,
      ),
    );
  });

  test('ozone column scales Chappuis absorption and reddens sunlight', () {
    final normal = AtmosphereOptics.compute(ozoneColumnDu: 300);
    final thin = AtmosphereOptics.compute(ozoneColumnDu: 100);
    expect(normal.ozone.green, greaterThan(thin.ozone.green * 2.5));
    final smoky = AtmosphereOptics.compute(
      aerosolType: AerosolType.smoke,
      aerosolOpticalDepth: 1.3,
    );
    final clear = sunTransmission(1);
    final hazy = sunTransmission(1, optics: smoky);
    expect(hazy.green, lessThan(clear.green));
    expect(hazy.blue, lessThan(hazy.green));
  });

  test('aerosol and ozone settings reject out-of-range values', () {
    for (final build in [
      () => SimulationState(aerosolOpticalDepth: 0),
      () => SimulationState(aerosolOpticalDepth: 2.1),
      () => SimulationState(humidity: -1),
      () => SimulationState(humidity: 101),
      () => SimulationState(ozoneColumnDu: 99),
      () => SimulationState(ozoneColumnDu: 501),
    ]) {
      expect(build, throwsArgumentError);
    }
  });

  test('plans persist advanced atmosphere and default old plans', () {
    final state = SimulationState(
      aerosolType: AerosolType.desert,
      aerosolOpticalDepth: 0.8,
      humidity: 18,
      ozoneColumnDu: 140,
    );
    final restored = SavedPlan.decode(SavedPlan('Dust', state).encode()).state;
    expect(restored.aerosolType, AerosolType.desert);
    expect(restored.aerosolOpticalDepth, 0.8);
    expect(restored.humidity, 18);
    expect(restored.ozoneColumnDu, 140);

    final legacy =
        jsonDecode(SavedPlan('Legacy', state).encode()) as Map<String, Object?>;
    legacy
      ..remove('aerosolType')
      ..remove('aerosolOpticalDepth')
      ..remove('humidity')
      ..remove('ozoneColumnDu');
    final old = SavedPlan.decode(jsonEncode(legacy)).state;
    expect(old.aerosolType, AerosolType.continental);
    expect(old.aerosolOpticalDepth, 0.005);
    expect(old.humidity, 40);
    expect(old.ozoneColumnDu, 300);
  });
}
