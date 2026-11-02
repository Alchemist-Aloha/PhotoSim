import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/terrain/terrain_patch.dart';
import 'package:photosim/data/terrain/terrain_sources.dart';
import 'package:photosim/data/water/water_patch.dart';
import 'package:photosim/data/water/water_repository.dart';

import 'terrain_fixture.dart';
import 'water_fixture.dart';

void main() {
  final atlasId = TileId(10, 511, 511);
  final id = TileId(13, 4092, 4092);
  final origin = id.point(0.5, 0.5);
  HeightField field(double height) =>
      HeightField(Float32List(256 * 256)..fillRange(0, 256 * 256, height), 256);
  TerrainPatch patch(double height) =>
      buildTerrainPatch(field(height), id, origin, 8);

  test('mask uses the published palette, preserves land and rejects service errors', () {
    final mask = decodeWaterMask(waterFixture());
    expect(mask[100 * 256 + 100], 1);
    expect(mask[10 * 256 + 10], 0);
    expect(
      decodeWaterMask(waterFixture(wet: (_, _) => false)).contains(1),
      isFalse,
    );
    expect(
      () => decodeWaterMask(
        Uint8List.fromList(utf8.encode('<ServiceException/>')),
      ),
      throwsFormatException,
    );
    expect(() => decodeWaterMask(terrainFixture()), throwsFormatException);
  });

  test(
    'disconnected lakes have separate flat levels, including below sea level',
    () {
      final mask = Uint8List(256 * 256), heights = Float32List(256 * 256);
      for (var y = 20; y < 40; y++) {
        for (var x = 20; x < 40; x++) {
          mask[y * 256 + x] = 1;
          heights[y * 256 + x] = -420;
        }
        for (var x = 60; x < 80; x++) {
          mask[y * 256 + x] = 1;
          heights[y * 256 + x] = 1820;
        }
      }
      final atlas = estimateWaterLevels(
        atlasId,
        mask,
        HeightField(heights, 256),
      );
      expect(atlas.level(30 / 256, 30 / 256), -420);
      expect(atlas.level(70 / 256, 30 / 256), 1820);
      expect(atlas.level(50 / 256, 30 / 256), isNull);
    },
  );

  test(
    'coastlines identify ocean without flattening below-sea-level lakes',
    () {
      expect(decodeOceanMask(coastFixture()).contains(1), isFalse);
      expect(
        decodeOceanMask(coastFixture(ocean: true)).every((v) => v == 1),
        isTrue,
      );
      expect(() => decodeOceanMask(waterFixture()), throwsFormatException);
      final mask = Uint8List(256 * 256)
        ..fillRange(0, 128 * 256, 2)
        ..fillRange(128 * 256, 256 * 256, 1);
      final atlas = estimateWaterLevels(atlasId, mask, field(-420));
      expect(atlas.level(0.5, 0.2), 0);
      expect(atlas.level(0.5, 0.8), -420);
    },
  );

  test('robust interior estimates ignore bad shoreline heights and isolated outliers', () {
    final mask = decodeWaterMask(waterFixture());
    final heights = field(100);
    for (var y = 80; y < 176; y++) {
      heights.heights[y * 256 + 80] = 800;
    }
    heights.heights[100 * 256 + 100] = 999;
    final atlas = estimateWaterLevels(atlasId, mask, heights);
    expect(atlas.level(0.5, 0.5), 100);
  });

  test('sloping water and narrow streams do not become flat reservoirs', () {
    final heights = Float32List(256 * 256);
    for (var y = 0; y < 256; y++) {
      for (var x = 0; x < 256; x++) {
        heights[y * 256 + x] = y.toDouble();
      }
    }
    final atlas = estimateWaterLevels(
      atlasId,
      decodeWaterMask(waterFixture()),
      HeightField(heights, 256),
    );
    expect(atlas.levels.any((value) => value.isFinite), isFalse);
    final narrow = decodeWaterMask(waterFixture(wet: (x, y) => x == 100));
    expect(
      estimateWaterLevels(
        atlasId,
        narrow,
        field(50),
      ).levels.any((value) => value.isFinite),
      isFalse,
    );
  });

  test('land holes remain dry; surfaces, outlines and normals follow the local Earth frame', () {
    final mask = decodeWaterMask(
      waterFixture(
        wet: (x, y) =>
            x >= 128 &&
            x < 144 &&
            y >= 128 &&
            y < 144 &&
            !(x >= 132 && x < 136 && y >= 132 && y < 136),
      ),
    );
    final atlas = estimateWaterLevels(atlasId, mask, field(20));
    final result = buildWaterPatch(atlas, patch(21), id, origin);
    expect(result.surface.indices, isNotEmpty);
    expect(result.outline.indices, isNotEmpty);
    for (var i = 0; i < result.surface.uvs.length; i += 8) {
      final u = (result.surface.uvs[i] + result.surface.uvs[i + 6]) / 2;
      final v = (result.surface.uvs[i + 1] + result.surface.uvs[i + 7]) / 2;
      expect(atlas.level(0.5 + u / 8, 0.5 + v / 8), 20);
    }
    final expected = LocalFrame(origin)
        .project(id.point(result.surface.uvs[0], result.surface.uvs[1]), 20.05);
    expect(result.surface.positions.take(3), [
      expected.x,
      expected.y,
      expected.z,
    ]);
    expect(result.surface.normals[1], closeTo(1, 0.001));
    expect(result.terrain.field.sample(0.1, 0.1), closeTo(19.85, 0.001));
    expect(result.terrain.field.sample(0.9, 0.9), 21);
    expect(patch(21).field.sample(0.1, 0.1), 21);
  });

  test('adjacent render tiles share one level and never outline their shared water edge', () {
    final atlas = estimateWaterLevels(
      atlasId,
      Uint8List(256 * 256)..fillRange(0, 256 * 256, 1),
      field(0),
    );
    final nextId = TileId(id.z, id.x + 1, id.y);
    final a = buildWaterPatch(atlas, patch(0), id, origin);
    final b = buildWaterPatch(
      atlas,
      buildTerrainPatch(field(0), nextId, origin, 8),
      nextId,
      origin,
    );
    expect(a.outline.indices, isEmpty);
    expect(b.outline.indices, isEmpty);
    for (var axis = 0; axis < 3; axis++) {
      expect(
        a.surface.positions[(31 * 4 + 1) * 3 + axis],
        closeTo(b.surface.positions[axis], 0.000001),
      );
    }
    expect(
      a.terrain.field.sample(0.5, 0.5),
      closeTo(b.terrain.field.sample(0.5, 0.5), 0.0001),
    );
  });

  test('coarse water masks never excavate hills and dry tiles leave geometry unchanged', () {
    final wet = estimateWaterLevels(
      atlasId,
      decodeWaterMask(waterFixture(wet: (_, _) => true)),
      field(0),
    );
    expect(
      buildWaterPatch(
        wet,
        patch(100),
        id,
        origin,
      ).terrain.field.sample(0.5, 0.5),
      100,
    );
    final original = patch(100);
    final dry = WaterAtlas(
      atlasId,
      Float32List(256 * 256)..fillRange(0, 256 * 256, double.nan),
    );
    expect(buildWaterPatch(dry, original, id, origin).terrain, same(original));
  });

  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('photosim-water-'),
  );
  tearDown(() => directory.delete(recursive: true));

  test('repository shares an atlas, caches original bytes with epoch/credit, and works offline', () async {
    final bytes = waterFixture(wet: (_, _) => true), requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'data-gis.unep-wcmc.org') {
        return http.Response('unavailable', 404);
      }
      if (request.url.queryParameters['LAYERS'] == oceanProvider.layer) {
        return http.Response.bytes(coastFixture(), 200);
      }
      if (request.url.host.contains('gibs')) {
        return http.Response.bytes(bytes, 200);
      }
      if (request.url.host.contains('mapterhorn')) {
        return http.Response('missing', 404);
      }
      return http.Response.bytes(terrainFixture(height: -50), 200);
    });
    WaterRepository repository(http.Client client) => WaterRepository(
      client: client,
      terrain: TerrainSources(client: client, directory: directory),
      directory: directory,
    );
    final source = repository(client), abort = Completer<void>();
    final results = await Future.wait([
      source.load(id, patch(-50), origin, abort: abort.future),
      source.load(id, patch(-50), origin, abort: abort.future),
    ]);
    expect(
      results.every((result) => result.surface.indices.isNotEmpty),
      isTrue,
    );
    final waterRequests = requests
        .where((uri) => uri.queryParameters['LAYERS'] == waterProvider.layer)
        .toList();
    expect(waterRequests, hasLength(1));
    expect(waterRequests.single.queryParameters['TIME'], '2015-01-01');
    expect(waterRequests.single.queryParameters['CRS'], 'EPSG:3857');
    final file = File('${directory.path}/$waterCacheKey/${atlasId.key}.png');
    expect(await file.readAsBytes(), bytes);
    final metadata =
        jsonDecode(await File('${file.path}.json').readAsString()) as Map;
    expect(metadata['attribution'], waterAttribution);
    expect(metadata['acquisitionTime'], '2015-01-01');
    final offline = MockClient((request) async {
      if (request.url.host == 'data-gis.unep-wcmc.org') {
        return http.Response('offline', 404);
      }
      if (request.url.host.contains('mapterhorn')) {
        return http.Response('offline primary', 404);
      }
      throw StateError('unexpected network: ${request.url}');
    });
    final restored = await repository(offline)
        .load(id, patch(-50), origin, abort: Completer<void>().future);
    expect(restored.surface.indices, isNotEmpty);
  });

  test('ocean-only atlases ignore bathymetry and skip DEM downloads', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'data-gis.unep-wcmc.org') {
        return http.Response('unavailable', 404);
      }
      if (request.url.queryParameters['LAYERS'] == oceanProvider.layer) {
        return http.Response.bytes(coastFixture(ocean: true), 200);
      }
      expect(request.url.queryParameters['LAYERS'], waterProvider.layer);
      return http.Response.bytes(waterFixture(wet: (_, _) => true), 200);
    });
    final source = WaterRepository(
      client: client,
      terrain: TerrainSources(client: client, directory: directory),
      directory: directory,
    );
    final result = await source.load(
      id,
      patch(-1000),
      origin,
      abort: Completer<void>().future,
    );
    expect(result.surface.indices, isNotEmpty);
    final point = LocalFrame(origin).project(id.point(0, 0), 0.05);
    expect(result.surface.positions.take(3), [point.x, point.y, point.z]);
    expect(await source.oceanCache.read(atlasId), isNotNull);
  });

  test(
    'empty masks skip DEM downloads and corrupt cached masks are replaced',
    () async {
      var demRequests = 0;
      final bytes = waterFixture(wet: (_, _) => false);
      final client = MockClient((request) async {
        if (request.url.host == 'data-gis.unep-wcmc.org') {
          return http.Response('unavailable', 404);
        }
        if (!request.url.host.contains('gibs')) demRequests++;
        return http.Response.bytes(bytes, 200);
      });
      final source = WaterRepository(
        client: client,
        terrain: TerrainSources(client: client, directory: directory),
        directory: directory,
      );
      await source.cache.write(atlasId, Uint8List.fromList([1, 2, 3]));
      final result = await source.load(
        id,
        patch(0),
        origin,
        abort: Completer<void>().future,
      );
      expect(result.surface.indices, isEmpty);
      expect(demRequests, 0);
      expect(await source.cache.read(atlasId), bytes);
    },
  );

  test(
    'aborted generations cannot publish a mask or poison the next generation',
    () async {
      final ready = Completer<void>(), response = Completer<void>();
      var count = 0;
      final client = MockClient((_) async {
        if (++count == 1) {
          ready.complete();
          await response.future;
        }
        return http.Response.bytes(waterFixture(wet: (_, _) => false), 200);
      });
      final source = WaterRepository(
        client: client,
        terrain: TerrainSources(client: client, directory: directory),
        directory: directory,
      );
      final abort = Completer<void>();
      final job = source.load(id, patch(0), origin, abort: abort.future);
      final assertion = expectLater(
        job,
        throwsA(isA<http.RequestAbortedException>()),
      );
      await ready.future;
      abort.complete();
      response.complete();
      await assertion;
      final result = await source.load(
        id,
        patch(0),
        origin,
        abort: Completer<void>().future,
      );
      expect(result.surface.indices, isEmpty);
    },
  );
}
