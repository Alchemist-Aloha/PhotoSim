import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/simulation_state.dart';
import 'geo.dart';
import 'terrain_geo.dart';

const terrainTileBudget = 256;

int terrainMeshResolution(TileId id, TileId center, RenderQuality quality) {
  final base = id.key == center.key ? 128 : (id.z == 13 ? 64 : 32);
  return quality == RenderQuality.high ? base * 2 : base;
}

/// Nominal circular envelope: nearby tile corners or the requested forward reach.
/// Coarse forward tiles can extend beyond it; this is not an exact fetch boundary.
double approximateTerrainLoadingRadius(SimulationState state) {
  final camera = TileId.coordinates(state.location, 13);
  final x = camera.x - camera.x.floor(), y = camera.y - camera.y.floor();
  final dx = state.terrainRings + math.max(x, 1 - x);
  final dy = state.terrainRings + math.max(y, 1 - y);
  final tileMeters =
      2 * math.pi * 6378137 / 8192 * math.cos(state.latitude * radians);
  return math.max(
    math.sqrt(dx * dx + dy * dy) * tileMeters,
    state.terrainForwardKm * 1000,
  );
}

List<LatLng> terrainLoadingCircle(SimulationState state) {
  final radius = approximateTerrainLoadingRadius(state);
  final points = List.generate(96, (i) {
    final point = destination(state.location, i * 360 / 96, radius);
    // Keep the circle continuous when it crosses the date line.
    final longitude =
        state.longitude + (point.longitude - state.longitude + 540) % 360 - 180;
    return LatLng(point.latitude, longitude);
  });
  return [...points, points.first];
}

/// Nearby z13 rings plus the horizontal envelope of the pitched optical frustum.
List<TileId> terrainCoverage(SimulationState state) {
  final center = TileId.at(state.location);
  final camera = TileId.coordinates(state.location, 13);
  final rings = state.terrainRings;
  final near = (
    center.x - rings.toDouble(),
    center.y - rings.toDouble(),
    center.x + rings + 1.0,
    center.y + rings + 1.0,
  );
  // shortcut: observer-scale Mercator envelope, use terrain-aware ENU selection for precision horizons.
  final tileMeters =
      2 * math.pi * 6378137 / 8192 * math.cos(state.latitude * radians);
  final reach = state.terrainForwardKm * 1000 / tileMeters;
  final pitch = state.pitch * radians;
  final along =
      math.cos(pitch) - math.sin(pitch).abs() * state.verticalFrustumExtent;
  // If the frustum includes zenith/nadir, its horizontal projection spans every azimuth.
  final halfAngle = along <= 0
      ? math.pi
      : math.atan(state.horizontalFrustumExtent / along);
  // Circumscribe the range arc so polygon chords cannot cut requested coverage short.
  final arcReach = reach / math.cos(halfAngle / 32);
  final sector = <math.Point<double>>[
    if (along > 0 || reach == 0) math.Point(camera.x, camera.y),
    if (reach > 0)
      for (var i = 0; i <= 32; i++)
        math.Point(
          camera.x +
              arcReach *
                  math.sin(
                    state.azimuth * radians - halfAngle + i * halfAngle / 16,
                  ),
          camera.y -
              arcReach *
                  math.cos(
                    state.azimuth * radians - halfAngle + i * halfAngle / 16,
                  ),
        ),
  ];
  final west = math.min(near.$1, sector.map((p) => p.x).reduce(math.min));
  final north = math.min(near.$2, sector.map((p) => p.y).reduce(math.min));
  final east = math.max(near.$3, sector.map((p) => p.x).reduce(math.max));
  final south = math.max(near.$4, sector.map((p) => p.y).reduce(math.max));
  var rootSpan = 1, rootZoom = 13;
  while (((east - west) / rootSpan + 2) * ((south - north) / rootSpan + 2) >
      16) {
    rootSpan *= 2;
    rootZoom--;
  }

  List<TileId> select(double detail) {
    final tiles = <TileId>[];
    void visit(int x, int y, int span, int zoom) {
      if (y < 0 || y >= 8192) return;
      final box = (
        x.toDouble(),
        y.toDouble(),
        (x + span).toDouble(),
        (y + span).toDouble(),
      );
      final nearby =
          box.$1 < near.$3 &&
          box.$3 > near.$1 &&
          box.$2 < near.$4 &&
          box.$4 > near.$2;
      if (!nearby && (reach == 0 || !_intersects(box, sector))) return;
      final dx = camera.x - camera.x.clamp(box.$1, box.$3);
      final dy = camera.y - camera.y.clamp(box.$2, box.$4);
      final distance = math.sqrt(dx * dx + dy * dy);
      if (span > 1 && (nearby || span * detail > math.max(1.0, distance))) {
        final half = span ~/ 2;
        for (final offset in [(0, 0), (half, 0), (0, half), (half, half)]) {
          visit(x + offset.$1, y + offset.$2, half, zoom + 1);
        }
      } else {
        tiles.add(TileId(zoom, (x ~/ span) % (1 << zoom), y ~/ span));
      }
    }

    for (
      var y = (north / rootSpan).floor() * rootSpan;
      y < south;
      y += rootSpan
    ) {
      for (
        var x = (west / rootSpan).floor() * rootSpan;
        x < east;
        x += rootSpan
      ) {
        visit(x, y, rootSpan, rootZoom);
      }
    }
    return tiles;
  }

  var detail = 2 / math.tan(state.horizontalFov / 2);
  var tiles = select(detail);
  // Coarsen distant coverage rather than truncate the requested reach or overrun the tile budget.
  while (tiles.length > terrainTileBudget) {
    detail = detail > 0.25 ? detail / 2 : 0;
    tiles = select(detail);
    if (detail == 0) break;
  }
  tiles.sort((a, b) {
    if (a.key == b.key) return 0;
    if (a.key == center.key) return -1;
    if (b.key == center.key) return 1;
    return terrainDistance(
      a,
      state.location,
    ).compareTo(terrainDistance(b, state.location));
  });
  return tiles;
}

/// Whole-tile render cutoff, preserving tiles intersecting the requested radius.
double terrainDistance(TileId tile, LatLng origin) {
  final uv = tile.uv(origin);
  final nearest = tile.point(uv.x.clamp(0.0, 1.0), uv.y.clamp(0.0, 1.0));
  return const Distance().as(LengthUnit.Meter, origin, nearest);
}

bool _intersects(
  (double, double, double, double) box,
  List<math.Point<double>> polygon,
) {
  final corners = [
    math.Point(box.$1, box.$2),
    math.Point(box.$3, box.$2),
    math.Point(box.$3, box.$4),
    math.Point(box.$1, box.$4),
  ];
  final axes = <math.Point<double>>[
    const math.Point(1, 0),
    const math.Point(0, 1),
  ];
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    axes.add(math.Point(a.y - b.y, b.x - a.x));
  }
  for (final axis in axes) {
    double dot(math.Point<double> p) => p.x * axis.x + p.y * axis.y;
    final p = polygon.map(dot), b = corners.map(dot);
    if (p.reduce(math.max) < b.reduce(math.min) ||
        b.reduce(math.max) < p.reduce(math.min)) {
      return false;
    }
  }
  return true;
}
