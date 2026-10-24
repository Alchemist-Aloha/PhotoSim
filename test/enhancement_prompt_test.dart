import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/data/enhancement_prompt.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';

import 'app_session_test.dart' show sessionFixture;

void main() {
  test(
    'prompt includes the full captured composition, derived data and credits',
    () {
      final state = sessionFixture().state;
      final text = enhancementPrompt(
        state,
        credits: 'Example © source',
        width: 1800,
        height: 2700,
      );
      final metadata =
          jsonDecode(text.substring(text.indexOf('{'))) as Map<String, dynamic>;
      final composition = SavedPlan('Snapshot', state).toJson()
        ..remove('version')
        ..remove('name');
      for (final field in composition.entries) {
        expect(metadata[field.key], field.value, reason: field.key);
      }
      expect(metadata['timestamp'], '2026-06-16T05:00:00.000Z');
      expect(metadata['estimatedLocalTime'], contains('2026-06-16T15:00:00'));
      expect(metadata['estimatedTimeZone'], 'Australia/Sydney');
      expect(metadata['groundElevationMeters'], 900);
      expect(metadata['cameraElevationMeters'], 800);
      expect(metadata['sensorWidthMm'], 15.6);
      expect(metadata['sunAltitudeDegrees'], state.sky.sun.altitude);
      expect(metadata['moonIlluminationFraction'], state.sky.moonIllumination);
      expect(metadata['outputWidthPixels'], 1800);
      expect(metadata['outputHeightPixels'], 2700);
      expect(metadata['sourceCredits'], 'Example © source');
      expect(text, contains('not a real photograph'));
      expect(text, contains('acquisition time is unknown'));
      expect(text, contains('attribution strip'));
    },
  );

  test(
    'unknown elevation and unsupported local dates remain explicitly unknown',
    () {
      final state = SimulationState(timestamp: DateTime.utc(2100, 1, 1));
      final text = enhancementPrompt(
        state,
        credits: '',
        width: 1200,
        height: 800,
      );
      final metadata =
          jsonDecode(text.substring(text.indexOf('{'))) as Map<String, dynamic>;
      expect(metadata['groundElevationMeters'], isNull);
      expect(metadata['cameraElevationMeters'], isNull);
      expect(metadata['estimatedLocalTime'], isNull);
      expect(metadata['localTimeStatus'], contains('1970–2037'));
      expect(metadata['timestamp'], '2100-01-01T00:00:00.000Z');
    },
  );
}
