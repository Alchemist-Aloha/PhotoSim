import 'dart:typed_data';
import 'dart:math' as math;

import 'lake_polygons.dart';
import 'lake_shore.dart';

import 'package:latlong2/latlong.dart';

import '../../core/terrain_geo.dart';
import '../imagery/imagery_repository.dart';
import '../terrain/terrain_patch.dart';

/// A fixed geographic atlas keeps neighboring render tiles at the same level.
class WaterAtlas {
  WaterAtlas(this.id, this.levels, {this.lakes = const []});
  final TileId id;
  final List<LakePolygon> lakes;

  /// NaN is land, missing coverage, or an uncertain/sloping water body.
  final Float32List levels;
  static const size = 256;

  double? level(double u, double v) {
    final x = (u * size).floor().clamp(0, size - 1);
    final y = (v * size).floor().clamp(0, size - 1);
    final value = levels[y * size + x];
    return value.isFinite ? value : null;
  }
}

Uint8List decodeWaterMask(Uint8List bytes) {
  final ImageryRaster raster;
  try {
    raster = decodeImagery(
      ImageryDecodeRequest(bytes, 256, retainTransparency: true),
    );
  } on ImageryUnavailable {
    return Uint8List(256 * 256);
  }
  final mask = Uint8List(256 * 256);
  for (var i = 0; i < mask.length; i++) {
    final offset = i * 4;
    if (raster.rgba[offset + 3] == 0) continue;
    // The published MODIS mask palette; never infer water from image brightness.
    if (raster.rgba[offset] != 168 ||
        raster.rgba[offset + 1] != 248 ||
        raster.rgba[offset + 2] != 255) {
      throw const FormatException('Unexpected water-mask palette');
    }
    mask[i] = 1;
  }
  return mask;
}

/// OSM's coastline-only mask includes inland lakes as land, unlike the MODIS mask.
Uint8List decodeOceanMask(Uint8List bytes) {
  final ImageryRaster raster;
  try {
    raster = decodeImagery(
      ImageryDecodeRequest(bytes, 256, retainTransparency: true),
    );
  } on ImageryUnavailable {
    return Uint8List(256 * 256)..fillRange(0, 256 * 256, 1);
  }
  final mask = Uint8List(256 * 256);
  for (var i = 0; i < mask.length; i++) {
    final o = i * 4;
    if (raster.rgba[o] != raster.rgba[o + 1] ||
        raster.rgba[o] != raster.rgba[o + 2] ||
        raster.rgba[o] > 76) {
      throw const FormatException('Unexpected coastline-mask palette');
    }
    mask[i] = raster.rgba[o + 3] < 128 ? 1 : 0;
  }
  return mask;
}

WaterAtlas estimateWaterLevels(TileId id, Uint8List mask, HeightField field) {
  const n = WaterAtlas.size;
  if (mask.length != n * n) throw const FormatException('Invalid water mask');
  final levels = Float32List(n * n)..fillRange(0, n * n, double.nan);
  final visited = Uint8List(n * n);
  bool wet(int x, int y) =>
      x >= 0 && y >= 0 && x < n && y < n && mask[y * n + x] == 1;
  for (var seed = 0; seed < mask.length; seed++) {
    if (mask[seed] == 2) {
      // Only coastline-classified ocean uses approximate mean sea level, not lake bathymetry.
      levels[seed] = 0;
      continue;
    }
    if (visited[seed] != 0 || mask[seed] == 0) continue;
    final cells = <int>[seed], heights = <double>[];
    visited[seed] = 1;
    for (var head = 0; head < cells.length; head++) {
      final cell = cells[head], x = cell % n, y = cell ~/ n;
      // Shoreline DEM samples often include land: use only interior mask pixels.
      if (wet(x - 1, y) && wet(x + 1, y) && wet(x, y - 1) && wet(x, y + 1)) {
        final height = field.sample((x + 0.5) / n, (y + 0.5) / n);
        if (height.isFinite) heights.add(height);
      }
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final nx = x + dx, ny = y + dy;
        if (!wet(nx, ny)) continue;
        final next = ny * n + nx;
        if (visited[next] == 0) {
          visited[next] = 1;
          cells.add(next);
        }
      }
    }
    if (heights.length < 4) continue;
    heights.sort();
    // No rivers or invented levels where the DEM disagrees by more than 4 m.
    if (heights[(heights.length * 0.9).floor()] -
            heights[(heights.length * 0.1).floor()] >
        4) {
      continue;
    }
    final height = heights[heights.length ~/ 2];
    // Lakes below sea level are valid and must never be clamped to the ocean level.
    for (final cell in cells) {
      levels[cell] = height;
    }
  }
  return WaterAtlas(id, levels);
}

class WaterMesh {
  final positions = <double>[], normals = <double>[], uvs = <double>[];
  final indices = <int>[];
}

class WaterPatch {
  WaterPatch(this.terrain, this.surface, this.outline);
  final TerrainPatch terrain;
  final WaterMesh surface, outline;
}

WaterPatch buildWaterPatch(
  WaterAtlas atlas,
  TerrainPatch terrain,
  TileId id,
  LatLng origin,
) {
  final frame = LocalFrame(origin);
  final topLeft = atlas.id.uv(id.point(0, 0));
  final scale = 1 / (1 << (id.z - atlas.id.z));
  final surface = WaterMesh(), outline = WaterMesh();
  double? level(double u, double v) =>
      atlas.level(topLeft.x + u * scale, topLeft.y + v * scale);
  void polygonQuad(
    WaterMesh mesh,
    List<math.Point<double>> points,
    double height,
  ) {
    final first = mesh.positions.length ~/ 3;
    for (final p in points) {
      final u = p.x, v = p.y;
      final location = id.point(u, v);
      final point = frame.project(location, height);
      final above = frame.project(location, height + 1) - point;
      above.normalize();
      mesh.positions.addAll([point.x, point.y, point.z]);
      mesh.normals.addAll([above.x, above.y, above.z]);
      mesh.uvs.addAll([u, v]);
    }
    mesh.indices.addAll([
      first,
      first + 2,
      first + 1,
      first + 1,
      first + 2,
      first + 3,
    ]);
  }

  void quad(
    WaterMesh mesh,
    double u0,
    double v0,
    double u1,
    double v1,
    double height,
  ) => polygonQuad(mesh, [
    math.Point(u0, v0),
    math.Point(u1, v0),
    math.Point(u0, v1),
    math.Point(u1, v1),
  ], height);

  for (final lake in atlas.lakes) {
    lakeSurfaceQuads(
      lake,
      id,
      (points) => polygonQuad(surface, points, lake.height + 0.05),
    );
    lakeShoreQuads(
      lake,
      id,
      (points) => polygonQuad(outline, points, lake.height + 0.08),
    );
  }
  final cells = (WaterAtlas.size * scale).round();
  // Every render tile uses the same atlas grid, so shared boundaries agree.
  for (var y = 0; y < cells; y++) {
    for (var x = 0; x < cells; x++) {
      final u = (x + 0.5) / cells, v = (y + 0.5) / cells;
      final height = level(u, v);
      if (height == null) continue;
      final u0 = x / cells, u1 = (x + 1) / cells;
      final v0 = y / cells, v1 = (y + 1) / cells;
      quad(surface, u0, v0, u1, v1, height + 0.05);
      // A narrow, water-side shore rim, never tile borders or a global sea plane.
      final rim = 0.015 / cells;
      bool shore(double a, double b) {
        final au = topLeft.x + a * scale, av = topLeft.y + b * scale;
        return au >= 0 &&
            au < 1 &&
            av >= 0 &&
            av < 1 &&
            atlas.level(au, av) == null;
      }

      if (shore(u - 1 / cells, v)) {
        quad(outline, u0, v0, u0 + rim, v1, height + 0.08);
      }
      if (shore(u + 1 / cells, v)) {
        quad(outline, u1 - rim, v0, u1, v1, height + 0.08);
      }
      if (shore(u, v - 1 / cells)) {
        quad(outline, u0, v0, u1, v0 + rim, height + 0.08);
      }
      if (shore(u, v + 1 / cells)) {
        quad(outline, u0, v1 - rim, u1, v1, height + 0.08);
      }
    }
  }
  if (surface.indices.isEmpty) return WaterPatch(terrain, surface, outline);
  final heights = Float32List.fromList(terrain.field.heights);
  final lakeHeights = lakeLevels(atlas.lakes, id, terrain.field.size);
  for (var y = 0; y < terrain.field.size; y++) {
    for (var x = 0; x < terrain.field.size; x++) {
      final index = y * terrain.field.size + x;
      final height = lakeHeights[index].isFinite
          ? lakeHeights[index]
          : level(
              (x + 0.5) / terrain.field.size,
              (y + 0.5) / terrain.field.size,
            );
      // Remove small DEM ripples beneath water, but never carve hills to fit a coarse mask.
      if (height != null && (heights[index] - height).abs() <= 4) {
        heights[index] = height - 0.15;
      }
    }
  }
  return WaterPatch(
    buildTerrainPatch(
      HeightField(heights, terrain.field.size),
      id,
      origin,
      terrain.resolution,
    ),
    surface,
    outline,
  );
}
