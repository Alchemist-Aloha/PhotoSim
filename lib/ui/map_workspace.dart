import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/geo.dart';
import '../models/simulation_state.dart';

class MapWorkspace extends StatefulWidget {
  const MapWorkspace({super.key, required this.state, required this.onChanged});
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;

  @override
  State<MapWorkspace> createState() => _MapWorkspaceState();
}

class _MapWorkspaceState extends State<MapWorkspace> {
  final controller = MapController();
  final mapKey = GlobalKey();
  bool tileError = false;

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
    final handle = destination(state.location, state.azimuth, 450);
    return Stack(
      children: [
        FlutterMap(
          key: mapKey,
          mapController: controller,
          options: MapOptions(
            initialCenter: state.location,
            initialZoom: 14,
            minZoom: 3,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: (_, point) => widget.onChanged(
              state.copyWith(
                latitude: point.latitude.clamp(-85.05112878, 85.05112878),
                longitude: (point.longitude + 180) % 360 - 180,
              ),
            ),
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
                    state.horizontalFov,
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
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: state.location,
                  width: 44,
                  height: 44,
                  child: Semantics(
                    label: 'Camera location. Drag to move.',
                    child: GestureDetector(
                      // Match the map's axis recognizers so marker drags win the gesture arena.
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
                  width: 36,
                  height: 36,
                  child: Semantics(
                    label: 'Camera direction. Drag to rotate.',
                    child: GestureDetector(
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
            const SimpleAttributionWidget(
              source: Text(
                '© OpenStreetMap contributors · openstreetmap.org/copyright',
              ),
            ),
          ],
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topLeft,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    tileError
                        ? 'Map tiles unavailable. Check your connection.\nCamera controls still work; switch workspaces to retry.'
                        : 'Click to place camera · Drag camera to move · Drag green handle to aim',
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 36,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'recenter',
            tooltip: 'Center map on camera',
            onPressed: () =>
                controller.move(state.location, controller.camera.zoom),
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
