import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'geo.dart';

class Constellation {
  const Constellation(this.name, this.anchor, this.lines);
  final String name;

  /// J2000 equatorial unit vectors.
  final Vector3 anchor;
  final List<List<Vector3>> lines;
}

List<Constellation> parseConstellations(String source) {
  final rows = jsonDecode(source);
  if (rows is! List || rows.isEmpty || rows.length > 100) {
    throw const FormatException('Invalid constellation catalog');
  }
  Vector3 point(dynamic p) {
    if (p is! List ||
        p.length != 2 ||
        p.any((n) => n is! num || !n.isFinite) ||
        p[0].abs() > 180 ||
        p[1].abs() > 90) {
      throw const FormatException('Invalid constellation coordinate');
    }
    final ra = p[0] * radians, dec = p[1] * radians;
    return Vector3(
      math.cos(dec) * math.cos(ra),
      math.cos(dec) * math.sin(ra),
      math.sin(dec),
    );
  }

  return rows
      .map((row) {
        if (row is! List ||
            row.length != 4 ||
            row[0] is! String ||
            row[0].trim().isEmpty ||
            row[0].length > 80 ||
            row[3] is! List ||
            row[3].isEmpty) {
          throw const FormatException('Invalid constellation row');
        }
        final lines = (row[3] as List)
            .map((line) {
              if (line is! List || line.length < 2 || line.length > 100) {
                throw const FormatException('Invalid constellation line');
              }
              return line.map(point).toList(growable: false);
            })
            .toList(growable: false);
        return Constellation(row[0], point([row[1], row[2]]), lines);
      })
      .toList(growable: false);
}

/// Thin great-circle ribbons rather than straight chords through the sky sphere.
({Float32List positions, List<int> indices}) constellationMesh(
  List<Constellation> catalog,
) {
  const distance = 39800.0, halfWidth = distance * 0.0007;
  final positions = <double>[], indices = <int>[];
  for (final constellation in catalog) {
    for (final line in constellation.lines) {
      for (var i = 1; i < line.length; i++) {
        final a = line[i - 1], b = line[i];
        final cross = a.cross(b);
        if (cross.length < 1e-9) continue;
        final side = cross.normalized() * halfWidth;
        final steps = (math.acos(a.dot(b).clamp(-1.0, 1.0)) / (2 * radians))
            .ceil();
        for (var j = 0; j < steps; j++) {
          Vector3 at(double t) => (a * (1 - t) + b * t).normalized() * distance;
          final start = at(j / steps), end = at((j + 1) / steps);
          final vertex = positions.length ~/ 3;
          for (final p in [
            start - side,
            start + side,
            end - side,
            end + side,
          ]) {
            positions.addAll([p.x, p.y, p.z]);
          }
          indices.addAll([
            vertex,
            vertex + 1,
            vertex + 2,
            vertex + 1,
            vertex + 3,
            vertex + 2,
          ]);
        }
      }
    }
  }
  return (positions: Float32List.fromList(positions), indices: indices);
}
