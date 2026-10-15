import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Burn attribution into the same-aspect-ratio image, not application controls.
Future<Uint8List> encodePreview(ui.Image image, String credits) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawImage(image, Offset.zero, Paint());
  final text = TextPainter(
    text: TextSpan(
      text: credits,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: image.width - 16.0);
  final height = text.height + 12;
  canvas.drawRect(
    Rect.fromLTWH(0, image.height - height, image.width.toDouble(), height),
    Paint()..color = const Color(0xBB000000),
  );
  text.paint(canvas, Offset(8, image.height - height + 6));
  text.dispose();
  final picture = recorder.endRecording();
  final stamped = await picture.toImage(image.width, image.height);
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
