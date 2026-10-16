import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/http_bytes.dart';
import 'package:photosim/data/terrain/terrain_repository.dart';
import 'package:photosim/data/terrain/tile_cache.dart';

import 'terrain_fixture.dart';

void main() {
  final uri = Uri.https('example.com', '/imagery');
  Future<List<int>> fetch(
    http.Client client, {
    Uri? url,
    Future<void>? abort,
    Duration timeout = const Duration(seconds: 20),
  }) => downloadBytes(
    client,
    url ?? uri,
    abort: abort ?? Completer<void>().future,
    maxBytes: 1024,
    timeout: timeout,
  );

  test('a download deadline aborts an unresponsive service', () async {
    final client = MockClient.streaming((request, _) async {
      await (request as http.AbortableRequest).abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    addTearDown(client.close);
    await expectLater(
      fetch(
        client,
        timeout: const Duration(milliseconds: 10),
      ).timeout(const Duration(seconds: 1)),
      throwsA(isA<http.RequestAbortedException>()),
    );
  });

  test('three streamed requests per origin; queued cancellation/deadline never send', () async {
    final bodies = <StreamController<List<int>>>[];
    var active = 0, peak = 0;
    final client = MockClient.streaming((request, _) async {
      active++;
      if (active > peak) peak = active;
      final body = StreamController<List<int>>(
        onCancel: () {
          active--;
        },
      );
      bodies.add(body);
      return http.StreamedResponse(body.stream, 200);
    });
    addTearDown(client.close);
    final stops = List.generate(6, (_) => Completer<void>());
    final jobs = [for (final stop in stops) fetch(client, abort: stop.future)];
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bodies.length, 3);
    final cancelled = expectLater(
      jobs[3],
      throwsA(isA<http.RequestAbortedException>()),
    );
    stops[3].complete();
    await cancelled;
    await expectLater(
      fetch(client, timeout: const Duration(milliseconds: 10)),
      throwsA(isA<http.RequestAbortedException>()),
    );
    expect(bodies.length, 3);
    for (final body in bodies.toList()) {
      body.add([1]);
      await body.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bodies.length, 5);
    for (final body in bodies.skip(3)) {
      body.add([1]);
      await body.close();
    }
    await Future.wait([
      for (var i = 0; i < jobs.length; i++)
        if (i != 3) jobs[i],
    ]);
    expect(peak, 3);
    expect(active, 0);
    final stopped = Completer<void>()..complete();
    await expectLater(
      fetch(client, abort: stopped.future),
      throwsA(isA<http.RequestAbortedException>()),
    );
    expect(bodies.length, 5);
  });

  test('429 retries with backoff, then recovers', () async {
    var calls = 0;
    final client = MockClient(
      (request) async => ++calls == 1
          ? http.Response('', 429, headers: {'retry-after': '0'})
          : http.Response('ok', 200),
    );
    addTearDown(client.close);
    final elapsed = Stopwatch()..start();
    expect(await fetch(client), [111, 107]);
    expect(calls, 2);
    expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(950));
  });

  test(
    'shared cooldown cancels promptly and does not block another origin',
    () async {
      var blockedCalls = 0;
      final received = Completer<void>();
      final client = MockClient((request) async {
        if (request.url.host != uri.host) return http.Response('ok', 200);
        blockedCalls++;
        if (!received.isCompleted) received.complete();
        return http.Response('', 429, headers: {'retry-after': '5'});
      });
      addTearDown(client.close);
      final firstStop = Completer<void>(), secondStop = Completer<void>();
      final first = expectLater(
        fetch(client, abort: firstStop.future),
        throwsA(isA<http.RequestAbortedException>()),
      );
      await received.future;
      await Future<void>.delayed(Duration.zero);
      final second = expectLater(
        fetch(client, abort: secondStop.future),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'status',
            contains('HTTP 429; service cooldown'),
          ),
        ),
      );
      expect(
        await fetch(
          client,
          url: Uri.https('other.example', '/tile'),
        ).timeout(const Duration(seconds: 1)),
        [111, 107],
      );
      firstStop.complete();
      secondStop.complete();
      await Future.wait([first, second]);
      expect(blockedCalls, 1);
    },
  );

  for (final code in [429, 503]) {
    test(
      '$code honors Retry-After ${code == 429 ? 'seconds' : 'HTTP-date'} and fails fast beyond the deadline',
      () async {
        var calls = 0;
        final client = MockClient((request) async {
          calls++;
          return http.Response(
            '',
            code,
            headers: {
              'retry-after': code == 429
                  ? '120'
                  : HttpDate.format(
                      DateTime.now().toUtc().add(const Duration(minutes: 2)),
                    ),
            },
          );
        });
        addTearDown(client.close);
        final failure = throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'cooldown',
            contains('HTTP $code; service cooldown'),
          ),
        );
        await expectLater(fetch(client), failure);
        await expectLater(fetch(client), failure);
        expect(calls, 1);
      },
    );
  }

  test('persistent throttling has at most two retries, even with a malformed header', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 429, headers: {'retry-after': 'not a date'});
    });
    addTearDown(client.close);
    await expectLater(
      fetch(client),
      throwsA(
        isA<http.ClientException>().having(
          (e) => e.message,
          'status',
          'HTTP 429',
        ),
      ),
    );
    expect(calls, 3);
  });

  test('cached terrain bypasses a service cooldown', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photosim-rate-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cache = TileCache(directory);
    final tile = TileId(13, 1374, 3167);
    await cache.write(tile, terrainFixture());
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 429, headers: {'retry-after': '120'});
    });
    addTearDown(client.close);
    await expectLater(
      fetch(client, url: tile.uri),
      throwsA(isA<http.ClientException>()),
    );
    final repository = TerrainRepository(client: client, cache: cache);
    final patch = await repository.load(
      tile,
      tile.point(0.5, 0.5),
      4,
      abort: Completer<void>().future,
    );
    expect(patch.field.sample(0.5, 0.5), 1234.5);
    expect(repository.cacheHits, 1);
    expect(repository.downloads, 0);
    expect(calls, 1);
  });

  test('huge Retry-After saturates safely rather than overflowing', () async {
    final client = MockClient(
      (_) async => http.Response(
        '',
        429,
        headers: {'retry-after': '9223372036854775807'},
      ),
    );
    addTearDown(client.close);
    await expectLater(
      fetch(client),
      throwsA(
        isA<http.ClientException>().having(
          (e) => e.message,
          'cooldown',
          contains('9999-12-31'),
        ),
      ),
    );
  });
  for (final declared in [true, false]) {
    test(
      'oversized body (declared: $declared) releases its request slot',
      () async {
        var calls = 0, cancelled = 0;
        final body = StreamController<List<int>>(
          onCancel: () {
            cancelled++;
          },
        );
        addTearDown(body.close);
        final client = MockClient.streaming((_, _) async {
          if (++calls > 1) return http.StreamedResponse(Stream.value([1]), 200);
          return http.StreamedResponse(
            body.stream,
            200,
            contentLength: declared ? 1025 : null,
          );
        });
        addTearDown(client.close);
        final rejected = expectLater(fetch(client), throwsFormatException);
        if (!declared) body.add(List.filled(1025, 0));
        await rejected;
        expect(cancelled, 1);
        expect(await fetch(client), [1]);
      },
    );
  }
  test('404 is not retried; rejected response bodies are cancelled', () async {
    var calls = 0, cancelled = 0;
    final client = MockClient.streaming((request, _) async {
      calls++;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled++;
        },
      );
      addTearDown(body.close);
      return http.StreamedResponse(body.stream, 404);
    });
    addTearDown(client.close);
    await expectLater(fetch(client), throwsA(isA<http.ClientException>()));
    expect(calls, 1);
    expect(cancelled, 1);
  });
}
