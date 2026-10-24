import 'dart:convert';
import 'dart:math' as math;

import '../core/local_time.dart';
import '../models/simulation_state.dart';
import 'saved_plans.dart';

/// Describe the captured state, not later edits to the shared composition.
String enhancementPrompt(
  SimulationState state, {
  required String credits,
  required int width,
  required int height,
}) {
  final clock = localClock(
    timestamp: state.timestamp,
    latitude: state.latitude,
    longitude: state.longitude,
  );
  final sky = state.sky;
  final metadata = {
    ...SavedPlan('Export snapshot', state).toJson()
      ..remove('version')
      ..remove('name'),
    'groundElevationMeters': state.groundElevation,
    'cameraElevationMeters': state.cameraElevation,
    'estimatedLocalTime': clock.time?.toIso8601String(),
    'estimatedTimeZone': clock.zoneId,
    'localTimeStatus': clock.warning,
    'sensorWidthMm': state.sensorWidth,
    'sensorHeightMm': state.sensorHeight,
    'horizontalFovDegrees': state.horizontalFov * 180 / math.pi,
    'verticalFovDegrees': state.verticalFov * 180 / math.pi,
    'sunAzimuthDegrees': sky.sun.azimuth,
    'sunAltitudeDegrees': sky.sun.altitude,
    'moonAzimuthDegrees': sky.moon.azimuth,
    'moonAltitudeDegrees': sky.moon.altitude,
    'moonIlluminationFraction': sky.moonIllumination,
    'galacticCenterAzimuthDegrees': state.galacticCenter.azimuth,
    'galacticCenterAltitudeDegrees': state.galacticCenter.altitude,
    'outputWidthPixels': width,
    'outputHeightPixels': height,
    'sourceCredits': credits,
  };
  return '''Enhance the attached PhotoSim render into a natural, photorealistic landscape photograph. Use the image as the composition reference and the metadata below as constraints.

Preserve the camera viewpoint, framing, horizon, terrain silhouettes, perspective, and calculated Sun, Moon and star positions. Improve surface detail, vegetation, atmospheric depth and lighting realism without inventing landmarks or moving celestial bodies. Respect the lens, exposure, white balance, depth of field and illustrative weather settings. Preserve the source attribution strip, legible and unchanged.

This is a planning simulation, not a real photograph, surveyed terrain, calibrated exposure or weather forecast. Terrain and imagery may be coarse, outdated and already shadowed; imagery acquisition time is unknown and is NOT the simulation timestamp. Timezone boundaries are estimated; UTC is authoritative. Unknown elevations/local times are null, not zero. The composition frame, grid, crosshair and level are omitted from the PNG. If constellation guides are enabled, remove their illustrative lines and labels without moving the stars. Do not treat AI-added details as factual location evidence.

Capture metadata (angles in degrees; coordinates in WGS84; height/elevation/focus distance in meters; focal length/sensor in mm; shutter in seconds; white balance in kelvin; cloud/rain/light amounts are fractions):
${const JsonEncoder.withIndent('  ').convert(metadata)}''';
}
