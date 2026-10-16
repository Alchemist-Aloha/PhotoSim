import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/terrain_geo.dart';
import 'terrain_patch.dart';
import 'terrain_provider.dart';
import 'terrain_repository.dart';
import 'tile_cache.dart';
import '../raster_cache.dart';

class TerrainSources {
  TerrainSources({
    required http.Client client,
    required Directory directory,
    RasterCache? budget,
  }) : sources = [
         for (final provider in TerrainProvider.values)
           TerrainRepository(
             client: client,
             provider: provider,
             cache: TileCache(
               Directory('${directory.path}/${provider.cacheKey}'),
               maxBytes: 128 * 1024 * 1024,
               budget: budget,
             ),
           ),
       ];

  final List<TerrainRepository> sources;
  int get cacheHits => sources.fold(0, (sum, source) => sum + source.cacheHits);
  int get downloads => sources.fold(0, (sum, source) => sum + source.downloads);
  String? get cacheWarning {
    for (final source in sources) {
      if (source.cache.warning != null) return source.cache.warning;
    }
    return null;
  }

  Future<({TerrainPatch patch, TerrainProvider provider, TileId rasterId})>
  load(
    TileId id,
    LatLng origin,
    int resolution, {
    required Future<void> abort,
  }) async {
    if (id.z > 13) {
      throw ArgumentError('Terrain zoom must not exceed 13');
    }
    var cancelled = false;
    unawaited(abort.then((_) => cancelled = true));
    final primary = sources.first;
    final parent = id.z == 13 ? TileId(12, id.x ~/ 2, id.y ~/ 2) : null;
    final preferParent =
        parent != null &&
        await primary.cache.read(id) == null &&
        await primary.cache.read(parent) != null;
    final candidates = [
      (primary, preferParent ? parent : id),
      if (parent != null) (primary, preferParent ? id : parent),
      (sources.last, id),
    ];
    Exception? failure;
    for (final (source, rasterId) in candidates) {
      if (cancelled) throw http.RequestAbortedException();
      try {
        final patch = await source.load(
          id,
          origin,
          resolution,
          abort: abort,
          rasterId: rasterId,
        );
        if (cancelled) throw http.RequestAbortedException();
        return (patch: patch, provider: source.provider, rasterId: rasterId);
      } on Exception catch (error) {
        if (cancelled) throw http.RequestAbortedException();
        failure = error;
      }
    }
    throw http.ClientException('All terrain sources unavailable: $failure');
  }
}
