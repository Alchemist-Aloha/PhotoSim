import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/astronomy.dart';
import '../core/geo.dart' show radians;
import '../core/night_sky.dart';

import 'package:vector_math/vector_math_64.dart' show Vector3;

enum CelestialTarget {
  none('No target'),
  sun('Sun'),
  moon('Moon'),
  galacticCenter('Galactic center');

  const CelestialTarget(this.label);
  final String label;
}

enum Sensor {
  fullFrame('Full-frame', 36, 24),
  apsC('APS-C', 23.5, 15.6);

  const Sensor(this.label, this.width, this.height);
  final String label;
  final double width;
  final double height;
}

enum RenderQuality {
  performance('Performance'),
  balanced('Balanced'),
  high('High');

  const RenderQuality(this.label);
  final String label;
}

enum Antialiasing {
  automatic('Auto (quality preset)'),
  off('Off'),
  fxaa('FXAA'),
  msaa('MSAA 4×');

  const Antialiasing(this.label);
  final String label;
}

enum ExposureMode {
  enhanced('Enhanced visibility'),
  automatic('Auto exposure'),
  manual('Manual exposure');

  const ExposureMode(this.label);
  final String label;
}

enum Weather {
  clear('Clear', 100, 1, 0),
  cloudy('Cloudy', 18, 0.35, 0),
  fog('Fog', 0.7, 0.2, 0),
  rain('Rain', 3.5, 0.15, 0.6);

  const Weather(
    this.label,
    this.visibilityKm,
    this.lightTransmission,
    this.rainIntensity,
  );
  final String label;
  final double visibilityKm, lightTransmission, rainIntensity;
}

@immutable
class SimulationState {
  static const minFocalLength = 8.0, maxFocalLength = 600.0;

  SimulationState({
    this.latitude = 37.744,
    this.longitude = -119.59,
    this.azimuth = 0,
    this.pitch = 8,
    this.roll = 0,
    this.portrait = false,
    this.showCrosshair = true,
    this.showGrid = false,
    this.showLevel = false,
    this.exposureMode = ExposureMode.enhanced,
    this.iso = 100,
    this.shutterSeconds = 1 / 125,
    this.exposureCompensation = 0,
    this.whiteBalance = 6500,
    this.height = 1.7,
    this.sensor = Sensor.fullFrame,
    this.focalLength = 24,
    this.groundElevation,
    this.relitImagery = true,
    this.showConstellations = false,
    this.terrainRings = 1,
    this.terrainForwardKm = 0,
    this.terrainRenderKm = 40,
    this.target = CelestialTarget.none,
    this.renderQuality = RenderQuality.balanced,
    this.antialiasing = Antialiasing.fxaa,
    this.weather = Weather.clear,
    double? weatherVisibilityKm,
    double? weatherLightTransmission,
    double? rainIntensity,
    this.depthOfField = false,
    this.aperture = 8,
    this.focusDistance = 1000,
    DateTime? timestamp,
  }) : weatherVisibilityKm = weatherVisibilityKm ?? weather.visibilityKm,
       weatherLightTransmission =
           weatherLightTransmission ?? weather.lightTransmission,
       rainIntensity = rainIntensity ?? weather.rainIntensity,
       timestamp = (timestamp ?? DateTime.now()).toUtc() {
    if (this.timestamp.year < 1900 ||
        this.timestamp.year > 2100 ||
        !latitude.isFinite ||
        latitude.abs() > 85.05112878 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        !azimuth.isFinite ||
        azimuth < 0 ||
        azimuth >= 360 ||
        !pitch.isFinite ||
        pitch.abs() > 85 ||
        !roll.isFinite ||
        roll.abs() > 180 ||
        !iso.isFinite ||
        iso < 50 ||
        iso > 25600 ||
        !shutterSeconds.isFinite ||
        shutterSeconds < 1 / 8000 ||
        shutterSeconds > 30 ||
        !exposureCompensation.isFinite ||
        exposureCompensation.abs() > 5 ||
        !whiteBalance.isFinite ||
        whiteBalance < 2000 ||
        whiteBalance > 12000 ||
        !height.isFinite ||
        height < 0.1 ||
        height > 100 ||
        !focalLength.isFinite ||
        focalLength < minFocalLength ||
        focalLength > maxFocalLength ||
        !this.weatherVisibilityKm.isFinite ||
        this.weatherVisibilityKm < 0.1 ||
        this.weatherVisibilityKm > 100 ||
        !this.weatherLightTransmission.isFinite ||
        this.weatherLightTransmission < 0 ||
        this.weatherLightTransmission > 1 ||
        !this.rainIntensity.isFinite ||
        this.rainIntensity < 0 ||
        this.rainIntensity > 1 ||
        !aperture.isFinite ||
        aperture < 1.4 ||
        aperture > 22 ||
        !focusDistance.isFinite ||
        focusDistance < 1 ||
        focusDistance > 1000000 ||
        terrainRings < 1 ||
        terrainRings > 3 ||
        !terrainForwardKm.isFinite ||
        terrainForwardKm < 0 ||
        terrainForwardKm > 40 ||
        !terrainRenderKm.isFinite ||
        terrainRenderKm < 2 ||
        terrainRenderKm > 40 ||
        (groundElevation != null &&
            (!groundElevation!.isFinite ||
                groundElevation! < -12000 ||
                groundElevation! > 10000))) {
      throw ArgumentError('Invalid camera parameters');
    }
  }

  final double latitude, longitude, azimuth, pitch, height, focalLength;
  final double roll, iso, shutterSeconds, exposureCompensation, whiteBalance;
  final bool portrait, showCrosshair, showGrid, showLevel;
  final ExposureMode exposureMode;
  bool get exposureProcessing =>
      exposureMode != ExposureMode.enhanced ||
      exposureCompensation != 0 ||
      whiteBalance != 6500;
  double get sensorWidth => portrait ? sensor.height : sensor.width;
  double get sensorHeight => portrait ? sensor.width : sensor.height;
  String get shutterLabel => shutterSeconds < 1
      ? '1/${(1 / shutterSeconds).round()} s'
      : '${shutterSeconds.toStringAsFixed(1)} s';
  final double? groundElevation;
  final bool relitImagery, showConstellations;
  final int terrainRings;
  final double terrainForwardKm, terrainRenderKm;
  final Sensor sensor;
  final DateTime timestamp;
  final CelestialTarget target;
  final RenderQuality renderQuality;
  final Antialiasing antialiasing;
  final Weather weather;
  final double weatherVisibilityKm, weatherLightTransmission, rainIntensity;
  bool get atmosphericEffects =>
      weather != Weather.clear ||
      weatherVisibilityKm < 100 ||
      weatherLightTransmission != 1;
  final bool depthOfField;
  final double aperture, focusDistance;

  CelestialPosition get galacticCenter => ObserverSkyFrame(
    timestamp: timestamp,
    latitude: latitude,
    longitude: longitude,
  ).galacticCenter;

  CelestialPosition? get targetPosition => switch (target) {
    CelestialTarget.none => null,
    CelestialTarget.sun => sky.sun,
    CelestialTarget.moon => sky.moon,
    CelestialTarget.galacticCenter => galacticCenter,
  };

  double? get targetAngularOffset {
    final position = targetPosition;
    return position == null
        ? null
        : math.acos(
                position.direction.dot(cameraFrame.forward).clamp(-1.0, 1.0),
              ) /
              radians;
  }

  /// ENU camera basis; positive roll rotates the camera clockwise looking forward.
  ({Vector3 forward, Vector3 right, Vector3 up}) get cameraFrame {
    final yaw = azimuth * radians, tilt = pitch * radians;
    final forward = Vector3(
      math.sin(yaw) * math.cos(tilt),
      math.sin(tilt),
      -math.cos(yaw) * math.cos(tilt),
    );
    final right = Vector3(math.cos(yaw), 0, math.sin(yaw));
    final up = right.cross(forward);
    final angle = roll * radians;
    return (
      forward: forward,
      right: right * math.cos(angle) - up * math.sin(angle),
      up: up * math.cos(angle) + right * math.sin(angle),
    );
  }

  bool containsDirection(Vector3 direction) {
    final frame = cameraFrame;
    final forward = frame.forward, right = frame.right, up = frame.up;
    final depth = direction.dot(forward);
    return depth > 0 &&
        direction.dot(right).abs() <=
            depth * math.tan(horizontalFov / 2) + 1e-12 &&
        direction.dot(up).abs() <= depth * math.tan(verticalFov / 2) + 1e-12;
  }

  SkyState get sky => calculateSky(
    timestamp: timestamp,
    latitude: latitude,
    longitude: longitude,
    elevation: (groundElevation ?? 0) + height,
  );

  LatLng get location => LatLng(latitude, longitude);
  double get horizontalFov => 2 * math.atan(sensorWidth / (2 * focalLength));
  double get verticalFov => 2 * math.atan(sensorHeight / (2 * focalLength));
  double get horizontalFrustumExtent =>
      math.cos(roll * radians).abs() * math.tan(horizontalFov / 2) +
      math.sin(roll * radians).abs() * math.tan(verticalFov / 2);
  double get verticalFrustumExtent =>
      math.sin(roll * radians).abs() * math.tan(horizontalFov / 2) +
      math.cos(roll * radians).abs() * math.tan(verticalFov / 2);
  double get mapFov => 2 * math.atan(horizontalFrustumExtent);

  SimulationState copyWith({
    double? latitude,
    double? longitude,
    double? azimuth,
    double? pitch,
    double? roll,
    bool? portrait,
    bool? showCrosshair,
    bool? showGrid,
    bool? showLevel,
    ExposureMode? exposureMode,
    double? iso,
    double? shutterSeconds,
    double? exposureCompensation,
    double? whiteBalance,
    double? height,
    Sensor? sensor,
    double? focalLength,
    double? groundElevation,
    bool? relitImagery,
    bool? showConstellations,
    int? terrainRings,
    double? terrainForwardKm,
    double? terrainRenderKm,
    CelestialTarget? target,
    RenderQuality? renderQuality,
    Antialiasing? antialiasing,
    Weather? weather,
    double? weatherVisibilityKm,
    double? weatherLightTransmission,
    double? rainIntensity,
    bool? depthOfField,
    double? aperture,
    double? focusDistance,
    DateTime? timestamp,
  }) {
    return SimulationState(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      azimuth: (azimuth ?? this.azimuth) % 360,
      pitch: (pitch ?? this.pitch).clamp(-85, 85),
      roll: roll ?? this.roll,
      portrait: portrait ?? this.portrait,
      showCrosshair: showCrosshair ?? this.showCrosshair,
      showGrid: showGrid ?? this.showGrid,
      showLevel: showLevel ?? this.showLevel,
      exposureMode: exposureMode ?? this.exposureMode,
      iso: iso ?? this.iso,
      shutterSeconds: shutterSeconds ?? this.shutterSeconds,
      exposureCompensation: exposureCompensation ?? this.exposureCompensation,
      whiteBalance: whiteBalance ?? this.whiteBalance,
      height: height ?? this.height,
      sensor: sensor ?? this.sensor,
      focalLength: (focalLength ?? this.focalLength).clamp(
        minFocalLength,
        maxFocalLength,
      ),
      groundElevation:
          (latitude != null && latitude != this.latitude) ||
              (longitude != null && longitude != this.longitude)
          ? null
          : groundElevation ?? this.groundElevation,
      relitImagery: relitImagery ?? this.relitImagery,
      showConstellations: showConstellations ?? this.showConstellations,
      terrainRings: terrainRings ?? this.terrainRings,
      terrainForwardKm: terrainForwardKm ?? this.terrainForwardKm,
      terrainRenderKm: terrainRenderKm ?? this.terrainRenderKm,
      target: target ?? this.target,
      renderQuality: renderQuality ?? this.renderQuality,
      antialiasing: antialiasing ?? this.antialiasing,
      weather: weather ?? this.weather,
      weatherVisibilityKm:
          weatherVisibilityKm ??
          (weather != null && weather != this.weather
              ? weather.visibilityKm
              : this.weatherVisibilityKm),
      weatherLightTransmission:
          weatherLightTransmission ??
          (weather != null && weather != this.weather
              ? weather.lightTransmission
              : this.weatherLightTransmission),
      rainIntensity:
          rainIntensity ??
          (weather != null && weather != this.weather
              ? weather.rainIntensity
              : this.rainIntensity),
      depthOfField: depthOfField ?? this.depthOfField,
      aperture: aperture ?? this.aperture,
      focusDistance: focusDistance ?? this.focusDistance,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
