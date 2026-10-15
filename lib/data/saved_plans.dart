import 'dart:convert';
import 'dart:io';

import '../models/simulation_state.dart';

class SavedPlan {
  SavedPlan(this.name, this.state) {
    if (name.trim().isEmpty || name.length > 80) {
      throw const FormatException('Plan name must contain 1–80 characters');
    }
  }
  final String name;
  final SimulationState state;

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'version': 2,
    'name': name,
    'timestamp': state.timestamp.toIso8601String(),
    'latitude': state.latitude,
    'longitude': state.longitude,
    'azimuth': state.azimuth,
    'pitch': state.pitch,
    'height': state.height,
    'sensor': state.sensor.name,
    'focalLength': state.focalLength,
    'target': state.target.name,
    'relitImagery': state.relitImagery,
    'showConstellations': state.showConstellations,
    'terrainRings': state.terrainRings,
    'terrainForwardKm': state.terrainForwardKm,
    'terrainRenderKm': state.terrainRenderKm,
    'renderQuality': state.renderQuality.name,
    'weather': state.weather.name,
    'weatherVisibilityKm': state.weatherVisibilityKm,
    'weatherLightTransmission': state.weatherLightTransmission,
    'rainIntensity': state.rainIntensity,
    'depthOfField': state.depthOfField,
    'aperture': state.aperture,
    'focusDistance': state.focusDistance,
  });

  static SavedPlan decode(String source) {
    if (utf8.encode(source).length > 32768) {
      throw const FormatException('Plan exceeds 32 KiB');
    }
    final json = jsonDecode(source);
    if (json is! Map ||
        json['version'] is! int ||
        ![1, 2].contains(json['version'])) {
      throw const FormatException('Unsupported plan format/version');
    }
    try {
      final timestamp = DateTime.parse(json['timestamp'] as String);
      if (!timestamp.isUtc ||
          timestamp.toIso8601String() != json['timestamp']) {
        throw const FormatException('Plan timestamp must be canonical UTC');
      }
      double number(String key) => (json[key] as num).toDouble();
      return SavedPlan(
        json['name'] as String,
        SimulationState(
          timestamp: timestamp,
          latitude: number('latitude'),
          longitude: number('longitude'),
          azimuth: number('azimuth'),
          pitch: number('pitch'),
          height: number('height'),
          sensor: Sensor.values.byName(json['sensor'] as String),
          focalLength: number('focalLength'),
          target: CelestialTarget.values.byName(json['target'] as String),
          relitImagery: json['relitImagery'] as bool,
          showConstellations: json['showConstellations'] as bool? ?? false,
          terrainRings: json['terrainRings'] as int? ?? 1,
          terrainForwardKm: (json['terrainForwardKm'] as num?)?.toDouble() ?? 0,
          terrainRenderKm: (json['terrainRenderKm'] as num?)?.toDouble() ?? 40,
          renderQuality: RenderQuality.values.byName(
            json['renderQuality'] as String? ?? 'balanced',
          ),
          weather: Weather.values.byName(json['weather'] as String? ?? 'clear'),
          weatherVisibilityKm: (json['weatherVisibilityKm'] as num?)
              ?.toDouble(),
          weatherLightTransmission: (json['weatherLightTransmission'] as num?)
              ?.toDouble(),
          rainIntensity: (json['rainIntensity'] as num?)?.toDouble(),
          depthOfField: json['depthOfField'] as bool? ?? false,
          aperture: (json['aperture'] as num?)?.toDouble() ?? 8,
          focusDistance: (json['focusDistance'] as num?)?.toDouble() ?? 1000,
        ),
      );
    } on Object {
      throw const FormatException('Invalid photography plan');
    }
  }
}

/// Native local snapshots. Every save creates a new file, never replaces a plan.
class PlanRepository {
  PlanRepository(this.directory);
  final Directory directory;

  Future<File> save(SavedPlan plan) async {
    final source = plan.encode();
    await directory.create(recursive: true);
    final staging = await directory.createTemp('.pending-');
    final file = File(
      '${directory.path}/plan-${staging.uri.pathSegments.where((s) => s.isNotEmpty).last.substring(9)}.json',
    );
    var reserved = false;
    try {
      final temporary = File('${staging.path}/plan.json');
      await temporary.writeAsString(source, flush: true);
      await file.create(exclusive: true);
      reserved = true;
      await temporary.rename(file.path);
      return file;
    } catch (_) {
      if (reserved && await file.exists()) await file.delete();
      rethrow;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<({List<SavedPlan> plans, int unreadable})> loadAll() async {
    if (!await directory.exists()) return (plans: <SavedPlan>[], unreadable: 0);
    final plans = <SavedPlan>[];
    var unreadable = 0;
    final files = await directory.list(followLinks: false).toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        if (await file.length() > 32768) {
          throw const FormatException('Plan exceeds 32 KiB');
        }
        plans.add(SavedPlan.decode(await file.readAsString()));
      } on Object {
        unreadable++;
      }
    }
    return (plans: plans, unreadable: unreadable);
  }
}
