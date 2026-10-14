import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/terrain/terrain_repository.dart';
import 'package:photosim/data/terrain/tile_cache.dart';

import 'terrain_fixture.dart';

void main() {
  const origin = LatLng(37.744, -119.59);
  final id = TileId.at(origin);
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('photosim-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'valid PNG is cached; revisits avoid HTTP and corrupted cache is replaced',
    () async {
      var requests = 0;
      final bytes = terrainFixture();
      final client = MockClient((request) async {
        requests++;
        expect(request.url, id.uri);
        expect(request.headers['user-agent'], contains('PhotoSim'));
        return http.Response.bytes(bytes, 200);
      });
      addTearDown(client.close);
      final cache = TileCache(directory);
      final repository = TerrainRepository(client: client, cache: cache);
      final stop = Completer<void>();
      final patch = await repository.load(id, origin, 8, abort: stop.future);
      expect(patch.field.sample(0.5, 0.5), 1234.5);
      await repository.load(id, origin, 16, abort: stop.future);
      expect(requests, 1);
      expect(repository.cacheHits, 1);
      await File('${directory.path}/${id.key}.png').writeAsString('corrupt');
      await repository.load(id, origin, 8, abort: stop.future);
      expect(requests, 2);
      expect(await cache.read(id), bytes);
      final metadata = jsonDecode(
        await File('${directory.path}/${id.key}.png.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(metadata['tile'], [id.z, id.x, id.y]);
      expect(metadata['provider'], 'Mapzen Terrarium');
      expect(DateTime.parse(metadata['downloadedAt'] as String).isUtc, isTrue);
    },
  );
  test('HTTP failures and invalid PNG do not poison the cache', () async {
    final client = MockClient((_) async => http.Response('missing', 404));
    addTearDown(client.close);
    final cache = TileCache(directory);
    final repository = TerrainRepository(client: client, cache: cache);
    await expectLater(
      repository.load(id, origin, 8, abort: Completer<void>().future),
      throwsA(isA<http.ClientException>()),
    );
    expect(await cache.read(id), isNull);
    final invalid = MockClient((_) async => http.Response('not a PNG', 200));
    addTearDown(invalid.close);
    final bad = TerrainRepository(client: invalid, cache: cache);
    await expectLater(
      bad.load(id, origin, 8, abort: Completer<void>().future),
      throwsFormatException,
    );
    expect(await cache.read(id), isNull);
  });
  test(
    'oversize HTTP bodies are rejected before decoding or caching',
    () async {
      final client = MockClient(
        (_) async => http.Response.bytes(Uint8List(1024 * 1024 + 1), 200),
      );
      addTearDown(client.close);
      final cache = TileCache(directory);
      final repository = TerrainRepository(client: client, cache: cache);
      await expectLater(
        repository.load(id, origin, 8, abort: Completer<void>().future),
        throwsFormatException,
      );
      expect(await cache.read(id), isNull);
    },
  );

  test(
    'cache filesystem failures do not prevent network terrain rendering',
    () async {
      final blocked = File('${directory.path}/blocked');
      await blocked.writeAsString('not a directory');
      final cache = TileCache(Directory(blocked.path));
      final client = MockClient(
        (_) async => http.Response.bytes(terrainFixture(), 200),
      );
      addTearDown(client.close);
      final repository = TerrainRepository(client: client, cache: cache);
      final patch = await repository.load(
        id,
        origin,
        8,
        abort: Completer<void>().future,
      );
      expect(patch.field.sample(0.5, 0.5), 1234.5);
      expect(cache.warning, isNotNull);
    },
  );

  test('cancellation stops an in-flight HTTP request', () async {
    final received = Completer<void>();
    final client = MockClient.streaming((request, _) async {
      received.complete();
      await (request as http.AbortableRequest).abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    addTearDown(client.close);
    final stop = Completer<void>();
    final repository = TerrainRepository(
      client: client,
      cache: TileCache(directory),
    );
    final pending = repository.load(id, origin, 8, abort: stop.future);
    final expectation = expectLater(
      pending,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await received.future;
    stop.complete();
    await expectation;
  });
  test(
    'bounded cache evicts least-recently-used tiles and ignores other files',
    () async {
      final cache = TileCache(directory, maxBytes: 1200);
      final a = TileId(13, 1, 1), b = TileId(13, 2, 1);
      await File('${directory.path}/user-plan.json').writeAsString('keep');
      await cache.write(a, terrainFixture().sublist(0, 600));
      await File('${directory.path}/${a.key}.png')
          .setLastModified(DateTime(2000));
      await cache.write(b, terrainFixture().sublist(0, 600));
      expect(await cache.read(a), isNull);
      expect(
        await File('${directory.path}/${a.key}.png.json').exists(),
        isFalse,
      );
      expect(await cache.read(b), isNotNull);
      expect(
        await File('${directory.path}/user-plan.json').readAsString(),
        'keep',
      );
    },
  );
}
