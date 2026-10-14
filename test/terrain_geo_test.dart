import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/core/terrain_geo.dart';

void main() {
  test('XYZ round trips geographic positions including the dateline', () {
    for (final point in [
      const LatLng(37.744, -119.59),
      const LatLng(-33, 151),
      const LatLng(85, 179.999),
      const LatLng(0, 180),
    ]) {
      final tile = TileId.at(point);
      final uv = tile.uv(point);
      final back = tile.point(uv.x, uv.y);
      expect(back.latitude, closeTo(point.latitude, 1e-9));
      expect(
        (back.longitude - point.longitude + 540) % 360 - 180,
        closeTo(0, 1e-9),
      );
    }
    expect(TileId(13, 0, 0).neighborhood().length, 6);
    expect(TileId(13, 0, 1).neighborhood().any((t) => t.x == 8191), isTrue);
    expect(() => TileId(13, -1, 0), throwsArgumentError);
  });
  test(
    'WGS84 ECEF and local east/north/up axes have meter scale and curvature',
    () {
      expect(ecef(const LatLng(0, 0), 0).x, 6378137);
      expect(ecef(const LatLng(90, 0), 0).z, closeTo(6356752.314245, 0.001));
      final frame = LocalFrame(const LatLng(0, 0));
      expect(frame.project(const LatLng(0, 0), 1234).y, closeTo(1234, 1e-6));
      final east = frame.project(const LatLng(0, 0.001), 0);
      expect(east.x, closeTo(111.31949, 0.001));
      expect(east.y, lessThan(0));
      expect(east.z, closeTo(0, 1e-6));
      final north = frame.project(const LatLng(0.001, 0), 0);
      expect(north.z, closeTo(-110.57427, 0.001));
    },
  );
}
