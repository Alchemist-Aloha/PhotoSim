import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/terrain_geo.dart';
import '../http_bytes.dart';
import '../raster_cache.dart';
import '../terrain/tile_cache.dart';
import 'lake_polygons.dart';

const lakeCacheKey = 'hydrolakes-v10-polygons-v1';
const lakeAttribution =
    'HydroLAKES v1.0 · Messager et al. (2016), CC BY 4.0; estimated static lake elevations';
const lakeEndpoint =
    'https://data-gis.unep-wcmc.org/server/rest/services/Oceanplus/_Global_lake_distribution_of_HydroLAKES_McGill_University/MapServer/0/query';

Uri lakeQuery(TileId id) {
  final nw = id.point(0, 0), se = id.point(1, 1);
  return Uri.parse(lakeEndpoint).replace(
    queryParameters: {
      'f': 'geojson',
      'where': '1=1',
      'geometry':
          '${nw.longitude},${se.latitude},${se.longitude},${nw.latitude}',
      'geometryType': 'esriGeometryEnvelope',
      'inSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': 'hylak_id,lake_name,elevation',
      'outSR': '4326',
      'returnGeometry': 'true',
      'resultRecordCount': '2000',
    },
  );
}

class LakeRepository {
  LakeRepository({
    required this.client,
    required Directory directory,
    RasterCache? budget,
  }) : cache = TileCache(
         Directory('${directory.path}/$lakeCacheKey'),
         budget: budget,
         maxEntryBytes: 16 * 1024 * 1024,
       );
  final http.Client client;
  final TileCache cache;
  final _pending = <(Future<void>, String), Future<List<LakePolygon>>>{};

  Future<List<LakePolygon>> _load(TileId id, Future<void> abort) async {
    final cached = await cache.read(id);
    if (cached != null) {
      try {
        return await compute(decodeLakePolygons, cached);
      } on Exception {
        await cache.remove(id);
      }
    }
    final uri = lakeQuery(id);
    final Uint8List bytes = await downloadBytes(
      client,
      uri,
      abort: abort,
      maxBytes: 16 * 1024 * 1024,
    );
    final lakes = await compute(decodeLakePolygons, bytes);
    await cache.write(
      id,
      bytes,
      metadata: {
        'provider': 'HydroLAKES v1.0 via UNEP-WCMC',
        'url': uri.toString(),
        'attribution': lakeAttribution,
        'encoding': 'GeoJSON full lake polygons',
        'verticalDatum': 'Dataset pour-point elevation; uncorrected',
      },
    );
    return lakes;
  }

  Future<List<LakePolygon>> load(
    TileId id, {
    required Future<void> abort,
  }) async {
    final key = (abort, id.key);
    final future = _pending.putIfAbsent(key, () => _load(id, abort));
    try {
      final result = await future;
      while (_pending.length > 32) {
        unawaited(_pending.remove(_pending.keys.first));
      }
      return result;
    } on Object {
      if (identical(_pending[key], future)) unawaited(_pending.remove(key));
      rethrow;
    }
  }
}
