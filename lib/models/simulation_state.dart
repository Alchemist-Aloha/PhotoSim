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

@immutable
class SimulationState {
  static const minFocalLength = 8.0, maxFocalLength = 600.0;

  SimulationState({
    this.latitude = 37.744,
    this.longitude = -119.59,
    this.azimuth = 0,
    this.pitch = 8,
    this.height = 1.7,
    this.sensor = Sensor.fullFrame,
    this.focalLength = 24,
    this.groundElevation,
    this.relitImagery = false,
    this.target = CelestialTarget.none,
    DateTime? timestamp,
  }) : timestamp = (timestamp ?? DateTime.utc(2026, 6, 21, 19)).toUtc() {
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
        !height.isFinite ||
        height < 0.1 ||
        height > 100 ||
        !focalLength.isFinite ||
        focalLength < minFocalLength ||
        focalLength > maxFocalLength ||
        (groundElevation != null &&
            (!groundElevation!.isFinite ||
                groundElevation! < -12000 ||
                groundElevation! > 10000))) {
      throw ArgumentError('Invalid camera parameters');
    }
  }

  final double latitude, longitude, azimuth, pitch, height, focalLength;
  final double? groundElevation;
  final bool relitImagery;
  final Sensor sensor;
  final DateTime timestamp;
  final CelestialTarget target;

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

  /// Rectangular optical frustum, not a terrain visibility prediction.
  bool containsDirection(Vector3 direction) {
    final yaw = azimuth * radians, tilt = pitch * radians;
    final forward = Vector3(
      math.sin(yaw) * math.cos(tilt),
      math.sin(tilt),
      -math.cos(yaw) * math.cos(tilt),
    );
    final right = Vector3(math.cos(yaw), 0, math.sin(yaw));
    final up = right.cross(forward);
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
  double get horizontalFov => 2 * math.atan(sensor.width / (2 * focalLength));
  double get verticalFov => 2 * math.atan(sensor.height / (2 * focalLength));

  SimulationState copyWith({
    double? latitude,
    double? longitude,
    double? azimuth,
    double? pitch,
    double? height,
    Sensor? sensor,
    double? focalLength,
    double? groundElevation,
    bool? relitImagery,
    CelestialTarget? target,
    DateTime? timestamp,
  }) {
    return SimulationState(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      azimuth: (azimuth ?? this.azimuth) % 360,
      pitch: (pitch ?? this.pitch).clamp(-85, 85),
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
      target: target ?? this.target,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
