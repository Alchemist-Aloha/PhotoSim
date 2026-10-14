import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const earthRadius = 6371008.8;
const radians = math.pi / 180;

/// Spherical great-circle destination; used for a short map FOV overlay.
LatLng destination(LatLng origin, double bearing, double distance) {
  final lat = origin.latitude * radians;
  final lon = origin.longitude * radians;
  final angle = distance / earthRadius;
  final direction = bearing * radians;
  final nextLat = math.asin(
    math.sin(lat) * math.cos(angle) +
        math.cos(lat) * math.sin(angle) * math.cos(direction),
  );
  final nextLon =
      lon +
      math.atan2(
        math.sin(direction) * math.sin(angle) * math.cos(lat),
        math.cos(angle) - math.sin(lat) * math.sin(nextLat),
      );
  return LatLng(nextLat / radians, (nextLon / radians + 540) % 360 - 180);
}

double bearing(LatLng origin, LatLng target) {
  final a = origin.latitude * radians;
  final b = target.latitude * radians;
  final delta = (target.longitude - origin.longitude) * radians;
  return (math.atan2(
                math.sin(delta) * math.cos(b),
                math.cos(a) * math.sin(b) -
                    math.sin(a) * math.cos(b) * math.cos(delta),
              ) /
              radians +
          360) %
      360;
}

List<LatLng> fovWedge(
  LatLng origin,
  double azimuth,
  double fov,
  double range,
) => [
  origin,
  for (var i = 0; i <= 32; i++)
    destination(origin, azimuth + (i / 32 - 0.5) * fov / radians, range),
];
