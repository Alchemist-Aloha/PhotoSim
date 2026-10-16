import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../models/simulation_state.dart';
import '../data/raster_cache.dart';
import 'cache_settings_panel.dart';

class CameraInspector extends StatelessWidget {
  const CameraInspector({
    super.key,
    required this.state,
    required this.onChanged,
    this.rasterCache,
    this.cacheError,
  });
  final RasterCache? rasterCache;
  final String? cacheError;
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;

  Widget control(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
    String suffix,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label  ${value.toStringAsFixed(1)}$suffix'),
      Slider(
        key: ValueKey(label),
        semanticFormatterCallback: (value) =>
            '${value.toStringAsFixed(1)}$suffix',
        label: label,
        value: value,
        min: min,
        max: max,
        onChanged: change,
      ),
    ],
  );

  Widget section(
    String title,
    IconData icon,
    List<Widget> children, {
    bool expanded = false,
  }) => ExpansionTile(
    key: PageStorageKey('inspector-$title'),
    initiallyExpanded: expanded,
    leading: Icon(icon, size: 20),
    title: Text(title),
    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
    childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('scene-inspector'),
    padding: const EdgeInsets.all(8),
    children: [
      section('Optics', Icons.camera_alt_outlined, [
        const Text('Sensor format'),
        const SizedBox(height: 8),
        SegmentedButton<Sensor>(
          showSelectedIcon: false,
          segments: [
            for (final sensor in Sensor.values)
              ButtonSegment(value: sensor, label: Text(sensor.label)),
          ],
          selected: {state.sensor},
          onSelectionChanged: (value) =>
              onChanged(state.copyWith(sensor: value.single)),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Landscape')),
            ButtonSegment(value: true, label: Text('Portrait')),
          ],
          selected: {state.portrait},
          onSelectionChanged: (value) =>
              onChanged(state.copyWith(portrait: value.single)),
        ),
        const SizedBox(height: 16),
        control(
          'Focal length',
          state.focalLength,
          SimulationState.minFocalLength,
          SimulationState.maxFocalLength,
          (value) => onChanged(state.copyWith(focalLength: value)),
          ' mm',
        ),
        Text(
          'Field of view: ${(state.horizontalFov / radians).toStringAsFixed(1)}° × '
          '${(state.verticalFov / radians).toStringAsFixed(1)}°',
        ),
      ], expanded: true),
      section('Position & orientation', Icons.explore_outlined, [
        Text(
          '${state.latitude.toStringAsFixed(5)}°, ${state.longitude.toStringAsFixed(5)}°',
        ),
        const SizedBox(height: 8),
        Text(
          'Place or drag the camera on the map.\nGround elevation: '
          '${state.groundElevation == null ? 'not loaded' : '${state.groundElevation!.toStringAsFixed(1)} m (source datum)'}',
        ),
        if (state.cameraElevation != null)
          Text(
            'Camera elevation: ${state.cameraElevation!.toStringAsFixed(1)} m${state.fixedElevation == null ? '' : ' (saved elevation override)'}',
          ),
        if (state.fixedElevation != null) ...[
          const Text(
            'Saved elevation override. WASD or changing the height offset resumes terrain-following movement.',
          ),
          TextButton(
            onPressed: () =>
                onChanged(state.copyWith(clearFixedElevation: true)),
            child: const Text('Resume ground-relative height'),
          ),
        ],
        const SizedBox(height: 16),
        control(
          'Azimuth',
          state.azimuth,
          0,
          360,
          (value) => onChanged(state.copyWith(azimuth: value)),
          '°',
        ),
        control(
          'Pitch',
          state.pitch,
          -85,
          85,
          (value) => onChanged(state.copyWith(pitch: value)),
          '°',
        ),
        control(
          'Roll',
          state.roll,
          -180,
          180,
          (value) => onChanged(state.copyWith(roll: value)),
          '°',
        ),
        control(
          state.fixedElevation == null
              ? 'Height above ground'
              : 'Ground-relative height offset',
          state.height,
          0.1,
          100,
          (value) => onChanged(state.copyWith(height: value)),
          ' m',
        ),
      ]),
      section('Exposure', Icons.exposure, [
        DropdownButtonFormField<ExposureMode>(
          key: ValueKey(state.exposureMode),
          initialValue: state.exposureMode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Exposure mode'),
          items: [
            for (final mode in ExposureMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(state.copyWith(exposureMode: value));
          },
        ),
        const SizedBox(height: 16),
        control(
          'Exposure aperture',
          state.aperture,
          1.4,
          22,
          (value) => onChanged(state.copyWith(aperture: value)),
          ' f-number',
        ),
        if (state.exposureMode == ExposureMode.manual) ...[
          Text('ISO ${state.iso.round()}'),
          Slider(
            key: const ValueKey('iso'),
            min: 0,
            max: 9,
            value: (math.log(state.iso / 50) / math.ln2).clamp(0, 9),
            semanticFormatterCallback: (value) =>
                'ISO ${(50 * math.pow(2, value)).round()}',
            onChanged: (value) => onChanged(
              state.copyWith(iso: (50 * math.pow(2, value)).toDouble()),
            ),
          ),
          Text('Shutter ${state.shutterLabel}'),
          Slider(
            key: const ValueKey('shutter'),
            min: -math.log(8000) / math.ln2,
            max: math.log(30) / math.ln2,
            value: (math.log(state.shutterSeconds) / math.ln2).clamp(
              -math.log(8000) / math.ln2,
              math.log(30) / math.ln2,
            ),
            semanticFormatterCallback: (value) =>
                '${math.pow(2, value).toStringAsFixed(5)} seconds',
            onChanged: (value) => onChanged(
              state.copyWith(shutterSeconds: math.pow(2, value).toDouble()),
            ),
          ),
        ],
        control(
          'Exposure compensation',
          state.exposureCompensation,
          -5,
          5,
          (value) => onChanged(state.copyWith(exposureCompensation: value)),
          ' EV',
        ),
        control(
          'White balance',
          state.whiteBalance,
          2000,
          12000,
          (value) => onChanged(state.copyWith(whiteBalance: value)),
          ' K',
        ),
        const Text(
          'Manual exposure uses photographic stop ratios relative to f/8, 1/125 s, ISO 100. Auto meters scene luminance. Enhanced visibility ignores ISO/shutter. Brightness and white balance are approximate, not calibrated; no noise or motion blur.',
        ),
      ]),
      section('Depth of field', Icons.blur_on, [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable depth of field'),
          value: state.depthOfField,
          onChanged: (value) => onChanged(state.copyWith(depthOfField: value)),
        ),
        control(
          'Aperture (f-number)',
          state.aperture,
          1.4,
          22,
          (value) => onChanged(state.copyWith(aperture: value)),
          '',
        ),
        Text(
          'Focus distance: ${state.focusDistance >= 1000000 ? '∞ (1,000 km)' : '${state.focusDistance.toStringAsFixed(1)} m'}',
        ),
        Slider(
          key: const ValueKey('focus-distance'),
          label: 'Focus distance',
          semanticFormatterCallback: (value) =>
              '${math.pow(10, value).toStringAsFixed(1)} meters',
          min: 0,
          max: 6,
          value: (math.log(state.focusDistance) / math.ln10).clamp(0, 6),
          onChanged: (value) => onChanged(
            state.copyWith(focusDistance: math.pow(10, value).toDouble()),
          ),
        ),
        const Text(
          'Smaller f-numbers increase out-of-focus blur and brighten Manual exposure. ISO/shutter controls are in Exposure.',
        ),
      ]),
      section('Weather', Icons.cloud_outlined, [
        DropdownButtonFormField<Weather>(
          key: ValueKey(state.weather),
          initialValue: state.weather,
          decoration: const InputDecoration(labelText: 'Weather preset'),
          items: [
            for (final weather in Weather.values)
              DropdownMenuItem(value: weather, child: Text(weather.label)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(state.copyWith(weather: value));
          },
        ),
        const SizedBox(height: 16),
        control(
          'Visibility',
          state.weatherVisibilityKm,
          0.1,
          100,
          (value) => onChanged(state.copyWith(weatherVisibilityKm: value)),
          ' km',
        ),
        control(
          'Light transmission',
          state.weatherLightTransmission * 100,
          0,
          100,
          (value) =>
              onChanged(state.copyWith(weatherLightTransmission: value / 100)),
          '%',
        ),
        if (state.weather == Weather.rain)
          control(
            'Rain intensity',
            state.rainIntensity * 100,
            0,
            100,
            (value) => onChanged(state.copyWith(rainIntensity: value / 100)),
            '%',
          ),
        TextButton(
          onPressed: () => onChanged(
            state.copyWith(
              weatherVisibilityKm: state.weather.visibilityKm,
              weatherLightTransmission: state.weather.lightTransmission,
              rainIntensity: state.weather.rainIntensity,
            ),
          ),
          child: const Text('Reset weather parameters'),
        ),
        const Text(
          'Illustrative conditions, not a forecast. Changing presets restores their defaults. Rain intensity controls screen-space streak density, not measured precipitation.',
        ),
      ]),
      section('Rendering', Icons.tune, [
        DropdownButtonFormField<RenderQuality>(
          key: ValueKey(state.renderQuality),
          initialValue: state.renderQuality,
          decoration: const InputDecoration(labelText: 'Render quality'),
          items: [
            for (final quality in RenderQuality.values)
              DropdownMenuItem(value: quality, child: Text(quality.label)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(state.copyWith(renderQuality: value));
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Antialiasing>(
          key: ValueKey(state.antialiasing),
          initialValue: state.antialiasing,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Antialiasing'),
          items: [
            for (final mode in Antialiasing.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(state.copyWith(antialiasing: value));
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'FXAA is enabled by default. MSAA falls back to FXAA if unsupported; Auto follows the quality preset.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Approximate relighting'),
          value: state.relitImagery,
          onChanged: (value) => onChanged(state.copyWith(relitImagery: value)),
        ),
        Text(
          state.relitImagery
              ? 'UTC-driven Sun/Moon light · approximate atmosphere'
              : state.atmosphericEffects || state.depthOfField
              ? 'Illustrative weather/DOF · captured shadows remain'
              : 'Natural imagery retains captured lighting',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Constellation guides'),
          value: state.showConstellations,
          onChanged: (value) =>
              onChanged(state.copyWith(showConstellations: value)),
        ),
      ]),
      section('Composition guides', Icons.grid_3x3, [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Crosshair'),
          value: state.showCrosshair,
          onChanged: (value) => onChanged(state.copyWith(showCrosshair: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Rule of thirds'),
          value: state.showGrid,
          onChanged: (value) => onChanged(state.copyWith(showGrid: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Horizon level'),
          value: state.showLevel,
          onChanged: (value) => onChanged(state.copyWith(showLevel: value)),
        ),
        const Text(
          'Composition guides are omitted from PNG exports. The level is the geometric horizontal plane, not a terrain-horizon prediction.',
        ),
      ]),
      section('Storage', Icons.storage, [
        CacheSettingsPanel(cache: rasterCache, error: cacheError),
      ]),
      section('About this preview', Icons.info_outline, [
        const Text(
          'Linux MVP\nSun/Moon readouts are airless topocentric centers; no refraction or terrain-horizon prediction. Relighting is approximate; photographic shadows remain in the imagery.',
        ),
      ]),
    ],
  );
}
