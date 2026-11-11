import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/terrain_geo.dart';
import 'lake_polygons.dart';

/// Only OpenMapTiles' water polygons classified as river, never waterway lines.
List<LakePolygon> decodeRiverPolygons(Uint8List bytes, TileId id) {
  if (bytes.length > 16 * 1024 * 1024) {
    throw const FormatException('Oversized river tile');
  }
  final rivers = <LakePolygon>[];
  var vertices = 0;
  for (final (field, wire, value) in _Pbf(bytes).fields()) {
    if (field != 3 || wire != 2) continue;
    String? name;
    var extent = 4096, version = 1;
    final keys = <String>[], values = <String?>[], features = <Uint8List>[];
    for (final (field, wire, value) in _Pbf(value as Uint8List).fields()) {
      switch ((field, wire)) {
        case (1, 2):
          name = utf8.decode(value as Uint8List);
        case (2, 2):
          features.add(value as Uint8List);
        case (3, 2):
          keys.add(utf8.decode(value as Uint8List));
        case (4, 2):
          String? text;
          for (final (field, wire, value) in _Pbf(
            value as Uint8List,
          ).fields()) {
            if (field == 1 && wire == 2) text = utf8.decode(value as Uint8List);
          }
          values.add(text);
        case (5, 0):
          extent = value as int;
        case (15, 0):
          version = value as int;
      }
    }
    if (name != 'water') continue;
    if (extent < 1 ||
        extent > 65536 ||
        version != 2 ||
        features.length > 10000) {
      throw const FormatException('Invalid river tile layer');
    }
    for (final feature in features) {
      var featureId = rivers.length, type = 0;
      final tags = <int>[], commands = <int>[];
      for (final (field, wire, value) in _Pbf(feature).fields()) {
        switch ((field, wire)) {
          case (1, 0):
            featureId = value as int;
          case (2, 2):
            tags.addAll(_Pbf(value as Uint8List).packed());
          case (3, 0):
            type = value as int;
          case (4, 2):
            commands.addAll(_Pbf(value as Uint8List).packed());
        }
      }
      if (tags.length.isOdd) throw const FormatException('Invalid river tags');
      String? classification, brunnel;
      for (var i = 0; i < tags.length; i += 2) {
        if (tags[i] >= keys.length || tags[i + 1] >= values.length) {
          throw const FormatException('Invalid river tag index');
        }
        if (keys[tags[i]] == 'class') classification = values[tags[i + 1]];
        if (keys[tags[i]] == 'brunnel') brunnel = values[tags[i + 1]];
      }
      if (type != 3 || classification != 'river' || brunnel == 'tunnel') {
        continue;
      }
      final rings = <List<math.Point<double>>>[];
      List<math.Point<double>>? ring;
      var x = 0, y = 0, cursor = 0;
      while (cursor < commands.length) {
        final command = commands[cursor++],
            op = command & 7,
            count = command >> 3;
        if (count == 0) throw const FormatException('Empty river command');
        if (op == 7) {
          if (count != 1 || ring == null || ring.toSet().length < 3) {
            throw const FormatException('Invalid river ring');
          }
          ring.add(ring.first);
          rings.add(ring);
          ring = null;
          continue;
        }
        if ((op != 1 && op != 2) ||
            (op == 1 && (count != 1 || ring != null)) ||
            (op == 2 && ring == null) ||
            count > (commands.length - cursor) ~/ 2) {
          throw const FormatException('Invalid river geometry command');
        }
        if (op == 1) ring = <math.Point<double>>[];
        for (var i = 0; i < count; i++) {
          final dx = commands[cursor++], dy = commands[cursor++];
          x += (dx >> 1) ^ -(dx & 1);
          y += (dy >> 1) ^ -(dy & 1);
          if (++vertices > 250000 ||
              x.abs() > extent * 16 ||
              y.abs() > extent * 16) {
            throw const FormatException('Invalid or oversized river geometry');
          }
          final point = id.point(x / extent, y / extent);
          ring!.add(math.Point(point.longitude, point.latitude));
        }
      }
      if (ring != null || rings.isEmpty) {
        throw const FormatException('Unclosed river geometry');
      }
      rivers.add(LakePolygon.tiled(featureId, rings));
    }
  }
  return rivers;
}

/// Bounded protobuf reader; unknown fields/layers are skipped without a dependency.
class _Pbf {
  _Pbf(this.bytes);
  final Uint8List bytes;
  var offset = 0;

  int integer() {
    var result = 0;
    for (var shift = 0; shift < 63 && offset < bytes.length; shift += 7) {
      final byte = bytes[offset++];
      result |= (byte & 127) << shift;
      if (byte < 128) return result;
    }
    throw const FormatException('Truncated or oversized protobuf integer');
  }

  Iterable<int> packed() sync* {
    while (offset < bytes.length) {
      yield integer();
    }
  }

  Iterable<(int, int, Object)> fields() sync* {
    while (offset < bytes.length) {
      final tag = integer(), field = tag >> 3, wire = tag & 7;
      if (field == 0) throw const FormatException('Invalid protobuf field');
      if (wire == 0) {
        yield (field, wire, integer());
      } else {
        final length = switch (wire) {
          1 => 8,
          2 => integer(),
          5 => 4,
          _ => throw const FormatException('Invalid protobuf wire type'),
        };
        if (length > bytes.length - offset) {
          throw const FormatException('Truncated protobuf field');
        }
        final value = Uint8List.sublistView(bytes, offset, offset + length);
        offset += length;
        yield (field, wire, value);
      }
    }
  }
}
