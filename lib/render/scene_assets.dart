import 'package:flutter_scene/scene.dart' as scene;

import 'atmosphere_sky.dart';
import 'clouds.dart';

/// Device-level scene inputs that do not belong to any scene graph.
///
/// Switching between the map and 3D Preview tears the scene down and rebuilds
/// it; decoding and uploading these assets again cost ~60 ms of every re-entry.
/// They are immutable once loaded, so one process-wide copy is shared by every
/// workspace instance.
class SceneAssets {
  SceneAssets._({
    required this.atmosphere,
    required this.lunarAlbedo,
    required this.milkyWay,
    required this.cloudMaterial,
    required this.cloudNoise,
    required this.waterMaterial,
  });

  final AtmosphereSky atmosphere;
  final scene.Texture2D lunarAlbedo, milkyWay;
  final scene.PreprocessedMaterial cloudMaterial;
  final scene.Texture2D cloudNoise;
  final scene.PreprocessedMaterial waterMaterial;

  static Future<SceneAssets>? _pending;

  /// Loads once per process; concurrent callers await the same future. A failed
  /// load is forgotten so the next 3D entry can retry.
  static Future<SceneAssets> load() => _pending ??= _load().then(
    (assets) => assets,
    onError: (Object error, StackTrace stack) {
      _pending = null;
      Error.throwWithStackTrace(error, stack);
    },
  );

  static Future<SceneAssets> _load() async {
    final (atmosphere, lunarAlbedo, milkyWay, clouds, water) = await (
      AtmosphereSky.load(),
      scene.Texture2D.fromAsset('assets/moon/lroc_color_2k.jpg', maxSize: 2048),
      scene.Texture2D.fromAsset('assets/sky/milky_way.png'),
      CloudRenderer.loadShared(),
      scene.loadFmatMaterial('assets/atmosphere/water.fmat'),
    ).wait;
    return SceneAssets._(
      atmosphere: atmosphere,
      lunarAlbedo: lunarAlbedo,
      milkyWay: milkyWay,
      cloudMaterial: clouds.material,
      cloudNoise: clouds.noise,
      waterMaterial: water,
    );
  }
}
