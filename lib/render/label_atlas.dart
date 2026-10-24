import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;

/// Rasterized flipbook of short sky labels, shared by constellations and planets.
///
/// One texture keeps label drawing to a single billboard node; the cell size is a
/// fixed pixel budget so text stays legible at any viewport by scaling per instance.
Future<scene.Texture2D> buildLabelAtlas(
  List<String> labels, {
  required Color color,
  double fontSize = 14,
  int columns = 8,
  int width = 192,
  int height = 40,
}) async {
  assert(labels.isNotEmpty);
  final rows = (labels.length / columns).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var i = 0; i < labels.length; i++) {
    final text = TextPainter(
      text: TextSpan(
        text: labels[i],
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 8);
    text.paint(
      canvas,
      Offset(
        i % columns * width + (width - text.width) / 2,
        i ~/ columns * height + (height - text.height) / 2,
      ),
    );
    text.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width * columns, height * rows);
  try {
    return await scene.Texture2D.fromImage(image);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
