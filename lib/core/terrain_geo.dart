import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import 'geo.dart';

/// Web Mercator XYZ tile. X wraps across the dateline; Y does not.
class TileId {
  TileId(this.z, this.x, this.y) {
    if (z < 0 || z > 15 || x < 0 || y < 0 || x >= 1 << z || y >= 1 << z) {
      throw ArgumentError('Invalid terrain tile');
    }
  }
  final int z, x, y;
  String get key => '$z-$x-$y';
  Uri get uri => Uri.parse(
    'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$z/$x/$y.png',
  );

  ({double west, double south, double east, double north}) get mercatorBounds {
    const halfWorld = math.pi * 6378137;
    final span = 2 * halfWorld / (1 << z);
    return (
      west: x * span - halfWorld,
      south: halfWorld - (y + 1) * span,
      east: (x + 1) * span - halfWorld,
      north: halfWorld - y * span,
    );
  }

  static Vector2 coordinates(LatLng location, int zoom) {
    final lat = location.latitude.clamp(-85.05112878, 85.05112878) * radians;
    final n = (1 << zoom).toDouble();
    return Vector2(
      (location.longitude + 180) / 360 * n,
      (1 - math.log(math.tan(math.pi / 4 + lat / 2)) / math.pi) / 2 * n,
    );
  }

  factory TileId.at(LatLng location, {int zoom = 13}) {
    final uv = coordinates(location, zoom);
    final n = 1 << zoom;
    return TileId(zoom, uv.x.floor() % n, uv.y.floor().clamp(0, n - 1));
  }

  LatLng point(double u, double v) {
    final n = (1 << z).toDouble();
    final angle = math.pi * (1 - 2 * (y + v) / n);
    final lat = math.atan((math.exp(angle) - math.exp(-angle)) / 2) / radians;
    return LatLng(lat, (x + u) / n * 360 - 180);
  }

  Vector2 uv(LatLng location) {
    final tile = coordinates(location, z);
    var u = tile.x - x;
    final n = (1 << z).toDouble();
    if (u > n / 2) u -= n;
    if (u < -n / 2) u += n;
    return Vector2(u, tile.y - y);
  }

  List<TileId> neighborhood() => [
    this,
    for (var dy = -1; dy <= 1; dy++)
      for (var dx = -1; dx <= 1; dx++)
        if ((dx != 0 || dy != 0) && y + dy >= 0 && y + dy < 1 << z)
          TileId(z, (x + dx) % (1 << z), y + dy),
  ];
}

/// WGS84 geodetic -> ECEF (meters).
Vector3 ecef(LatLng point, double height) {
  const a = 6378137.0;
  const e2 = 6.6943799901413165e-3;
  final lat = point.latitude * radians;
  final lon = point.longitude * radians;
  final n = a / math.sqrt(1 - e2 * math.sin(lat) * math.sin(lat));
  return Vector3(
    (n + height) * math.cos(lat) * math.cos(lon),
    (n + height) * math.cos(lat) * math.sin(lon),
    (n * (1 - e2) + height) * math.sin(lat),
  );
}

/// Camera-relative rendering frame: X east, Y up, Z south.
class LocalFrame {
  LocalFrame(this.origin) : center = ecef(origin, 0);
  final LatLng origin;
  final Vector3 center;

  Vector3 project(LatLng point, double height) {
    final delta = ecef(point, height) - center;
    final lat = origin.latitude * radians;
    final lon = origin.longitude * radians;
    final east = -math.sin(lon) * delta.x + math.cos(lon) * delta.y;
    final north =
        -math.sin(lat) * math.cos(lon) * delta.x -
        math.sin(lat) * math.sin(lon) * delta.y +
        math.cos(lat) * delta.z;
    final up =
        math.cos(lat) * math.cos(lon) * delta.x +
        math.cos(lat) * math.sin(lon) * delta.y +
        math.sin(lat) * delta.z;
    return Vector3(east, up, -north);
  }
}
