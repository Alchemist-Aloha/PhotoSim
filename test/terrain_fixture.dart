import 'dart:typed_data';

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
