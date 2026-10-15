import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;

import '../models/simulation_state.dart';

/// Existing backend effects; no geographic resources change with these settings.
void configurePhotography(scene.Scene world, SimulationState state) {
  final quality = state.renderQuality;
  world.renderScale = quality == RenderQuality.performance ? 0.7 : 1;
  world.renderQuality
    ..tier = switch (quality) {
      RenderQuality.performance => scene.RenderQualityTier.low,
      RenderQuality.balanced => scene.RenderQualityTier.medium,
      RenderQuality.high => scene.RenderQualityTier.high,
    }
    ..adaptive = false;
  world.directionalLight!.castsShadow =
      state.relitImagery && state.weather == Weather.clear;
  world.directionalLight!.shadowMapResolution = switch (quality) {
    RenderQuality.performance => 1024,
    RenderQuality.balanced => 2048,
    RenderQuality.high => 4096,
  };
  world.depthOfField
    ..enabled = state.depthOfField
    ..fStop = state.aperture
    ..focusDistance = state.focusDistance
    ..focalLength = state.focalLength / 1000
    ..sensorHeight = state.sensor.height / 1000
    ..blurScale = 1
    ..quality = switch (quality) {
      RenderQuality.performance => scene.DepthOfFieldQuality.low,
      RenderQuality.balanced => scene.DepthOfFieldQuality.medium,
      RenderQuality.high => scene.DepthOfFieldQuality.high,
    };
  final brightness = ((state.sky.sun.altitude + 18) / 33).clamp(0.02, 1.0);
  world.fog
    ..enabled = state.weather != Weather.clear
    ..mode = scene.FogMode.exponential
    ..density = scene.Fog.visibilityDensity(switch (state.weather) {
      Weather.clear => 100000,
      Weather.cloudy => 18000,
      Weather.fog => 700,
      Weather.rain => 3500,
    })
    ..color = vm.Vector3(0.42, 0.46, 0.50) * brightness;
}

double weatherTransmission(Weather weather) => switch (weather) {
  Weather.clear => 1,
  Weather.cloudy => 0.35,
  Weather.fog => 0.2,
  Weather.rain => 0.15,
};
