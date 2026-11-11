import 'dart:math' as math;

import '../../core/terrain_geo.dart';
import '../terrain/terrain_patch.dart';
import 'lake_polygons.dart';
import 'water_patch.dart';

/// Clip footprints to terrain triangles so sloping water cannot disappear inside the DEM.
void addRiverMeshes(
  List<LakePolygon> rivers,
  TerrainPatch terrain,
  WaterMesh surface,
) {
  final frame = LocalFrame(terrain.origin);
  double cross(math.Point<double> a, math.Point<double> b) =>
      a.x * b.y - a.y * b.x;
  int interval(List<double> axis, double value) {
    final next = axis.indexWhere((v) => v >= value);
    return (next < 0 ? axis.length - 2 : next - 1).clamp(0, axis.length - 2);
  }

  void drape(WaterMesh mesh, List<math.Point<double>> quad, double clearance) {
    final minU = quad.map((p) => p.x).reduce(math.min).clamp(0.0, 1.0);
    final maxU = quad.map((p) => p.x).reduce(math.max).clamp(0.0, 1.0);
    final minV = quad.map((p) => p.y).reduce(math.min).clamp(0.0, 1.0);
    final maxV = quad.map((p) => p.y).reduce(math.max).clamp(0.0, 1.0);
    if (minU >= maxU || minV >= maxV) return;
    for (
      var y = interval(terrain.vs, minV);
      y <= interval(terrain.vs, maxV);
      y++
    ) {
      for (
        var x = interval(terrain.us, minU);
        x <= interval(terrain.us, maxU);
        x++
      ) {
        final start = (y * (terrain.us.length - 1) + x) * 6;
        for (var t = start; t < start + 6; t += 3) {
          final indices = terrain.indices.sublist(t, t + 3);
          final triangle = [
            for (final i in indices)
              math.Point(terrain.uvs[i * 2], terrain.uvs[i * 2 + 1]),
          ];
          final a = triangle[0], ab = triangle[1] - a, ac = triangle[2] - a;
          final area = cross(ab, ac);
          if (area.abs() < 1e-15) continue;
          var polygon = [quad[0], quad[1], quad[3], quad[2]];
          for (var edge = 0; edge < 3 && polygon.isNotEmpty; edge++) {
            final p = triangle[edge], direction = triangle[(edge + 1) % 3] - p;
            double side(math.Point<double> q) =>
                cross(direction, q - p) * area.sign;
            final clipped = <math.Point<double>>[];
            var previous = polygon.last, d0 = side(previous);
            for (final current in polygon) {
              final d1 = side(current);
              if ((d0 >= 0) != (d1 >= 0)) {
                clipped.add(previous + (current - previous) * (d0 / (d0 - d1)));
              }
              if (d1 >= 0) clipped.add(current);
              previous = current;
              d0 = d1;
            }
            polygon = clipped;
          }
          if (polygon.length < 3) continue;
          final first = mesh.positions.length ~/ 3;
          for (final p in polygon) {
            final b = cross(p - a, ac) / area, c = cross(ab, p - a) / area;
            final weights = [1 - b - c, b, c];
            final location = terrain.id.point(p.x, p.y);
            final up = frame.project(location, 1) - frame.project(location, 0);
            up.normalize();
            for (var axis = 0; axis < 3; axis++) {
              var coordinate = up[axis] * clearance;
              for (var j = 0; j < 3; j++) {
                coordinate +=
                    terrain.positions[indices[j] * 3 + axis] * weights[j];
              }
              mesh.positions.add(coordinate);
              mesh.normals.add(up[axis]);
            }
            mesh.uvs.addAll([p.x, p.y]);
          }
          for (var i = 1; i < polygon.length - 1; i++) {
            // UV's southward axis is reversed in the local ground plane.
            mesh.indices.addAll([first, first + i + 1, first + i]);
          }
        }
      }
    }
  }

  for (final river in rivers) {
    lakeSurfaceQuads(river, terrain.id, (p) => drape(surface, p, 0.08));
    // Vector tiles split rivers internally; outlining their edges invents banks.
  }
}
