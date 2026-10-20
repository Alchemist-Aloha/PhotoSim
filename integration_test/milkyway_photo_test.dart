import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/core/local_time.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/render/clouds.dart';
import 'package:photosim/ui/simulation_workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'export a reproducible Yosemite Milky Way photograph and metadata',
    (tester) async {
      if (!Platform.isLinux) return;
      const labels = bool.fromEnvironment('CONSTELLATION_LABELS');
      final output = Directory(
        labels
            ? 'build/validation/milkyway-photo-labeled'
            : 'build/validation/milkyway-photo',
      );
      await output.create(recursive: true);
      final raw = File('${output.absolute.path}/raw.png');
      if (await raw.exists()) await raw.delete();
      var state = SimulationState(
        latitude: 37.744,
        longitude: -119.59,
        timestamp: DateTime.utc(2026, 6, 15, 8),
        azimuth: 180,
        pitch: 25,
        focalLength: 20,
        exposureMode: ExposureMode.enhanced,
        aperture: 2.8,
        iso: 3200,
        shutterSeconds: 15,
        cloudType: CloudType.cumulus,
        cloudAmount: 0,
        cloudSeed: 0,
        showConstellations: labels,
        showCrosshair: false,
        showGrid: false,
        showLevel: false,
      );
      state = state.copyWith(azimuth: state.galacticCenter.azimuth);
      expect(state.sky.sun.altitude, lessThan(-18));
      expect(state.sky.moon.altitude, lessThan(0));
      expect(state.galacticCenter.altitude, greaterThan(15));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SimulationWorkspace(
                state: state,
                cacheDirectory: Directory('${output.absolute.path}/cache'),
                onChanged: (next) => update(() => state = next),
                onGroundElevationChanged: (location, elevation) {
                  if (state.location == location) {
                    update(
                      () => state = state.copyWith(groundElevation: elevation),
                    );
                  }
                },
              ),
            ),
          ),
        ),
      );
      final export = find.widgetWithText(OutlinedButton, 'Export PNG');
      for (var i = 0; i < 240; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (export.evaluate().isNotEmpty &&
            tester.widget<OutlinedButton>(export).onPressed != null) {
          break;
        }
      }
      expect(export, findsOneWidget);
      expect(tester.widget<OutlinedButton>(export).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(export);
      for (var i = 0; i < 40 && find.text('Save PNG').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Save PNG'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        raw.path,
      );
      await tester.tap(find.text('Save PNG'));
      for (var i = 0; i < 60 && !await raw.exists(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(await raw.exists(), isTrue);
      expect(await raw.length(), greaterThan(10000));
      final clock = localClock(
        timestamp: state.timestamp,
        latitude: state.latitude,
        longitude: state.longitude,
      );
      final sky = state.sky;
      final metadata = {
        'purpose': 'Raw simulator photograph for an AI-assisted realism comparison, not a measured forecast.',
        'raw_image': 'raw.png',
        'location':
            'Yosemite Valley, California, USA; view toward the Galactic center',
        'estimated_local_time': clock.time?.toIso8601String(),
        'timezone': clock.zoneId,
        'plan': jsonDecode(
          SavedPlan('Yosemite Milky Way study', state).encode(),
        ),
        'ground_elevation_m_source_datum': state.groundElevation,
        'camera_elevation_m_source_datum': state.cameraElevation,
        'sensor_width_mm': state.sensorWidth,
        'sensor_height_mm': state.sensorHeight,
        'horizontal_fov_degrees': state.horizontalFov * 180 / 3.141592653589793,
        'vertical_fov_degrees': state.verticalFov * 180 / 3.141592653589793,
        'sun': {
          'azimuth_degrees': sky.sun.azimuth,
          'altitude_degrees': sky.sun.altitude,
          'diameter_degrees': sky.sun.angularRadius * 360 / 3.141592653589793,
        },
        'moon': {
          'azimuth_degrees': sky.moon.azimuth,
          'altitude_degrees': sky.moon.altitude,
          'diameter_degrees': sky.moon.angularRadius * 360 / 3.141592653589793,
          'illuminated_fraction': sky.moonIllumination,
        },
        'galactic_center': {
          'azimuth_degrees': state.galacticCenter.azimuth,
          'altitude_degrees': state.galacticCenter.altitude,
        },
        'exposure_note': 'Enhanced visibility renders artistic night-sky brightness. ISO 3200, f/2.8 and 15 s are stored photographic reference settings, not an active calibrated manual exposure.',
        'procedural_cloud_layer': {
          'base_above_ground_km': cloudLayer(state.cloudType).base,
          'thickness_km': cloudLayer(state.cloudType).thickness,
          'render_distance_km': cloudRenderDistanceKm,
          'note': 'Nominal illustrative layer, not measured meteorology.',
        },
        'weather_note': 'Manually specified clear sky, 0% cloud amount, no rain, 500 km visibility control and 100% light transmission. Not historical weather or a forecast.',
        'limitations': 'Terrain and imagery resolution, captured imagery lighting, approximate exposure and atmospheric scattering. Milky Way uses simplified brightness contours and 5,044 bundled stars, not calibrated astrophotography; no star tracking or long-exposure trail simulation. AI enhancement may invent detail.',
      };
      await File('${output.path}/metadata.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(metadata)}\n',
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
