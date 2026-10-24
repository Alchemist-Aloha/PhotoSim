import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter/material.dart' show Color, Size;

import 'constellations.dart';

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../core/astronomy.dart';
import '../core/geo.dart';
import '../core/night_sky.dart';
import '../core/planets.dart';
import '../models/simulation_state.dart';
import 'celestial_material.dart';
import 'label_atlas.dart';

({Float32List positions, Float32List colors, List<int> indices}) starMesh(
  List<Star> stars,
) {
  final positions = Float32List(stars.length * 9 * 3);
  final colors = Float32List(stars.length * 9 * 4);
  final indices = <int>[];
  // Indexed writes: setRange with a list literal built ~130k throwaway lists for the
  // bundled 5k-star catalog, all on the UI isolate during scene creation.
  for (var i = 0; i < stars.length; i++) {
    final star = stars[i], d = star.direction;
    final u = d
        .cross(d.z.abs() > 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1))
        .normalized();
    final v = d.cross(u);
    // shortcut: unresolved stars use exaggerated fixed-angular disks, not a calibrated PSF/exposure model.
    final flux = math.pow(10, -0.2 * star.magnitude).toDouble();
    final radius = NightSkyRenderer.starDistance * (0.0005 + 0.0008 * flux);
    final brightness = 0.25 + flux;
    for (var j = 0; j < 9; j++) {
      final angle = (j - 1) * math.pi / 4;
      final p =
          d * NightSkyRenderer.starDistance +
          (j == 0
              ? Vector3.zero()
              : (u * math.cos(angle) + v * math.sin(angle)) * radius);
      final vertex = i * 9 + j;
      positions[vertex * 3] = p.x;
      positions[vertex * 3 + 1] = p.y;
      positions[vertex * 3 + 2] = p.z;
      final color = vertex * 4;
      colors[color] = brightness;
      colors[color + 1] = brightness;
      colors[color + 2] = brightness;
      colors[color + 3] = 1;
      if (j > 0) indices.addAll([i * 9, i * 9 + j % 8 + 1, vertex]);
    }
  }
  return (positions: positions, colors: colors, indices: indices);
}

scene.MeshGeometry _milkyWayGeometry() {
  const columns = 128, rows = 64;
  final positions = Float32List((columns + 1) * (rows + 1) * 3);
  final uvs = Float32List((columns + 1) * (rows + 1) * 2);
  final indices = <int>[];
  for (var y = 0; y <= rows; y++) {
    final dec = (90 - y / rows * 180) * radians;
    final cosDec = math.cos(dec), sinDec = math.sin(dec);
    for (var x = 0; x <= columns; x++) {
      final ra = (x / columns * 360 - 180) * radians;
      final i = y * (columns + 1) + x;
      positions[i * 3] = cosDec * math.cos(ra) * NightSkyRenderer.bandDistance;
      positions[i * 3 + 1] =
          cosDec * math.sin(ra) * NightSkyRenderer.bandDistance;
      positions[i * 3 + 2] = sinDec * NightSkyRenderer.bandDistance;
      uvs[i * 2] = x / columns;
      uvs[i * 2 + 1] = y / rows;
      if (x < columns && y < rows) {
        final b = i + columns + 1;
        indices.addAll([i, i + 1, b, b, i + 1, b + 1]);
      }
    }
  }
  return scene.MeshGeometry.fromArrays(
    positions: positions,
    texCoords: uvs,
    indices: indices,
  );
}

class NightSkyRenderer {
  NightSkyRenderer(List<Star> stars, scene.Texture2D milkyWay) {
    final data = starMesh(stars);
    starGeometry = scene.MeshGeometry.fromArrays(
      positions: data.positions,
      colors: data.colors,
      indices: data.indices,
    );
    // Celestial proxy distances must not clip the far-cloud ray march as terrain depth.
    starMaterial = CelestialMaterial()..alphaMode = scene.AlphaMode.blend;
    bandMaterial = CelestialMaterial(colorTexture: milkyWay)
      ..alphaMode = scene.AlphaMode.blend;
    starNode =
        scene.Node(name: 'Stars', mesh: scene.Mesh(starGeometry, starMaterial))
          ..shadowCastingMode = scene.ShadowCastingMode.off
          ..renderOrder = -30;
    bandNode =
        scene.Node(
            name: 'Milky Way',
            mesh: scene.Mesh(_milkyWayGeometry(), bandMaterial),
          )
          ..shadowCastingMode = scene.ShadowCastingMode.off
          ..renderOrder = -40;
    marker = scene.Node(
      name: 'Galactic center',
      mesh: scene.Mesh(
        scene.SphereGeometry(radius: 100, segments: 16, rings: 8),
        CelestialMaterial()..baseColorFactor = vm.Vector4(0.65, 0.3, 1, 1),
      ),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
    // Sgr A*, matching ObserverSkyFrame.galacticCenter.
    final center = Star(
      1,
      266.416817 * radians,
      -29.007825 * radians,
      0,
    ).direction;
    marker.position = vm.Vector3(center.x, center.y, center.z) * 28000;
    root = scene.Node(name: 'Night sky')
      ..add(starNode)
      ..add(bandNode)
      ..add(marker);
    for (final planet in Planet.values) {
      final colour = _planetColour[planet]!;
      planets[planet] = scene.Node(
        name: planet.label,
        mesh: scene.Mesh(
          scene.SphereGeometry(radius: 1, segments: 12, rings: 6),
          CelestialMaterial()..baseColorFactor = colour,
        ),
      )..shadowCastingMode = scene.ShadowCastingMode.off;
      root.add(planets[planet]!);
    }
  }

  /// Planet label names, drawn by [labelAtlasForPlanets].
  static List<String> get planetLabels => [
    for (final planet in Planet.values) planet.label,
  ];

  static Future<scene.Texture2D> labelAtlasForPlanets() =>
      buildLabelAtlas(planetLabels, color: const Color(0xFFFFE9B8));

  /// Marker tints; brightness comes from apparent magnitude, as with stars.
  static final _planetColour = <Planet, vm.Vector4>{
    Planet.mercury: vm.Vector4(0.86, 0.83, 0.78, 1),
    Planet.venus: vm.Vector4(1, 0.97, 0.86, 1),
    Planet.mars: vm.Vector4(0.93, 0.53, 0.36, 1),
    Planet.jupiter: vm.Vector4(0.94, 0.87, 0.72, 1),
    Planet.saturn: vm.Vector4(0.93, 0.85, 0.6, 1),
    Planet.uranus: vm.Vector4(0.68, 0.88, 0.93, 1),
    Planet.neptune: vm.Vector4(0.6, 0.71, 0.95, 1),
  };
  ConstellationRenderer? constellations;
  final planets = <Planet, scene.Node>{};
  scene.Node? planetLabelNode;
  scene.BillboardGeometry? planetLabelGeometry;

  /// Planet names reuse the constellation label budget so guides stay one node.
  Future<void> loadPlanetLabels() async {
    if (planetLabelNode != null) return;
    final geometry = scene.BillboardGeometry(capacity: Planet.values.length)
      ..flipbookColumns = 8
      ..flipbookRows = 1;
    final node = scene.Node(
      name: 'Planet names',
      mesh: scene.Mesh(
        geometry,
        scene.SpriteMaterial(colorTexture: await labelAtlasForPlanets()),
      ),
    )..shadowCastingMode = scene.ShadowCastingMode.off;
    planetLabelGeometry = geometry;
    planetLabelNode = node;
    root.add(node);
  }

  void addConstellations(ConstellationRenderer renderer) {
    constellations = renderer;
    root.add(renderer.root);
  }

  void updateLabels(SimulationState state, Size viewport) {
    constellations?.update(state, viewport, _rotation);
    _updatePlanetLabels(state, viewport);
  }

  /// Same framing test as constellation names, but planets move, so anchors come
  /// from the current ephemeris rather than a static catalog.
  void _updatePlanetLabels(SimulationState state, Size viewport) {
    final geometry = planetLabelGeometry,
        node = planetLabelNode,
        direction = _planetDirections;
    if (geometry == null || node == null || direction == null) return;
    final frame = state.cameraFrame;
    final forward = vm.Vector3(
      frame.forward.x,
      frame.forward.y,
      frame.forward.z,
    );
    final up = vm.Vector3(frame.up.x, frame.up.y, frame.up.z);
    final right = vm.Vector3(frame.right.x, frame.right.y, frame.right.z);
    final visible = starMaterial.baseColorFactor.x > 0 && viewport.height > 0;
    node.visible = visible;
    if (!visible) return;
    geometry.worldUp = up;
    var count = 0;
    for (var i = 0; i < Planet.values.length; i++) {
      final anchor = direction[Planet.values[i]]!;
      final d = _rotation.transformed(vm.Vector3(anchor.x, anchor.y, anchor.z));
      final depth = d.dot(forward);
      if (d.y <= 0 || depth <= 0) continue;
      if (d.dot(right).abs() > depth * math.tan(state.horizontalFov / 2) ||
          d.dot(up).abs() > depth * math.tan(state.verticalFov / 2)) {
        continue;
      }
      final unitsPerPixel =
          2 *
          planetDistance *
          depth *
          math.tan(state.verticalFov / 2) /
          viewport.height;
      geometry.setInstance(
        count++,
        center: vm.Vector3(anchor.x, anchor.y, anchor.z) * planetDistance,
        width: 192 * unitsPerPixel,
        height: 40 * unitsPerPixel,
        frame: i.toDouble(),
      );
    }
    geometry.commit(count);
  }

  static const starDistance = 40000.0, bandDistance = 45000.0;
  static const planetDistance = 39500.0;
  late final scene.Node root, starNode, bandNode, marker;
  late final scene.MeshGeometry starGeometry;
  late final scene.UnlitMaterial starMaterial, bandMaterial;
  (DateTime, double, double)? _lastObserver;
  DateTime? _planetStamp;
  Map<Planet, vm.Vector3>? _planetDirections;
  vm.Matrix3 _rotation = vm.Matrix3.identity();

  void update(
    SimulationState state,
    vm.Vector3 eye, {
    ObserverSkyFrame? frame,
    SkyState? sky,
  }) {
    final observer = (state.timestamp, state.latitude, state.longitude);
    if (_lastObserver != observer) {
      final skyFrame = frame ?? state.observerFrame;
      final x = skyFrame.direction(0, 0),
          y = skyFrame.direction(math.pi / 2, 0),
          z = skyFrame.direction(0, math.pi / 2);
      _rotation = vm.Matrix3.columns(
        vm.Vector3(x.x, x.y, x.z),
        vm.Vector3(y.x, y.y, y.z),
        vm.Vector3(z.x, z.y, z.z),
      );
      _lastObserver = observer;
    }
    // Positions drift at most a few arcminutes per hour; skip per-playback-tick work.
    if (_planetStamp == null ||
        state.timestamp.difference(_planetStamp!).abs() >
            const Duration(hours: 1)) {
      _planetStamp = state.timestamp;
      _planetDirections = {
        for (final body in state.planets)
          body.planet: vm.Vector3(
            math.cos(body.dec) * math.cos(body.ra),
            math.cos(body.dec) * math.sin(body.ra),
            math.sin(body.dec),
          ),
      };
      for (final body in state.planets) {
        final anchor = _planetDirections![body.planet]!;
        final flux = math.pow(10, -0.2 * body.magnitude).toDouble();
        // Bright planets read slightly larger than a star of equal magnitude.
        final radius = planetDistance * (0.0007 + 0.0011 * flux);
        planets[body.planet]!
          ..position = anchor * planetDistance
          ..scale = vm.Vector3.all(radius);
      }
    }
    root.localTransform = vm.Matrix4.identity()
      ..setRotation(_rotation)
      ..setTranslation(eye);
    final current = sky ?? state.sky;
    final stars = nightVisibility(current) * state.weatherLightTransmission,
        band =
            nightVisibility(current, milkyWay: true) *
            state.weatherLightTransmission;
    starNode.visible = stars > 0;
    bandNode.visible = band > 0.001;
    starMaterial.baseColorFactor = vm.Vector4(stars, stars, stars, 1);
    bandMaterial.baseColorFactor = vm.Vector4(1, 1, 1, band);
    marker.visible = state.target == CelestialTarget.galacticCenter;
    for (final node in planets.values) {
      node.visible = stars > 0;
    }
    constellations?.root.visible = state.showConstellations;
  }
}
