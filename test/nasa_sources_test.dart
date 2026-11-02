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
import 'package:photosim/data/imagery/imagery_sources.dart';
import 'package:photosim/data/terrain/terrain_patch.dart';
import 'package:photosim/data/terrain/terrain_provider.dart';
import 'package:photosim/data/terrain/terrain_sources.dart';

import 'imagery_fixture.dart';
import 'terrain_fixture.dart';

Uint8List elevation(int height) {
  final data = ByteData(256 * 256 * 2);
  for (var i = 0; i < 256 * 256; i++) {
    data.setInt16(i * 2, height, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  late Directory directory;
  final tile = TileId.at(const LatLng(37.744, -119.59));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('photosim-nasa-');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'NASA requests match terrain bounds, coverage and fixed imagery epoch',
    () {
      final b = tile.mercatorBounds;
      final bbox = '${b.west},${b.south},${b.east},${b.north}';
      for (final provider in [
        TerrainProvider.nasaNed,
        TerrainProvider.nasaAster,
      ]) {
        final uri = provider.request(tile);
        expect(uri.scheme, 'https');
        expect(uri.host, 'worldwind26.arc.nasa.gov');
        expect(uri.queryParameters['BBOX'], bbox);
        expect(uri.queryParameters['CRS'], 'EPSG:3857');
        expect(uri.queryParameters['FORMAT'], 'application/bil16');
        expect(
          uri.queryParameters['LAYERS'],
          provider == TerrainProvider.nasaNed ? 'USGS-NED' : 'aster_v2',
        );
        expect(uri.queryParameters['WIDTH'], '256');
        expect(provider.covers(tile), isTrue);
        expect(provider.covers(TileId.at(const LatLng(84, 0))), isFalse);
      }
      final sydney = TileId.at(const LatLng(-33.86, 151.21));
      expect(TerrainProvider.nasaNed.covers(sydney), isFalse);
      expect(TerrainProvider.nasaAster.covers(sydney), isTrue);
      for (final size in [256, 1024]) {
        final uri = nasaImageryProvider.requests(tile, size).single;
        expect(uri.host, 'gibs.earthdata.nasa.gov');
        expect(uri.queryParameters['BBOX'], bbox);
        expect(uri.queryParameters['CRS'], 'EPSG:3857');
        expect(uri.queryParameters['TIME'], '2000-12-01');
        expect(uri.queryParameters['WIDTH'], '$size');
        expect(uri.queryParameters['HEIGHT'], '$size');
      }
    },
  );

  test(
    'BIL16 is signed little-endian, north-up, and rejects voids/XML/truncation',
    () {
      final bytes = elevation(1200);
      final data = ByteData.sublistView(bytes);
      data.setInt16(0, -430, Endian.little);
      data.setInt16((256 * 256 - 1) * 2, 8800, Endian.little);
      final field = decodeNasaElevation(bytes);
      expect(field.size, 256);
      expect(field.sample(0, 0), -430);
      expect(field.sample(1, 1), 8800);
      for (final invalid in [-32768, -9999, 10001]) {
        data.setInt16(2, invalid, Endian.little);
        expect(() => decodeNasaElevation(bytes), throwsFormatException);
      }
      expect(() => decodeNasaElevation(Uint8List(2)), throwsFormatException);
      expect(
        () => decodeNasaElevation(
          Uint8List.fromList(utf8.encode('<ServiceException/>')),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'NASA is opt-in; elevation fallback caches original bytes and provenance',
    () async {
      final requests = <Uri>[];
      final bil = elevation(1450);
      final client = MockClient((request) async {
        requests.add(request.url);
        return request.url.host == 'worldwind26.arc.nasa.gov'
            ? http.Response.bytes(bil, 200)
            : http.Response('missing', 404);
      });
      addTearDown(client.close);
      expect(
        TerrainSources(
          client: client,
          directory: directory,
        ).sources.map((s) => s.provider),
        [TerrainProvider.mapterhorn, TerrainProvider.mapzen],
      );
      final sources = TerrainSources(
        client: client,
        directory: directory,
        useNasa: true,
      );
      final abort = Completer<void>().future;
      final result = await sources.load(
        tile,
        tile.point(0.5, 0.5),
        8,
        abort: abort,
      );
      expect(result.provider, TerrainProvider.nasaNed);
      expect(result.patch.field.sample(0.5, 0.5), 1450);
      expect(requests.map((uri) => uri.host), [
        'tiles.mapterhorn.com',
        'tiles.mapterhorn.com',
        'worldwind26.arc.nasa.gov',
      ]);
      await sources.load(tile, tile.point(0.5, 0.5), 8, abort: abort);
      expect(sources.cacheHits, 1);
      expect(sources.downloads, 1);
      final folder = '${directory.path}/${TerrainProvider.nasaNed.cacheKey}';
      expect(await File('$folder/${tile.key}.png').readAsBytes(), bil);
      final metadata = jsonDecode(
        await File('$folder/${tile.key}.png.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(metadata['provider'], TerrainProvider.nasaNed.label);
      expect(metadata['encoding'], 'BIL16 little-endian signed meters');
      expect(metadata['verticalDatum'], 'NAVD88 (uncorrected)');
      expect(metadata['url'], TerrainProvider.nasaNed.request(tile).toString());
    },
  );

  test(
    'NASA voids and service exceptions fall through to ASTER then Mapzen',
    () async {
      for (final asterWorks in [true, false]) {
        final layers = <String>[];
        final client = MockClient((request) async {
          if (request.url.host == 'worldwind26.arc.nasa.gov') {
            final layer = request.url.queryParameters['LAYERS']!;
            layers.add(layer);
            return layer == 'USGS-NED'
                ? http.Response.bytes(elevation(-9999), 200)
                : asterWorks
                ? http.Response.bytes(elevation(1300), 200)
                : http.Response('<ServiceException/>', 200);
          }
          return request.url.host == 's3.amazonaws.com'
              ? http.Response.bytes(terrainFixture(), 200)
              : http.Response('missing', 404);
        });
        addTearDown(client.close);
        final sources = TerrainSources(
          client: client,
          directory: Directory('${directory.path}/$asterWorks'),
          useNasa: true,
        );
        final result = await sources.load(
          tile,
          tile.point(0.5, 0.5),
          8,
          abort: Completer<void>().future,
        );
        expect(
          result.provider,
          asterWorks ? TerrainProvider.nasaAster : TerrainProvider.mapzen,
        );
        expect(layers, ['USGS-NED', 'aster_v2']);
        expect(await sources.sources[1].cache.read(tile), isNull);
      }
    },
  );

  test('regional imagery remains first; optional NASA precedes EOX and caches by resolution', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response.bytes(
        imageryFixture(
          int.parse(request.url.queryParameters['WIDTH'] ?? '256'),
        ),
        200,
      );
    });
    addTearDown(client.close);
    expect(
      ImagerySources(
        client: client,
        directory: directory,
      ).sources.any((s) => s.provider == nasaImageryProvider),
      isFalse,
    );
    final sources = ImagerySources(
      client: client,
      directory: directory,
      useNasa: true,
    );
    final abort = Completer<void>().future;
    expect(
      (await sources.load(tile, 256, abort: abort)).providers.single,
      naipImageryProvider,
    );
    final sydney = TileId.at(const LatLng(-33.86, 151.21));
    for (final size in [256, 1024]) {
      final result = await sources.load(sydney, size, abort: abort);
      expect(result.providers.single, nasaImageryProvider);
      expect(result.raster.size, size);
      await sources.load(sydney, size, abort: abort);
      final metadata = jsonDecode(
        await File(
          '${directory.path}/${nasaImageryProvider.cacheKey}-$size-v1/${sydney.key}.png.json',
        ).readAsString(),
      ) as Map<String, dynamic>;
      expect(
        metadata['url'],
        nasaImageryProvider.requests(sydney, size).single.toString(),
      );
      expect(metadata['attribution'], contains('2000'));
    }
    expect(requests, hasLength(3));
    expect(sources.cacheHits, 2);
  });

  test(
    'empty or failed NASA imagery preserves the existing EOX fallback',
    () async {
      for (final empty in [true, false]) {
        final hosts = <String>[];
        final client = MockClient((request) async {
          hosts.add(request.url.host);
          if (request.url.host == 'gibs.earthdata.nasa.gov') {
            return empty
                ? http.Response.bytes(imageryFixture(256, empty: true), 200)
                : http.Response(
                    'unavailable',
                    503,
                    headers: {'retry-after': '120'},
                  );
          }
          return http.Response.bytes(imageryFixture(256), 200);
        });
        addTearDown(client.close);
        final sources = ImagerySources(
          client: client,
          directory: Directory('${directory.path}/$empty'),
          useNasa: true,
        );
        final result = await sources.load(
          TileId.at(const LatLng(-33.86, 151.21)),
          256,
          abort: Completer<void>().future,
        );
        expect(result.providers.single, imageryProviders.last);
        expect(hosts, ['gibs.earthdata.nasa.gov', 'tiles.maps.eox.at']);
      }
    },
  );
}
