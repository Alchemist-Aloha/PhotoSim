import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/core/terrain_coverage.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/terrain/terrain_patch.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/render/photography.dart';

void main() {
  test(
    'High geometry doubles mesh sampling, other quality budgets stay unchanged',
    () {
      final center = TileId.at(const LatLng(37.744, -119.59));
      final neighbor = TileId(center.z, center.x + 1, center.y);
      final far = TileId(11, center.x ~/ 4, center.y ~/ 4);
      for (final quality in RenderQuality.values) {
        final factor = quality == RenderQuality.high ? 2 : 1;
        expect(terrainMeshResolution(center, center, quality), 128 * factor);
        expect(terrainMeshResolution(neighbor, center, quality), 64 * factor);
        expect(terrainMeshResolution(far, center, quality), 32 * factor);
      }
    },
  );
  test('full DEM geometry retains narrow peaks, valid uint32 indices and unit normals', () {
    final id = TileId.at(const LatLng(37.744, -119.59));
    final heights = Float32List(256 * 256)..[100 * 256 + 100] = 1000;
    final field = HeightField(heights, 256);
    final origin = id.point(0.5, 0.5);
    final balanced = buildTerrainPatch(field, id, origin, 128);
    final high = buildTerrainPatch(field, id, origin, 256);
    double peak(TerrainPatch patch) =>
        [for (var i = 1; i < patch.positions.length; i += 3) patch.positions[i]]
            .reduce(math.max);
    expect(peak(high), greaterThan(peak(balanced) + 500));
    expect(high.indices.reduce(math.max), greaterThan(65535));
    expect(
      high.indices.every((i) => i >= 0 && i < high.positions.length ~/ 3),
      isTrue,
    );
    for (var i = 0; i < high.normals.length; i += 3) {
      final length =
          high.normals[i] * high.normals[i] +
          high.normals[i + 1] * high.normals[i + 1] +
          high.normals[i + 2] * high.normals[i + 2];
      expect(length, closeTo(1, 1e-5));
    }
    expect(
      high.groundElevationAt(id.point(100.5 / 256, 100.5 / 256)),
      greaterThanOrEqualTo(999.99),
    );
  });
  test('shadow profiles blend cascades, track angular size and reset expensive effects', () {
    final light = scene.DirectionalLight();
    for (final quality in [
      RenderQuality.high,
      RenderQuality.performance,
      RenderQuality.balanced,
    ]) {
      final state = SimulationState(
        timestamp: DateTime.utc(2026, 6, 21, 19),
        renderQuality: quality,
      );
      configureTerrainShadows(light, state);
      expect(
        light.shadowCascadeCount,
        quality == RenderQuality.performance ? 2 : 4,
      );
      expect(light.cascadeOverlap, greaterThan(0));
      expect(light.firstCascadeFarBound, 300);
      expect(light.shadowCascadeSplitLambda, 0.8);
      expect(light.angularRadius, closeTo(state.sky.sun.angularRadius, 1e-12));
      expect(
        light.shadowFilter,
        quality == RenderQuality.high
            ? scene.DirectionalShadowFilter.pcss
            : scene.DirectionalShadowFilter.bilinearPcf,
      );
      expect(light.contactShadows, quality == RenderQuality.high);
      final camera = scene.PerspectiveCamera(fovNear: 0.5, fovFar: 50000);
      final cascades = light.computeCascades(camera, 1.5);
      expect(cascades, hasLength(light.shadowCascadeCount));
      configureTerrainShadows(light, state.copyWith(terrainRenderKm: 2));
      expect(light.shadowMaxDistance, 2000);
      configureTerrainShadows(light, state.copyWith(weather: Weather.fog));
      expect(light.castsShadow, isFalse);
      expect(light.contactShadows, isFalse);
      configureTerrainShadows(light, state.copyWith(relitImagery: false));
      expect(light.castsShadow, isFalse);
      expect(light.contactShadows, isFalse);
      final night = state.copyWith(timestamp: DateTime.utc(2026, 6, 22, 7));
      configureTerrainShadows(light, night);
      expect(light.angularRadius, closeTo(night.sky.moon.angularRadius, 1e-12));
    }
  });
}
