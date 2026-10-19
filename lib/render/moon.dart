import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vector_math/vector_math_64.dart' show Vector3, Matrix3;

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

/// Near-side orientation using projected lunar north; libration is not modeled.
Matrix3 moonTextureOrientation(Vector3 moonDirection, Vector3 northPole) {
  if (!moonDirection.length2.isFinite ||
      moonDirection.length2 < 1e-12 ||
      !northPole.length2.isFinite ||
      northPole.length2 < 1e-12) {
    throw ArgumentError('Invalid lunar orientation');
  }
  final front = -moonDirection.normalized();
  var north = northPole - front * northPole.dot(front);
  if (north.length2 < 1e-12) {
    final fallback = front.y.abs() < 0.9 ? Vector3(0, 1, 0) : Vector3(0, 0, 1);
    north = fallback - front * fallback.dot(front);
  }
  north.normalize();
  return Matrix3.columns(-front, north, north.cross(front).normalized());
}

class MoonRenderer {
  MoonRenderer(scene.Texture2D albedo) {
    final data = scene.SphereGeometry(
      radius: 1,
      segments: 128,
      rings: 64,
    ).extractMeshData();
    // NASA's longitude increases eastward; the engine sphere's U runs the opposite way.
    final uvs = data.texCoords!;
    for (var i = 0; i < uvs.length; i += 2) {
      uvs[i] = 1 - uvs[i];
    }
    geometry = scene.MeshGeometry.fromMeshData(
      data,
      storage: scene.GeometryStorage.updatable,
    );
    normals = data.normals!;
    node = scene.Node(
      name: 'Moon',
      mesh: scene.Mesh(
        geometry,
        CelestialMaterial(colorTexture: albedo)
          ..alphaMode = scene.AlphaMode.blend,
      ),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
  }

  // shortcut: smooth sphere with fixed near-side aspect; add libration/relief for precise lunar feature planning.
  static const distance = 30000.0;
  late final scene.MeshGeometry geometry;
  late final Float32List normals;
  late final scene.Node node;
  Vector3? lastLight;

  void update(SkyState sky, vm.Vector3 eye, Vector3 northPole) {
    final orientation = moonTextureOrientation(sky.moon.direction, northPole);
    final light = orientation.transposed().transformed(sky.moonToSunDirection);
    if (lastLight != light) {
      geometry.updateColors(moonColors(normals, light));
      lastLight = light;
    }
    final d = sky.moon.direction;
    final radius = distance * math.sin(sky.moon.angularRadius);
    node
      ..position = eye + vm.Vector3(d.x, d.y, d.z) * distance
      ..rotation = vm.Quaternion.fromRotation(
        vm.Matrix3.fromList(orientation.storage),
      )
      ..scale = vm.Vector3.all(radius);
  }
}
