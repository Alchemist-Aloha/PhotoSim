import 'dart:typed_data';
import 'dart:convert';

import 'package:photosim/core/terrain_geo.dart';
import 'package:image/image.dart' as image;
import 'package:http/http.dart' as http;

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

const riverTileJson =
    '{"tiles":["https://tiles.openfreemap.org/planet/test/{z}/{x}/{y}.pbf"]}';

http.Response riverResponse(Uri uri, Uint8List tile) => uri.path == '/planet'
    ? http.Response(riverTileJson, 200)
    : http.Response.bytes(tile, 200);

TileId riverTile(Uri uri) {
  final parts = uri.pathSegments;
  return TileId(
    int.parse(parts[parts.length - 3]),
    int.parse(parts[parts.length - 2]),
    int.parse(parts.last.split('.').first),
  );
}

List<int> pbfInteger(int value) {
  final bytes = <int>[];
  while (value >= 128) {
    bytes.add((value & 127) | 128);
    value >>= 7;
  }
  return [...bytes, value];
}

List<int> pbfBytes(int field, List<int> bytes) => [
  ...pbfInteger((field << 3) | 2),
  ...pbfInteger(bytes.length),
  ...bytes,
];

Uint8List riverFixture(
  TileId id,
  List<List<List<double>>> rings, {
  TileId? tile,
  String classification = 'river',
  String layer = 'water',
  int type = 3,
  List<int>? commands,
  List<int> tags = const [0, 0],
  int extent = 4096,
}) {
  var x = 0, y = 0;
  final geometry = <int>[];
  for (final ring in rings) {
    final points =
        ring.length > 1 &&
            ring.first[0] == ring.last[0] &&
            ring.first[1] == ring.last[1]
        ? ring.take(ring.length - 1)
        : ring;
    var first = true;
    for (final p in points) {
      final uv = (tile ?? id).uv(id.point(p[0], p[1]));
      final nx = (uv.x * extent).round(), ny = (uv.y * extent).round();
      geometry.addAll([
        first ? 9 : 10,
        ...[(nx - x), (ny - y)].map((v) => (v << 1) ^ (v >> 63)),
      ]);
      x = nx;
      y = ny;
      first = false;
    }
    geometry.add(15);
  }
  return Uint8List.fromList(
    pbfBytes(3, [
      ...pbfBytes(1, utf8.encode(layer)),
      if (rings.isNotEmpty || commands != null)
        ...pbfBytes(2, [
          8,
          9,
          ...pbfBytes(2, tags.expand(pbfInteger).toList()),
          24,
          type,
          ...pbfBytes(4, (commands ?? geometry).expand(pbfInteger).toList()),
        ]),
      ...pbfBytes(3, utf8.encode('class')),
      ...pbfBytes(4, pbfBytes(1, utf8.encode(classification))),
      40,
      ...pbfInteger(extent),
      120,
      2,
    ]),
  );
}

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
