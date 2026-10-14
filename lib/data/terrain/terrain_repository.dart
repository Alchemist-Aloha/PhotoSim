import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/terrain_geo.dart';
import '../http_bytes.dart';
import 'terrain_patch.dart';
import 'tile_cache.dart';

class TerrainRepository {
  TerrainRepository({required this.client, required this.cache});
  final http.Client client;
  final TileCache cache;
  int cacheHits = 0, downloads = 0;

  Future<TerrainPatch> load(
    TileId id,
    LatLng origin,
    int resolution, {
    required Future<void> abort,
  }) async {
    var cancelled = false;
    abort.then((_) => cancelled = true);
    final stored = await cache.read(id);
    if (stored != null) {
      try {
        final patch = await compute(
          decodeAndBuildTerrain,
          TerrainBuildRequest(stored, id, origin, resolution),
        );
        if (cancelled) throw http.RequestAbortedException(id.uri);
        cacheHits++;
        return patch;
      } on FormatException {
        await cache.remove(id);
      }
    }
    final bytes = await downloadBytes(
      client,
      id.uri,
      abort: abort,
      maxBytes: 1024 * 1024,
    );
    final patch = await compute(
      decodeAndBuildTerrain,
      TerrainBuildRequest(bytes, id, origin, resolution),
    );
    if (cancelled) throw http.RequestAbortedException(id.uri);
    await cache.write(id, bytes);
    downloads++;
    return patch;
  }
}
