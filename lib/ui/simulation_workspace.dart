import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../core/geo.dart';
import '../core/terrain_geo.dart';
import '../data/imagery/imagery_repository.dart';
import '../data/terrain/terrain_repository.dart';
import '../data/terrain/tile_cache.dart';
import '../models/simulation_state.dart';

class SimulationWorkspace extends StatefulWidget {
  const SimulationWorkspace({
    super.key,
    required this.state,
    required this.onChanged,
  });
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;

  @override
  State<SimulationWorkspace> createState() => _SimulationWorkspaceState();
}

class _SimulationWorkspaceState extends State<SimulationWorkspace> {
  scene.Scene? world;
  TerrainRepository? repository;
  ImageryRepository? imagery;
  final patches = <String, ({TileId id, scene.Node node})>{};
  final textures = <scene.Node, scene.Texture2D>{};
  final partialImagery = <String>{};
  bool imageryLoading = false;
  int imageryFailures = 0;
  String? imageryFailure;
  final client = http.Client();
  final terrainNodes = <scene.Node>[];
  Completer<void>? cancellation;
  int generation = 0;
  int loaded = 0, failed = 0, total = 0;
  double? ground;
  String? tileFailure;
  Object? error;
  bool loading = true;
  scene.PhysicalSkySource? skySource;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      await scene.Scene.initializeStaticResources();
      final directory = await getApplicationCacheDirectory();
      if (!mounted) return;
      repository = TerrainRepository(
        client: client,
        cache: TileCache(Directory('${directory.path}/photosim/terrain-v1')),
      );
      imagery = ImageryRepository(
        client: client,
        previewCache: TileCache(
          Directory('${directory.path}/photosim/naip-natural-256-v1'),
          maxBytes: 64 * 1024 * 1024,
          maxEntryBytes: 8 * 1024 * 1024,
        ),
        detailCache: TileCache(
          Directory('${directory.path}/photosim/naip-natural-1024-v1'),
          maxBytes: 192 * 1024 * 1024,
          maxEntryBytes: 8 * 1024 * 1024,
        ),
      );
      skySource = scene.PhysicalSkySource(turbidity: 2);
      world = scene.Scene()..skybox = scene.Skybox(skySource!);
      world!.directionalLight = scene.DirectionalLight(
        castsShadow: true,
        cacheStaticShadows: false,
        shadowMaxDistance: 16000,
        shadowMapResolution: 2048,
        // Kilometer-scale patches need meter-scale bias to avoid self-shadow acne.
        shadowDepthBias: 0.8,
        shadowNormalBias: 2,
        intensity: 3,
      );
      await loadTerrain();
    } catch (failure, stack) {
      debugPrint('PhotoSim 3D initialization failed: $failure\n$stack');
      if (mounted) {
        setState(() {
          error = failure;
          loading = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant SimulationWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.latitude != widget.state.latitude ||
        oldWidget.state.longitude != widget.state.longitude) {
      if (repository != null && world != null) loadTerrain();
    }
    if (oldWidget.state.relitImagery != widget.state.relitImagery) {
      for (final entry in textures.entries) {
        applyTexture(entry.key, entry.value);
      }
    }
  }

  Future<void> loadTerrain() async {
    if (cancellation != null && !cancellation!.isCompleted) {
      cancellation!.complete();
    }
    final token = ++generation;
    final stop = cancellation = Completer<void>();
    final origin = widget.state.location;
    final center = TileId.at(origin);
    final tiles = center.neighborhood();
    for (final node in terrainNodes) {
      world!.remove(node);
    }
    terrainNodes.clear();
    patches.clear();
    textures.clear();
    partialImagery.clear();
    setState(() {
      imageryLoading = false;
      imageryFailures = 0;
      imageryFailure = null;
      loaded = 0;
      failed = 0;
      total = tiles.length;
      ground = null;
      tileFailure = null;
      loading = true;
    });
    // Center first; at most three fetch/decode/build jobs are active.
    for (var start = 0; start < tiles.length; start += 3) {
      if (!mounted || token != generation) return;
      await Future.wait(
        tiles.skip(start).take(3).map((id) async {
          try {
            // shortcut: fixed 3×3 region with distance LOD, use screen-error quadtree for longer-range planning.
            final patch = await repository!.load(
              id,
              origin,
              id.key == center.key ? 128 : 64,
              abort: stop.future,
            );
            if (!mounted || token != generation) return;
            final geometry = scene.MeshGeometry.fromArrays(
              positions: patch.positions,
              normals: patch.normals,
              texCoords: patch.uvs,
              indices: patch.indices,
              retainCpuData: false,
            );
            final material = scene.PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.32, 0.40, 0.25, 1)
              ..roughnessFactor = 1
              ..metallicFactor = 0;
            final node = scene.Node(
              name: id.key,
              mesh: scene.Mesh(geometry, material),
            );
            world!.add(node);
            terrainNodes.add(node);
            patches[id.key] = (id: id, node: node);
            if (id.key == center.key) {
              final uv = id.uv(origin);
              ground = patch.field.sample(uv.x, uv.y);
              widget.onChanged(widget.state.copyWith(groundElevation: ground));
            }
            setState(() => loaded++);
          } catch (failure) {
            if (!mounted || token != generation) return;
            setState(() {
              failed++;
              tileFailure = '$failure';
            });
          }
        }),
      );
    }
    if (mounted && token == generation) {
      setState(() => loading = false);
      await loadImagery(token, stop);
    }
  }

  void applyTexture(scene.Node node, scene.Texture2D texture) {
    final geometry = node.mesh!.primitives.single.geometry;
    final material = widget.state.relitImagery
        ? (scene.PhysicallyBasedMaterial(baseColorTexture: texture)
            ..roughnessFactor = 1
            ..metallicFactor = 0)
        : (scene.UnlitMaterial(colorTexture: texture)..displayReferred = true);
    // Reassign the mesh to notify Scene of the material change; geometry stays resident.
    node.mesh = scene.Mesh(geometry, material);
  }

  void setRelighting(bool value) =>
      widget.onChanged(widget.state.copyWith(relitImagery: value));

  Future<void> loadImagery(int token, Completer<void> stop) async {
    if (!mounted || token != generation) return;
    setState(() {
      imageryLoading = true;
      imageryFailures = 0;
      imageryFailure = null;
    });
    final centerKey = TileId.at(widget.state.location).key;
    final entries = patches.values.toList()
      ..sort(
        (a, b) => (b.id.key == centerKey ? 1 : 0).compareTo(
          a.id.key == centerKey ? 1 : 0,
        ),
      );
    Future<void> update(({TileId id, scene.Node node}) patch, int size) async {
      try {
        final raster = await imagery!.load(patch.id, size, abort: stop.future);
        if (!mounted || token != generation) return;
        final texture = scene.Texture2D.fromPixels(
          raster.rgba,
          raster.size,
          raster.size,
          sampling: const scene.TextureSampling(
            addressMode: gpu.SamplerAddressMode.clampToEdge,
          ),
        );
        textures[patch.node] = texture;
        applyTexture(patch.node, texture);
        setState(() {
          if (raster.partial) {
            partialImagery.add(patch.id.key);
          } else {
            partialImagery.remove(patch.id.key);
          }
        });
      } catch (failure) {
        if (!mounted || token != generation) return;
        // Retain an existing preview when higher resolution cannot be fetched.
        setState(() {
          imageryFailures++;
          imageryFailure = '$failure';
        });
      }
    }

    for (var start = 0; start < entries.length; start += 3) {
      if (!mounted || token != generation) return;
      await Future.wait(
        entries.skip(start).take(3).map((entry) => update(entry, 256)),
      );
    }
    final center = patches[centerKey];
    if (mounted &&
        token == generation &&
        center != null &&
        textures.containsKey(center.node)) {
      await update(center, 1024);
    }
    if (mounted && token == generation) setState(() => imageryLoading = false);
  }

  @override
  void dispose() {
    generation++;
    if (cancellation != null && !cancellation!.isCompleted) {
      cancellation!.complete();
    }
    client.close();
    world?.dispose();
    terrainNodes.clear();
    patches.clear();
    textures.clear();
    world = null;
    super.dispose();
  }

  void showSources() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Terrain & imagery sources and limitations'),
      content: const SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: SelectableText(
            'Mapzen Terrain Tiles · AWS Open Data\n'
            'Source credits: tilezen/joerd docs/attribution.md on GitHub.\n\n'
            'ArcticDEM: DEM(s) created from DigitalGlobe, Inc., imagery; funded under NSF awards 1043681, 1559691, 1542736.\n'
            'Australia: © Commonwealth of Australia (Geoscience Australia) 2017.\n'
            'Austria: © offene Daten Österreichs – Digitales Geländemodell (DGM) Österreich.\n'
            'Canada: Contains information licensed under the Open Government Licence – Canada.\n'
            'Europe: Produced using Copernicus data and information funded by the European Union – EU-DEM layers.\n'
            'Global ETOPO1: DOC/NOAA/NESDIS/NCEI, US Department of Commerce; US Government material.\n'
            'Mexico: INEGI, Continental relief, 2016.\n'
            'New Zealand: Copyright 2011 Crown copyright (c) Land Information New Zealand and the New Zealand Government (All rights reserved).\n'
            'Norway: © Kartverket.\n'
            'United Kingdom: © Environment Agency copyright and/or database right 2015. All rights reserved.\n'
            'US 3DEP and global GMTED2010/SRTM: courtesy of the US Geological Survey.\n\n'
            'Elevation source datum is uncorrected. Ground height follows the downloaded raster, not a surveyed site. '
            'The fixed local region and coarse mesh are not suitable for precise distant-horizon predictions. '
            'Aerial imagery: USGS, USDA, The National Map: Orthoimagery (NAIP). '
            'The mosaic acquisition dates vary and are not yet queried; they do not follow simulation time. '
            'Natural imagery preserves original colors and baked-in lighting. Relighting is approximate and can double existing shadows. '
            'Where NAIP is missing, the green surface remains a labeled fallback material. '
            'Solar direction is calculated locally with Astronomia (Meeus, MIT); brightness and sky appearance are approximate. '
            'Sun/Moon readouts omit atmospheric refraction. Moon rendering and moonlight are not yet implemented.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 40),
              const SizedBox(height: 16),
              const Text('3D rendering is unavailable. The map still works.'),
              const SizedBox(height: 8),
              SelectableText('$error'),
              const Text(
                'Requires Flutter GPU / Impeller and a compatible graphics driver.',
              ),
            ],
          ),
        ),
      );
    }
    final active = world;
    if (active == null) return const Center(child: CircularProgressIndicator());
    final state = widget.state;
    final yaw = state.azimuth * radians, pitch = state.pitch * radians;
    final eye = vm.Vector3(0, (ground ?? 0) + state.height, 0);
    final direction = vm.Vector3(
      math.sin(yaw) * math.cos(pitch),
      math.sin(pitch),
      -math.cos(yaw) * math.cos(pitch),
    );
    final sun = state.sky.sun;
    final sunDirection = vm.Vector3(
      sun.direction.x,
      sun.direction.y,
      sun.direction.z,
    );
    final daylight = (sun.altitude / 15).clamp(0.0, 1.0);
    final twilight = ((sun.altitude + 18) / 18).clamp(0.0, 1.0);
    skySource!
      ..sunDirection = sunDirection
      ..sunAngularRadius = sun.angularRadius;
    // shortcut: clear-sky color/brightness ramps, use calibrated radiometry for exposure simulation.
    active.environmentIntensity = 0.005 + 0.245 * twilight;
    active.directionalLight!
      ..direction = -sunDirection
      ..intensity = 3 * daylight
      ..color = vm.Vector3(1, 0.45 + 0.53 * daylight, 0.15 + 0.80 * daylight);
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Real terrain · $loaded/$total tiles${loading ? ' · loading' : ''}',
                ),
                Text(
                  'USGS NAIP · ${textures.length}/$loaded textures${imageryLoading ? ' · loading' : ''}',
                ),
                if (textures.length < loaded || partialImagery.isNotEmpty)
                  const Text('Fallback surface where imagery is missing'),
                FilterChip(
                  label: const Text('Approximate relighting'),
                  selected: state.relitImagery,
                  onSelected: setRelighting,
                ),
                Text(
                  state.relitImagery
                      ? 'UTC-driven sunlight · approximate clear sky'
                      : 'Natural imagery retains captured lighting',
                ),
              ],
            ),
          ),
        ),
        if (failed > 0 || repository!.cache.warning != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    failed > 0
                        ? '$failed terrain tiles unavailable. ${tileFailure ?? ''}'
                        : repository!.cache.warning!,
                  ),
                ),
                TextButton(
                  onPressed: loading || imageryLoading ? null : loadTerrain,
                  child: const Text('Retry terrain'),
                ),
              ],
            ),
          ),
        if (imageryFailures > 0 ||
            imagery!.previewCache.warning != null ||
            imagery!.detailCache.warning != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    imageryFailures > 0
                        ? 'Imagery unavailable or incomplete: $imageryFailure. Terrain remains usable.'
                        : imagery!.previewCache.warning ??
                              imagery!.detailCache.warning!,
                  ),
                ),
                TextButton(
                  onPressed: loading || imageryLoading
                      ? null
                      : () => loadImagery(generation, cancellation!),
                  child: const Text('Retry imagery'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ground == null
              ? Center(
                  child: loading
                      ? const CircularProgressIndicator()
                      : const Text(
                          'Camera ground tile unavailable. Retry terrain or select another location.',
                        ),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: state.sensor.width / state.sensor.height,
                    child: GestureDetector(
                      onPanUpdate: (details) => widget.onChanged(
                        state.copyWith(
                          azimuth: state.azimuth + details.delta.dx * 0.2,
                          pitch: state.pitch - details.delta.dy * 0.2,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          scene.SceneView(
                            active,
                            camera: scene.PerspectiveCamera(
                              position: eye,
                              target: eye + direction,
                              fovRadiansY: state.verticalFov,
                              fovNear: 0.5,
                              fovFar: 20000,
                            ),
                          ),
                          const IgnorePointer(
                            child: Center(
                              child: Icon(
                                Icons.add,
                                color: Colors.white54,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Drag to aim · Change UTC time to move the Sun'),
              TextButton(
                onPressed: showSources,
                child: const Text('© Terrain & imagery sources'),
              ),
              Text(
                '${repository!.cacheHits} cached · ${repository!.downloads} downloaded',
              ),
              Text(
                'NAIP: ${imagery!.cacheHits} cached · ${imagery!.downloads} downloaded',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
