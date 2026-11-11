import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;

import '../core/atmosphere.dart';
import '../core/sunlight.dart';
import '../models/simulation_state.dart';
import 'photo_framing.dart';

({double base, double thickness, double scale, double extinction}) cloudLayer(
  CloudType type,
) => switch (type) {
  CloudType.cumulus => (base: 1.6, thickness: 2.4, scale: 1.3, extinction: 3.5),
  CloudType.stratocumulus => (
    base: 1.0,
    thickness: 0.9,
    scale: 1.4,
    extinction: 4.0,
  ),
  CloudType.stratus => (base: 0.7, thickness: 0.6, scale: 3.5, extinction: 5.0),
  CloudType.cirrus => (base: 8.0, thickness: 0.8, scale: 2.5, extinction: 0.7),
  CloudType.cumulonimbus => (
    base: 1.2,
    thickness: 7.0,
    scale: 3.0,
    extinction: 5.0,
  ),
};

const cloudRenderDistanceKm = 256.0;

/// Elevated clouds can receive sunlight while the ground is already in shadow.
({double red, double green, double blue}) cloudSunColor(
  double sunAltitude,
  double altitudeKm, {
  AtmosphereOptics? optics,
}) {
  final dip =
      math.acos(6371 / (6371 + altitudeKm.clamp(0, 30))) * 180 / math.pi;
  // No 1.5° floor: a setting deck keeps reddening through the last degree, which
  // is what turns cloud undersides from gold to crimson after ground sunset.
  final light = sunTransmission(
    (sunAltitude + dip).clamp(-1.0, 90.0),
    optics: optics,
  );
  return (red: light.red, green: light.green, blue: light.blue);
}

// shortcut: average cloud attenuation, add cloud-shadow maps for spatially varying terrain light.
double cloudLightTransmission(SimulationState state) =>
    1 - state.cloudAmount * (state.cloudType == CloudType.cirrus ? 0.15 : 0.55);

class CloudRenderer {
  CloudRenderer(this.material) {
    node =
        scene.Node(
            name: 'Clouds',
            mesh: scene.Mesh(
              scene.SphereGeometry(radius: 25000, segments: 32, rings: 16),
              material,
            ),
          )
          ..shadowCastingMode = scene.ShadowCastingMode.off
          // Composite after the Moon/Milky Way; opaque terrain depth occludes the decks.
          ..renderOrder = 100;
  }

  static Future<CloudRenderer> load() async => CloudRenderer(
    await scene.loadFmatMaterial('assets/atmosphere/clouds.fmat'),
  );

  final scene.PreprocessedMaterial material;
  late final scene.Node node;

  void update(
    SimulationState state,
    vm.Vector3 eye, {
    scene.PreprocessedMaterial? reflectionMaterial,
  }) {
    node
      ..position = eye
      ..visible = state.cloudAmount > 0;
    final layer = cloudLayer(state.cloudType);
    final sky = state.sky;
    final sun = sky.sun.direction;
    final groundKm = (state.groundElevation ?? (eye.y - state.height)) / 1000;
    final light = cloudSunColor(
      sky.sun.altitude,
      groundKm + layer.base + layer.thickness * 0.5,
      optics: state.atmosphereOptics,
    );
    final day = ((sky.sun.altitude + 6) / 11).clamp(0.0, 1.0);
    final moon = sky.moon.direction;
    final moonStrength =
        sky.moonIllumination *
        sky.moonIllumination *
        math.max(0.0, moon.y) *
        (1 - day);
    // Geographic anchoring keeps a saved seed stable across camera motion and scene recreation.
    final lat = state.latitude * math.pi / 180;
    final origin = vm.Vector3(
      state.longitude * math.pi / 180 * 6371 * math.cos(lat),
      eye.y / 1000,
      -state.latitude * math.pi / 180 * 6371,
    );
    final random = math.Random(state.cloudSeed);
    final seed = vm.Vector3(
      random.nextDouble() * 200,
      random.nextDouble() * 200,
      random.nextDouble() * 200,
    );
    for (final target in [material, ?reflectionMaterial]) {
      final p = target.parameters;
      p
        ..setVec3('seed_offset', seed)
        ..setVec3('cloud_origin', origin)
        ..setVec4(
          'layer',
          vm.Vector4(
            groundKm + layer.base,
            layer.thickness,
            layer.scale,
            layer.extinction,
          ),
        )
        ..setVec3('sun_direction', vm.Vector3(sun.x, sun.y, sun.z))
        ..setVec3('sun_color', vm.Vector3(light.red, light.green, light.blue))
        ..setFloat('moon_strength', moonStrength)
        ..setFloat('energy', state.weatherLightTransmission)
        ..setFloat('amount', state.cloudAmount)
        ..setFloat('max_distance', cloudRenderDistanceKm)
        ..setInt('cloud_type', state.cloudType.index)
        ..setInt('noise_octaves', switch (state.renderQuality) {
          RenderQuality.performance => 3,
          RenderQuality.balanced => 4,
          RenderQuality.high => 5,
        });
    }
    material.parameters.setFloat('scene_far', previewFarDistanceMeters);
    if (reflectionMaterial != null) {
      final disk = sunDiskTransmission(
        sky.sun.altitude,
        optics: state.atmosphereOptics,
      );
      reflectionMaterial.parameters
        ..setFloat('solar_radius', sky.sun.angularRadius)
        ..setVec3(
          'sun_disk_color',
          vm.Vector3(disk.red, disk.green, disk.blue),
        );
    }
  }
}
