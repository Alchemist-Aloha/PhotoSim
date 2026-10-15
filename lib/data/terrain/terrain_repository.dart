import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/terrain_geo.dart';
import '../http_bytes.dart';
import 'terrain_patch.dart';
import 'terrain_provider.dart';
import 'tile_cache.dart';

class TerrainRepository {
  TerrainRepository({
    required this.client,
    required this.cache,
    this.provider = TerrainProvider.mapzen,
  });
  final http.Client client;
  final TileCache cache;
  final TerrainProvider provider;
  int cacheHits = 0, downloads = 0;

  Future<TerrainPatch> load(
    TileId id,
    LatLng origin,
    int resolution, {
    required Future<void> abort,
    TileId? rasterId,
  }) async {
    rasterId ??= id;
    final uri = provider.request(rasterId);
    var cancelled = false;
    abort.then((_) => cancelled = true);
    final stored = await cache.read(rasterId);
    if (stored != null) {
      try {
        final patch = await compute(
          decodeAndBuildTerrain,
          TerrainBuildRequest(
            stored,
            id,
            origin,
            resolution,
            provider: provider,
            rasterId: rasterId,
          ),
        );
        if (cancelled) throw http.RequestAbortedException(uri);
        cacheHits++;
        return patch;
      } on FormatException {
        await cache.remove(rasterId);
      }
    }
    final bytes = await downloadBytes(
      client,
      uri,
      abort: abort,
      maxBytes: 1024 * 1024,
    );
    final patch = await compute(
      decodeAndBuildTerrain,
      TerrainBuildRequest(
        bytes,
        id,
        origin,
        resolution,
        provider: provider,
        rasterId: rasterId,
      ),
    );
    if (cancelled) throw http.RequestAbortedException(uri);
    await cache.write(
      rasterId,
      bytes,
      metadata: {
        'provider': provider.label,
        'url': uri.toString(),
        'attribution': provider.attribution,
        'pixels': provider.pixels,
        'horizontalCrs': 'EPSG:3857',
        'encoding': provider == TerrainProvider.mapterhorn
            ? 'Terrarium lossless WebP'
            : 'Terrarium PNG',
        'acquisitionTimeNote': 'Blended source dates vary; not queried',
      },
    );
    downloads++;
    return patch;
  }
}
