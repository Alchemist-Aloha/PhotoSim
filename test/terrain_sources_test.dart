import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/terrain/terrain_patch.dart';
import 'package:photosim/data/terrain/terrain_provider.dart';
import 'package:photosim/data/terrain/terrain_sources.dart';

import 'terrain_fixture.dart';

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'photosim-terrain-sources-',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));
  final id = TileId(13, 2, 2);
  final origin = id.point(0.5, 0.5);

  test(
    'lossless WebP retains fractional, negative and north-up Terrarium samples',
    () {
      final field = decodeMapterhorn(terrainQuadrantFixture());
      expect(field.size, 512);
      expect(field.sample(0.25, 0.25), 1000.25);
      expect(field.sample(0.75, 0.25), 2000.5);
      expect(field.sample(0.25, 0.75), -5.75);
      expect(field.sample(0.75, 0.75), 4000.75);
      expect(decodeMapterhorn(terrainWebpFixture()).sample(0.5, 0.5), 1234.5);
    },
  );

  test('invalid, lossy, oversize, transparent, void and deceptive WebP are rejected', () {
    for (final bytes in [
      Uint8List(100),
      Uint8List(1024 * 1024 + 1),
      terrainVoidWebpFixture(),
      terrainTransparentWebpFixture(),
      terrainWebpFixture().sublist(0, 40),
    ]) {
      expect(() => decodeMapterhorn(bytes), throwsFormatException);
    }
    final lossy = terrainWebpFixture()..[15] = 0x20;
    expect(() => decodeMapterhorn(lossy), throwsFormatException);
    final huge = terrainWebpFixture();
    ByteData.sublistView(huge)
        .setUint32(21, 16383 | (16383 << 14), Endian.little);
    expect(() => decodeMapterhorn(huge), throwsFormatException);
  });

  test(
    'parent crop maps all four child tiles exactly without changing UV bounds',
    () {
      final parent = TileId(12, 1, 1);
      for (final entry in [
        (0, 0, 1000.25),
        (1, 0, 2000.5),
        (0, 1, -5.75),
        (1, 1, 4000.75),
      ]) {
        final child = TileId(13, 2 + entry.$1, 2 + entry.$2);
        final patch = decodeAndBuildTerrain(
          TerrainBuildRequest(
            terrainQuadrantFixture(),
            child,
            child.point(0.5, 0.5),
            8,
            provider: TerrainProvider.mapterhorn,
            rasterId: parent,
          ),
        );
        expect(patch.field.size, 256);
        expect(patch.field.sample(0, 0), entry.$3);
        expect(patch.field.sample(1, 1), entry.$3);
        expect(patch.uvs.every((v) => v >= 0 && v <= 1), isTrue);
      }
      expect(
        () => decodeAndBuildTerrain(
          TerrainBuildRequest(
            terrainWebpFixture(),
            id,
            origin,
            8,
            provider: TerrainProvider.mapterhorn,
            rasterId: TileId(12, 9, 9),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test('preferred account-free source caches independently and records actual provenance', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      expect(request.headers['user-agent'], contains('PhotoSim'));
      return http.Response.bytes(terrainWebpFixture(), 200);
    });
    addTearDown(client.close);
    final sources = TerrainSources(client: client, directory: directory);
    final abort = Completer<void>().future;
    final result = await sources.load(id, origin, 8, abort: abort);
    expect(result.provider, TerrainProvider.mapterhorn);
    expect(result.rasterId.key, id.key);
    expect(result.patch.field.size, 512);
    expect(result.patch.field.sample(0.5, 0.5), 1234.5);
    final again = await sources.load(id, origin, 16, abort: abort);
    expect(again.patch.resolution, 16);
    expect(requests, [TerrainProvider.mapterhorn.request(id)]);
    expect(requests.single.queryParameters, isEmpty);
    expect(sources.cacheHits, 1);
    expect(sources.downloads, 1);
    final metadata = jsonDecode(
      await File('${directory.path}/mapterhorn-v1/${id.key}.png.json')
          .readAsString(),
    ) as Map<String, Object?>;
    expect(metadata['provider'], 'Mapterhorn');
    expect(metadata['pixels'], 512);
    expect(metadata['encoding'], 'Terrarium lossless WebP');
    expect(metadata['attribution'], contains('mapterhorn.com/attribution'));
    expect(metadata['url'], requests.single.toString());
    expect(await sources.sources.last.cache.read(id), isNull);
    expect(
      sources.sources.fold(0, (sum, source) => sum + source.cache.maxBytes),
      256 * 1024 * 1024,
    );
    await File('${directory.path}/mapterhorn-v1/${id.key}.png')
        .writeAsString('corrupt');
    await sources.load(id, origin, 8, abort: abort);
    expect(requests, hasLength(2));
  });

  test('missing regional tile uses global parent; cached parents avoid repeated HTTP', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return request.url.path.startsWith('/13/')
          ? http.Response('Archive not found', 404)
          : http.Response.bytes(terrainQuadrantFixture(), 200);
    });
    addTearDown(client.close);
    final sources = TerrainSources(client: client, directory: directory);
    final abort = Completer<void>().future;
    final first = await sources.load(id, origin, 8, abort: abort);
    expect(first.rasterId.z, 12);
    expect(first.patch.field.sample(0.5, 0.5), 1000.25);
    final neighbor = TileId(13, 3, 2);
    final second = await sources.load(
      neighbor,
      neighbor.point(0.5, 0.5),
      8,
      abort: abort,
    );
    expect(second.patch.field.sample(0.5, 0.5), 2000.5);
    await sources.load(id, origin, 8, abort: abort);
    expect(requests, hasLength(2));
    expect(sources.downloads, 1);
    expect(sources.cacheHits, 2);
    expect(await sources.sources.first.cache.read(id), isNull);
    final metadata = jsonDecode(
      await File('${directory.path}/mapterhorn-v1/12-1-1.png.json')
          .readAsString(),
    ) as Map<String, Object?>;
    expect(metadata['tile'], [12, 1, 1]);
    expect(
      metadata['url'],
      TerrainProvider.mapterhorn.request(TileId(12, 1, 1)).toString(),
    );
  });

  test('service failures, invalid elevation and deadline aborts fall back to Mapzen', () async {
    for (final failure in ['http', 'void', 'timeout']) {
      final client = MockClient((request) async {
        if (request.url.host == 'tiles.mapterhorn.com') {
          if (failure == 'timeout') {
            throw http.RequestAbortedException(request.url);
          }
          return failure == 'http'
              ? http.Response('unavailable', 503)
              : http.Response.bytes(terrainVoidWebpFixture(), 200);
        }
        return http.Response.bytes(terrainFixture(), 200);
      });
      addTearDown(client.close);
      final sources = TerrainSources(
        client: client,
        directory: Directory('${directory.path}/$failure'),
      );
      final result = await sources.load(
        id,
        origin,
        8,
        abort: Completer<void>().future,
      );
      expect(result.provider, TerrainProvider.mapzen);
      expect(result.patch.field.sample(0.5, 0.5), 1234.5);
      expect(sources.downloads, 1);
      expect(await sources.sources.first.cache.read(id), isNull);
      expect(await sources.sources.last.cache.read(id), isNotNull);
    }
  });

  test(
    'distant coarse tiles use their own zoom and never probe a child/parent',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(terrainWebpFixture(), 200);
      });
      addTearDown(client.close);
      final sources = TerrainSources(client: client, directory: directory);
      final coarse = TileId(11, 1, 1);
      final result = await sources.load(
        coarse,
        coarse.point(0.5, 0.5),
        32,
        abort: Completer<void>().future,
      );
      expect(result.patch.field.size, 512);
      expect(result.rasterId.key, coarse.key);
      expect(requests.single.path, '/11/1/1.webp');
    },
  );

  test('all services failing leaves caches empty', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    addTearDown(client.close);
    final sources = TerrainSources(client: client, directory: directory);
    await expectLater(
      sources.load(id, origin, 8, abort: Completer<void>().future),
      throwsA(isA<http.ClientException>()),
    );
    expect(sources.downloads, 0);
    expect(directory.listSync(recursive: true), isEmpty);
  });

  test(
    'caller cancellation stops fallback and does not populate caches',
    () async {
      final received = Completer<void>();
      var requests = 0;
      final client = MockClient.streaming((request, _) async {
        requests++;
        received.complete();
        await (request as http.AbortableRequest).abortTrigger;
        throw http.RequestAbortedException(request.url);
      });
      addTearDown(client.close);
      final sources = TerrainSources(client: client, directory: directory);
      final stop = Completer<void>();
      final pending = expectLater(
        sources.load(id, origin, 8, abort: stop.future),
        throwsA(isA<http.RequestAbortedException>()),
      );
      await received.future;
      stop.complete();
      await pending;
      expect(requests, 1);
      expect(directory.listSync(recursive: true), isEmpty);
    },
  );

  test(
    'bundled source credits include upstream producers and license references',
    () async {
      final sources = jsonDecode(
        await File('assets/terrain/mapterhorn-attribution.json').readAsString(),
      ) as List<Object?>;
      final credits = sources.cast<Map<String, Object?>>();
      for (final code in [
        'glo30',
        'usgs3dep13',
        'cahrdem2',
        'swissalti3d',
        'frrgealti5metro',
        'ukengland',
        'fi',
        'no',
        'nz',
        'jpdem10a',
      ]) {
        final source = credits.singleWhere((s) => s['source'] == code);
        expect(source['producer'], isNotEmpty);
        expect(source['license'], isNotEmpty);
        expect(Uri.parse(source['license_pdf'] as String).scheme, 'https');
      }
    },
  );
}
