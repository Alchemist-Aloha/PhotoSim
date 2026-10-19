import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/core/terrain_coverage.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/map_workspace.dart';

void main() {
  test('loading envelope follows fetch settings, not render distance', () {
    final state = SimulationState(timestamp: DateTime.utc(2026));
    final near = approximateTerrainLoadingRadius(state);
    expect(near, greaterThan(0));
    expect(
      approximateTerrainLoadingRadius(state.copyWith(terrainRings: 3)),
      greaterThan(near),
    );
    expect(
      approximateTerrainLoadingRadius(state.copyWith(terrainForwardKm: 40)),
      40000,
    );
    expect(
      approximateTerrainLoadingRadius(state.copyWith(terrainRenderKm: 2)),
      near,
    );
  });
  test('geodesic circles close cleanly, including across the date line and near poles', () {
    for (final site in [
      (0.0, 0.0),
      (45.0, 179.999),
      (-45.0, -179.999),
      (85.0, 179.999),
    ]) {
      final state = SimulationState(
        latitude: site.$1,
        longitude: site.$2,
        terrainForwardKm: 40,
      );
      final points = terrainLoadingCircle(state);
      expect(points, hasLength(97));
      expect(points.first, points.last);
      for (var i = 0; i < points.length; i++) {
        final normalized = LatLng(
          points[i].latitude,
          (points[i].longitude + 180) % 360 - 180,
        );
        expect(
          const Distance().as(LengthUnit.Meter, state.location, normalized),
          closeTo(40000, 250),
        );
        if (i > 0) {
          expect(
            (points[i].longitude - points[i - 1].longitude).abs(),
            lessThan(180),
          );
        }
      }
    }
  });
  testWidgets(
    'map range is dashed and updates live with location and fetch preferences',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('photosim-range-map-');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        dir.deleteSync(recursive: true);
      });
      var state = SimulationState(timestamp: DateTime.utc(2026));
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return MapWorkspace(
                  state: state,
                  onChanged: (next) => setState(() => state = next),
                );
              },
            ),
          ),
        ),
      );
      Polyline circle() => tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .last;
      final before = circle();
      expect(before.pattern.segments, [8, 6]);
      expect(before.points, terrainLoadingCircle(state));
      rebuild(
        () => state = state.copyWith(
          latitude: 35,
          longitude: 140,
          terrainForwardKm: 30,
        ),
      );
      await tester.pump();
      expect(circle().points, terrainLoadingCircle(state));
      expect(circle().points, isNot(before.points));
      expect(
        find.textContaining('30.0 km requested terrain extent'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
