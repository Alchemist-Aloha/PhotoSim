import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/astronomy.dart';

enum Sensor {
  fullFrame('Full-frame', 36, 24),
  apsC('APS-C', 23.5, 15.6);

  const Sensor(this.label, this.width, this.height);
  final String label;
  final double width;
  final double height;
}

enum Lens {
  wide('16–35 mm', 16, 35),
  standard('24–70 mm', 24, 70),
  telephoto('70–200 mm', 70, 200),
  custom('Custom focal length', 8, 600);

  const Lens(this.label, this.min, this.max);
  final String label;
  final double min;
  final double max;
}

@immutable
class SimulationState {
  SimulationState({
    this.latitude = 37.744,
    this.longitude = -119.59,
    this.azimuth = 0,
    this.pitch = 8,
    this.height = 1.7,
    this.sensor = Sensor.fullFrame,
    this.lens = Lens.standard,
    this.focalLength = 24,
    this.groundElevation,
    this.relitImagery = false,
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
        focalLength < lens.min ||
        focalLength > lens.max ||
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
  final Lens lens;
  final DateTime timestamp;

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
    Lens? lens,
    double? focalLength,
    double? groundElevation,
    bool? relitImagery,
    DateTime? timestamp,
  }) {
    final selectedLens = lens ?? this.lens;
    return SimulationState(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      azimuth: (azimuth ?? this.azimuth) % 360,
      pitch: (pitch ?? this.pitch).clamp(-85, 85),
      height: height ?? this.height,
      sensor: sensor ?? this.sensor,
      lens: selectedLens,
      focalLength: (focalLength ?? this.focalLength).clamp(
        selectedLens.min,
        selectedLens.max,
      ),
      groundElevation:
          (latitude != null && latitude != this.latitude) ||
              (longitude != null && longitude != this.longitude)
          ? null
          : groundElevation ?? this.groundElevation,
      relitImagery: relitImagery ?? this.relitImagery,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
