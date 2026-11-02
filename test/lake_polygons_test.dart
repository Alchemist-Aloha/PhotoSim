import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/terrain/terrain_patch.dart';
import 'package:photosim/data/terrain/terrain_sources.dart';
import 'package:photosim/data/water/lake_polygons.dart';
import 'package:photosim/data/water/lake_repository.dart';
import 'package:photosim/data/water/lake_shore.dart';
import 'package:photosim/data/water/water_patch.dart';
import 'package:photosim/data/water/water_repository.dart';

import 'water_fixture.dart';

void main() {
  final id = TileId(10, 511, 511);
  final square = [
    [0.1, 0.1],
    [0.9, 0.1],
    [0.9, 0.9],
    [0.1, 0.9],
    [0.1, 0.1],
  ];
  HeightField field(double h) =>
      HeightField(Float32List(65536)..fillRange(0, 65536, h), 256);
  Float32List dry() => Float32List(65536)..fillRange(0, 65536, double.nan);

  test('validated identified polygon levels preserve negative lakes and multipolygons', () {
    final bytes = lakeFixture(id, [square], height: -420);
    final lakes = decodeLakePolygons(bytes);
    expect(lakes.single.id, 7);
    expect(lakeLevels(lakes, id, 256)[128 * 256 + 128], -420);
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final feature = (json['features'] as List).single as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    geometry['type'] = 'MultiPolygon';
    geometry['coordinates'] = [
      geometry['coordinates'],
      geometry['coordinates'],
    ];
    expect(
      decodeLakePolygons(Uint8List.fromList(utf8.encode(jsonEncode(json)))),
      hasLength(2),
    );
    json['exceededTransferLimit'] = true;
    expect(
      () =>
          decodeLakePolygons(Uint8List.fromList(utf8.encode(jsonEncode(json)))),
      throwsFormatException,
    );
    expect(
      () => decodeLakePolygons(Uint8List.fromList(utf8.encode('{"error":{}}'))),
      throwsFormatException,
    );
    expect(
      () => decodeLakePolygons(lakeFixture(id, [square.take(4).toList()])),
      throwsFormatException,
    );
  });

  test(
    'curved concave polygon and island retain consistent vector coverage',
    () {
      final lakes = decodeLakePolygons(
        lakeFixture(id, [
          [
            [0.1, 0.1],
            [0.9, 0.1],
            [0.9, 0.9],
            [0.5, 0.9],
            [0.5, 0.5],
            [0.1, 0.5],
            [0.1, 0.1],
          ],
          [
            [0.2, 0.2],
            [0.3, 0.2],
            [0.3, 0.3],
            [0.2, 0.3],
            [0.2, 0.2],
          ],
        ]),
      );
      var area = 0.0;
      lakeSurfaceQuads(lakes.single, id, (p) {
        area += ((p[1].x - p[0].x) + (p[3].x - p[2].x)) / 2 * (p[2].y - p[0].y);
        final x = p.map((v) => v.x).reduce((a, b) => a + b) / 4;
        final y = p.map((v) => v.y).reduce((a, b) => a + b) / 4;
        expect(x > 0.201 && x < 0.299 && y > 0.201 && y < 0.299, isFalse);
      });
      final rings = lakeTileRings(lakes.single, id);
      double ringArea(List<math.Point<double>> ring) {
        var sum = 0.0;
        for (var i = 1; i < ring.length; i++) {
          sum += ring[i - 1].x * ring[i].y - ring[i].x * ring[i - 1].y;
        }
        return sum.abs() / 2;
      }

      expect(
        area,
        closeTo(ringArea(rings.first) - ringArea(rings.last), 1e-10),
      );
      expect(area, closeTo(0.47, 1e-6));
      final levels = lakeLevels(lakes, id, 256);
      expect(levels[64 * 256 + 64].isNaN, isTrue);
      expect(levels[180 * 256 + 64].isNaN, isTrue);
    },
  );

  test(
    'bounded quadratic corners share exactly one contour across tiles and LODs',
    () {
      final tile = TileId(13, 4092, 4092);
      final lake = decodeLakePolygons(lakeFixture(tile, [square])).single;
      final curve = lakeTileRings(lake, tile).single;
      final corner = curve.where((p) => p.x < 0.11 && p.y < 0.11).toList();
      expect(corner.length, greaterThan(3));
      expect(curve.first, curve.last);
      final trim = corner.first.y - 0.1;
      final meters =
          40075016.68557849 /
          (1 << tile.z) *
          math.cos(tile.point(0.1, 0.1).latitude * math.pi / 180);
      expect(trim * meters, closeTo(10, 1e-6));
      for (final p in corner) {
        final x = (p.x - 0.1).clamp(0.0, 1.0), y = (p.y - 0.1).clamp(0.0, 1.0);
        expect(math.sqrt(x / trim) + math.sqrt(y / trim), closeTo(1, 0.0001));
      }
      for (final neighbor in [
        TileId(tile.z, tile.x + 1, tile.y),
        TileId(12, tile.x ~/ 2, tile.y ~/ 2),
      ]) {
        final other = lakeTileRings(lake, neighbor).single;
        expect(other.length, curve.length);
        for (var i = 0; i < curve.length; i++) {
          expect(
            (other[i].x + neighbor.x) / (1 << neighbor.z),
            closeTo((curve[i].x + tile.x) / (1 << tile.z), 1e-14),
          );
          expect(
            (other[i].y + neighbor.y) / (1 << neighbor.z),
            closeTo((curve[i].y + tile.y) / (1 << tile.z), 1e-14),
          );
        }
      }
      final shore = <List<math.Point<double>>>[];
      lakeShoreQuads(lake, tile, shore.add);
      for (var i = 0; i < shore.length; i++) {
        final next = shore[(i + 1) % shore.length];
        expect(shore[i][2].distanceTo(next[0]), lessThan(1e-10));
        expect(shore[i][3].distanceTo(next[1]), lessThan(1e-10));
      }
      expect(lake.rings.single, hasLength(5));
    },
  );

  test('short edges, duplicate points, and either winding keep finite closed curves', () {
    final tiny = [
      [0.5, 0.5],
      [0.5004, 0.5],
      [0.5004, 0.5],
      [0.5004, 0.5004],
      [0.5, 0.5004],
      [0.5, 0.5],
    ];
    for (final ring in [tiny, tiny.reversed.toList()]) {
      final curve = lakeTileRings(
        decodeLakePolygons(lakeFixture(id, [ring])).single,
        id,
      ).single;
      expect(curve.length, greaterThan(5));
      expect(curve.first, curve.last);
      for (final p in curve) {
        expect(p.x.isFinite && p.y.isFinite, isTrue);
        expect(p.x, inInclusiveRange(0.5 - 1e-10, 0.5004 + 1e-10));
        expect(p.y, inInclusiveRange(0.5 - 1e-10, 0.5004 + 1e-10));
      }
    }
  });

  test('same lake spans atlas boundaries without artificial shores or DEM rejection', () {
    final lakes = decodeLakePolygons(
      lakeFixture(id, [
        [
          [-1.0, -1.0],
          [3.0, -1.0],
          [3.0, 2.0],
          [-1.0, 2.0],
          [-1.0, -1.0],
        ],
      ], height: 73),
    );
    for (final tile in [id, TileId(id.z, id.x + 1, id.y)]) {
      final atlas = WaterAtlas(tile, dry(), lakes: lakes);
      final original = buildTerrainPatch(
        field(75),
        tile,
        id.point(0.5, 0.5),
        8,
      );
      final patch = buildWaterPatch(atlas, original, tile, id.point(0.5, 0.5));
      expect(patch.surface.indices, isNotEmpty);
      expect(patch.outline.indices, isEmpty);
      expect(patch.terrain.field.sample(0.5, 0.5), closeTo(72.85, 0.001));
      expect(lakeLevels(lakes, tile, 256).every((v) => v == 73), isTrue);
      var shoreQuads = 0;
      lakeShoreQuads(lakes.single, tile, (_) => shoreQuads++);
      expect(shoreQuads, 0);
    }
  });

  test('Rochester HydroLAKES shoreline covers Lake Ontario but not inland Rochester', () async {
    // Real HydroLAKES geometry clipped only to the regression region; see fixtures/README.md.
    final lakes = decodeLakePolygons(
      await File('test/fixtures/lake_ontario_rochester.geojson').readAsBytes(),
    );
    expect(lakes.single.id, 7);
    expect(lakes.single.height, 73);
    for (final (location, wet) in [
      (const LatLng(43.30, -77.60), true),
      (const LatLng(43.20, -77.60), false),
    ]) {
      final tile = TileId.at(location);
      final uv = tile.uv(location);
      final levels = lakeLevels(lakes, tile, 256);
      expect(
        levels[(uv.y * 256).floor() * 256 + (uv.x * 256).floor()].isFinite,
        wet,
      );
      if (wet) {
        final patch = buildWaterPatch(
          WaterAtlas(tile, dry(), lakes: lakes),
          buildTerrainPatch(field(75), tile, location, 8),
          tile,
          location,
        );
        expect(patch.surface.indices, isNotEmpty);
        expect(patch.terrain.field.sample(uv.x, uv.y), closeTo(72.85, 0.001));
      }
    }
  });

  test('shoreline stays above interpolated terrain at every mesh detail', () {
    final tile = TileId(13, 4092, 4092);
    final origin = tile.point(0.5, 0.5);
    final lakes = decodeLakePolygons(
      lakeFixture(tile, [
        [
          [0.1, 0.1],
          [0.9, 0.1],
          [0.1, 0.9],
          [0.1, 0.1],
        ],
      ]),
    );
    for (final resolution in [8, 32, 128]) {
      final original = buildTerrainPatch(field(101), tile, origin, resolution);
      final patch = buildWaterPatch(
        WaterAtlas(tile, dry(), lakes: lakes),
        original,
        tile,
        origin,
      );
      for (var i = 1; i < 40; i++) {
        final u = 0.1 + 0.8 * i / 40;
        final position = tile.point(u, 1 - u - 0.00001);
        expect(
          patch.terrain.groundElevationAt(position),
          lessThan(100.04),
          reason:
              'Terrain must not turn the diagonal polygon shore into mesh-sized steps ($resolution, $i)',
        );
      }
      expect(patch.terrain.field.sample(0.95, 0.95), 101);
      expect(original.field.sample(0.5, 0.5), 101);
    }
  });

  test(
    'shore clearance agrees across tile edges without expanding water coverage',
    () {
      final tile = TileId(13, 4092, 4092);
      final neighbor = TileId(tile.z, tile.x + 1, tile.y);
      final origin = tile.point(0.5, 0.5);
      final lakes = decodeLakePolygons(
        lakeFixture(tile, [
          [
            [0.8, 0.2],
            [0.99, 0.2],
            [0.99, 0.8],
            [0.8, 0.8],
            [0.8, 0.2],
          ],
        ]),
      );
      WaterPatch build(TileId id, double height) => buildWaterPatch(
        WaterAtlas(id, dry(), lakes: lakes),
        buildTerrainPatch(field(height), id, origin, 8),
        id,
        origin,
      );
      final a = build(tile, 101), b = build(neighbor, 101);
      expect(b.surface.indices, isEmpty);
      expect(b.outline.indices, isEmpty);
      expect(
        b.terrain.field.sample(0, 0.5),
        closeTo(a.terrain.field.sample(1, 0.5), 0.001),
      );
      expect(b.terrain.field.sample(0.5, 0.5), 101);
      expect(build(tile, 200).terrain.field.sample(0.9, 0.5), 200);
    },
  );

  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('photosim-lakes-'),
  );
  tearDown(() => directory.delete(recursive: true));

  test(
    'full lake queries deduplicate, validate cache, and work offline',
    () async {
      final bytes = lakeFixture(id, [square]);
      var calls = 0;
      final repository = LakeRepository(
        client: MockClient((request) async {
          calls++;
          expect(
            request.url.queryParameters['outFields'],
            'hylak_id,lake_name,elevation',
          );
          expect(
            request.url.queryParameters.containsKey('maxAllowableOffset'),
            isFalse,
          );
          expect(request.url.queryParameters['outSR'], '4326');
          return http.Response.bytes(bytes, 200);
        }),
        directory: directory,
      );
      await repository.cache.write(id, Uint8List.fromList([1, 2, 3]));
      final abort = Completer<void>().future;
      final results = await Future.wait([
        repository.load(id, abort: abort),
        repository.load(id, abort: abort),
      ]);
      expect(calls, 1);
      expect(results.every((v) => v.single.id == 7), isTrue);
      final offline = LakeRepository(
        client: MockClient((_) async => throw StateError('network')),
        directory: directory,
      );
      expect(
        (await offline.load(id, abort: Completer<void>().future)).single.height,
        100,
      );
      expect(await repository.cache.read(id), bytes);
    },
  );

  test('polygon lake coverage survives missing MODIS pixels and mask service failure', () async {
    for (final maskFailure in [false, true]) {
      final client = MockClient((request) async {
        if (request.url.host == 'data-gis.unep-wcmc.org') {
          return http.Response.bytes(lakeFixture(id, [square]), 200);
        }
        if (maskFailure) return http.Response('unavailable', 404);
        return http.Response.bytes(waterFixture(wet: (_, _) => false), 200);
      });
      final source = WaterRepository(
        client: client,
        terrain: TerrainSources(client: client, directory: directory),
        directory: directory,
      );
      final original = buildTerrainPatch(field(101), id, id.point(0.5, 0.5), 8);
      final patch = await source.load(
        id,
        original,
        id.point(0.5, 0.5),
        abort: Completer<void>().future,
      );
      expect(patch.surface.indices, isNotEmpty);
      expect(patch.terrain.field.sample(0.5, 0.5), closeTo(99.85, 0.001));
      // Ensure the second case actually exercises a service failure rather than cached masks.
      await source.cache.remove(id);
    }
  });

  test(
    'polygon surface meshes are clipped even for remote rings and islands',
    () {
      final lake = decodeLakePolygons(lakeFixture(id, [square])).single;
      lakeSurfaceQuads(lake, id, (p) {
        expect(
          p.every((v) => v.x >= 0 && v.x <= 1 && v.y >= 0 && v.y <= 1),
          isTrue,
        );
        final area = (p[1].x - p[0].x) * (p[2].y - p[0].y);
        expect(area, greaterThanOrEqualTo(0));
        expect(p[2].distanceTo(p[0]), lessThan(math.sqrt(2)));
      });
    },
  );
}
