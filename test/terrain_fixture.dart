import 'dart:typed_data';
import 'dart:convert';

import 'package:image/image.dart' as image;

Uint8List terrainFixture({double height = 1234.5}) {
  final value = height + 32768;
  final png = image.Image(width: 256, height: 256, numChannels: 3);
  image.fill(
    png,
    color: image.ColorRgb8(
      (value / 256).floor(),
      value.floor() % 256,
      ((value - value.floor()) * 256).round(),
    ),
  );
  return image.encodePng(png);
}

// Lossless 512px WebP fixtures generated with Pillow; no geographic data is bundled.
Uint8List terrainWebpFixture() => base64Decode(
  'UklGRi4AAABXRUJQVlA4TCIAAAAv/8F/AAdQ6RIWsP8BgUCyv/cMRfQ/4z//+c9//vOf//wf',
);
Uint8List terrainQuadrantFixture() => base64Decode(
  'UklGRloAAABXRUJQVlA4TE0AAAAv/8F/AB8gFED87cJoBRCJwrZNmE7ga14foPmP/4KJCwbZRnrJl3zJBxhAI/o/AZu/PP/xH//xH//xH/8x3OQ/z3/8x3/8x3/8x38MBwA=',
);
Uint8List terrainVoidWebpFixture() => base64Decode(
  'UklGRiwAAABXRUJQVlA4TCAAAAAv/8F/AAcQEf0PCASS/b1nKKL/Gf/5z3/+85///Of/AA==',
);
Uint8List terrainTransparentWebpFixture() => base64Decode(
  'UklGRjQAAABXRUJQVlA4TCcAAAAv/8F/EA8w0kM4gPMfh1DQtg3Dn3R3OTii/5niP//5z3/+85///P8A',
);
