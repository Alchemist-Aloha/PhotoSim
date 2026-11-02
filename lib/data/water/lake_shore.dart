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
    math.Point<double> offset(int index) {
      final count = ring.length - 1;
      final p = ring[index % count];
      final a = p - ring[(index + count - 1) % count];
      final b = ring[(index + 1) % count] - p;
      if (a.magnitude == 0 || b.magnitude == 0) return const math.Point(0, 0);
      final na = math.Point(-a.y, a.x) * (1 / a.magnitude);
      final nb = math.Point(-b.y, b.x) * (1 / b.magnitude);
      final miter = na + nb;
      final denominator = miter.x * nb.x + miter.y * nb.y;
      if (denominator < 1e-8) return nb * halfWidth;
      // Shared, bounded miter joins avoid gaps and spikes between curve segments.
      return miter *
          math.min(halfWidth / denominator, 2 * halfWidth / miter.magnitude);
    }

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
      final na = offset(i - 1), nb = offset(i);
      final count = ((end - start) * length * 32).ceil();
      for (var part = 0; part < count; part++) {
        final t0 = start + (end - start) * part / count;
        final t1 = start + (end - start) * (part + 1) / count;
        final x0 = a.x + dx * t0, y0 = a.y + dy * t0;
        final x1 = a.x + dx * t1, y1 = a.y + dy * t1;
        final p = math.Point(x0, y0), q = math.Point(x1, y1);
        final n0 = na * (1 - t0) + nb * t0;
        final n1 = na * (1 - t1) + nb * t1;
        emit([p + n0, p - n0, q + n1, q - n1]);
      }
    }
  }
}
