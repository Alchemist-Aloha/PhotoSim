import 'package:flutter/material.dart';

/// Short landscape windows keep tools reachable without covering the photograph.
class PreviewTools extends StatelessWidget {
  const PreviewTools({
    super.key,
    required this.onTerrain,
    required this.onConstellations,
    required this.constellations,
    this.onExport,
  });
  final VoidCallback onTerrain, onConstellations;
  final VoidCallback? onExport;
  final bool constellations;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'Preview tools',
    icon: const Icon(Icons.more_horiz),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 0, child: Text('Terrain range')),
      CheckedPopupMenuItem(
        value: 1,
        checked: constellations,
        child: const Text('Constellations'),
      ),
      PopupMenuItem(
        value: 2,
        enabled: onExport != null,
        child: const Text('Export PNG'),
      ),
    ],
    onSelected: (value) {
      switch (value) {
        case 0:
          onTerrain();
        case 1:
          onConstellations();
        case 2:
          onExport?.call();
      }
    },
  );
}
