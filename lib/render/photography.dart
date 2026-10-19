import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;

import '../models/simulation_state.dart';
import '../core/exposure.dart';

void configureTerrainShadows(
  scene.DirectionalLight light,
  SimulationState state,
) {
  final high = state.renderQuality == RenderQuality.high;
  final performance = state.renderQuality == RenderQuality.performance;
  final distance = math.min(
    state.terrainRenderKm * 1000,
    high ? 24000.0 : 16000.0,
  );
  final sky = state.sky;
  light
    ..castsShadow = state.relitImagery && state.weather == Weather.clear
    ..shadowMapResolution = high ? 4096 : (performance ? 1024 : 2048)
    ..shadowCascadeCount = performance ? 2 : 4
    ..shadowMaxDistance = distance
    ..firstCascadeFarBound = 300
    ..shadowCascadeSplitLambda = 0.8
    ..cascadeOverlap = 0.12
    ..shadowFadeRange = distance * 0.15
    ..shadowFilter = high
        ? scene.DirectionalShadowFilter.pcss
        : scene.DirectionalShadowFilter.bilinearPcf
    // Softness also feeds the backend's grazing-angle receiver bias; keep its world-space cap small.
    ..shadowSoftness = high ? 0.15 : 0.08
    ..shadowDepthBias = high ? 0.2 : (performance ? 0.8 : 0.4)
    ..shadowNormalBias = high ? 0.5 : (performance ? 2 : 1.2)
    ..contactShadows =
        high && state.relitImagery && state.weather == Weather.clear
    ..contactShadowDistance = 3
    ..angularRadius = sky.sun.altitude > 0
        ? sky.sun.angularRadius
        : sky.moon.angularRadius;
}

/// Applies camera effects and atmosphere without downloading geographic resources.
void configurePhotography(scene.Scene world, SimulationState state) {
  world.exposure = exposureMultiplier(state);
  world.autoExposure
    ..enabled = state.exposureMode == ExposureMode.automatic
    ..strength = 1
    ..compensation = 0
    // Hold the existing GPU exposure factor so terrain fill cannot remeter the sky.
    ..speedUp = state.relitImagery && state.cameraLightStrength > 0 ? 0 : 3
    ..speedDown = state.relitImagery && state.cameraLightStrength > 0 ? 0 : 1;
  world.postProcess.colorGrading
    ..enabled = state.whiteBalance != 6500
    // shortcut: approximate color-temperature correction, use calibrated chromatic adaptation for colorimetry.
    ..temperature = ((state.whiteBalance - 6500) / 6500).clamp(-1.0, 1.0);
  final quality = state.renderQuality;
  world.renderScale = quality == RenderQuality.performance ? 0.7 : 1;
  final aa = switch (state.antialiasing) {
    Antialiasing.automatic => scene.AntiAliasingMode.auto,
    Antialiasing.off => scene.AntiAliasingMode.none,
    Antialiasing.fxaa => scene.AntiAliasingMode.fxaa,
    Antialiasing.msaa => scene.AntiAliasingMode.msaa,
  };
  if (world.antiAliasingMode != aa) world.antiAliasingMode = aa;
  world.renderQuality
    ..tier = switch (quality) {
      RenderQuality.performance => scene.RenderQualityTier.low,
      RenderQuality.balanced => scene.RenderQualityTier.medium,
      RenderQuality.high => scene.RenderQualityTier.high,
    }
    ..adaptive = false;
  configureTerrainShadows(world.directionalLight!, state);
  world.depthOfField
    ..enabled = state.depthOfField
    ..fStop = state.aperture
    ..focusDistance = state.focusDistance
    ..focalLength = state.focalLength / 1000
    ..sensorHeight = state.sensorHeight / 1000
    ..blurScale = 1
    ..quality = switch (quality) {
      RenderQuality.performance => scene.DepthOfFieldQuality.low,
      RenderQuality.balanced => scene.DepthOfFieldQuality.medium,
      RenderQuality.high => scene.DepthOfFieldQuality.high,
    };
  final brightness = ((state.sky.sun.altitude + 18) / 33).clamp(0.02, 1.0);
  world.fog
    ..enabled =
        state.relitImagery ||
        state.weather != Weather.clear ||
        state.weatherVisibilityKm < 100
    ..skyColorInfluence = state.relitImagery ? 1 : 0
    ..mode = scene.FogMode.exponential
    ..density = scene.Fog.visibilityDensity(state.weatherVisibilityKm * 1000)
    ..color = vm.Vector3(0.42, 0.46, 0.50) * brightness;
}
