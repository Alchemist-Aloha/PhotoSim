import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;

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
  double altitudeKm,
) {
  final dip =
      math.acos(6371 / (6371 + altitudeKm.clamp(0, 30))) * 180 / math.pi;
  // No 1.5° floor: a setting deck keeps reddening through the last degree, which
  // is what turns cloud undersides from gold to crimson after ground sunset.
  final light = sunTransmission((sunAltitude + dip).clamp(-1.0, 90.0));
  return (red: light.red, green: light.green, blue: light.blue);
}

// shortcut: average cloud attenuation, add cloud-shadow maps for spatially varying terrain light.
double cloudLightTransmission(SimulationState state) =>
    1 - state.cloudAmount * (state.cloudType == CloudType.cirrus ? 0.15 : 0.55);

/// The material and noise texture, shared by every [CloudRenderer] instance.
class CloudResources {
  const CloudResources(this.material, this.noise);
  final scene.PreprocessedMaterial material;
  final scene.Texture2D noise;
}

class CloudRenderer {
  CloudRenderer(CloudResources resources)
    : material = resources.material,
      _noise = resources.noise {
    material.parameters.setTexture(
      'cloud_noise',
      _noise.gpuTexture,
      sampler: _noise.sampledSampler,
    );
    node =
        scene.Node(
            name: 'Clouds',
            mesh: scene.Mesh(
              scene.SphereGeometry(radius: 25000, segments: 32, rings: 16),
              material,
            ),
          )
          ..shadowCastingMode = scene.ShadowCastingMode.off
          // Composite after the Moon/Milky Way; opaque terrain depth bounds the volume.
          ..renderOrder = 100;
  }

  static Future<CloudResources> loadShared() async {
    final (material, noise) = await (
      scene.loadFmatMaterial('assets/atmosphere/clouds.fmat'),
      scene.Texture2D.fromAsset(
        'assets/atmosphere/cloud_noise.png',
        content: scene.TextureContent.data,
        sampling: const scene.TextureSampling(mipmaps: false),
      ),
    ).wait;
    return CloudResources(material, noise);
  }

  static Future<CloudRenderer> load() async =>
      CloudRenderer(await loadShared());

  final scene.PreprocessedMaterial material;
  final scene.Texture2D _noise;
  late final scene.Node node;
  int? lastSeed;

  void update(SimulationState state, vm.Vector3 eye) {
    node
      ..position = eye
      ..visible = state.cloudAmount > 0;
    if (!node.visible) return;
    final layer = cloudLayer(state.cloudType);
    final sky = state.sky;
    final sun = sky.sun.direction;
    final groundKm = (state.groundElevation ?? (eye.y - state.height)) / 1000;
    final light = cloudSunColor(
      sky.sun.altitude,
      groundKm + layer.base + layer.thickness * 0.5,
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
    final p = material.parameters;
    if (lastSeed != state.cloudSeed) {
      final random = math.Random(state.cloudSeed);
      p.setVec3(
        'seed_offset',
        vm.Vector3(
          random.nextDouble() * 200,
          random.nextDouble() * 200,
          random.nextDouble() * 200,
        ),
      );
      lastSeed = state.cloudSeed;
    }
    p
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
      ..setVec3('moon_direction', vm.Vector3(moon.x, moon.y, moon.z))
      ..setFloat('moon_strength', moonStrength)
      ..setFloat('daylight', day)
      ..setFloat('energy', state.weatherLightTransmission)
      ..setFloat('amount', state.cloudAmount)
      ..setFloat('max_distance', cloudRenderDistanceKm)
      ..setFloat('scene_far', previewFarDistanceMeters)
      ..setInt('cloud_type', state.cloudType.index)
      ..setInt('view_steps', switch (state.renderQuality) {
        RenderQuality.performance => 24,
        RenderQuality.balanced => 48,
        RenderQuality.high => 64,
      });
  }
}
