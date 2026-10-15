import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/imagery/imagery_provider.dart';
import 'package:photosim/data/imagery/imagery_repository.dart';
import 'package:photosim/data/imagery/imagery_sources.dart';

import 'imagery_fixture.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('photosim-sources-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  int pixels(Uri uri) => int.parse(
    uri.queryParameters['WIDTH'] ??
        uri.queryParameters['size']!.split(',').first,
  );

  test('WMS exports preserve terrain bounds, dimensions and north-up Mercator axes', () {
    final tile = TileId.at(const LatLng(46.58, 7.96));
    final bounds = tile.mercatorBounds;
    for (final provider in imageryProviders.whereType<WmsImageryProvider>()) {
      final q = provider.request(tile, 1024).queryParameters;
      expect(q['VERSION'], '1.3.0');
      expect(q['CRS'], 'EPSG:3857');
      expect(
        q['BBOX'],
        '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
      );
      expect(q['WIDTH'], '1024');
      expect(q['HEIGHT'], '1024');
      expect(q['TRANSPARENT'], 'TRUE');
      expect(q['FORMAT'], 'image/png');
      expect(q['LAYERS'], provider.layer);
      expect(() => provider.request(tile, 9999), throwsArgumentError);
    }
    final global = imageryProviders.last as WmsImageryProvider;
    expect(global.layer, 's2cloudless_3857');
    expect(global.attribution, contains('2016'));
    expect(global.attribution, contains('CC BY 4.0'));
    expect(
      (imageryProviders[1] as WmsImageryProvider).layer,
      'ch.swisstopo.images-swissimage',
    );
  });

  test(
    'regional selection, global fallback and per-source preview/detail caches',
    () async {
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        return http.Response.bytes(imageryFixture(pixels(request.url)), 200);
      });
      addTearDown(client.close);
      final sources = ImagerySources(client: client, directory: directory);
      final abort = Completer<void>().future;
      for (final entry in [
        (const LatLng(37.744, -119.59), 'USGS NAIP'),
        (const LatLng(46.58, 7.96), 'swisstopo SWISSIMAGE'),
        (const LatLng(48.86, 2.35), 'IGN BD ORTHO'),
        (const LatLng(-21.12, 55.53), 'IGN BD ORTHO'),
        (const LatLng(-33.86, 151.21), 'EOX Sentinel-2 cloudless 2016'),
        (const LatLng(-1.29, 36.82), 'EOX Sentinel-2 cloudless 2016'),
        (const LatLng(75, -40), 'EOX Sentinel-2 cloudless 2016'),
      ]) {
        final tile = TileId.at(entry.$1);
        for (final size in [256, 1024]) {
          final result = await sources.load(tile, size, abort: abort);
          expect(result.providers.single.name, entry.$2);
          expect(result.raster.size, size);
          expect(result.raster.rgba.sublist(0, 4), [255, 0, 0, 255]);
          final source = sources.sources.singleWhere(
            (source) => source.provider.name == entry.$2,
          );
          final cache = size == 256 ? source.previewCache : source.detailCache;
          final metadata = jsonDecode(
            await File('${cache.directory.path}/${tile.key}.png.json')
                .readAsString(),
          );
          expect(metadata['provider'], entry.$2);
          expect(metadata['attribution'], result.providers.single.attribution);
          expect(
            metadata['url'],
            source.provider.request(tile, size).toString(),
          );
          final again = await sources.load(tile, size, abort: abort);
          expect(again.providers.single.name, entry.$2);
        }
      }
      expect(requested, hasLength(14));
      expect(sources.downloads, 14);
      expect(sources.cacheHits, 14);
    },
  );

  test(
    'service errors, malformed responses and empty coverage fall back globally',
    () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.host);
        if (request.url.host == 'wms.geo.admin.ch') {
          return http.Response(
            '<ServiceException>unavailable</ServiceException>',
            200,
          );
        }
        if (request.url.host == 'data.geopf.fr') {
          return http.Response.bytes(imageryFixture(256, empty: true), 200);
        }
        if (request.url.host == 'imagery.nationalmap.gov') {
          return http.Response('unavailable', 503);
        }
        return http.Response.bytes(imageryFixture(256), 200);
      });
      addTearDown(client.close);
      final sources = ImagerySources(client: client, directory: directory);
      final abort = Completer<void>().future;
      for (final location in [
        const LatLng(46.58, 7.96),
        const LatLng(37.744, -119.59),
      ]) {
        final result = await sources.load(
          TileId.at(location),
          256,
          abort: abort,
        );
        expect(result.providers.single, imageryProviders.last);
      }
      expect(requested, [
        'wms.geo.admin.ch',
        'data.geopf.fr',
        'tiles.maps.eox.at',
        'imagery.nationalmap.gov',
        'tiles.maps.eox.at',
      ]);
      expect(sources.downloads, 2);
      expect(
        await sources.sources.first.previewCache.read(
          TileId.at(const LatLng(37.744, -119.59)),
        ),
        isNull,
      );
    },
  );

  test('partial regional coverage overlays global pixels without losing regional pixels', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'imagery.nationalmap.gov') {
        return http.Response.bytes(imageryFixture(256, partial: true), 200);
      }
      return http.Response.bytes(imageryFixture(256), 200);
    });
    addTearDown(client.close);
    final sources = ImagerySources(client: client, directory: directory);
    final result = await sources.load(
      TileId.at(const LatLng(37.744, -119.59)),
      256,
      abort: Completer<void>().future,
    );
    expect(result.providers.map((p) => p.name), [
      'USGS NAIP',
      'EOX Sentinel-2 cloudless 2016',
    ]);
    expect(result.raster.partial, isFalse);
    expect(result.raster.rgba.sublist(0, 4), [255, 0, 0, 255]);
    expect(result.raster.rgba.sublist(4, 8), [80, 120, 160, 255]);
    await sources.load(
      TileId.at(const LatLng(37.744, -119.59)),
      256,
      abort: Completer<void>().future,
    );
    expect(sources.downloads, 2);
    expect(sources.cacheHits, 2);
  });

  test(
    'partial coverage survives global failure with a labeled fallback surface',
    () async {
      final client = MockClient(
        (request) async => request.url.host == 'imagery.nationalmap.gov'
            ? http.Response.bytes(imageryFixture(256, partial: true), 200)
            : http.Response('unavailable', 503),
      );
      addTearDown(client.close);
      final sources = ImagerySources(client: client, directory: directory);
      final result = await sources.load(
        TileId.at(const LatLng(37.744, -119.59)),
        256,
        abort: Completer<void>().future,
      );
      expect(result.providers.single.name, 'USGS NAIP');
      expect(result.raster.partial, isTrue);
      expect(result.raster.rgba.sublist(4, 8), [154, 170, 137, 255]);
    },
  );

  test('alpha composition respects order and fractional coverage', () {
    ImageryRaster pixel(List<int> rgba) =>
        ImageryRaster(Uint8List.fromList(rgba), 1, true);
    final result = compositeImagery([
      pixel([200, 100, 0, 128]),
      pixel([0, 0, 200, 255]),
      pixel([255, 255, 255, 255]),
    ]);
    expect(result.rgba, [100, 50, 100, 255]);
    expect(result.partial, isFalse);
    final partial = compositeImagery([
      pixel([255, 0, 0, 128]),
    ]);
    expect(partial.rgba, [205, 85, 68, 255]);
    expect(partial.partial, isTrue);
  });

  test(
    'all sources failing reports unavailable and does not cache failures',
    () async {
      final client = MockClient((_) async => http.Response('unavailable', 503));
      addTearDown(client.close);
      final sources = ImagerySources(client: client, directory: directory);
      await expectLater(
        sources.load(
          TileId.at(const LatLng(-33.86, 151.21)),
          256,
          abort: Completer<void>().future,
        ),
        throwsA(isA<ImageryUnavailable>()),
      );
      expect(sources.downloads, 0);
      expect(directory.listSync(recursive: true), isEmpty);
    },
  );

  test(
    'service timeout falls back when the caller has not cancelled',
    () async {
      final client = MockClient((request) async {
        if (request.url.host == 'imagery.nationalmap.gov') {
          throw http.RequestAbortedException(request.url);
        }
        return http.Response.bytes(imageryFixture(256), 200);
      });
      addTearDown(client.close);
      final sources = ImagerySources(client: client, directory: directory);
      final result = await sources.load(
        TileId.at(const LatLng(37.744, -119.59)),
        256,
        abort: Completer<void>().future,
      );
      expect(result.providers.single, imageryProviders.last);
      expect(sources.downloads, 1);
    },
  );

  test('caller cancellation stops fallback and leaves cache empty', () async {
    final received = Completer<void>();
    var requests = 0;
    final client = MockClient.streaming((request, _) async {
      requests++;
      received.complete();
      await (request as http.AbortableRequest).abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    addTearDown(client.close);
    final sources = ImagerySources(client: client, directory: directory);
    final stop = Completer<void>();
    final pending = expectLater(
      sources.load(
        TileId.at(const LatLng(37.744, -119.59)),
        256,
        abort: stop.future,
      ),
      throwsA(isA<http.RequestAbortedException>()),
    );
    await received.future;
    stop.complete();
    await pending;
    expect(requests, 1);
    expect(directory.listSync(recursive: true), isEmpty);
  });
}
