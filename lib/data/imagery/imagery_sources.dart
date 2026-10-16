import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/terrain_geo.dart';
import '../terrain/tile_cache.dart';
import '../raster_cache.dart';
import 'imagery_provider.dart';
import 'imagery_repository.dart';

/// Regional aerial imagery first; fill remaining coverage with the global mosaic.
class ImagerySources {
  ImagerySources({
    required http.Client client,
    required Directory directory,
    RasterCache? budget,
  }) : sources = [
         for (final provider in imageryProviders)
           ImageryRepository(
             client: client,
             provider: provider,
             retainTransparency: true,
             previewCache: TileCache(
               Directory('${directory.path}/${provider.cacheKey}-256-v1'),
               maxBytes: 16 * 1024 * 1024,
               budget: budget,
               maxEntryBytes: 8 * 1024 * 1024,
             ),
             detailCache: TileCache(
               Directory('${directory.path}/${provider.cacheKey}-1024-v1'),
               maxBytes: 48 * 1024 * 1024,
               budget: budget,
               maxEntryBytes: 8 * 1024 * 1024,
             ),
           ),
       ];

  final List<ImageryRepository> sources;
  int get cacheHits => sources.fold(0, (sum, source) => sum + source.cacheHits);
  int get downloads => sources.fold(0, (sum, source) => sum + source.downloads);
  String? get cacheWarning {
    for (final source in sources) {
      final warning = source.previewCache.warning ?? source.detailCache.warning;
      if (warning != null) return warning;
    }
    return null;
  }

  Future<({ImageryRaster raster, List<ImageryProvider> providers})> load(
    TileId tile,
    int pixels, {
    required Future<void> abort,
  }) async {
    if (pixels != 256 && pixels != 1024) {
      throw ArgumentError('Unsupported imagery resolution');
    }
    var cancelled = false;
    unawaited(abort.then((_) => cancelled = true));
    final layers = <ImageryRaster>[];
    final providers = <ImageryProvider>[];
    Exception? failure;
    for (final source in sources) {
      if (cancelled) throw http.RequestAbortedException();
      if (!source.provider.covers(tile)) continue;
      try {
        final raster = await source.load(tile, pixels, abort: abort);
        layers.add(raster);
        providers.add(source.provider);
        if (!raster.partial) break;
      } on Exception catch (error) {
        // A service deadline may also abort HTTP; only caller cancellation stops fallback.
        if (cancelled) throw http.RequestAbortedException();
        failure = error;
      }
    }
    if (cancelled) throw http.RequestAbortedException();
    if (layers.isEmpty) {
      throw ImageryUnavailable(
        'No imagery available: ${failure ?? 'outside source extents'}',
      );
    }
    final raster = layers.length == 1 && !layers.first.partial
        ? layers.first
        : await compute(compositeImagery, layers);
    if (cancelled) throw http.RequestAbortedException();
    return (raster: raster, providers: providers);
  }
}

/// Front-to-back alpha compositing, with the labeled green surface behind all sources.
ImageryRaster compositeImagery(List<ImageryRaster> layers) {
  final size = layers.first.size;
  final rgba = Uint8List(size * size * 4);
  var partial = false;
  for (var offset = 0; offset < rgba.length; offset += 4) {
    var remaining = 1.0, red = 0.0, green = 0.0, blue = 0.0;
    for (final layer in layers) {
      final weight = layer.rgba[offset + 3] / 255 * remaining;
      red += layer.rgba[offset] * weight;
      green += layer.rgba[offset + 1] * weight;
      blue += layer.rgba[offset + 2] * weight;
      remaining -= weight;
      if (remaining == 0) break;
    }
    if (remaining > 0) partial = true;
    rgba[offset] = (red + 154 * remaining).round().clamp(0, 255);
    rgba[offset + 1] = (green + 170 * remaining).round().clamp(0, 255);
    rgba[offset + 2] = (blue + 137 * remaining).round().clamp(0, 255);
    rgba[offset + 3] = 255;
  }
  return ImageryRaster(rgba, size, partial);
}
