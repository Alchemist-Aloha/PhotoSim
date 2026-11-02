import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../core/sunlight.dart';

/// Spherical scattering with ozone and precomputed isotropic multiple scattering.
class AtmosphereSky extends scene.PhysicalSkySource {
  AtmosphereSky._(this.shader, this._multipleScattering)
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

  static Future<AtmosphereSky> load() async {
    final (shader, multipleScattering) = await (
      scene.loadFmatSky('assets/atmosphere/sky.fmat'),
      scene.Texture2D.fromAsset(
        'assets/atmosphere/multiple_scattering.png',
        content: scene.TextureContent.data,
        sampling: const scene.TextureSampling(
          mipmaps: false,
          addressMode: gpu.SamplerAddressMode.clampToEdge,
        ),
      ),
    ).wait;
    return AtmosphereSky._(shader, multipleScattering);
  }

  final scene.PreprocessedSky shader;
  final scene.Texture2D _multipleScattering;
  vm.Vector3 moonDirection = vm.Vector3(0, -1, 0);
  double lunarRadiance = 0;
  double observerHeight = 2;
  int viewSamples = 8, lightSamples = 8;

  @override
  gpu.Shader get fragmentShader => shader.fragmentShader;

  @override
  void bind(
    pass,
    scene.TransientWriter transientsBuffer,
    scene.EnvironmentMap environment,
  ) {
    shader.parameters
      ..setTexture(
        'multiple_scattering',
        _multipleScattering.gpuTexture,
        sampler: _multipleScattering.sampledSampler,
      )
      ..setVec3('sun_direction', sunDirection)
      ..setVec3('moon_direction', moonDirection)
      ..setVec3('rayleigh', rayleighColor * (rayleighCoefficient * 0.1))
      ..setVec3('mie', mieColor * (turbidity * mieCoefficient * 0.434))
      ..setVec3(
        'ozone',
        vm.Vector3(clearSkyOzone.red, clearSkyOzone.green, clearSkyOzone.blue),
      )
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
