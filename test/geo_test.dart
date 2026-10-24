import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng;
import 'package:photosim/core/geo.dart';

void main() {
  test('cardinal destination and bearing agree', () {
    const origin = LatLng(37.744, -119.59);
    const distance = Distance();
    for (final azimuth in [0.0, 90.0, 180.0, 270.0]) {
      final point = destination(origin, azimuth, 1000);
      final difference = (bearing(origin, point) - azimuth + 540) % 360 - 180;
      expect(difference, closeTo(0, 1e-7));
      expect(distance(origin, point), closeTo(1000, 2));
    }
  });
  test('exact polar destinations tolerate floating-point roundoff', () {
    for (final latitude in [
      89.914,
      89.919,
      89.926,
      -89.914,
      -89.919,
      -89.926,
    ]) {
      final pole = latitude > 0 ? 90.0 : -90.0;
      final distance = (pole - latitude).abs() * radians * earthRadius;
      final point = destination(
        LatLng(latitude, 179.999),
        latitude > 0 ? 0 : 180,
        distance,
      );
      expect(point.latitude, closeTo(pole, 1e-9));
      expect(point.longitude.isFinite, isTrue);
      expect(point.longitude, inInclusiveRange(-180, 180));
    }
  });

  test('dateline wraps and FOV wedge boundaries match camera optics', () {
    final point = destination(const LatLng(0, 179.999), 90, 1000);
    expect(point.longitude, lessThan(-179));
    const origin = LatLng(0, 0);
    final wedge = fovWedge(origin, 90, math.pi / 3, 1000);
    expect(wedge.first, origin);
    expect(bearing(origin, wedge[1]), closeTo(60, 1e-7));
    expect(bearing(origin, wedge.last), closeTo(120, 1e-7));
  });
}
