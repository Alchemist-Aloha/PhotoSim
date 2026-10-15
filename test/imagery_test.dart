import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:image/image.dart' as image;
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/imagery/imagery_provider.dart';
import 'package:photosim/data/imagery/imagery_repository.dart';
import 'package:photosim/data/terrain/tile_cache.dart';

import 'imagery_fixture.dart';

void main() {
  final tile = TileId.at(const LatLng(37.744, -119.59));
  const provider = NaipProvider();
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('photosim-imagery-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('export uses exact terrain EPSG:3857 bounds without aspect-ratio adjustment', () {
    final uri = provider.request(tile, 256);
    expect(uri.host, 'imagery.nationalmap.gov');
    final query = uri.queryParameters;
    expect(query['bboxSR'], '3857');
    expect(query['imageSR'], '3857');
    expect(query['size'], '256,256');
    expect(query['format'], 'png32');
    expect(query['adjustAspectRatio'], 'false');
    expect(
      (jsonDecode(query['renderingRule']!)
          as Map<String, Object?>)['rasterFunction'],
      'NaturalColor',
    );
    final bounds = query['bbox']!.split(',').map(double.parse).toList();
    final nw = tile.point(0, 0), se = tile.point(1, 1);
    double x(double lon) => lon * math.pi / 180 * 6378137;
    double y(double lat) =>
        math.log(math.tan(math.pi / 4 + lat * math.pi / 360)) * 6378137;
    expect(bounds[0], closeTo(x(nw.longitude), 1e-6));
    expect(bounds[1], closeTo(y(se.latitude), 1e-6));
    expect(bounds[2], closeTo(x(se.longitude), 1e-6));
    expect(bounds[3], closeTo(y(nw.latitude), 1e-6));
    expect(() => provider.request(tile, 9999), throwsArgumentError);
  });

  test('raster orientation preserves northwest and southeast color pixels', () {
    final raster = decodeImagery(
      ImageryDecodeRequest(imageryFixture(256), 256),
    );
    expect(raster.rgba.sublist(0, 4), [255, 0, 0, 255]);
    expect(raster.rgba.sublist(raster.rgba.length - 4), [0, 0, 255, 255]);
    expect(raster.partial, isFalse);
  });
  test('indexed PNG preserves palette colors and transparent no-data for compositing', () {
    final png = image.Image(
      width: 256,
      height: 256,
      withPalette: true,
      numChannels: 4,
    );
    png.palette!.setRgba(0, 80, 120, 160, 255);
    png.palette!.setRgba(1, 0, 0, 0, 0);
    png.setPixelIndex(1, 0, 1);
    final raster = decodeImagery(
      ImageryDecodeRequest(image.encodePng(png), 256, retainTransparency: true),
    );
    expect(raster.rgba.sublist(0, 8), [80, 120, 160, 255, 0, 0, 0, 0]);
    expect(raster.partial, isTrue);
  });
  test('cached JPEG responses are bounded and decode as opaque RGB', () {
    final jpeg = image.Image(width: 256, height: 256, numChannels: 3);
    image.fill(jpeg, color: image.ColorRgb8(80, 120, 160));
    final bytes = image.encodeJpg(jpeg);
    final raster = decodeImagery(ImageryDecodeRequest(bytes, 256));
    expect(raster.rgba[0], closeTo(80, 2));
    expect(raster.rgba[1], closeTo(120, 2));
    expect(raster.rgba[2], closeTo(160, 2));
    expect(raster.rgba[3], 255);
    expect(raster.partial, isFalse);
    expect(
      () => decodeImagery(ImageryDecodeRequest(bytes, 1024)),
      throwsFormatException,
    );
    expect(
      () => decodeImagery(ImageryDecodeRequest(bytes.sublist(0, 40), 256)),
      throwsFormatException,
    );
  });
  test(
    'partial no-data becomes fallback material; empty coverage is unavailable',
    () {
      final raster = decodeImagery(
        ImageryDecodeRequest(imageryFixture(256, partial: true), 256),
      );
      expect(raster.partial, isTrue);
      expect(raster.rgba.sublist(4, 8), [154, 170, 137, 255]);
      expect(
        () => decodeImagery(
          ImageryDecodeRequest(imageryFixture(256, empty: true), 256),
        ),
        throwsA(isA<ImageryUnavailable>()),
      );
    },
  );
  test(
    'invalid, oversize and mismatched images are rejected at trust boundary',
    () {
      expect(
        () => decodeImagery(
          ImageryDecodeRequest(
            Uint8List.fromList(utf8.encode('{"error": {}}')),
            256,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => decodeImagery(
          ImageryDecodeRequest(Uint8List(8 * 1024 * 1024 + 1), 256),
        ),
        throwsFormatException,
      );
      expect(
        () => decodeImagery(ImageryDecodeRequest(imageryFixture(256), 1024)),
        throwsFormatException,
      );
      expect(
        () => decodeImagery(
          ImageryDecodeRequest(imageryFixture(256).sublist(0, 40), 256),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'preview/detail cache independently and revisits do not call HTTP',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        final size = int.parse(
          request.url.queryParameters['size']!.split(',').first,
        );
        return http.Response.bytes(imageryFixture(size), 200);
      });
      addTearDown(client.close);
      final preview = TileCache(Directory('${directory.path}/preview'));
      final detail = TileCache(
        Directory('${directory.path}/detail'),
        maxEntryBytes: 8 * 1024 * 1024,
      );
      final repository = ImageryRepository(
        client: client,
        previewCache: preview,
        detailCache: detail,
      );
      final abort = Completer<void>().future;
      await repository.load(tile, 256, abort: abort);
      await repository.load(tile, 1024, abort: abort);
      await repository.load(tile, 256, abort: abort);
      await repository.load(tile, 1024, abort: abort);
      expect(requests, 2);
      expect(repository.cacheHits, 2);
      final metadata = jsonDecode(
        await File('${detail.directory.path}/${tile.key}.png.json')
            .readAsString(),
      ) as Map<String, Object?>;
      expect(metadata['provider'], 'USGS NAIP');
      expect(metadata['pixels'], 1024);
      expect(metadata['url'], provider.request(tile, 1024).toString());
      expect(metadata['acquisitionTime'], isNull);
      expect(metadata['horizontalCrs'], 'EPSG:3857');
      await File('${preview.directory.path}/${tile.key}.png')
          .writeAsString('bad');
      await repository.load(tile, 256, abort: abort);
      expect(requests, 3);
    },
  );
  test('outside NAIP extent skips network and preserves terrain-independent fallback', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('', 500);
    });
    addTearDown(client.close);
    final cache = TileCache(directory);
    final repository = ImageryRepository(
      client: client,
      previewCache: cache,
      detailCache: cache,
    );
    await expectLater(
      repository.load(
        TileId.at(const LatLng(51.5, -0.1)),
        256,
        abort: Completer<void>().future,
      ),
      throwsA(isA<ImageryUnavailable>()),
    );
    expect(requests, 0);
  });
  test(
    'missing imagery is not cached, and detail failure retains cached preview',
    () async {
      final client = MockClient(
        (request) async => request.url.queryParameters['size'] == '256,256'
            ? http.Response.bytes(imageryFixture(256), 200)
            : http.Response('unavailable', 503),
      );
      addTearDown(client.close);
      final preview = TileCache(Directory('${directory.path}/preview'));
      final detail = TileCache(Directory('${directory.path}/detail'));
      final repository = ImageryRepository(
        client: client,
        previewCache: preview,
        detailCache: detail,
      );
      final abort = Completer<void>().future;
      await repository.load(tile, 256, abort: abort);
      await expectLater(
        repository.load(tile, 1024, abort: abort),
        throwsA(isA<http.ClientException>()),
      );
      expect(await preview.read(tile), isNotNull);
      expect(await detail.read(tile), isNull);
      final emptyClient = MockClient(
        (_) async => http.Response.bytes(imageryFixture(256, empty: true), 200),
      );
      addTearDown(emptyClient.close);
      final emptyCache = TileCache(Directory('${directory.path}/empty'));
      final emptyRepository = ImageryRepository(
        client: emptyClient,
        previewCache: emptyCache,
        detailCache: emptyCache,
      );
      await expectLater(
        emptyRepository.load(tile, 256, abort: abort),
        throwsA(isA<ImageryUnavailable>()),
      );
      expect(await emptyCache.read(tile), isNull);
    },
  );
  test('imagery HTTP cancellation does not populate the cache', () async {
    final received = Completer<void>();
    final client = MockClient.streaming((request, _) async {
      received.complete();
      await (request as http.AbortableRequest).abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    addTearDown(client.close);
    final cache = TileCache(directory);
    final repository = ImageryRepository(
      client: client,
      previewCache: cache,
      detailCache: cache,
    );
    final stop = Completer<void>();
    final pending = expectLater(
      repository.load(tile, 256, abort: stop.future),
      throwsA(isA<http.RequestAbortedException>()),
    );
    await received.future;
    stop.complete();
    await pending;
    expect(await cache.read(tile), isNull);
  });
}
