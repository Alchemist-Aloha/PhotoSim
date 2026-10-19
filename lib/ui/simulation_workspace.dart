import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../core/constellations.dart';
import '../render/constellations.dart';
import '../core/night_sky.dart';
import '../core/terrain_geo.dart';
import '../core/terrain_coverage.dart';
import '../data/imagery/imagery_provider.dart';
import '../data/imagery/imagery_sources.dart';
import '../data/terrain/terrain_provider.dart';
import '../data/terrain/terrain_sources.dart';
import '../models/simulation_state.dart';
import '../render/moon.dart';
import '../render/photography.dart';
import '../render/photo_framing.dart';
import '../core/sunlight.dart';
import '../data/image_export.dart';
import '../data/raster_cache.dart';
import 'rain_overlay.dart';
import 'photography_overlays.dart';
import 'wasd_navigation.dart';
import 'camera_gestures.dart';
import 'preview_tools.dart';
import '../core/camera_movement.dart';
import '../data/terrain/terrain_patch.dart';
import '../render/night_sky.dart';

class SimulationWorkspace extends StatefulWidget {
  const SimulationWorkspace({
    super.key,
    required this.state,
    required this.onChanged,
    this.onPausePlayback,
    this.cleanPreview = false,
    this.httpClient,
    this.cacheDirectory,
    this.rasterCache,
  });
  final RasterCache? rasterCache;
  final http.Client? httpClient;
  final Directory? cacheDirectory;
  final bool cleanPreview;
  final VoidCallback? onPausePlayback;
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;

  @override
  State<SimulationWorkspace> createState() => _SimulationWorkspaceState();
}

class _SimulationWorkspaceState extends State<SimulationWorkspace> {
  final photoKey = GlobalKey();
  bool exporting = false;
  scene.Scene? world;
  scene.GradientSkySource? overcastSky;
  TerrainSources? repository;
  final terrainProviders = <String, TerrainProvider>{};
  String terrainCredits = '';
  ImagerySources? imagery;
  final patches = <String, ({TileId id, scene.Node node})>{};
  final textures = <scene.Node, scene.Texture2D>{};
  final partialImagery = <String>{};
  final detailedImagery = <String>{};
  Set<String> wantedTiles = {};
  LatLng? terrainOrigin;
  Timer? coverageDebounce;
  final imageProviders = <String, List<ImageryProvider>>{};
  bool imageryLoading = false;
  int imageryFailures = 0;
  String? imageryFailure;
  late final http.Client client;
  late final bool ownsClient;
  final terrainNodes = <scene.Node>[];
  Completer<void>? cancellation;
  int generation = 0;
  int loaded = 0, failed = 0, total = 0;
  double? ground;
  TerrainPatch? cameraGroundField;
  TileId? cameraGroundTile;
  LatLng? navigationLocation;
  String? tileFailure;
  Object? error;
  bool loading = true;
  scene.PhysicalSkySource? skySource;
  MoonRenderer? moonRenderer;
  NightSkyRenderer? nightRenderer;

  @override
  void initState() {
    super.initState();
    ownsClient = widget.httpClient == null;
    client = widget.httpClient ?? http.Client();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    try {
      await scene.Scene.initializeStaticResources();
      final budget =
          widget.rasterCache ??
          RasterCache(
            Directory(
              '${(widget.cacheDirectory ?? await getApplicationCacheDirectory()).path}/photosim',
            ),
          );
      await budget.initialize();
      if (!mounted) return;
      terrainCredits =
          (jsonDecode(
                await rootBundle.loadString(
                  'assets/terrain/mapterhorn-attribution.json',
                ),
              ) as List<Object?>)
              .cast<Map<String, Object?>>()
              .map(
                (source) =>
                    '${source['name']}\n${source['producer']}\n${source['license']}\n'
                    '${source['website']}\n${source['license_pdf']}',
              )
              .toSet()
              .join('\n\n');
      if (!mounted) return;
      repository = TerrainSources(
        client: client,
        directory: budget.directory,
        budget: budget,
      );
      imagery = ImagerySources(
        client: client,
        directory: budget.directory,
        budget: budget,
      );
      skySource = scene.PhysicalSkySource(
        turbidity: 2,
        rayleighCoefficient: 1,
        rayleighColor: vm.Vector3(
          clearSkyRayleigh.red,
          clearSkyRayleigh.green,
          clearSkyRayleigh.blue,
        ),
        mieCoefficient: clearSkyMie,
        mieEccentricity: 0.76,
      );
      overcastSky = scene.GradientSkySource();
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
      moonRenderer = MoonRenderer();
      world!.add(moonRenderer!.node);
      final stars = parseStarCatalog(
        await rootBundle.loadString('assets/sky/stars.json'),
      );
      if (!mounted) return;
      final band = await scene.Texture2D.fromAsset('assets/sky/milky_way.png');
      if (!mounted) return;
      final figures = parseConstellations(
        await rootBundle.loadString('assets/sky/constellations.json'),
      );
      final constellations = await ConstellationRenderer.create(figures);
      if (!mounted) return;
      nightRenderer = NightSkyRenderer(stars, band, constellations);
      world!.add(nightRenderer!.root);
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
    final old = oldWidget.state, next = widget.state;
    if (old.timestamp != next.timestamp ||
        old.location != next.location ||
        old.weather != next.weather ||
        old.weatherLightTransmission != next.weatherLightTransmission ||
        old.renderQuality != next.renderQuality) {
      world?.skyEnvironment?.invalidate();
    }
    if (old.latitude != next.latitude ||
        old.longitude != next.longitude ||
        old.terrainRings != next.terrainRings ||
        old.terrainForwardKm != next.terrainForwardKm) {
      final nearbyNavigation =
          next.location == navigationLocation &&
          terrainOrigin != null &&
          TileId.at(next.location).key == TileId.at(terrainOrigin!).key &&
          old.terrainRings == next.terrainRings &&
          old.terrainForwardKm == next.terrainForwardKm;
      if (nearbyNavigation) {
        if (coverageDebounce?.isActive != true) {
          coverageDebounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted && nightRenderer != null) unawaited(loadTerrain());
          });
        }
      } else {
        coverageDebounce?.cancel();
        if (old.location == next.location) {
          coverageDebounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted && nightRenderer != null) unawaited(loadTerrain());
          });
        } else if (nightRenderer != null) {
          unawaited(loadTerrain());
        }
      }
    } else if (next.terrainForwardKm > 0 &&
        (old.azimuth != next.azimuth ||
            old.pitch != next.pitch ||
            old.roll != next.roll ||
            old.portrait != next.portrait ||
            old.sensor != next.sensor ||
            old.focalLength != next.focalLength)) {
      coverageDebounce?.cancel();
      coverageDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted && nightRenderer != null) unawaited(loadTerrain());
      });
    }
    if (old.terrainRenderKm != next.terrainRenderKm ||
        old.location != next.location) {
      updateTerrainVisibility();
    }
    if (old.relitImagery != next.relitImagery ||
        old.weather != next.weather ||
        old.atmosphericEffects != next.atmosphericEffects ||
        old.weatherLightTransmission != next.weatherLightTransmission ||
        old.depthOfField != next.depthOfField ||
        old.exposureProcessing != next.exposureProcessing) {
      for (final entry in textures.entries) {
        applyTexture(entry.key, entry.value);
      }
    }
  }

  void navigate(double forward, double right) {
    final next = moveCamera(widget.state, forward, right);
    if (identical(next, widget.state)) return;
    final field = cameraGroundField;
    if (field != null &&
        TileId.at(next.location).key == cameraGroundTile?.key) {
      final sampled = field.groundElevationAt(next.location);
      if (sampled == null) return;
      ground = sampled;
      navigationLocation = next.location;
      widget.onChanged(next.copyWith(groundElevation: ground));
    } else {
      navigationLocation = next.location;
      widget.onChanged(next);
    }
  }

  void updateTerrainVisibility() {
    for (final patch in patches.values) {
      patch.node.visible =
          terrainDistance(patch.id, widget.state.location) <=
          widget.state.terrainRenderKm * 1000;
    }
  }

  Future<void> loadTerrain({bool retry = false}) async {
    final location = widget.state.location;
    // shortcut: rebase on camera-tile exit; retain more height fields for uninterrupted long-range flight.
    final retainFrame =
        location == navigationLocation &&
        terrainOrigin != null &&
        TileId.at(location).key == TileId.at(terrainOrigin!).key;
    final origin = retainFrame ? terrainOrigin! : location;
    final rebase = terrainOrigin != origin;
    final tiles = terrainCoverage(widget.state);
    final wanted = tiles.map((tile) => tile.key).toSet();
    if (!rebase &&
        !retry &&
        wanted.length == wantedTiles.length &&
        wanted.containsAll(wantedTiles)) {
      return;
    }
    wantedTiles = wanted;
    terrainOrigin = origin;
    if (cancellation != null && !cancellation!.isCompleted) {
      cancellation!.complete();
    }
    final token = ++generation;
    final stop = cancellation = Completer<void>();
    final center = TileId.at(origin);
    for (final key in patches.keys.toList()) {
      if (!rebase && wanted.contains(key)) continue;
      final node = patches.remove(key)!.node;
      world!.remove(node);
      terrainNodes.remove(node);
      textures.remove(node);
      terrainProviders.remove(key);
      partialImagery.remove(key);
      imageProviders.remove(key);
      detailedImagery.remove(key);
    }
    setState(() {
      imageryLoading = false;
      imageryFailures = 0;
      imageryFailure = null;
      loaded = patches.length;
      failed = 0;
      total = tiles.length;
      if (rebase) {
        ground = null;
        cameraGroundField = null;
        cameraGroundTile = null;
      }
      tileFailure = null;
      loading = true;
    });
    final missing = tiles
        .where((tile) => !patches.containsKey(tile.key))
        .toList();
    Future<void>? nearbyImagery;
    // Near-first jobs, bounded concurrency; overlapping resident patches keep their buffers/textures.
    for (var start = 0; start < missing.length; start += 3) {
      if (!mounted || token != generation) return;
      await Future.wait(
        missing.skip(start).take(3).map((id) async {
          try {
            final result = await repository!.load(
              id,
              origin,
              id.key == center.key ? 128 : (id.z == 13 ? 64 : 32),
              abort: stop.future,
            );
            if (!mounted || token != generation) return;
            final patch = result.patch;
            terrainProviders[id.key] = result.provider;
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
            final node =
                scene.Node(name: id.key, mesh: scene.Mesh(geometry, material))
                  ..visible =
                      terrainDistance(id, widget.state.location) <=
                      widget.state.terrainRenderKm * 1000;
            world!.add(node);
            terrainNodes.add(node);
            patches[id.key] = (id: id, node: node);
            if (id.key == center.key) {
              final sampled = patch.groundElevationAt(widget.state.location);
              if (sampled == null) {
                throw const FormatException('Camera ground mesh unavailable');
              }
              cameraGroundField = patch;
              cameraGroundTile = id;
              ground = sampled;
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
      // Preview nearby surfaces in parallel; slow imagery must not block distant terrain.
      if (start == 0 && missing.length > 3 && mounted && token == generation) {
        nearbyImagery = loadImagery(token, stop, detail: false);
      }
    }
    if (mounted && token == generation) {
      setState(() => loading = false);
      if (nearbyImagery != null) await nearbyImagery;
      await loadImagery(token, stop, retry: retry);
    }
  }

  void applyTexture(scene.Node node, scene.Texture2D texture) {
    final geometry = node.mesh!.primitives.single.geometry;
    final material = widget.state.relitImagery
        ? (scene.PhysicallyBasedMaterial(baseColorTexture: texture)
            ..roughnessFactor = 1
            ..metallicFactor = 0)
        : (scene.UnlitMaterial(colorTexture: texture)
            // Display-referred surfaces bypass the backend's fog and depth-of-field passes.
            ..displayReferred =
                !widget.state.atmosphericEffects &&
                !widget.state.depthOfField &&
                !widget.state.exposureProcessing
            ..baseColorFactor = vm.Vector4.all(
              widget.state.weatherLightTransmission,
            )
            ..baseColorFactor.a = 1);
    // Reassign the mesh to notify Scene of the material change; geometry stays resident.
    node.mesh = scene.Mesh(geometry, material);
  }

  Future<void> loadImagery(
    int token,
    Completer<void> stop, {
    bool retry = false,
    bool detail = true,
  }) async {
    if (!mounted || token != generation) return;
    setState(() {
      imageryLoading = true;
      imageryFailures = 0;
      imageryFailure = null;
    });
    final centerKey = TileId.at(widget.state.location).key;
    final entries =
        patches.values
            .where(
              (patch) =>
                  !textures.containsKey(patch.node) ||
                  (retry &&
                      partialImagery.contains(patch.id.key) &&
                      !detailedImagery.contains(patch.id.key)),
            )
            .toList()
          ..sort(
            (a, b) => (b.id.key == centerKey ? 1 : 0).compareTo(
              a.id.key == centerKey ? 1 : 0,
            ),
          );
    Future<void> update(({TileId id, scene.Node node}) patch, int size) async {
      try {
        final result = await imagery!.load(patch.id, size, abort: stop.future);
        final raster = result.raster;
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
          imageProviders[patch.id.key] = result.providers;
          if (size == 1024) detailedImagery.add(patch.id.key);
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
    if (detail &&
        mounted &&
        token == generation &&
        center != null &&
        textures.containsKey(center.node) &&
        (retry || !detailedImagery.contains(centerKey))) {
      await update(center, 1024);
    }
    if (mounted && token == generation) setState(() => imageryLoading = false);
  }

  Future<void> exportImage() async {
    if (exporting) return;
    widget.onPausePlayback?.call();
    setState(() => exporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final snapshot = widget.state;
      final boundary =
          photoKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final region = photoRegion(
        boundary.size,
        snapshot.sensorWidth / snapshot.sensorHeight,
      );
      if (region.shortestSide < 32) {
        throw StateError('Photo region is too small to export');
      }
      final ratio = math.min(
        MediaQuery.devicePixelRatioOf(context),
        math.min(
          4096 / boundary.size.longestSide,
          math.sqrt(12000000 / (boundary.size.width * boundary.size.height)),
        ),
      );
      final image = await boundary.toImage(pixelRatio: ratio);
      late final Uint8List bytes;
      try {
        final credits = {
          ...terrainProviders.values.map((provider) => provider.attribution),
          ...imageProviders.values
              .expand((providers) => providers)
              .map((provider) => provider.attribution),
          'Sky catalog: D3-Celestial / XHIP · BSD-3-Clause',
        }.join(' · ');
        bytes = await encodePreview(
          image,
          '$credits\n'
          '${snapshot.timestamp.toIso8601String()} · ${snapshot.sensor.label} · ${snapshot.focalLength.toStringAsFixed(1)} mm · '
          'f/${snapshot.aperture.toStringAsFixed(1)} · ISO ${snapshot.iso.round()} · ${snapshot.shutterLabel} · ${snapshot.exposureMode.label} · ${snapshot.weather.label} (illustrative) · visibility ${snapshot.weatherVisibilityKm.toStringAsFixed(1)} km · light ${(snapshot.weatherLightTransmission * 100).round()}% · rain ${(snapshot.rainIntensity * 100).round()}%',
          crop: Rect.fromLTRB(
            region.left * ratio,
            region.top * ratio,
            region.right * ratio,
            region.bottom * ratio,
          ),
        );
      } finally {
        image.dispose();
      }
      if (Platform.isAndroid) {
        await const MethodChannel('photosim/export').invokeMethod<String>(
          'savePng',
          {
            'bytes': bytes,
            'name':
                'photosim-${DateTime.now().toUtc().microsecondsSinceEpoch}.png',
          },
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved PNG to Pictures/PhotoSim.')),
        );
        return;
      }
      final directory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      if (!mounted) return;
      var path =
          '${directory.path}/photosim-${DateTime.now().toUtc().microsecondsSinceEpoch}.png';
      final destination = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export PNG'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Exports the framed photo region with weather, depth of field and source credits; no frame, lens label, crosshair or controls. Maximum 4096 px / 12 MP. Existing files are never overwritten.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: path,
                    onChanged: (value) => path = value,
                    decoration: const InputDecoration(
                      labelText: 'Absolute PNG path',
                    ),
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
            TextButton(
              onPressed: () => Navigator.pop(context, path.trim()),
              child: const Text('Save PNG'),
            ),
          ],
        ),
      );
      if (destination == null) return;
      final file = await savePreview(destination, bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText('Exported PNG · ${file.path}')),
      );
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $failure')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  void dispose() {
    coverageDebounce?.cancel();
    generation++;
    if (cancellation != null && !cancellation!.isCompleted) {
      cancellation!.complete();
    }
    if (ownsClient) client.close();
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
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: SelectableText(
            'Preferred terrain: © Mapterhorn · https://mapterhorn.com/attribution\n'
            'Account-free tiles combine Copernicus GLO-30 with open regional terrain. '
            'Nominal source grids can be 1–10 m where available, but this preview still uses '
            'a coarse mesh and does not display native lidar detail. '
            'Global zoom-12 tiles are cropped where higher zooms are absent. '
            'Mapzen remains the independent fallback.\n\n'
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
            'Bounded distance/FOV coverage and coarse meshes are not suitable for precise distant-horizon predictions. '
            'Imagery automatically prefers regional aerial sources over the global mosaic.\n'
            'USGS, USDA, The National Map: Orthoimagery (NAIP, public domain).\n'
            'France: © IGN · BD ORTHO · Licence Ouverte 2.0.\n'
            'Switzerland: ©swisstopo · SWISSIMAGE (open government data).\n'
            'Global: EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH '
            '(Contains modified Copernicus Sentinel data 2016) · CC BY 4.0 '
            '(https://creativecommons.org/licenses/by/4.0/). '
            'Only the freely reusable 2016 mosaic is used, not newer non-commercial layers. '
            'Source orthophotos can reach 20 cm in France and 10–25 cm in Switzerland; '
            'the global mosaic is about 10 m. Service limits and the current terrain textures '
            'downsample these sources; native aerial detail is not displayed. '
            'The mosaic acquisition dates vary and are not yet queried; they do not follow simulation time. '
            'Natural imagery preserves original colors and baked-in lighting. Relighting is approximate and can double existing shadows. '
            'Missing regional pixels fall back to the global mosaic. If all sources fail, '
            'the green surface remains a labeled fallback material. '
            'Solar direction is calculated locally with Astronomia (Meeus, MIT); brightness and sky appearance are approximate. '
            'Sun/Moon readouts omit atmospheric refraction. The Moon is an untextured phase-lit sphere; '
            'moonlight brightness is an artistic approximation, not calibrated exposure. '
            'Stars: XHIP (Anderson & Francis, 2012); Milky Way outlines: Jose R. Vieira, '
            'via D3-Celestial (Olaf Frohn, BSD-3-Clause). Constellation names and illustrative connecting figures '
            'also come from D3-Celestial; figures are not official IAU boundaries. Night-sky brightness and star sizes are artistic.\n\n'
            'Mapterhorn upstream source credits and license references:\n\n$terrainCredits',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'PhotoSim'),
          child: const Text('Software & sky-data licenses'),
        ),
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
    final credits = {
      ...terrainProviders.values.map((provider) => provider.attribution),
      ...imageProviders.values
          .expand((providers) => providers)
          .map((provider) => provider.attribution),
    }.join(' · ');
    final active = world;
    if (active == null) return const Center(child: CircularProgressIndicator());
    final state = widget.state;
    final frame = state.cameraFrame;
    final eye = vm.Vector3(
      0,
      state.cameraElevation ?? (ground ?? 0) + state.height,
      0,
    );
    final anchor = terrainOrigin;
    final transform = anchor == null || anchor == state.location
        ? vm.Matrix4.identity()
        : vm.Matrix4.fromList(
            LocalFrame(state.location)
                .transformFrom(LocalFrame(anchor))
                .storage,
          );
    for (final node in terrainNodes) {
      node.localTransform = transform;
    }
    final direction = vm.Vector3(
      frame.forward.x,
      frame.forward.y,
      frame.forward.z,
    );
    final cameraUp = vm.Vector3(frame.up.x, frame.up.y, frame.up.z);
    final skyLayerState = widget.cleanPreview
        ? state.copyWith(
            showConstellations: false,
            target: CelestialTarget.none,
          )
        : state;
    final sky = state.sky;
    // shortcut: Auto meters the whole context canvas; add backend ROI metering for photo-only Auto.
    configurePhotography(active, state);
    final sun = sky.sun;
    moonRenderer!.update(sky, eye);
    nightRenderer?.update(skyLayerState, eye);
    final sunDirection = vm.Vector3(
      sun.direction.x,
      sun.direction.y,
      sun.direction.z,
    );
    final solarLight = sunlight(sun.altitude);
    // Do not retain baked daylight after jumping across the solar horizon.
    if ((skySource!.sunDirection.y > 0) != (sunDirection.y > 0)) {
      active.skyEnvironment = null;
    }
    skySource!
      ..sunDirection = sunDirection
      ..sunAngularRadius = sun.angularRadius
      ..energy = state.weatherLightTransmission;
    active.environmentIntensity = 1;
    final transmission = state.weatherLightTransmission;
    moonRenderer!.node.visible = state.weather == Weather.clear;
    if (state.weather == Weather.clear) {
      if (active.skybox?.source != skySource) {
        active.skybox = scene.Skybox(skySource!);
      }
    } else {
      final brightness =
          ((sun.altitude + 18) / 33).clamp(0.0, 1.0) * transmission;
      overcastSky!
        ..sunColor = vm.Vector3.zero()
        ..zenithColor = vm.Vector3(0.22, 0.25, 0.29) * brightness
        ..horizonColor = vm.Vector3(0.42, 0.46, 0.50) * brightness
        ..groundColor = vm.Vector3(0.12, 0.13, 0.14) * brightness;
      if (active.skybox?.source != overcastSky) {
        active.skybox = scene.Skybox(overcastSky!);
      }
    }
    final lightingSky = active.skybox!.source as scene.ShaderSkySource;
    if (!identical(active.skyEnvironment?.source, lightingSky)) {
      active.skyEnvironment = scene.SkyEnvironment(lightingSky);
    }
    final faceResolution = switch (state.renderQuality) {
      RenderQuality.performance => 32,
      RenderQuality.balanced => 64,
      RenderQuality.high => 128,
    };
    active.skyEnvironment!
      ..faceResolution = faceResolution
      ..equirectWidth = faceResolution * 4;
    final moon = sky.moon.direction;
    // The one shadow-casting light follows the Moon once the Sun is below horizontal.
    active.directionalLight!
      ..direction = sun.altitude > 0
          ? -sunDirection
          : -vm.Vector3(moon.x, moon.y, moon.z)
      ..intensity =
          (sun.altitude > 0 ? solarLight.intensity : moonlightIntensity(sky)) *
          transmission
      ..color = sun.altitude > 0
          ? vm.Vector3(solarLight.red, solarLight.green, solarLight.blue)
          : vm.Vector3(0.85, 0.90, 1);
    return LayoutBuilder(
      builder: (context, bounds) => Stack(
        fit: StackFit.expand,
        children: [
          ground == null
              ? Center(
                  child: loading
                      ? const CircularProgressIndicator()
                      : const Text(
                          'Camera ground tile unavailable. Retry terrain or select another location.',
                        ),
                )
              : WasdNavigation(
                  enabled:
                      !exporting &&
                      cameraGroundField != null &&
                      cameraGroundTile?.key == TileId.at(state.location).key,
                  onMove: navigate,
                  child: CameraGestures(
                    state: state,
                    onChanged: widget.onChanged,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // shortcut: stream for the photo frustum; add viewport-aware prefetch for outer context if needed.
                        final region = photoRegion(
                          constraints.biggest,
                          state.sensorWidth / state.sensorHeight,
                        );
                        nightRenderer?.updateLabels(skyLayerState, region.size);
                        // Keep physical CoC calibrated to photo pixels, not the larger context canvas.
                        active.depthOfField.blurScale =
                            constraints.maxHeight > 0
                            ? region.height / constraints.maxHeight
                            : 1;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            RepaintBoundary(
                              key: photoKey,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Semantics(
                                    label: state.showConstellations
                                        ? 'Constellation guides. Labels in the photo field of view: ${nightRenderer!.constellations.activeNames.join(', ')}. Terrain may occlude labels.'
                                        : '3D photography preview',
                                    // Scene's +Z-forward camera reverses east/west in our ENU axes.
                                    child: Transform.flip(
                                      flipX: true,
                                      child: scene.SceneView(
                                        active,
                                        camera: scene.PerspectiveCamera(
                                          position: eye,
                                          target: eye + direction,
                                          up: cameraUp,
                                          fovRadiansY: previewVerticalFov(
                                            state,
                                            constraints.biggest,
                                          ),
                                          fovNear: 0.5,
                                          fovFar: 50000,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (state.weather == Weather.rain &&
                                      state.rainIntensity > 0)
                                    RainOverlay(intensity: state.rainIntensity),
                                ],
                              ),
                            ),
                            PhotographyOverlays(
                              state: state,
                              showGuides: !widget.cleanPreview,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
          if (!widget.cleanPreview)
            Align(
              alignment: Alignment.topRight,
              child: bounds.maxHeight < 400
                  ? Card(
                      key: const ValueKey('preview-actions'),
                      margin: const EdgeInsets.all(12),
                      child: PreviewTools(
                        constellations: state.showConstellations,
                        onConstellations: () => widget.onChanged(
                          state.copyWith(
                            showConstellations: !state.showConstellations,
                          ),
                        ),
                        onExport:
                            ground == null ||
                                loading ||
                                imageryLoading ||
                                exporting
                            ? null
                            : exportImage,
                      ),
                    )
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 540,
                        maxHeight: bounds.maxHeight * 0.4,
                      ),
                      child: Card(
                        key: const ValueKey('preview-actions'),
                        elevation: 4,
                        color: Theme.of(context).colorScheme.surfaceContainer
                            .withValues(alpha: 0.9),
                        margin: const EdgeInsets.all(12),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DefaultTextStyle.merge(
                                  style: Theme.of(context).textTheme.bodySmall,
                                  child: Wrap(
                                    spacing: 16,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Tooltip(
                                        key: const ValueKey(
                                          'terrain-cache-count',
                                        ),
                                        message:
                                            '${repository!.cacheHits} cached · ${repository!.downloads} downloaded',
                                        child: Text(
                                          'Terrain $loaded/$total${loading ? ' · loading' : ''}',
                                          key: const ValueKey('terrain-status'),
                                        ),
                                      ),
                                      Tooltip(
                                        key: const ValueKey(
                                          'imagery-cache-count',
                                        ),
                                        message:
                                            '${imagery!.cacheHits} cached · ${imagery!.downloads} downloaded',
                                        child: Text(
                                          'Imagery ${textures.length}/$loaded${imageryLoading ? ' · loading' : ''}',
                                          key: const ValueKey('imagery-status'),
                                        ),
                                      ),
                                      if (textures.length < loaded ||
                                          partialImagery.isNotEmpty)
                                        const Tooltip(
                                          message: 'Fallback surface where imagery is missing',
                                          child: Text('Partial imagery'),
                                        ),
                                      Tooltip(
                                        message: Platform.isAndroid
                                            ? 'Drag to aim · Pinch to zoom · Place the camera on the map to move'
                                            : 'Click preview · Drag to aim · WASD: 30 m/s, follows terrain',
                                        child: const Icon(
                                          Icons.help_outline,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    FilterChip(
                                      label: const Text('Constellations'),
                                      showCheckmark: false,
                                      avatar: const Icon(
                                        Icons.auto_awesome,
                                        size: 18,
                                      ),
                                      tooltip: 'Show constellation names and connecting figures (planning guides, not IAU boundaries)',
                                      selected: state.showConstellations,
                                      onSelected: (value) => widget.onChanged(
                                        state.copyWith(
                                          showConstellations: value,
                                        ),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed:
                                          ground == null ||
                                              loading ||
                                              imageryLoading ||
                                              exporting
                                          ? null
                                          : exportImage,
                                      icon: const Icon(Icons.image_outlined),
                                      label: Text(
                                        exporting ? 'Exporting…' : 'Export PNG',
                                      ),
                                    ),
                                  ],
                                ),
                                if (!widget.cleanPreview &&
                                    (failed > 0 ||
                                        repository!.cacheWarning != null))
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            failed > 0
                                                ? '$failed terrain tiles unavailable. ${tileFailure ?? ''}'
                                                : repository!.cacheWarning!,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: loading || imageryLoading
                                              ? null
                                              : () => loadTerrain(retry: true),
                                          child: const Text('Retry terrain'),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (!widget.cleanPreview &&
                                    (imageryFailures > 0 ||
                                        imagery!.cacheWarning != null))
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            imageryFailures > 0
                                                ? 'Imagery unavailable or incomplete: $imageryFailure. Terrain remains usable.'
                                                : imagery!.cacheWarning!,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: loading || imageryLoading
                                              ? null
                                              : () => loadImagery(
                                                  generation,
                                                  cancellation!,
                                                  retry: true,
                                                ),
                                          child: const Text('Retry imagery'),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          if (!widget.cleanPreview)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                key: const ValueKey('preview-info'),
                color: Theme.of(context).colorScheme.surfaceContainer
                    .withValues(alpha: 0.9),
                child: Tooltip(
                  message:
                      '${credits.isEmpty ? 'Terrain & imagery sources' : credits}\nClick for sources and licenses',
                  child: InkWell(
                    key: const ValueKey('preview-sources'),
                    onTap: showSources,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        credits.isEmpty
                            ? '© Terrain & imagery sources'
                            : credits,
                        key: const ValueKey('preview-credit'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
