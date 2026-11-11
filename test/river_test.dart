import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/terrain/terrain_patch.dart';
import 'package:photosim/data/terrain/terrain_sources.dart';
import 'package:photosim/data/water/river_polygons.dart';
import 'package:photosim/data/water/lake_polygons.dart';
import 'package:photosim/data/water/river_repository.dart';
import 'package:photosim/data/water/water_patch.dart';
import 'package:photosim/data/water/water_repository.dart';

import 'water_fixture.dart';

void main() {
  final id = TileId(13, 4092, 4092), origin = id.point(0.5, 0.5);
  final bank = [
    [-0.2, 0.3],
    [1.2, 0.35],
    [1.2, 0.65],
    [-0.2, 0.7],
    [-0.2, 0.3],
  ];
  final island = [
    [0.4, 0.45],
    [0.6, 0.45],
    [0.6, 0.55],
    [0.4, 0.55],
    [0.4, 0.45],
  ];
  final dry = Float32List(65536)..fillRange(0, 65536, double.nan);
  TerrainPatch terrain() => buildTerrainPatch(
    HeightField(
      Float32List.fromList([
        for (var y = 0; y < 256; y++)
          for (var x = 0; x < 256; x++)
            100 + 40 * (x + 0.5) / 256 + 3 * math.sin(y / 10),
      ]),
      256,
    ),
    id,
    origin,
    16,
  );

  test(
    'only water class=river polygons are used, with closed island rings',
    () {
      final rivers = decodeRiverPolygons(riverFixture(id, [bank, island]), id);
      expect(rivers, hasLength(1));
      expect(rivers.single.rings, hasLength(2));
      expect(rivers.single.rings.every((r) => r.first == r.last), isTrue);
      for (final bytes in [
        riverFixture(id, [bank], classification: 'lake'),
        riverFixture(id, [bank], classification: 'ocean'),
        riverFixture(id, [bank], layer: 'waterway'),
        riverFixture(id, [bank], type: 2),
        riverFixture(id, []),
      ]) {
        expect(decodeRiverPolygons(bytes, id), isEmpty);
      }
    },
  );

  test(
    'malformed protobuf, tags, commands and oversized geometry are rejected',
    () {
      for (final bytes in [
        Uint8List.fromList([26, 255]),
        Uint8List.fromList([0]),
        Uint8List.fromList([31]),
        Uint8List.fromList(List.filled(10, 255)),
        riverFixture(id, [bank], tags: [0]),
        riverFixture(id, [bank], tags: [2, 0]),
        riverFixture(id, [bank], tags: [0, 2]),
        riverFixture(id, [bank], extent: 0),
        riverFixture(id, [], commands: [9, 0, 0, 10, 2, 2]),
        riverFixture(id, [], commands: [0]),
        riverFixture(id, [], commands: [15]),
        riverFixture(id, [], commands: [9, 0, 0, 11]),
        riverFixture(id, [], commands: [9, 0, 0, 10, 2, 2, 15]),
        riverFixture(id, [], commands: [9, 0, 0, 18, 2000000, 0, 0, 2, 15]),
      ]) {
        expect(() => decodeRiverPolygons(bytes, id), throwsFormatException);
      }
      final valid = riverFixture(id, [bank]);
      expect(
        () => decodeRiverPolygons(valid.sublist(0, valid.length - 1), id),
        throwsFormatException,
      );
    },
  );

  test(
    'tile-cut shared edges stay straight without invented shore outlines',
    () {
      final bytes = riverFixture(id, [
        [
          [0.0, 0.25],
          [1.0, 0.25],
          [1.0, 0.75],
          [0.0, 0.75],
          [0.0, 0.25],
        ],
      ]);
      final river = decodeRiverPolygons(bytes, id).single;
      final rings = lakeTileRings(river, id);
      expect(rings.single, hasLength(5));
      for (final p in rings.single) {
        expect(p.x == 0 || (p.x - 1).abs() < 1e-9, isTrue);
      }
    },
  );

  test('river mesh follows terrain triangles, slopes, clips banks and preserves islands without carving', () {
    final original = terrain();
    final result = buildWaterPatch(
      WaterAtlas(
        id,
        dry,
        rivers: decodeRiverPolygons(riverFixture(id, [bank, island]), id),
      ),
      original,
      id,
      origin,
    );
    expect(result.terrain, same(original));
    expect(result.adjustedTerrain, isFalse);
    expect(result.surface.indices, isNotEmpty);
    expect(result.outline.indices, isEmpty);
    final mesh = result.surface;
    double cross(math.Point<double> a, math.Point<double> b) =>
        a.x * b.y - a.y * b.x;
    double terrainY(double u, double v) {
      final x = (original.us.indexWhere((s) => s >= u) - 1).clamp(
        0,
        original.us.length - 2,
      );
      final y = (original.vs.indexWhere((s) => s >= v) - 1).clamp(
        0,
        original.vs.length - 2,
      );
      final start = (y * (original.us.length - 1) + x) * 6;
      for (var t = start; t < start + 6; t += 3) {
        final indices = original.indices.sublist(t, t + 3);
        final p = [
          for (final i in indices)
            math.Point(original.uvs[i * 2], original.uvs[i * 2 + 1]),
        ];
        final ab = p[1] - p[0], ac = p[2] - p[0], hit = math.Point(u, v) - p[0];
        final b = cross(hit, ac) / cross(ab, ac),
            c = cross(ab, hit) / cross(ab, ac);
        if (b >= -1e-5 && c >= -1e-5 && b + c <= 1.00001) {
          return original.positions[indices[0] * 3 + 1] * (1 - b - c) +
              original.positions[indices[1] * 3 + 1] * b +
              original.positions[indices[2] * 3 + 1] * c;
        }
      }
      throw StateError('Missing terrain triangle');
    }

    var minHeight = double.infinity, maxHeight = -double.infinity;
    for (var i = 0; i < mesh.indices.length; i += 3) {
      final indices = mesh.indices.sublist(i, i + 3);
      final u = indices.map((j) => mesh.uvs[j * 2]).reduce((a, b) => a + b) / 3;
      final v =
          indices.map((j) => mesh.uvs[j * 2 + 1]).reduce((a, b) => a + b) / 3;
      final height =
          indices
              .map((j) => mesh.positions[j * 3 + 1])
              .reduce((a, b) => a + b) /
          3;
      expect(u, inInclusiveRange(0, 1));
      expect(v, inInclusiveRange(0.299, 0.701));
      expect(u > 0.401 && u < 0.599 && v > 0.451 && v < 0.549, isFalse);
      expect(height - terrainY(u, v), closeTo(0.08, 0.0001));
      minHeight = math.min(minHeight, height);
      maxHeight = math.max(maxHeight, height);
    }
    expect(maxHeight - minHeight, greaterThan(30));
    expect(mesh.positions.every((v) => v.isFinite), isTrue);
  });

  test(
    'real OpenFreeMap Anacostia tile renders over actual DC terrain',
    () async {
      final rivers = decodeRiverPolygons(
        await File('test/fixtures/anacostia_water.pbf').readAsBytes(),
        TileId(10, 293, 391),
      );
      expect(rivers.any((river) => river.id == 518587842), isTrue);
      expect(rivers.any((river) => river.id == 622041512), isTrue);
      final id = TileId(13, 2344, 3134), origin = id.point(0.5, 0.5);
      final terrain = buildTerrainPatch(
        decodeTerrarium(
          await File('test/fixtures/anacostia_terrain.png').readAsBytes(),
        ),
        id,
        origin,
        32,
      );
      final water = buildWaterPatch(
        WaterAtlas(TileId(10, 293, 391), dry, rivers: rivers),
        terrain,
        id,
        origin,
      );
      expect(water.surface.indices, isNotEmpty);
      expect(water.surface.positions.every((v) => v.isFinite), isTrue);
      expect(water.outline.indices, isEmpty);
    },
  );

  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('photosim-rivers-'),
  );
  tearDown(() => directory.delete(recursive: true));

  test(
    'TileJSON discovery, corrupt cache recovery and offline tile reuse',
    () async {
      final bytes = riverFixture(id, [bank]);
      final requests = <Uri>[];
      final repository = RiverRepository(
        client: MockClient((request) async {
          requests.add(request.url);
          expect(request.url.host, 'tiles.openfreemap.org');
          expect(request.headers['user-agent'], contains('PhotoSim/'));
          return riverResponse(request.url, bytes);
        }),
        directory: directory,
      );
      await repository.cache.write(id, Uint8List.fromList([1, 2, 3]));
      expect(
        await repository.load(id, abort: Completer<void>().future),
        hasLength(1),
      );
      expect(requests.map((u) => u.path), [
        '/planet',
        '/planet/test/13/4092/4092.pbf',
      ]);
      final metadata = jsonDecode(
        await File('${directory.path}/$riverCacheKey/${id.key}.png.json')
            .readAsString(),
      ) as Map;
      expect(metadata['attribution'], riverAttribution);
      final offline = RiverRepository(
        client: MockClient((_) async => throw StateError('network')),
        directory: directory,
      );
      expect(
        await offline.load(id, abort: Completer<void>().future),
        hasLength(1),
      );
      final other = TileId(13, id.x + 1, id.y);
      final invalid = RiverRepository(
        client: MockClient(
          (request) async =>
              riverResponse(request.url, Uint8List.fromList([26, 255])),
        ),
        directory: directory,
      );
      await expectLater(
        invalid.load(other, abort: Completer<void>().future),
        throwsFormatException,
      );
      expect(await invalid.cache.read(other), isNull);
    },
  );

  test(
    'invalid TileJSON cannot redirect requests and can be retried',
    () async {
      for (final json in [
        '{}',
        '{"tiles":[]}',
        '{"tiles":["https://example.org/{z}/{x}/{y}.pbf"]}',
        '{"tiles":["http://tiles.openfreemap.org/{z}/{x}/{y}.pbf"]}',
        '{"tiles":["https://tiles.openfreemap.org/fixed.pbf"]}',
      ]) {
        var requests = 0;
        final repository = RiverRepository(
          client: MockClient((request) async {
            requests++;
            return http.Response(json, 200);
          }),
          directory: directory,
        );
        for (var i = 0; i < 2; i++) {
          await expectLater(
            repository.load(id, abort: Completer<void>().future),
            throwsFormatException,
          );
        }
        expect(requests, 2);
      }
    },
  );

  test(
    'river-only coverage survives lake/mask outages and shares atlas requests',
    () async {
      var riverRequests = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'tiles.openfreemap.org') {
          if (request.url.path == '/planet') {
            return http.Response(riverTileJson, 200);
          }
          riverRequests++;
          return http.Response.bytes(
            riverFixture(id, [bank], tile: riverTile(request.url)),
            200,
          );
        }
        return http.Response('unavailable', 404);
      });
      final source = WaterRepository(
        client: client,
        terrain: TerrainSources(client: client, directory: directory),
        directory: directory,
      );
      final abort = Completer<void>();
      final original = terrain();
      final results = await Future.wait([
        source.load(id, original, origin, abort: abort.future),
        source.load(id, original, origin, abort: abort.future),
      ]);
      expect(riverRequests, 1);
      expect(
        results.every(
          (r) => r.surface.indices.isNotEmpty && !r.riversUnavailable,
        ),
        isTrue,
      );
      abort.complete();
      await expectLater(
        source.load(id, original, origin, abort: abort.future),
        throwsA(isA<http.RequestAbortedException>()),
      );
    },
  );

  test('river outage is reported without discarding available lakes', () async {
    final client = MockClient(
      (request) async => request.url.host == 'data-gis.unep-wcmc.org'
          ? http.Response.bytes(lakeFixture(id, [bank]), 200)
          : http.Response('unavailable', 404),
    );
    final source = WaterRepository(
      client: client,
      terrain: TerrainSources(client: client, directory: directory),
      directory: directory,
    );
    final result = await source.load(
      id,
      terrain(),
      origin,
      abort: Completer<void>().future,
    );
    expect(result.riversUnavailable, isTrue);
    expect(result.surface.indices, isNotEmpty);
  });
}
