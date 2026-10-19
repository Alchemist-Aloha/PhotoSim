import 'package:flutter/material.dart';

import '../core/terrain_coverage.dart';
import '../models/simulation_state.dart';

class TerrainRangeControls extends StatelessWidget {
  const TerrainRangeControls({
    super.key,
    required this.state,
    required this.onChanged,
  });
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Surrounding fetch radius: ${state.terrainRings} tile rings'),
      Semantics(
        label: 'Surrounding fetch radius',
        child: Slider(
          key: const ValueKey('terrain-rings'),
          value: state.terrainRings.toDouble(),
          min: 1,
          max: 3,
          divisions: 2,
          label: '${state.terrainRings} rings',
          semanticFormatterCallback: (value) => '${value.round()} tile rings',
          onChanged: (value) =>
              onChanged(state.copyWith(terrainRings: value.round())),
        ),
      ),
      Text(
        'Forward fetch distance: ${state.terrainForwardKm.toStringAsFixed(0)} km${state.terrainForwardKm == 0 ? ' (off)' : ''}',
      ),
      Semantics(
        label: 'Forward fetch distance',
        child: Slider(
          key: const ValueKey('terrain-forward'),
          value: state.terrainForwardKm,
          min: 0,
          max: 40,
          divisions: 40,
          label: '${state.terrainForwardKm.toStringAsFixed(0)} km',
          semanticFormatterCallback: (value) => '${value.round()} km',
          onChanged: (value) =>
              onChanged(state.copyWith(terrainForwardKm: value)),
        ),
      ),
      Text('Render distance: ${state.terrainRenderKm.toStringAsFixed(0)} km'),
      Semantics(
        label: 'Terrain render distance',
        child: Slider(
          key: const ValueKey('terrain-render'),
          value: state.terrainRenderKm,
          min: 2,
          max: 40,
          divisions: 38,
          label: '${state.terrainRenderKm.toStringAsFixed(0)} km',
          semanticFormatterCallback: (value) => '${value.round()} km',
          onChanged: (value) =>
              onChanged(state.copyWith(terrainRenderKm: value)),
        ),
      ),
      Text(
        'Dashed map circle: ≈${(approximateTerrainLoadingRadius(state) / 1000).toStringAsFixed(1)} km requested extent.',
      ),
      const SizedBox(height: 8),
      const Text(
        'Changes apply automatically. Forward coverage follows the camera FOV, pitch and aim after you stop adjusting. '
        'Nearby tiles stay available in all directions. Distant tiles are coarser '
        '(maximum $terrainTileBudget tiles). The circle is an approximate envelope, not an exact tile boundary or download-status indicator. '
        'Rendering uses whole-tile distance limits and view-frustum culling; '
        'it cannot show terrain beyond the fetched area. Larger ranges use more data and memory.',
      ),
    ],
  );
}
