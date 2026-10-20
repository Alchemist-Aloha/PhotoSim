import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/terrain_coverage.dart';
import '../models/simulation_state.dart';

class MapWorkspace extends StatefulWidget {
  const MapWorkspace({
    super.key,
    required this.state,
    required this.onChanged,
    this.initialCenter,
    this.initialZoom = 14,
    this.onViewChanged,
    this.guideDismissed = false,
    this.onGuideDismissedChanged,
    this.onMoveCompleted,
  });
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;
  final LatLng? initialCenter;
  final double initialZoom;
  final void Function(LatLng center, double zoom)? onViewChanged;
  final bool guideDismissed;
  final ValueChanged<bool>? onGuideDismissedChanged;
  final ValueChanged<SimulationState>? onMoveCompleted;

  @override
  State<MapWorkspace> createState() => _MapWorkspaceState();
}

class _MapWorkspaceState extends State<MapWorkspace> {
  final controller = MapController();
  final mapKey = GlobalKey();
  bool tileError = false;
  SimulationState? moveStart;

  void beginMove(DragStartDetails _) => moveStart = widget.state;

  void finishMove() {
    final before = moveStart;
    moveStart = null;
    if (before != null) widget.onMoveCompleted?.call(before);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void dragMarker(DragUpdateDetails details, bool direction) {
    final box = mapKey.currentContext!.findRenderObject()! as RenderBox;
    final next = controller.camera.screenOffsetToLatLng(
      box.globalToLocal(details.globalPosition),
    );
    widget.onChanged(
      direction
          ? widget.state.copyWith(azimuth: bearing(widget.state.location, next))
          : widget.state.copyWith(
              latitude: next.latitude.clamp(-85.05112878, 85.05112878),
              longitude: (next.longitude + 180) % 360 - 180,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final loadingRadiusKm = approximateTerrainLoadingRadius(state) / 1000;
    final handle = destination(state.location, state.azimuth, 450);
    final sky = state.sky;
    final compact =
        MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.sizeOf(context).height < 600;
    // flutter_map bounds require normalized longitudes, so split at the date line.
    final circleSegments = <List<LatLng>>[[]];
    for (final point in terrainLoadingCircle(state)) {
      final normalized = point.longitude < -180 || point.longitude > 180
          ? LatLng(point.latitude, (point.longitude + 180) % 360 - 180)
          : point;
      if (circleSegments.last.isNotEmpty &&
          (circleSegments.last.last.longitude - normalized.longitude).abs() >
              180) {
        circleSegments.add([]);
      }
      circleSegments.last.add(normalized);
    }
    final bodies = [
      ('Sun', sky.sun, const Color(0xFFFFC857)),
      ('Moon', sky.moon, const Color(0xFFADD8FF)),
      ('Galactic center', state.galacticCenter, const Color(0xFFD4ADFF)),
    ];
    return Stack(
      children: [
        FlutterMap(
          key: mapKey,
          mapController: controller,
          options: MapOptions(
            initialCenter: widget.initialCenter ?? state.location,
            initialZoom: widget.initialZoom,
            onPositionChanged: (camera, _) =>
                widget.onViewChanged?.call(camera.center, camera.zoom),
            minZoom: 3,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: (_, point) {
              widget.onChanged(
                state.copyWith(
                  latitude: point.latitude.clamp(-85.05112878, 85.05112878),
                  longitude: (point.longitude + 180) % 360 - 180,
                ),
              );
              widget.onMoveCompleted?.call(state);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'org.photosim.photosim',
              maxNativeZoom: 19,
              errorTileCallback: (_, _, _) {
                if (!tileError && mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => tileError = true);
                  });
                }
              },
            ),
            PolygonLayer(
              polygons: [
                Polygon(
                  points: fovWedge(
                    state.location,
                    state.azimuth,
                    state.mapFov,
                    1000,
                  ),
                  color: const Color(0x4434D9B0),
                  borderColor: const Color(0xFF169B7C),
                  borderStrokeWidth: 2,
                ),
              ],
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [state.location, handle],
                  color: const Color(0xFF169B7C),
                  strokeWidth: 2,
                ),
                for (final body in bodies)
                  Polyline(
                    points: [
                      state.location,
                      destination(state.location, body.$2.azimuth, 1000),
                    ],
                    color: body.$3,
                    strokeWidth: 3,
                    borderColor: const Color(0xFF16232B),
                    borderStrokeWidth: 1,
                    pattern: body.$2.altitude > 0
                        ? const StrokePattern.solid()
                        : StrokePattern.dashed(segments: [8, 5]),
                  ),
                for (final points in circleSegments)
                  if (points.length > 1)
                    Polyline(
                      points: points,
                      color: Theme.of(context).colorScheme.primary,
                      strokeWidth: 2,
                      borderColor: Theme.of(context).colorScheme.surface,
                      borderStrokeWidth: 1,
                      pattern: StrokePattern.dashed(segments: [8, 6]),
                    ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final body in bodies)
                  Marker(
                    point: destination(state.location, body.$2.azimuth, 1000),
                    width: 210,
                    height: 40,
                    child: IgnorePointer(
                      child: Semantics(
                        label:
                            '${body.$1} bearing ${body.$2.azimuth.toStringAsFixed(1)} degrees, '
                            'altitude ${body.$2.altitude.toStringAsFixed(1)} degrees. '
                            '${body.$2.altitude > 0 ? 'Above' : 'Below'} horizontal; terrain visibility unknown.',
                        excludeSemantics: true,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF16232B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                '${body.$1} alt ${body.$2.altitude.toStringAsFixed(1)}°',
                                style: TextStyle(color: body.$3),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Marker(
                  point: state.location,
                  width: 48,
                  height: 48,
                  child: Semantics(
                    label: 'Camera location. Drag to move.',
                    child: GestureDetector(
                      // Match the map's axis recognizers so marker drags win the gesture arena.
                      onHorizontalDragStart: beginMove,
                      onVerticalDragStart: beginMove,
                      onHorizontalDragEnd: (_) => finishMove(),
                      onVerticalDragEnd: (_) => finishMove(),
                      onHorizontalDragCancel: finishMove,
                      onVerticalDragCancel: finishMove,
                      onHorizontalDragUpdate: (details) =>
                          dragMarker(details, false),
                      onVerticalDragUpdate: (details) =>
                          dragMarker(details, false),
                      child: const CircleAvatar(
                        backgroundColor: Color(0xFF123E38),
                        child: Icon(Icons.photo_camera, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                Marker(
                  point: handle,
                  width: 48,
                  height: 48,
                  child: Semantics(
                    label: 'Camera direction. Drag to rotate.',
                    child: GestureDetector(
                      onHorizontalDragStart: beginMove,
                      onVerticalDragStart: beginMove,
                      onHorizontalDragEnd: (_) => finishMove(),
                      onVerticalDragEnd: (_) => finishMove(),
                      onHorizontalDragCancel: finishMove,
                      onVerticalDragCancel: finishMove,
                      onHorizontalDragUpdate: (details) =>
                          dragMarker(details, true),
                      onVerticalDragUpdate: (details) =>
                          dragMarker(details, true),
                      child: const CircleAvatar(
                        backgroundColor: Color(0xFF169B7C),
                        child: Icon(
                          Icons.open_with,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    '© OpenStreetMap contributors · openstreetmap.org/copyright',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tileError)
                        const Text(
                          'Map tiles unavailable. Check your connection. Camera controls still work; switch workspaces to retry.',
                        ),
                      if (!widget.guideDismissed)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                compact ||
                                        Theme.of(context).platform ==
                                            TargetPlatform.android
                                    ? 'Tap to place camera · Drag camera to move · Drag green handle to aim'
                                    : 'Click to place camera · Drag camera to move · Drag green handle to aim',
                              ),
                            ),
                            if (widget.onGuideDismissedChanged != null)
                              IconButton(
                                tooltip: 'Hide map guidance',
                                onPressed: () =>
                                    widget.onGuideDismissedChanged!(true),
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      Text(
                        '≈${loadingRadiusKm.toStringAsFixed(1)} km requested terrain extent · dashed circle',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 128,
          right: 16,
          child: IconButton.filledTonal(
            tooltip: 'Map guide',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                scrollable: true,
                title: const Text('Map guide'),
                content: Text(
                  'Tap to place the camera. Drag the camera to move; drag its green handle to aim. Use Undo after a move to restore the previous position or direction.\n\n'
                  'For precise placement without dragging, enter latitude and longitude in Camera controls → Position & orientation.\n\n'
                  'Amber: Sun · Blue: Moon · Violet: Galactic center. Dashed bearing lines mean below horizontal.\n\n'
                  'Dashed circle: approximately ${loadingRadiusKm.toStringAsFixed(1)} km requested terrain extent. Forward fetching is directional; the circle is not an exact tile boundary or a download-status indicator. Render distance is a separate limit.\n\n'
                  'Bearing guides only, not rise/set or terrain visibility predictions.',
                ),
                actions: [
                  if (widget.guideDismissed &&
                      widget.onGuideDismissedChanged != null)
                    TextButton(
                      onPressed: () {
                        widget.onGuideDismissedChanged!(false);
                        Navigator.pop(context);
                      },
                      child: const Text('Show map guidance'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ),
        Positioned(
          bottom: 64,
          right: 16,
          child: IconButton.filledTonal(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'Center map on camera',
            onPressed: () =>
                controller.move(state.location, controller.camera.zoom),
            icon: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
