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
  testWidgets('export a reproducible Yosemite cloud photograph and metadata', (
    tester,
  ) async {
    if (!Platform.isLinux) return;
    final output = Directory('build/validation/cloud-photo');
    await output.create(recursive: true);
    final raw = File('${output.absolute.path}/raw.png');
    if (await raw.exists()) await raw.delete();
    var state = SimulationState(
      latitude: 37.744,
      longitude: -119.59,
      timestamp: DateTime.utc(2026, 6, 22, 2),
      azimuth: 85,
      pitch: 8,
      focalLength: 35,
      exposureMode: ExposureMode.manual,
      aperture: 8,
      iso: 100,
      shutterSeconds: 1 / 125,
      cloudType: CloudType.cumulus,
      cloudAmount: 0.60,
      cloudSeed: 4721,
      showCrosshair: false,
      showGrid: false,
      showLevel: false,
    );
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
      'location': 'Yosemite Valley, California, USA; eastward view toward the Half Dome area',
      'estimated_local_time': clock.time?.toIso8601String(),
      'timezone': clock.zoneId,
      'plan': jsonDecode(SavedPlan('Yosemite cloud study', state).encode()),
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
      'procedural_cloud_layer': {
        'base_above_ground_km': cloudLayer(state.cloudType).base,
        'thickness_km': cloudLayer(state.cloudType).thickness,
        'render_distance_km': cloudRenderDistanceKm,
        'note': 'Nominal illustrative layer, not measured meteorology.',
      },
      'weather_note': 'Manually specified illustrative cumulus clouds at 60% amount, no rain, 500 km visibility control. The Clear preset supplies clear-air defaults; clouds override its initial zero amount. Not historical weather or a forecast.',
      'limitations': 'Terrain and imagery resolution, captured imagery lighting, approximate exposure and atmospheric scattering; procedural clouds without measured cloud heights or spatial terrain cloud shadows. AI enhancement may invent detail.',
    };
    await File('${output.path}/metadata.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(metadata)}\n',
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
