import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;

import '../../core/terrain_geo.dart';
import '../http_bytes.dart';
import '../terrain/tile_cache.dart';
import 'imagery_provider.dart';

class ImageryUnavailable implements Exception {
  const ImageryUnavailable(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class ImageryRaster {
  ImageryRaster(this.rgba, this.size, this.partial);
  final Uint8List rgba;
  final int size;
  final bool partial;
}

class ImageryDecodeRequest {
  ImageryDecodeRequest(
    this.bytes,
    this.size, {
    this.retainTransparency = false,
  });
  final Uint8List bytes;
  final int size;
  final bool retainTransparency;
}

ImageryRaster decodeImagery(ImageryDecodeRequest request) {
  final bytes = request.bytes;
  if ((request.size != 256 && request.size != 1024) ||
      bytes.length < 33 ||
      bytes.length > 8 * 1024 * 1024) {
    throw const FormatException('Invalid imagery raster');
  }
  final image.Decoder decoder;
  if (bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10) {
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(8) != 13 ||
        header.getUint32(12) != 0x49484452 ||
        header.getUint32(16) != request.size ||
        header.getUint32(20) != request.size ||
        bytes[24] != 8 ||
        (bytes[25] != 2 && bytes[25] != 3 && bytes[25] != 6)) {
      throw const FormatException('Unexpected imagery size or PNG encoding');
    }
    decoder = image.PngDecoder(maxPixels: request.size * request.size);
  } else if (bytes[0] == 0xff && bytes[1] == 0xd8) {
    // EOX can serve a cached JPEG for a PNG GetMap request aligned to its tile grid.
    decoder = image.JpegDecoder(maxPixels: request.size * request.size);
  } else {
    throw const FormatException('Expected PNG or JPEG imagery');
  }
  image.Image? decoded;
  try {
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width != request.size ||
        info.height != request.size) {
      throw const FormatException('Unexpected imagery dimensions');
    }
    decoded = decoder.decodeFrame(0);
  } catch (error) {
    throw FormatException('Malformed imagery raster: $error');
  }
  if (decoded == null) throw const FormatException('Could not decode imagery');
  final rgba = Uint8List(request.size * request.size * 4);
  var present = 0, partial = false;
  // getPixel(x, y) allocates a fresh Pixel on every call: 1M+ objects per 1024² tile.
  // The decoder's optional `pixel` argument reuses one instance for the whole scan.
  final pixel = decoded.getPixel(0, 0);
  for (var y = 0; y < request.size; y++) {
    for (var x = 0; x < request.size; x++) {
      decoded.getPixel(x, y, pixel);
      final alpha = pixel.a.toInt();
      if (alpha > 0) present++;
      if (alpha < 255) partial = true;
      final offset = (y * request.size + x) * 4;
      if (request.retainTransparency) {
        rgba[offset] = pixel.r.toInt();
        rgba[offset + 1] = pixel.g.toInt();
        rgba[offset + 2] = pixel.b.toInt();
        rgba[offset + 3] = alpha;
      } else {
        final inverse = 1 - alpha / 255;
        // Missing coverage stays visibly distinct from real imagery.
        rgba[offset] = (pixel.r * alpha / 255 + 154 * inverse).round();
        rgba[offset + 1] = (pixel.g * alpha / 255 + 170 * inverse).round();
        rgba[offset + 2] = (pixel.b * alpha / 255 + 137 * inverse).round();
        rgba[offset + 3] = 255;
      }
    }
  }
  if (present == 0) {
    throw const ImageryUnavailable('Source has no imagery in this tile');
  }
  return ImageryRaster(rgba, request.size, partial);
}

class TiledImageryDecodeRequest {
  TiledImageryDecodeRequest(
    this.tiles,
    this.size, {
    this.retainTransparency = false,
  });
  final List<Uint8List> tiles;
  final int size;
  final bool retainTransparency;
}

class TiledImageryResult {
  TiledImageryResult(this.raster, this.png);
  final ImageryRaster raster;
  final Uint8List png;
}

/// Stitches a row-major 4×4 tile grid; missing sub-tiles stay transparent for fallback.
TiledImageryResult decodeTiledImagery(TiledImageryDecodeRequest request) {
  if (request.size != 1024 || request.tiles.length != 16) {
    throw const FormatException('Invalid tiled imagery');
  }
  final rgba = Uint8List(request.size * request.size * 4);
  var partial = false, present = false;
  for (var index = 0; index < request.tiles.length; index++) {
    final ImageryRaster tile;
    try {
      tile = decodeImagery(
        ImageryDecodeRequest(
          request.tiles[index],
          256,
          retainTransparency: true,
        ),
      );
    } on ImageryUnavailable {
      partial = true;
      continue;
    }
    present = true;
    partial = partial || tile.partial;
    final dx = index % 4 * 256, dy = index ~/ 4 * 256;
    for (var y = 0; y < 256; y++) {
      final source = y * 256 * 4;
      final destination = ((dy + y) * 1024 + dx) * 4;
      rgba.setRange(destination, destination + 1024, tile.rgba, source);
    }
  }
  if (!present) {
    throw const ImageryUnavailable('Source has no imagery in this tile');
  }
  if (!request.retainTransparency) {
    for (var offset = 0; offset < rgba.length; offset += 4) {
      final alpha = rgba[offset + 3];
      if (alpha == 255) continue;
      final inverse = 1 - alpha / 255;
      rgba[offset] = (rgba[offset] * alpha / 255 + 154 * inverse).round();
      rgba[offset + 1] = (rgba[offset + 1] * alpha / 255 + 170 * inverse)
          .round();
      rgba[offset + 2] = (rgba[offset + 2] * alpha / 255 + 137 * inverse)
          .round();
      rgba[offset + 3] = 255;
    }
  }
  final png = image.encodePng(
    image.Image.fromBytes(
      width: 1024,
      height: 1024,
      bytes: rgba.buffer,
      numChannels: 4,
    ),
  );
  return TiledImageryResult(ImageryRaster(rgba, 1024, partial), png);
}

class ImageryRepository {
  ImageryRepository({
    required this.client,
    required this.previewCache,
    required this.detailCache,
    this.provider = naipImageryProvider,
    this.retainTransparency = false,
  });
  final http.Client client;
  final TileCache previewCache, detailCache;
  final ImageryProvider provider;
  final bool retainTransparency;
  int cacheHits = 0, downloads = 0;

  Future<ImageryRaster> load(
    TileId tile,
    int pixels, {
    required Future<void> abort,
  }) async {
    final uris = provider.requests(tile, pixels);
    if (!provider.covers(tile)) {
      throw ImageryUnavailable('Outside ${provider.name} service extent');
    }
    final uri = uris.first;
    var cancelled = false;
    unawaited(abort.then((_) => cancelled = true));
    final cache = pixels == 256 ? previewCache : detailCache;
    final stored = await cache.read(tile);
    if (stored != null) {
      try {
        final result = await compute(
          decodeImagery,
          ImageryDecodeRequest(
            stored,
            pixels,
            retainTransparency: retainTransparency,
          ),
        );
        if (cancelled) throw http.RequestAbortedException(uri);
        cacheHits++;
        return result;
      } on FormatException {
        await cache.remove(tile);
      } on ImageryUnavailable {
        await cache.remove(tile);
      }
    }
    Uint8List cacheBytes;
    ImageryRaster result;
    if (uris.length == 1) {
      cacheBytes = await _download(uris.single, abort);
      result = await compute(
        decodeImagery,
        ImageryDecodeRequest(
          cacheBytes,
          pixels,
          retainTransparency: retainTransparency,
        ),
      );
    } else {
      final tiles = await Future.wait([
        for (final uri in uris) _download(uri, abort),
      ]);
      final tiled = await compute(
        decodeTiledImagery,
        TiledImageryDecodeRequest(
          tiles,
          pixels,
          retainTransparency: retainTransparency,
        ),
      );
      cacheBytes = tiled.png;
      result = tiled.raster;
    }
    if (cancelled) throw http.RequestAbortedException(uri);
    await cache.write(
      tile,
      cacheBytes,
      metadata: {
        'provider': provider.name,
        'url': uri.toString(),
        'sourceTiles': uris.length,
        'pixels': pixels,
        'attribution': provider.attribution,
        'verticalDatum': null,
        'horizontalCrs': 'EPSG:3857',
        'partialCoverage': result.partial,
        'acquisitionTimeNote': 'Mosaic source dates vary; not queried',
      },
    );
    downloads++;
    return result;
  }

  Future<Uint8List> _download(Uri uri, Future<void> abort) =>
      downloadBytes(client, uri, abort: abort, maxBytes: 8 * 1024 * 1024);
}
