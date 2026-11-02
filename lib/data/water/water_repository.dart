import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/terrain_geo.dart';
import '../http_bytes.dart';
import '../imagery/imagery_provider.dart';
import '../raster_cache.dart';
import '../terrain/terrain_patch.dart';
import '../terrain/terrain_sources.dart';
import '../terrain/tile_cache.dart';
import 'water_patch.dart';
import 'lake_polygons.dart';
import 'lake_repository.dart';

const waterCacheKey = 'modis-water-2015-256-v1';
const oceanCacheKey = 'osm-coast-mask-256-v1';
const waterAttribution =
    '$lakeAttribution · NASA EOSDIS GIBS MODIS 2015 / © OpenStreetMap contributors coastlines; mean sea level';
const oceanProvider = WmsImageryProvider(
  name: 'OSM coastline land mask',
  cacheKey: oceanCacheKey,
  attribution: waterAttribution,
  endpoint: 'https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi',
  layer: 'OSM_Land_Mask',
);
const waterProvider = WmsImageryProvider(
  name: 'MODIS water mask 2015',
  cacheKey: waterCacheKey,
  attribution: waterAttribution,
  endpoint: 'https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi',
  layer: 'MODIS_Terra_L3_Land_Water_Mask',
  time: '2015-01-01',
);

WaterAtlas _estimate((TileId, Uint8List, HeightField) request) =>
    estimateWaterLevels(request.$1, request.$2, request.$3);
WaterPatch _build((WaterAtlas, TerrainPatch, TileId, LatLng) request) =>
    buildWaterPatch(request.$1, request.$2, request.$3, request.$4);

class WaterRepository {
  WaterRepository({
    required this.client,
    required this.terrain,
    required Directory directory,
    RasterCache? budget,
  }) : cache = TileCache(
         Directory('${directory.path}/$waterCacheKey'),
         budget: budget,
       ),
       oceanCache = TileCache(
         Directory('${directory.path}/$oceanCacheKey'),
         budget: budget,
       ),
       lakes = LakeRepository(
         client: client,
         directory: directory,
         budget: budget,
       );
  final http.Client client;
  final TerrainSources terrain;
  final TileCache cache, oceanCache;
  final LakeRepository lakes;
  final _atlases = <(Future<void>, String), Future<WaterAtlas>>{};

  Future<Uint8List> _mask(
    TileId id,
    Future<void> abort,
    WmsImageryProvider provider,
    TileCache cache,
    Uint8List Function(Uint8List) decode,
  ) async {
    final uri = provider.requests(id, 256).single;
    var bytes = await cache.read(id);
    Uint8List? mask;
    if (bytes != null) {
      try {
        mask = await compute(decode, bytes);
      } on Exception {
        await cache.remove(id);
      }
    }
    if (mask == null) {
      bytes = await downloadBytes(
        client,
        uri,
        abort: abort,
        maxBytes: 1024 * 1024,
      );
      mask = await compute(decode, bytes);
      await cache.write(
        id,
        bytes,
        metadata: {
          'provider': provider.name,
          'url': uri.toString(),
          'acquisitionTime': provider.time,
          'attribution': waterAttribution,
          'encoding': 'WMS mask palette PNG',
          'verticalDatum': null,
        },
      );
    }
    return mask!;
  }

  Future<WaterAtlas> _load(TileId id, Future<void> abort) async {
    List<LakePolygon>? polygons;
    try {
      polygons = await lakes.load(id, abort: abort);
    } on http.RequestAbortedException {
      rethrow;
    } on Exception {
      // Polygon outages retain the existing mask/DEM fallback, never fabricated levels.
    }
    WaterAtlas atlas;
    try {
      atlas = await _raster(id, abort, inland: polygons == null);
    } on http.RequestAbortedException {
      rethrow;
    } on Exception {
      if (polygons == null) rethrow;
      atlas = WaterAtlas(
        id,
        Float32List(256 * 256)..fillRange(0, 256 * 256, double.nan),
      );
    }
    return WaterAtlas(id, atlas.levels, lakes: polygons ?? const []);
  }

  Future<WaterAtlas> _raster(
    TileId id,
    Future<void> abort, {
    required bool inland,
  }) async {
    final waterMask = await _mask(
      id,
      abort,
      waterProvider,
      cache,
      decodeWaterMask,
    );
    if (!waterMask.contains(1)) {
      return WaterAtlas(
        id,
        Float32List(256 * 256)..fillRange(0, 256 * 256, double.nan),
      );
    }
    final ocean = await _mask(
      id,
      abort,
      oceanProvider,
      oceanCache,
      decodeOceanMask,
    );
    for (var i = 0; i < waterMask.length; i++) {
      if (waterMask[i] == 1) {
        waterMask[i] = ocean[i] == 1 ? 2 : (inland ? 1 : 0);
      }
    }
    final HeightField field;
    if (waterMask.contains(1)) {
      final dem = await terrain.load(id, id.point(0.5, 0.5), 2, abort: abort);
      field = dem.patch.field;
    } else {
      field = HeightField(Float32List(4), 2);
    }
    return compute(_estimate, (id, waterMask, field));
  }

  Future<WaterPatch> load(
    TileId id,
    TerrainPatch patch,
    LatLng origin, {
    required Future<void> abort,
  }) async {
    var cancelled = false;
    unawaited(abort.then((_) => cancelled = true));
    // shortcut: components spanning 40 km atlas boundaries are estimated separately;
    // use identified lake polygons before adding surveyed levels or large-lake precision.
    final zoom = id.z < 10 ? id.z : 10;
    final factor = 1 << (id.z - zoom);
    final atlasId = TileId(zoom, id.x ~/ factor, id.y ~/ factor);
    final key = (abort, atlasId.key);
    final future = _atlases.putIfAbsent(key, () => _load(atlasId, abort));
    WaterAtlas atlas;
    try {
      atlas = await future;
    } on Object {
      if (identical(_atlases[key], future)) {
        unawaited(_atlases.remove(key));
      }
      rethrow;
    }
    if (cancelled) throw http.RequestAbortedException();
    // Bound decoded memory; raw masks and DEMs remain in the shared disk LRU.
    while (_atlases.length > 32) {
      unawaited(_atlases.remove(_atlases.keys.first));
    }
    final result = await compute(_build, (atlas, patch, id, origin));
    if (cancelled) throw http.RequestAbortedException();
    return result;
  }
}
