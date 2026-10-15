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
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if ((request.size != 256 && request.size != 1024) ||
      bytes.length < 33 ||
      bytes.length > 8 * 1024 * 1024) {
    throw const FormatException('Invalid imagery raster');
  }
  final image.Decoder decoder;
  if (List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v)) {
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
  for (var y = 0; y < request.size; y++) {
    for (var x = 0; x < request.size; x++) {
      final pixel = decoded.getPixel(x, y);
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
        // Missing coverage stays visibly distinct from real imagery.
        rgba[offset] = (pixel.r * alpha / 255 + 154 * (1 - alpha / 255))
            .round();
        rgba[offset + 1] = (pixel.g * alpha / 255 + 170 * (1 - alpha / 255))
            .round();
        rgba[offset + 2] = (pixel.b * alpha / 255 + 137 * (1 - alpha / 255))
            .round();
        rgba[offset + 3] = 255;
      }
    }
  }
  if (present == 0) {
    throw const ImageryUnavailable('Source has no imagery in this tile');
  }
  return ImageryRaster(rgba, request.size, partial);
}

class ImageryRepository {
  ImageryRepository({
    required this.client,
    required this.previewCache,
    required this.detailCache,
    this.provider = const NaipProvider(),
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
    final uri = provider.request(tile, pixels);
    if (!provider.covers(tile)) {
      throw ImageryUnavailable('Outside ${provider.name} service extent');
    }
    var cancelled = false;
    abort.then((_) => cancelled = true);
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
    final bytes = await downloadBytes(
      client,
      uri,
      abort: abort,
      maxBytes: 8 * 1024 * 1024,
      // EOX's dynamic detail exports can take more than 20 seconds; previews remain usable.
      timeout: const Duration(seconds: 40),
    );
    final result = await compute(
      decodeImagery,
      ImageryDecodeRequest(
        bytes,
        pixels,
        retainTransparency: retainTransparency,
      ),
    );
    if (cancelled) throw http.RequestAbortedException(uri);
    await cache.write(
      tile,
      bytes,
      metadata: {
        'provider': provider.name,
        'url': uri.toString(),
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
}
