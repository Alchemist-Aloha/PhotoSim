import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../models/simulation_state.dart';

class CameraInspector extends StatelessWidget {
  const CameraInspector({
    super.key,
    required this.state,
    required this.onChanged,
  });
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

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('CAMERA', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 16),
      Text(
        '${state.latitude.toStringAsFixed(5)}°, ${state.longitude.toStringAsFixed(5)}°',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        'Place or drag the camera on the map.\nGround elevation: '
        '${state.groundElevation == null ? 'not loaded' : '${state.groundElevation!.toStringAsFixed(1)} m (source datum)'}',
      ),
      const Divider(height: 32),
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
      const SizedBox(height: 20),
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
      const Divider(height: 32),
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
        'Height above ground',
        state.height,
        0.1,
        100,
        (value) => onChanged(state.copyWith(height: value)),
        ' m',
      ),
      const Divider(height: 32),
      const Text(
        'Early development build\nSun/Moon readouts are airless topocentric centers; no refraction or terrain-horizon prediction. Sun/Moon lighting is approximate. Natural imagery retains its original lighting.',
      ),
    ],
  );
}
