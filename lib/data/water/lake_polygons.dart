import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/terrain_geo.dart';

List<LakeEdge> _tileEdges(LakePolygon lake, TileId id) =>
    _edges(lakeTileRings(lake, id))
        .where(
          (e) => math.min(e.$1.y, e.$2.y) <= 1 && math.max(e.$1.y, e.$2.y) >= 0,
        )
        .toList();

/// Full lake geometry and one dataset elevation, independent of render/atlas tiles.
class LakePolygon {
  LakePolygon(this.id, this.height, this.rings);
  final int id;
  final double height;
  final List<List<math.Point<double>>> rings;
  late final _curvedRings = rings.map(_curveRing).toList();
}

List<LakePolygon> decodeLakePolygons(Uint8List bytes) {
  final json = jsonDecode(utf8.decode(bytes));
  if (json is! Map<String, dynamic> ||
      json['type'] != 'FeatureCollection' ||
      json['exceededTransferLimit'] == true ||
      json['features'] is! List) {
    throw const FormatException('Invalid or truncated lake polygons');
  }
  final features = json['features'] as List;
  if (features.length >= 2000) throw const FormatException('Too many lakes');
  final lakes = <LakePolygon>[];
  var vertices = 0;
  for (final feature in features) {
    if (feature is! Map) throw const FormatException('Invalid lake feature');
    final properties = feature['properties'], geometry = feature['geometry'];
    if (properties is! Map || geometry is! Map) {
      throw const FormatException('Missing lake properties or geometry');
    }
    final id = properties['hylak_id'], height = properties['elevation'];
    if (id is! int || id <= 0) throw const FormatException('Invalid lake ID');
    // Missing elevations cannot safely establish a shared surface level.
    if (height == null || height == -9999) continue;
    if (height is! num ||
        !height.isFinite ||
        height < -12000 ||
        height > 10000) {
      throw const FormatException('Invalid lake elevation');
    }
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) {
      throw const FormatException('Invalid lake coordinates');
    }
    final List<dynamic> polygons;
    if (geometry['type'] == 'Polygon') {
      polygons = [coordinates];
    } else if (geometry['type'] == 'MultiPolygon') {
      polygons = coordinates;
    } else {
      throw const FormatException('Expected lake polygon');
    }
    for (final polygon in polygons) {
      if (polygon is! List || polygon.isEmpty) {
        throw const FormatException('Empty lake polygon');
      }
      final rings = <List<math.Point<double>>>[];
      for (final ring in polygon) {
        if (ring is! List || ring.length < 4) {
          throw const FormatException('Invalid lake ring');
        }
        final points = <math.Point<double>>[];
        for (final coordinate in ring) {
          if (++vertices > 250000 ||
              coordinate is! List ||
              coordinate.length < 2) {
            throw const FormatException('Invalid or oversized lake geometry');
          }
          final x = coordinate[0], y = coordinate[1];
          if (x is! num ||
              y is! num ||
              !x.isFinite ||
              !y.isFinite ||
              x.abs() > 180 ||
              y.abs() > 85.051129) {
            throw const FormatException('Invalid lake coordinate');
          }
          points.add(math.Point(x.toDouble(), y.toDouble()));
        }
        if (points.first != points.last) {
          throw const FormatException('Unclosed lake ring');
        }
        rings.add(points);
      }
      lakes.add(LakePolygon(id, height.toDouble(), rings));
    }
  }
  return lakes;
}

// Round corners in world coordinates so adjacent tiles and mesh LODs share one curve.
List<math.Point<double>> _curveRing(List<math.Point<double>> ring) {
  final points = <math.Point<double>>[];
  for (final point in ring) {
    final radians = point.y * math.pi / 180;
    final projected = math.Point(
      (point.x + 180) / 360,
      (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) / 2,
    );
    if (points.isEmpty || points.last != projected) points.add(projected);
  }
  if (points.length > 1 && points.first == points.last) points.removeLast();
  if (points.length < 3) {
    return [...points, if (points.isNotEmpty) points.first];
  }
  final curved = <math.Point<double>>[];
  for (var i = 0; i < points.length; i++) {
    final b = points[i];
    final incoming = points[(i + points.length - 1) % points.length] - b;
    final outgoing = points[(i + 1) % points.length] - b;
    final latitude =
        2 * math.atan(math.exp((0.5 - b.y) * 2 * math.pi)) - math.pi / 2;
    final meters = 40075016.68557849 * math.cos(latitude);
    // Short edges retain half their straight span; cutbacks never exceed 10 m.
    final trim = math.min(
      10 / meters,
      math.min(incoming.magnitude, outgoing.magnitude) / 4,
    );
    final a = b + incoming * (trim / incoming.magnitude);
    final c = b + outgoing * (trim / outgoing.magnitude);
    final bend = (a - b + c - b).magnitude * meters / 4;
    if (bend < 0.02) {
      curved.add(b);
      continue;
    }
    // Quadratic Bezier segments stay inside the corner's control triangle (no spline overshoot).
    final steps = math.sqrt(bend / 0.02).ceil().clamp(2, 16);
    for (var step = 0; step <= steps; step++) {
      final t = step / steps, s = 1 - t;
      curved.add(a * (s * s) + b * (2 * s * t) + c * (t * t));
    }
  }
  return [...curved, curved.first];
}

/// Project shared curves without wrapping longitudes around the camera.
List<List<math.Point<double>>> lakeTileRings(LakePolygon lake, TileId id) {
  final n = (1 << id.z).toDouble();
  return [
    for (final ring in lake._curvedRings)
      [for (final p in ring) math.Point(p.x * n - id.x, p.y * n - id.y)],
  ];
}

typedef LakeEdge = (math.Point<double>, math.Point<double>);
List<LakeEdge> _edges(List<List<math.Point<double>>> rings) => [
  for (final ring in rings)
    for (var i = 1; i < ring.length; i++) (ring[i - 1], ring[i]),
];

double _x(LakeEdge edge, double y) =>
    edge.$1.x +
    (y - edge.$1.y) / (edge.$2.y - edge.$1.y) * (edge.$2.x - edge.$1.x);

List<LakeEdge> _crossings(List<LakeEdge> edges, double y) =>
    edges
        .where(
          (edge) =>
              (edge.$1.y <= y && edge.$2.y > y) ||
              (edge.$2.y <= y && edge.$1.y > y),
        )
        .toList()
      ..sort((a, b) => _x(a, y).compareTo(_x(b, y)));

/// Even/odd filling preserves islands, independent of ring winding.
Float32List lakeLevels(
  List<LakePolygon> lakes,
  TileId id,
  int size, {
  double padding = 0,
}) {
  final levels = Float32List(size * size)
    ..fillRange(0, size * size, double.nan);
  for (final lake in lakes) {
    final edges = _tileEdges(lake, id);
    for (var y = 0; y < size; y++) {
      final v = (y + 0.5) / size,
          crossings = _crossings(edges, (y + 0.5) / size);
      for (var i = 1; i < crossings.length; i += 2) {
        final start = (_x(crossings[i - 1], v) * size - 0.5).ceil().clamp(
          0,
          size,
        );
        final end = (_x(crossings[i], v) * size - 0.5).ceil().clamp(0, size);
        levels.fillRange(y * size + start, y * size + end, lake.height);
      }
    }
    if (padding == 0) continue;
    // Clear the terrain's interpolation footprint, not just water pixel centers.
    for (final (a, b) in _edges(lakeTileRings(lake, id))) {
      final first = ((math.min(a.y, b.y) - padding) * size - 0.5).ceil().clamp(
        0,
        size,
      );
      final last = ((math.max(a.y, b.y) + padding) * size - 0.5).floor().clamp(
        -1,
        size - 1,
      );
      for (var y = first; y <= last; y++) {
        final v = (y + 0.5) / size;
        final dy = b.y - a.y;
        final t0 = dy == 0 ? 0.0 : ((v - padding - a.y) / dy).clamp(0.0, 1.0);
        final t1 = dy == 0 ? 1.0 : ((v + padding - a.y) / dy).clamp(0.0, 1.0);
        final x0 = a.x + (b.x - a.x) * t0;
        final x1 = a.x + (b.x - a.x) * t1;
        final start = ((math.min(x0, x1) - padding) * size - 0.5).ceil().clamp(
          0,
          size,
        );
        final end = ((math.max(x0, x1) + padding) * size - 0.5).ceil().clamp(
          0,
          size,
        );
        levels.fillRange(y * size + start, y * size + end, lake.height);
      }
    }
  }
  return levels;
}

/// Curved shoreline edges with grid subdivision to retain Earth curvature.
/// Adding vertex and tile-edge intersection rows keeps topology fixed within a strip.
void lakeSurfaceQuads(
  LakePolygon lake,
  TileId id,
  void Function(List<math.Point<double>>) emit,
) {
  final edges = _tileEdges(lake, id);
  final rows = <double>{for (var i = 0; i <= 32; i++) i / 32};
  for (final edge in edges) {
    for (final p in [edge.$1, edge.$2]) {
      if (p.x >= 0 && p.x <= 1 && p.y > 0 && p.y < 1) rows.add(p.y);
    }
    for (final x in [0.0, 1.0]) {
      final dx = edge.$2.x - edge.$1.x;
      if (dx == 0) continue;
      final t = (x - edge.$1.x) / dx;
      final y = edge.$1.y + t * (edge.$2.y - edge.$1.y);
      if (t > 0 && t < 1 && y > 0 && y < 1) rows.add(y);
    }
  }
  final sorted = rows.toList()..sort();
  for (var row = 1; row < sorted.length; row++) {
    final top = sorted[row - 1], bottom = sorted[row];
    if (bottom - top < 1e-12) continue;
    final crossings = _crossings(edges, (top + bottom) / 2);
    for (var i = 1; i < crossings.length; i += 2) {
      final left = crossings[i - 1], right = crossings[i];
      final a = _x(left, top).clamp(0.0, 1.0),
          b = _x(right, top).clamp(0.0, 1.0);
      final c = _x(left, bottom).clamp(0.0, 1.0),
          d = _x(right, bottom).clamp(0.0, 1.0);
      final count = (math.max(b - a, d - c) * 32).ceil();
      for (var part = 0; part < count; part++) {
        final u = part / count, v = (part + 1) / count;
        emit([
          math.Point(a + (b - a) * u, top),
          math.Point(a + (b - a) * v, top),
          math.Point(c + (d - c) * u, bottom),
          math.Point(c + (d - c) * v, bottom),
        ]);
      }
    }
  }
}
