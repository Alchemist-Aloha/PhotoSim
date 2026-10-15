import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../models/simulation_state.dart';

class TerrainRangeDialog extends StatefulWidget {
  const TerrainRangeDialog({super.key, required this.state});
  final SimulationState state;

  @override
  State<TerrainRangeDialog> createState() => _TerrainRangeDialogState();
}

class _TerrainRangeDialogState extends State<TerrainRangeDialog> {
  late int rings = widget.state.terrainRings;
  late double forward = widget.state.terrainForwardKm;
  late double render = widget.state.terrainRenderKm;

  @override
  Widget build(BuildContext context) {
    final tileKm =
        2 *
        math.pi *
        6378137 /
        8192 /
        1000 *
        math.cos(widget.state.latitude * radians);
    return AlertDialog(
      title: const Text('Terrain range'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Surrounding fetch radius: $rings tile rings (~${(rings * tileKm).toStringAsFixed(1)} km)',
              ),
              Semantics(
                label: 'Surrounding fetch radius',
                child: Slider(
                  key: const ValueKey('terrain-rings'),
                  value: rings.toDouble(),
                  min: 1,
                  max: 3,
                  divisions: 2,
                  label: '$rings rings',
                  onChanged: (value) => setState(() => rings = value.round()),
                ),
              ),
              Text(
                'Forward fetch distance: ${forward.toStringAsFixed(0)} km${forward == 0 ? ' (off)' : ''}',
              ),
              Semantics(
                label: 'Forward fetch distance',
                child: Slider(
                  key: const ValueKey('terrain-forward'),
                  value: forward,
                  min: 0,
                  max: 40,
                  divisions: 40,
                  label: '${forward.toStringAsFixed(0)} km',
                  onChanged: (value) => setState(() => forward = value),
                ),
              ),
              Text('Render distance: ${render.toStringAsFixed(0)} km'),
              Semantics(
                label: 'Terrain render distance',
                child: Slider(
                  key: const ValueKey('terrain-render'),
                  value: render,
                  min: 2,
                  max: 40,
                  divisions: 38,
                  label: '${render.toStringAsFixed(0)} km',
                  onChanged: (value) => setState(() => render = value),
                ),
              ),
              const Text(
                'Forward coverage follows the camera FOV, pitch and aim after you stop adjusting. '
                'Nearby tiles stay available in all directions. Distant tiles are coarser (maximum 256 tiles). '
                'Rendering uses whole-tile distance limits and view-frustum culling; '
                'it cannot show terrain beyond the fetched area. Larger ranges use more data and memory.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            rings: rings,
            forwardKm: forward,
            renderKm: render,
          )),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
