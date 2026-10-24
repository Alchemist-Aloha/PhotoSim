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
  test('tile projection rejects nonfinite coordinates before clamping', () {
    final tile = TileId(13, 0, 0);
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      for (final point in [LatLng(value, 0), LatLng(0, value)]) {
        expect(() => TileId.coordinates(point, 13), throwsArgumentError);
        expect(() => TileId.at(point), throwsArgumentError);
        expect(() => tile.uv(point), throwsArgumentError);
      }
    }
  });

  test('tile projection rejects unsupported zooms before shifting', () {
    const origin = LatLng(37.744, -119.59);
    for (final zoom in [-1, 16, 64, 1 << 31]) {
      expect(() => TileId.coordinates(origin, zoom), throwsArgumentError);
      expect(() => TileId.at(origin, zoom: zoom), throwsArgumentError);
    }
  });

  test('finite poles still clamp and date-line world copies still wrap', () {
    for (final zoom in [0, 13, 15]) {
      for (final latitude in [-90.0, 90.0]) {
        for (final longitude in [-540.0, -180.0, 180.0, 540.0]) {
          final tile = TileId.at(LatLng(latitude, longitude), zoom: zoom);
          expect(tile.x, 0);
          expect(tile.y, latitude > 0 ? 0 : (1 << zoom) - 1);
        }
      }
    }
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
