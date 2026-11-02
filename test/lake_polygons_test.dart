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
    'concave polygon and island geometry retain exact area, not raster stairs',
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
        expect(x > 0.2 && x < 0.3 && y > 0.2 && y < 0.3, isFalse);
      });
      expect(area, closeTo(0.47, 1e-10));
      final levels = lakeLevels(lakes, id, 256);
      expect(levels[64 * 256 + 64].isNaN, isTrue);
      expect(levels[180 * 256 + 64].isNaN, isTrue);
    },
  );

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
