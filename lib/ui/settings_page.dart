import 'package:flutter/material.dart';

import '../data/raster_cache.dart';
import '../models/simulation_state.dart';
import 'cache_settings_panel.dart';

/// App-wide, low-frequency preferences kept out of the camera inspector.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.state,
    required this.onChanged,
    this.rasterCache,
    this.cacheError,
  });

  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;
  final RasterCache? rasterCache;
  final String? cacheError;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SimulationState state = widget.state;

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) state = widget.state;
  }

  void update(SimulationState next) {
    setState(() => state = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rendering', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<RenderQuality>(
                    key: ValueKey(state.renderQuality),
                    initialValue: state.renderQuality,
                    decoration: const InputDecoration(
                      labelText: 'Render quality',
                    ),
                    items: [
                      for (final quality in RenderQuality.values)
                        DropdownMenuItem(
                          value: quality,
                          child: Text(quality.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        update(state.copyWith(renderQuality: value));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Antialiasing>(
                    key: ValueKey(state.antialiasing),
                    initialValue: state.antialiasing,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Antialiasing',
                    ),
                    items: [
                      for (final mode in Antialiasing.values)
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        update(state.copyWith(antialiasing: value));
                      }
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
                    onChanged: (value) =>
                        update(state.copyWith(relitImagery: value)),
                  ),
                  Text(
                    state.relitImagery
                        ? 'UTC-driven Sun/Moon light · approximate atmosphere'
                        : state.atmosphericEffects || state.depthOfField
                        ? 'Illustrative weather/DOF · captured shadows remain'
                        : 'Natural imagery retains captured lighting',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.cameraLightStrength == 0
                        ? 'Camera light: off'
                        : 'Camera light: ${state.cameraLightStrength.toStringAsFixed(0)}%',
                  ),
                  Semantics(
                    label: 'Camera light strength',
                    child: Slider(
                      key: const ValueKey('camera-light-strength'),
                      value: state.cameraLightStrength,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      semanticFormatterCallback: (value) =>
                          value == 0 ? 'Off' : '${value.round()} percent',
                      onChanged: state.relitImagery
                          ? (value) => update(
                              state.copyWith(cameraLightStrength: value),
                            )
                          : null,
                    ),
                  ),
                  const Text(
                    'Terrain-only preview fill from the camera. 0% is off; requires approximate relighting. Auto exposure is held while the light is on.',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Constellation guides'),
                    value: state.showConstellations,
                    onChanged: (value) =>
                        update(state.copyWith(showConstellations: value)),
                  ),
                  const Divider(height: 32),
                  Text('Storage', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  CacheSettingsPanel(
                    cache: widget.rasterCache,
                    error: widget.cacheError,
                  ),
                  const Divider(height: 32),
                  Text('About this preview', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'PhotoSim\nSun/Moon readouts are airless topocentric centers; no refraction or terrain-horizon prediction. Relighting is approximate; photographic shadows remain in the imagery.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
