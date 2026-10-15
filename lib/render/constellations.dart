import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;

import '../core/constellations.dart';
import '../models/simulation_state.dart';

class ConstellationRenderer {
  ConstellationRenderer._(this.catalog, scene.Texture2D atlas) {
    final data = constellationMesh(catalog);
    lines = scene.Node(
      name: 'Constellation highlights',
      mesh: scene.Mesh(
        scene.MeshGeometry.fromArrays(
          positions: data.positions,
          indices: data.indices,
        ),
        scene.UnlitMaterial()
          ..alphaMode = scene.AlphaMode.blend
          ..baseColorFactor = vm.Vector4(0.3, 0.65, 1, 0.45),
      ),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
    labels = scene.BillboardGeometry(capacity: catalog.length)
      ..flipbookColumns = 8
      ..flipbookRows = (catalog.length / 8).ceil();
    final names = scene.Node(
      name: 'Constellation names',
      mesh: scene.Mesh(labels, scene.SpriteMaterial(colorTexture: atlas)),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
    root = scene.Node(name: 'Constellations')
      ..visible = false
      ..add(lines)
      ..add(names);
  }
  final List<Constellation> catalog;
  late final scene.Node root, lines;
  late final scene.BillboardGeometry labels;
  final activeNames = <String>[];

  static Future<ConstellationRenderer> create(
    List<Constellation> catalog,
  ) async {
    const width = 192, height = 40;
    final rows = (catalog.length / 8).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < catalog.length; i++) {
      final text = TextPainter(
        text: TextSpan(
          text: catalog[i].name,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFFBBDDFF),
            shadows: [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 8);
      text.paint(
        canvas,
        Offset(
          i % 8 * width + (width - text.width) / 2,
          i ~/ 8 * height + (height - text.height) / 2,
        ),
      );
      text.dispose();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width * 8, height * rows);
    try {
      return ConstellationRenderer._(
        catalog,
        await scene.Texture2D.fromImage(image),
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  /// Called in the sensor viewport's layout so text keeps a readable pixel size.
  void update(SimulationState state, Size viewport, vm.Matrix3 rotation) {
    root.visible = state.showConstellations;
    activeNames.clear();
    if (!root.visible || viewport.height <= 0) return;
    final frame = state.cameraFrame;
    final forward = vm.Vector3(
      frame.forward.x,
      frame.forward.y,
      frame.forward.z,
    );
    final up = vm.Vector3(frame.up.x, frame.up.y, frame.up.z);
    final right = vm.Vector3(frame.right.x, frame.right.y, frame.right.z);
    labels.worldUp = up;
    var count = 0;
    for (var i = 0; i < catalog.length; i++) {
      final anchor = catalog[i].anchor;
      final d = rotation.transformed(vm.Vector3(anchor.x, anchor.y, anchor.z));
      final depth = d.dot(forward);
      if (d.y <= 0 || depth <= 0) continue;
      if (d.dot(right).abs() > depth * math.tan(state.horizontalFov / 2) ||
          d.dot(up).abs() > depth * math.tan(state.verticalFov / 2)) {
        continue;
      }
      activeNames.add(catalog[i].name);
      final unitsPerPixel =
          2 * 39700 * depth * math.tan(state.verticalFov / 2) / viewport.height;
      // shortcut: fixed-size labels without collision layout; add decluttering if wide-angle names overlap.
      labels.setInstance(
        count++,
        center: vm.Vector3(anchor.x, anchor.y, anchor.z) * 39700,
        width: 192 * unitsPerPixel,
        height: 40 * unitsPerPixel,
        frame: i.toDouble(),
      );
    }
    labels.commit(count);
  }
}
