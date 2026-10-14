import 'dart:typed_data';

import 'package:image/image.dart' as image;

Uint8List imageryFixture(int size, {bool partial = false, bool empty = false}) {
  final png = image.Image(width: size, height: size, numChannels: 4);
  image.fill(png, color: image.ColorRgba8(80, 120, 160, empty ? 0 : 255));
  if (!empty) {
    png.setPixelRgba(0, 0, 255, 0, 0, 255);
    png.setPixelRgba(size - 1, size - 1, 0, 0, 255, 255);
    if (partial) png.setPixelRgba(1, 0, 0, 0, 0, 0);
  }
  return image.encodePng(png);
}
