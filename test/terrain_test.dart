import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/terrain/terrain_patch.dart';

import 'terrain_fixture.dart';

void main() {
  test('walking ground follows uphill/downhill and never samples below the visible mesh', () {
    final id = TileId.at(const LatLng(37.744, -119.59));
    final origin = id.point(0.5, 0.5);
    // Coarse vertices are all 1000 m, but the source has a valley between them.
    final field = HeightField(
      Float32List.fromList([
        for (var y = 0; y < 5; y++) ...[1000, 0, 1000, 1000, 1000],
      ]),
      5,
    );
    final patch = buildTerrainPatch(field, id, origin, 2);
    final valley = id.point(0.3, 0.5);
    expect(field.sample(0.3, 0.5), closeTo(0, 1e-5));
    expect(patch.groundElevationAt(valley), greaterThan(990));
    // A source peak omitted by coarse geometry must also remain safe.
    final peak = HeightField(
      Float32List.fromList([
        for (var y = 0; y < 5; y++) ...[0, 1000, 0, 0, 0],
      ]),
      5,
    );
    final peakPatch = buildTerrainPatch(peak, id, origin, 2);
    expect(peakPatch.groundElevationAt(valley), closeTo(1000, 1e-4));
    final ramp = HeightField(
      Float32List.fromList([
        for (var y = 0; y < 5; y++) ...[0, 250, 500, 750, 1000],
      ]),
      5,
    );
    final slope = buildTerrainPatch(ramp, id, origin, 2);
    final low = slope.groundElevationAt(id.point(0.2, 0.5))!;
    final high = slope.groundElevationAt(id.point(0.8, 0.5))!;
    expect(high, greaterThan(low + 500));
    expect(slope.groundElevationAt(id.point(-0.1, 0.5)), isNull);
  });
  test('walking ground covers inserted vertices, cell boundaries and polar/dateline tiles', () {
    for (final location in [
      const LatLng(37.744, -119.59),
      const LatLng(85, 179.9999),
      const LatLng(-85, -179.9999),
    ]) {
      final id = TileId.at(location);
      final patch = buildTerrainPatch(
        HeightField(
          Float32List(256 * 256)..fillRange(0, 256 * 256, 1234.5),
          256,
        ),
        id,
        location,
        128,
      );
      expect(patch.groundElevationAt(location), closeTo(1234.5, 0.01));
      for (final u in [0.0, 0.1, 0.5, 0.99, 1.0]) {
        for (final v in [0.0, 0.1, 0.5, 0.99, 1.0]) {
          expect(
            patch.groundElevationAt(id.point(u, v)),
            closeTo(1234.5, 0.01),
            reason: '$location, $u, $v, uv=${id.uv(id.point(u, v))}',
          );
        }
      }
    }
  });
  test('Terrarium includes negative and fractional elevations', () {
    expect(terrariumHeight(128, 0, 0), 0);
    expect(terrariumHeight(127, 255, 128), -0.5);
    expect(terrariumHeight(137, 219, 68), 2523.265625);
    final field = decodeTerrarium(terrainFixture());
    expect(field.heights.length, 65536);
    expect(field.sample(0.3, 0.7), 1234.5);
  });
  test('bilinear sampling uses pixel centers and clamps boundaries', () {
    final field = HeightField(Float32List.fromList([0, 10, 20, 30]), 2);
    expect(field.sample(0.5, 0.5), 15);
    expect(field.sample(0, 0), 0);
    expect(field.sample(1, 1), 30);
  });
  test('invalid, oversize, void and deceptive PNG headers are rejected', () {
    expect(() => decodeTerrarium(Uint8List(100)), throwsFormatException);
    expect(
      () => decodeTerrarium(Uint8List(1024 * 1024 + 1)),
      throwsFormatException,
    );
    expect(
      () => decodeTerrarium(terrainFixture(height: -32768)),
      throwsFormatException,
    );
    final malicious = terrainFixture();
    ByteData.sublistView(malicious).setUint32(16, 999999);
    expect(() => decodeTerrarium(malicious), throwsFormatException);
  });
  test(
    'camera-relative mesh includes a ground vertex and unit upward normals',
    () {
      const origin = LatLng(37.744, -119.59);
      final id = TileId.at(origin);
      final field = decodeTerrarium(terrainFixture());
      final patch = buildTerrainPatch(field, id, origin, 16);
      var cameraVertex = false;
      for (var i = 0; i < patch.positions.length; i += 3) {
        if (patch.positions[i].abs() < 0.01 &&
            patch.positions[i + 2].abs() < 0.01 &&
            (patch.positions[i + 1] - 1234.5).abs() < 0.01) {
          cameraVertex = true;
        }
        final nx = patch.normals[i],
            ny = patch.normals[i + 1],
            nz = patch.normals[i + 2];
        expect(nx * nx + ny * ny + nz * nz, closeTo(1, 1e-5));
      }
      expect(cameraVertex, isTrue);
      expect(patch.normals[1], greaterThan(0.99));
      expect(patch.uvs.length, patch.positions.length ~/ 3 * 2);
      expect(
        patch.indices.every((i) => i >= 0 && i < patch.positions.length ~/ 3),
        isTrue,
      );
    },
  );
  test(
    'neighboring LOD tiles share boundary coordinates at equal elevations',
    () {
      const origin = LatLng(37.744, -119.59);
      final id = TileId.at(origin);
      final next = TileId(id.z, id.x + 1, id.y);
      final field = decodeTerrarium(terrainFixture());
      final a = buildTerrainPatch(field, id, origin, 8);
      final b = buildTerrainPatch(field, next, origin, 4);
      // Compare matching UV boundary vertices; skirts are below the same edge.
      for (var i = 0; i < b.uvs.length; i += 2) {
        if (b.uvs[i] != 0) continue;
        final v = b.uvs[i + 1];
        final matches = <int>[];
        for (var j = 0; j < a.uvs.length; j += 2) {
          if (a.uvs[j] == 1 && a.uvs[j + 1] == v) matches.add(j ~/ 2);
        }
        expect(matches, isNotEmpty);
        expect(
          matches.any(
            (j) =>
                (a.positions[j * 3] - b.positions[i ~/ 2 * 3]).abs() < 0.001 &&
                (a.positions[j * 3 + 1] - b.positions[i ~/ 2 * 3 + 1]).abs() <
                    0.001 &&
                (a.positions[j * 3 + 2] - b.positions[i ~/ 2 * 3 + 2]).abs() <
                    0.001,
          ),
          isTrue,
        );
      }
    },
  );
}
