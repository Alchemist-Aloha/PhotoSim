import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/core/terrain_coverage.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/models/simulation_state.dart';

void main() {
  test(
    'defaults preserve the existing 3×3 region and near-first camera tile',
    () {
      final state = SimulationState();
      final center = TileId.at(state.location);
      final tiles = terrainCoverage(state);
      expect(tiles.first.key, center.key);
      expect(
        tiles.map((t) => t.key).toSet(),
        center.neighborhood().map((t) => t.key).toSet(),
      );
      expect(terrainCoverage(state.copyWith(terrainRings: 3)), hasLength(49));
    },
  );

  test(
    'forward coverage follows aim and optical FOV while retaining nearby tiles',
    () {
      final state = SimulationState(pitch: 0, azimuth: 0, terrainForwardKm: 30);
      bool covers(List<TileId> tiles, double azimuth, double distance) {
        final point = destination(state.location, azimuth, distance);
        return tiles.any((tile) {
          final uv = tile.uv(point);
          return uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1;
        });
      }

      final north = terrainCoverage(state);
      expect(covers(north, 0, 27000), isTrue);
      expect(covers(north, 25, 24000), isTrue);
      expect(covers(north, 180, 27000), isFalse);
      expect(north.any((tile) => tile.z < 13), isTrue);
      for (final nearby in TileId.at(state.location).neighborhood()) {
        expect(north.any((tile) => tile.key == nearby.key), isTrue);
      }
      final south = terrainCoverage(state.copyWith(azimuth: 180));
      expect(covers(south, 180, 27000), isTrue);
      expect(covers(south, 0, 27000), isFalse);
      final telephoto = terrainCoverage(state.copyWith(focalLength: 600));
      expect(covers(telephoto, 0, 27000), isTrue);
      expect(covers(telephoto, 25, 24000), isFalse);
      expect(telephoto.length, lessThan(north.length));
      expect(telephoto.every((tile) => tile.z == 13), isTrue);
      final wide = terrainCoverage(state.copyWith(focalLength: 8));
      expect(covers(wide, 55, 24000), isTrue);
      expect(covers(north, 55, 24000), isFalse);
      expect(
        terrainCoverage(state.copyWith(terrainRenderKm: 2)).map((t) => t.key),
        north.map((t) => t.key),
      );
    },
  );

  test('pitch and sensor changes affect the projected frustum envelope', () {
    final state = SimulationState(pitch: 0, terrainForwardKm: 30);
    final level = terrainCoverage(state).map((t) => t.key).toSet();
    final apsc = terrainCoverage(state.copyWith(sensor: Sensor.apsC))
        .map((t) => t.key)
        .toSet();
    final overhead = terrainCoverage(state.copyWith(pitch: 85));
    expect(apsc, isNot(level));
    final behind = destination(state.location, 180, 24000);
    expect(
      overhead.any((tile) {
        final uv = tile.uv(behind);
        return uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1;
      }),
      isTrue,
    );
  });

  test('coverage is bounded, unique and non-overlapping across poles/dateline/FOVs', () {
    for (final latitude in [-85.0, 0.0, 37.0, 85.0]) {
      final telephoto = terrainCoverage(
        SimulationState(
          latitude: latitude,
          focalLength: 600,
          terrainRings: 3,
          terrainForwardKm: 40,
        ),
      );
      expect(telephoto.length, lessThanOrEqualTo(terrainTileBudget));
      for (final longitude in [-179.99, 0.0, 179.99]) {
        for (final azimuth in [0.0, 90.0, 180.0, 270.0]) {
          for (final pitch in [0.0, 85.0]) {
            final state = SimulationState(
              latitude: latitude,
              longitude: longitude,
              azimuth: azimuth,
              pitch: pitch,
              focalLength: 8,
              terrainRings: 3,
              terrainForwardKm: 40,
            );
            final tiles = terrainCoverage(state);
            expect(tiles.length, lessThanOrEqualTo(terrainTileBudget));
            expect(tiles.map((tile) => tile.key).toSet().length, tiles.length);
            final keys = tiles.map((tile) => tile.key).toSet();
            for (final tile in tiles) {
              for (var z = tile.z - 1; z >= 0; z--) {
                final span = 1 << (tile.z - z);
                expect(
                  keys,
                  isNot(contains('$z-${tile.x ~/ span}-${tile.y ~/ span}')),
                );
              }
            }
          }
        }
      }
    }
  });

  test('render cutoff keeps the camera tile and excludes distant tiles', () {
    final state = SimulationState(terrainForwardKm: 30);
    final tiles = terrainCoverage(state);
    expect(terrainDistance(tiles.first, state.location), closeTo(0, 0.01));
    expect(
      tiles.any((tile) => terrainDistance(tile, state.location) > 20000),
      isTrue,
    );
    expect(
      tiles
          .where((tile) => terrainDistance(tile, state.location) <= 2000)
          .length,
      lessThan(tiles.length),
    );
  });

  test(
    'terrain settings validate limits and copy without losing ground/time',
    () {
      final state = SimulationState(groundElevation: 1200);
      final changed = state.copyWith(
        terrainRings: 3,
        terrainForwardKm: 40,
        terrainRenderKm: 2,
      );
      expect(changed.groundElevation, 1200);
      expect(changed.timestamp, state.timestamp);
      for (final action in <void Function()>[
        () => state.copyWith(terrainRings: 0),
        () => state.copyWith(terrainRings: 4),
        () => state.copyWith(terrainForwardKm: -1),
        () => state.copyWith(terrainForwardKm: double.nan),
        () => state.copyWith(terrainForwardKm: 41),
        () => state.copyWith(terrainRenderKm: 1),
        () => state.copyWith(terrainRenderKm: double.infinity),
      ]) {
        expect(action, throwsArgumentError);
      }
    },
  );
}
