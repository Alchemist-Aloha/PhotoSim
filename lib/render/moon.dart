import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../core/astronomy.dart';
import '../core/geo.dart';
import 'celestial_material.dart';

/// Approximate appearance, deliberately not calibrated irradiance/exposure.
double moonlightIntensity(SkyState sky) =>
    0.03 *
    math.pow(sky.moonIllumination, 2) *
    math.max(0, math.sin(sky.moon.altitude * radians)) *
    (-sky.sun.altitude / 6).clamp(0.0, 1.0);

Float32List moonColors(Float32List normals, Vector3 lightDirection) {
  final colors = Float32List(normals.length ~/ 3 * 4);
  for (var i = 0; i < normals.length ~/ 3; i++) {
    final light = math.max(
      0.0,
      normals[i * 3] * lightDirection.x +
          normals[i * 3 + 1] * lightDirection.y +
          normals[i * 3 + 2] * lightDirection.z,
    );
    // Fade into the sky instead of painting the unlit hemisphere black.
    colors[i * 4] = colors[i * 4 + 1] = colors[i * 4 + 2] = 1;
    colors[i * 4 + 3] = light;
  }
  return colors;
}

class MoonRenderer {
  MoonRenderer() {
    final data = scene.SphereGeometry(
      radius: 1,
      segments: 128,
      rings: 64,
    ).extractMeshData();
    geometry = scene.MeshGeometry.fromMeshData(
      data,
      storage: scene.GeometryStorage.updatable,
    );
    normals = data.normals!;
    node = scene.Node(
      name: 'Moon',
      mesh: scene.Mesh(
        geometry,
        CelestialMaterial()..alphaMode = scene.AlphaMode.blend,
      ),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
  }

  // shortcut: a distant Lambertian sphere without albedo/libration or atmosphere; upgrade for photographic lunar detail.
  static const distance = 30000.0;
  late final scene.MeshGeometry geometry;
  late final Float32List normals;
  late final scene.Node node;
  Vector3? lastLight;

  void update(SkyState sky, vm.Vector3 eye) {
    final light = sky.moonToSunDirection;
    if (lastLight != light) {
      geometry.updateColors(moonColors(normals, light));
      lastLight = light;
    }
    final d = sky.moon.direction;
    final radius = distance * math.sin(sky.moon.angularRadius);
    node
      ..position = eye + vm.Vector3(d.x, d.y, d.z) * distance
      ..scale = vm.Vector3.all(radius);
  }
}
