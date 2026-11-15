import 'package:flutter/material.dart';

/// Short landscape windows keep tools reachable without covering the photograph.
class PreviewTools extends StatelessWidget {
  const PreviewTools({
    super.key,
    required this.onConstellations,
    required this.constellations,
    this.onExport,
    this.exportBlocked,
    this.onShowStatus,
    this.warning = false,
  });

  /// Restores the full status panel when the user collapsed it.
  final VoidCallback? onShowStatus;

  /// Loading problems are hidden while collapsed; flag them on the button.
  final bool warning;

  /// Why export is unavailable, shown under the disabled menu item.
  final String? exportBlocked;
  final VoidCallback onConstellations;
  final VoidCallback? onExport;
  final bool constellations;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: warning ? 'Preview tools · loading problems' : 'Preview tools',
    icon: Icon(warning ? Icons.warning_amber : Icons.more_horiz),
    itemBuilder: (_) => [
      CheckedPopupMenuItem(
        value: 1,
        checked: constellations,
        child: const Text('Constellations'),
      ),
      PopupMenuItem(
        value: 2,
        enabled: onExport != null,
        child: exportBlocked == null || onExport != null
            ? const Text('Export PNG')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Export PNG'),
                  Text(
                    exportBlocked!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
      if (onShowStatus != null)
        const PopupMenuItem(value: 3, child: Text('Show status panel')),
    ],
    onSelected: (value) {
      switch (value) {
        case 1:
          onConstellations();
        case 2:
          onExport?.call();
        case 3:
          onShowStatus?.call();
      }
    },
  );
}
