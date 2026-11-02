import 'dart:math' as math;

import '../../core/terrain_geo.dart';
import 'lake_polygons.dart';

/// Only original shores are outlined, never the edges introduced by tile clipping.
void lakeShoreQuads(
  LakePolygon lake,
  TileId id,
  void Function(List<math.Point<double>>) emit,
) {
  final meters =
      40075016.68557849 /
      (1 << id.z) *
      math.cos(id.point(0.5, 0.5).latitude * math.pi / 180);
  final halfWidth = 0.5 / meters;
  for (final ring in lakeTileRings(lake, id)) {
    for (var i = 1; i < ring.length; i++) {
      final a = ring[i - 1], b = ring[i];
      final dx = b.x - a.x, dy = b.y - a.y;
      var start = 0.0, end = 1.0;
      for (final (origin, delta) in [(a.x, dx), (a.y, dy)]) {
        if (delta.abs() < 1e-15) {
          if (origin < 0 || origin > 1) end = -1;
        } else {
          final t0 = -origin / delta, t1 = (1 - origin) / delta;
          start = math.max(start, math.min(t0, t1));
          end = math.min(end, math.max(t0, t1));
        }
      }
      if (end <= start) continue;
      final length = math.sqrt(dx * dx + dy * dy);
      final nx = -dy / length * halfWidth, ny = dx / length * halfWidth;
      final count = ((end - start) * length * 32).ceil();
      for (var part = 0; part < count; part++) {
        final t0 = start + (end - start) * part / count;
        final t1 = start + (end - start) * (part + 1) / count;
        final x0 = a.x + dx * t0, y0 = a.y + dy * t0;
        final x1 = a.x + dx * t1, y1 = a.y + dy * t1;
        emit([
          math.Point(x0 + nx, y0 + ny),
          math.Point(x0 - nx, y0 - ny),
          math.Point(x1 + nx, y1 + ny),
          math.Point(x1 - nx, y1 - ny),
        ]);
      }
    }
  }
}
