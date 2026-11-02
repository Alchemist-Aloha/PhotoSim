import 'dart:typed_data';
import 'dart:convert';

import 'package:photosim/core/terrain_geo.dart';
import 'package:image/image.dart' as image;

Uint8List lakeFixture(
  TileId id,
  List<List<List<double>>> rings, {
  double height = 100,
  int lakeId = 7,
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'hylak_id': lakeId, 'elevation': height},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              for (final ring in rings)
                [
                  for (final p in ring)
                    [
                      id.point(p[0], p[1]).longitude,
                      id.point(p[0], p[1]).latitude,
                    ],
                ],
            ],
          },
        },
      ],
    }),
  ),
);

Uint8List coastFixture({bool ocean = false}) {
  final png = image.Image(width: 256, height: 256, numChannels: 4);
  if (!ocean) image.fill(png, color: image.ColorRgba8(75, 75, 75, 255));
  return image.encodePng(png);
}

Uint8List waterFixture({bool Function(int x, int y)? wet}) {
  final png = image.Image(width: 256, height: 256, numChannels: 4);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      if (wet?.call(x, y) ?? (x >= 80 && x < 176 && y >= 80 && y < 176)) {
        png.setPixelRgba(x, y, 168, 248, 255, 255);
      }
    }
  }
  return image.encodePng(png);
}
