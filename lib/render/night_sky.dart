import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter/material.dart' show Size;

import 'constellations.dart';

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../core/geo.dart';
import '../core/night_sky.dart';
import '../models/simulation_state.dart';

({Float32List positions, Float32List colors, List<int> indices}) starMesh(
  List<Star> stars,
) {
  final positions = Float32List(stars.length * 9 * 3);
  final colors = Float32List(stars.length * 9 * 4);
  final indices = <int>[];
  for (var i = 0; i < stars.length; i++) {
    final star = stars[i], d = star.direction;
    final u = d
        .cross(d.z.abs() > 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1))
        .normalized();
    final v = d.cross(u);
    // shortcut: unresolved stars use exaggerated fixed-angular disks, not a calibrated PSF/exposure model.
    final flux = math.pow(10, -0.2 * star.magnitude).toDouble();
    final radius = NightSkyRenderer.starDistance * (0.0005 + 0.0008 * flux);
    for (var j = 0; j < 9; j++) {
      final angle = (j - 1) * math.pi / 4;
      final p =
          d * NightSkyRenderer.starDistance +
          (j == 0
              ? Vector3.zero()
              : (u * math.cos(angle) + v * math.sin(angle)) * radius);
      final vertex = i * 9 + j;
      positions.setRange(vertex * 3, vertex * 3 + 3, [p.x, p.y, p.z]);
      colors.setRange(vertex * 4, vertex * 4 + 4, [
        0.25 + flux,
        0.25 + flux,
        0.25 + flux,
        1,
      ]);
      if (j > 0) indices.addAll([i * 9, i * 9 + j % 8 + 1, vertex]);
    }
  }
  return (positions: positions, colors: colors, indices: indices);
}

scene.MeshGeometry _milkyWayGeometry() {
  const columns = 128, rows = 64;
  final positions = Float32List((columns + 1) * (rows + 1) * 3);
  final uvs = Float32List((columns + 1) * (rows + 1) * 2);
  final indices = <int>[];
  for (var y = 0; y <= rows; y++) {
    final dec = (90 - y / rows * 180) * radians;
    for (var x = 0; x <= columns; x++) {
      final ra = (x / columns * 360 - 180) * radians;
      final i = y * (columns + 1) + x;
      positions.setRange(i * 3, i * 3 + 3, [
        math.cos(dec) * math.cos(ra) * NightSkyRenderer.bandDistance,
        math.cos(dec) * math.sin(ra) * NightSkyRenderer.bandDistance,
        math.sin(dec) * NightSkyRenderer.bandDistance,
      ]);
      uvs.setRange(i * 2, i * 2 + 2, [x / columns, y / rows]);
      if (x < columns && y < rows) {
        final b = i + columns + 1;
        indices.addAll([i, i + 1, b, b, i + 1, b + 1]);
      }
    }
  }
  return scene.MeshGeometry.fromArrays(
    positions: positions,
    texCoords: uvs,
    indices: indices,
  );
}

class NightSkyRenderer {
  NightSkyRenderer(
    List<Star> stars,
    scene.Texture2D milkyWay,
    this.constellations,
  ) {
    final data = starMesh(stars);
    starGeometry = scene.MeshGeometry.fromArrays(
      positions: data.positions,
      colors: data.colors,
      indices: data.indices,
    );
    starMaterial = scene.UnlitMaterial();
    bandMaterial = scene.UnlitMaterial(colorTexture: milkyWay)
      ..alphaMode = scene.AlphaMode.blend;
    starNode = scene.Node(
      name: 'Stars',
      mesh: scene.Mesh(starGeometry, starMaterial),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
    bandNode = scene.Node(
      name: 'Milky Way',
      mesh: scene.Mesh(_milkyWayGeometry(), bandMaterial),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
    marker = scene.Node(
      name: 'Galactic center',
      mesh: scene.Mesh(
        scene.SphereGeometry(radius: 100, segments: 16, rings: 8),
        scene.UnlitMaterial()..baseColorFactor = vm.Vector4(0.65, 0.3, 1, 1),
      ),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
    final center = Star(
      1,
      266.4051 * radians,
      -28.936175 * radians,
      0,
    ).direction;
    marker.position = vm.Vector3(center.x, center.y, center.z) * 28000;
    root = scene.Node(name: 'Night sky')
      ..add(starNode)
      ..add(bandNode)
      ..add(marker)
      ..add(constellations.root);
  }
  final ConstellationRenderer constellations;

  void updateLabels(SimulationState state, Size viewport) =>
      constellations.update(state, viewport, _rotation);

  static const starDistance = 40000.0, bandDistance = 45000.0;
  late final scene.Node root, starNode, bandNode, marker;
  late final scene.MeshGeometry starGeometry;
  late final scene.UnlitMaterial starMaterial, bandMaterial;
  (DateTime, double, double)? _lastObserver;
  vm.Matrix3 _rotation = vm.Matrix3.identity();

  void update(SimulationState state, vm.Vector3 eye) {
    final observer = (state.timestamp, state.latitude, state.longitude);
    if (_lastObserver != observer) {
      final frame = ObserverSkyFrame(
        timestamp: state.timestamp,
        latitude: state.latitude,
        longitude: state.longitude,
      );
      final x = frame.direction(0, 0),
          y = frame.direction(math.pi / 2, 0),
          z = frame.direction(0, math.pi / 2);
      _rotation = vm.Matrix3.columns(
        vm.Vector3(x.x, x.y, x.z),
        vm.Vector3(y.x, y.y, y.z),
        vm.Vector3(z.x, z.y, z.z),
      );
      _lastObserver = observer;
    }
    root.localTransform = vm.Matrix4.identity()
      ..setRotation(_rotation)
      ..setTranslation(eye);
    final sky = state.sky;
    final stars = nightVisibility(sky),
        band = nightVisibility(sky, milkyWay: true);
    starNode.visible = stars > 0;
    bandNode.visible = band > 0.001;
    starMaterial.baseColorFactor = vm.Vector4(stars, stars, stars, 1);
    bandMaterial.baseColorFactor = vm.Vector4(1, 1, 1, band);
    marker.visible = state.target == CelestialTarget.galacticCenter;
    constellations.root.visible = state.showConstellations;
  }
}
