import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Crop the framed photograph, then burn attribution; guides stay outside the source.
Future<Uint8List> encodePreview(
  ui.Image image,
  String credits, {
  Rect? crop,
}) async {
  final source =
      crop ??
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  if (!source.isFinite ||
      source.width < 1 ||
      source.height < 1 ||
      source.left < 0 ||
      source.top < 0 ||
      source.right > image.width ||
      source.bottom > image.height) {
    throw ArgumentError('Invalid photo crop');
  }
  final width = source.width.round(), heightPixels = source.height.round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawImageRect(
      image,
      source,
      Rect.fromLTWH(0, 0, width.toDouble(), heightPixels.toDouble()),
      Paint(),
    );
  final text = TextPainter(
    text: TextSpan(
      text: credits,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: (width - 16.0).clamp(0, double.infinity));
  final height = text.height + 12;
  canvas.drawRect(
    Rect.fromLTWH(0, heightPixels - height, width.toDouble(), height),
    Paint()..color = const Color(0xBB000000),
  );
  text.paint(canvas, Offset(8, heightPixels - height + 6));
  text.dispose();
  final picture = recorder.endRecording();
  final stamped = await picture.toImage(width, heightPixels);
  try {
    final data = await stamped.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding unavailable');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    stamped.dispose();
    picture.dispose();
  }
}

/// Never overwrite an existing photograph; publish only a completely written PNG.
Future<File> savePreview(String path, Uint8List bytes) async {
  final file = File(path);
  if (!file.isAbsolute || !path.toLowerCase().endsWith('.png')) {
    throw const FormatException('Choose an absolute path ending in .png');
  }
  final staging = await file.parent.createTemp('.photosim-export-');
  var reserved = false;
  try {
    final temporary = File('${staging.path}/preview.png');
    await temporary.writeAsBytes(bytes, flush: true);
    await file.create(exclusive: true);
    reserved = true;
    await temporary.rename(file.path);
    return file;
  } catch (_) {
    if (reserved && await file.exists()) await file.delete();
    rethrow;
  } finally {
    await staging.delete(recursive: true);
  }
}
