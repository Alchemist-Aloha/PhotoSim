import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../core/sunlight.dart';

/// Spherical single scattering, retaining the existing daylight authoring API.
class AtmosphereSky extends scene.PhysicalSkySource {
  AtmosphereSky._(this.shader)
    : super(
        turbidity: 2,
        rayleighCoefficient: 1,
        rayleighColor: vm.Vector3(
          clearSkyRayleigh.red,
          clearSkyRayleigh.green,
          clearSkyRayleigh.blue,
        ),
        mieCoefficient: clearSkyMie,
        mieEccentricity: 0.76,
      );

  static Future<AtmosphereSky> load() async =>
      AtmosphereSky._(await scene.loadFmatSky('assets/atmosphere/sky.fmat'));

  final scene.PreprocessedSky shader;
  vm.Vector3 moonDirection = vm.Vector3(0, -1, 0);
  double lunarRadiance = 0;
  double observerHeight = 2;
  int viewSamples = 8, lightSamples = 4;

  @override
  gpu.Shader get fragmentShader => shader.fragmentShader;

  @override
  void bind(
    pass,
    scene.TransientWriter transientsBuffer,
    scene.EnvironmentMap environment,
  ) {
    shader.parameters
      ..setVec3('sun_direction', sunDirection)
      ..setVec3('moon_direction', moonDirection)
      ..setVec3('rayleigh', rayleighColor * (rayleighCoefficient * 0.1))
      ..setVec3('mie', mieColor * (turbidity * mieCoefficient * 0.434))
      ..setVec3('ground_color', groundColor)
      ..setFloat('solar_radius', sunAngularRadius)
      ..setFloat('energy', energy)
      ..setFloat('lunar_radiance', lunarRadiance)
      ..setFloat('observer_height', observerHeight.clamp(2, 10000) / 1000)
      ..setFloat('eccentricity', mieEccentricity)
      ..setInt('view_samples', viewSamples)
      ..setInt('light_samples', lightSamples);
    shader.bind(pass, transientsBuffer, environment);
  }
}
