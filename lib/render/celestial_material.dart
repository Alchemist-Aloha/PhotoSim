import 'package:flutter_scene/scene.dart' as scene;

/// Celestial proxy distances are not atmospheric path lengths.
class CelestialMaterial extends scene.UnlitMaterial {
  CelestialMaterial({super.colorTexture});

  @override
  void bind(
    pass,
    scene.TransientWriter transientsBuffer,
    scene.Lighting lighting,
  ) => super.bind(
    pass,
    transientsBuffer,
    // Unlit binding needs only the environment placeholder and view direction;
    // omit fog without bypassing exposure, tone mapping or terrain depth tests.
    scene.Lighting(
      environmentMap: lighting.environmentMap,
      cameraForward: lighting.cameraForward,
      orthographic: lighting.orthographic,
    ),
  );
}
