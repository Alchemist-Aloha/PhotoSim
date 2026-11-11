import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/terrain_geo.dart';
import '../http_bytes.dart';
import '../raster_cache.dart';
import '../terrain/tile_cache.dart';
import 'lake_polygons.dart';
import 'river_polygons.dart';

const riverCacheKey = 'openfreemap-rivers-v1';
const riverAttribution =
    'OpenFreeMap · © OpenMapTiles · Data from © OpenStreetMap contributors, ODbL 1.0; terrain-derived river heights';
const riverEndpoint = 'https://tiles.openfreemap.org/planet';

List<LakePolygon> _decode((Uint8List, TileId) request) =>
    decodeRiverPolygons(request.$1, request.$2);

class RiverRepository {
  RiverRepository({
    required this.client,
    required Directory directory,
    RasterCache? budget,
  }) : cache = TileCache(
         Directory('${directory.path}/$riverCacheKey'),
         budget: budget,
         maxEntryBytes: 16 * 1024 * 1024,
       );
  final http.Client client;
  final TileCache cache;
  Future<String>? _template;

  Future<String> _loadTemplate(Future<void> abort) async {
    final bytes = await downloadBytes(
      client,
      Uri.parse(riverEndpoint),
      abort: abort,
      maxBytes: 256 * 1024,
    );
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map ||
        json['tiles'] is! List ||
        (json['tiles'] as List).isEmpty) {
      throw const FormatException('Invalid OpenFreeMap TileJSON');
    }
    final template = (json['tiles'] as List).first;
    if (template is! String ||
        !['{z}', '{x}', '{y}'].every(template.contains)) {
      throw const FormatException('Invalid OpenFreeMap tile template');
    }
    final uri = Uri.parse(template);
    if (uri.scheme != 'https' ||
        uri.host != 'tiles.openfreemap.org' ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.endsWith('.pbf')) {
      throw const FormatException('Invalid OpenFreeMap tile URL');
    }
    return template;
  }

  Future<List<LakePolygon>> load(
    TileId id, {
    required Future<void> abort,
  }) async {
    final cached = await cache.read(id);
    if (cached != null) {
      try {
        return await compute(_decode, (cached, id));
      } on Exception {
        await cache.remove(id);
      }
    }
    final pending = _template ??= _loadTemplate(abort);
    final String template;
    try {
      template = await pending;
    } on Object {
      if (identical(_template, pending)) _template = null;
      rethrow;
    }
    final uri = Uri.parse(
      template
          .replaceAll('{z}', '${id.z}')
          .replaceAll('{x}', '${id.x}')
          .replaceAll('{y}', '${id.y}'),
    );
    final bytes = await downloadBytes(
      client,
      uri,
      abort: abort,
      maxBytes: 16 * 1024 * 1024,
    );
    final rivers = await compute(_decode, (bytes, id));
    await cache.write(
      id,
      bytes,
      metadata: {
        'provider': 'OpenFreeMap OpenMapTiles water polygons (class=river)',
        'url': uri.toString(),
        'attribution': riverAttribution,
        'encoding': 'Mapbox Vector Tile protobuf',
        'verticalDatum': 'None; draped over loaded terrain',
      },
    );
    return rivers;
  }
}
