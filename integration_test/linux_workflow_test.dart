import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/core/night_sky.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/render/moon.dart';

Future<double> viewportBrightness(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final viewport = tester.getRect(find.byType(scene.SceneView));
  var total = 0.0, count = 0;
  for (
    var y = viewport.top.toInt() + 8;
    y < viewport.bottom.toInt() - 8;
    y += 8
  ) {
    for (
      var x = viewport.left.toInt() + 8;
      x < viewport.right.toInt() - 8;
      x += 8
    ) {
      final offset = (y * image.width + x) * 4;
      total +=
          0.2126 * raw.getUint8(offset) +
          0.7152 * raw.getUint8(offset + 1) +
          0.0722 * raw.getUint8(offset + 2);
      count++;
    }
  }
  image.dispose();
  return total / count;
}

Future<int> brightSkyPixels(
  WidgetTester tester,
  GlobalKey key, {
  int threshold = 100,
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final rect = tester.getRect(find.byType(scene.SceneView));
  var count = 0;
  for (var y = rect.top.toInt() + 8; y < rect.bottom.toInt() - 8; y++) {
    for (var x = rect.left.toInt() + 8; x < rect.right.toInt() - 8; x++) {
      if ((x - rect.center.dx).abs() < 16 && (y - rect.center.dy).abs() < 16) {
        continue;
      }
      final offset = (y * image.width + x) * 4;
      if (raw.getUint8(offset) > threshold ||
          raw.getUint8(offset + 1) > threshold ||
          raw.getUint8(offset + 2) > threshold) {
        count++;
      }
    }
  }
  image.dispose();
  return count;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Linux map and GPU camera workflow', (tester) async {
    final captureKey = GlobalKey();
    final planDirectory = await Directory.systemTemp.createTemp(
      'photosim-workflow-plans-',
    );
    addTearDown(() => planDirectory.delete(recursive: true));
    final planStore = PlanRepository(planDirectory);
    SimulationState camera() =>
        tester.widget<CameraInspector>(find.byType(CameraInspector)).state;
    Future<void> waitForImagery() async {
      for (
        var i = 0;
        i < 240 && find.text('USGS NAIP · 9/9 textures').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('USGS NAIP · 9/9 textures'), findsOneWidget);
    }

    Future<void> capture(String name) async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/validation').create(recursive: true);
      await File('build/validation/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: PhotoSimApp(plans: planStore),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    final original = camera();
    await tester.tapAt(
      tester.getCenter(find.byType(FlutterMap)) + const Offset(100, 50),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(camera().latitude, isNot(original.latitude));
    final clicked = camera();
    await tester.drag(find.byIcon(Icons.photo_camera), const Offset(50, 20));
    await tester.pump();
    final placed = camera();
    expect(placed.latitude, isNot(clicked.latitude));
    expect(placed.longitude, isNot(clicked.longitude));
    await tester.drag(find.byIcon(Icons.open_with), const Offset(70, 0));
    await tester.pump();
    expect(camera().azimuth, isNot(placed.azimuth));
    expect(camera().latitude, placed.latitude);
    final aimed = camera();
    final polygon = tester
        .widget<PolygonLayer>(find.byType(PolygonLayer))
        .polygons
        .single;
    final edgeAngle = bearing(aimed.location, polygon.points.last);
    final expected = (aimed.azimuth + aimed.horizontalFov / radians / 2) % 360;
    expect((edgeAngle - expected + 540) % 360 - 180, closeTo(0, 1e-7));
    await capture('linux-map');
    await tester.tap(find.text('3D Preview'));
    for (
      var i = 0;
      i < 30 && find.byType(scene.SceneView).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(scene.SceneView), findsOneWidget);
    for (
      var i = 0;
      i < 120 && find.text('Real terrain · 9/9 tiles').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Real terrain · 9/9 tiles'), findsOneWidget);
    expect(camera().groundElevation, inInclusiveRange(500, 3000));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    final initialView = tester.widget<scene.SceneView>(
      find.byType(scene.SceneView),
    );
    final world = initialView.scene;
    final meshes = world!.root.children
        .where((node) => node.mesh != null && node.name != 'Moon')
        .map((node) => node.mesh!.primitives.single.geometry)
        .toList();
    await waitForImagery();
    final texturedMeshes = world.root.children
        .where((node) => node.mesh != null && node.name != 'Moon')
        .toList();
    expect(texturedMeshes.length, 9);
    for (var i = 0; i < meshes.length; i++) {
      expect(
        texturedMeshes[i].mesh!.primitives.single.geometry,
        same(meshes[i]),
      );
      expect(
        texturedMeshes[i].mesh!.primitives.single.material,
        isA<scene.UnlitMaterial>(),
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
    final naturalImage =
        await (captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final raw = (await naturalImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final viewport = tester.getRect(find.byType(scene.SceneView));
    final colors = <int>{};
    for (
      var y = viewport.top.toInt() + 8;
      y < viewport.bottom.toInt() - 8;
      y += 8
    ) {
      for (
        var x = viewport.left.toInt() + 8;
        x < viewport.right.toInt() - 8;
        x += 8
      ) {
        final offset = (y * naturalImage.width + x) * 4;
        colors.add(
          (raw.getUint8(offset) << 16) |
              (raw.getUint8(offset + 1) << 8) |
              raw.getUint8(offset + 2),
        );
      }
    }
    naturalImage.dispose();
    // Actual image detail, not merely a material assignment on a still-green render.
    expect(colors.length, greaterThan(500));
    await capture('linux-naip-natural');
    await tester.tap(find.text('Approximate relighting'));
    await tester.pump();
    expect(
      texturedMeshes.first.mesh!.primitives.single.material,
      isA<scene.PhysicallyBasedMaterial>(),
    );
    expect(
      (initialView.camera! as scene.PerspectiveCamera).fovRadiansY,
      aimed.verticalFov,
    );
    expect(
      (initialView.camera! as scene.PerspectiveCamera).position.y,
      closeTo(camera().groundElevation! + camera().height, 0.001),
    );
    expect(world.directionalLight!.castsShadow, isTrue);
    final lightDirection = world.directionalLight!.direction.clone();
    final counters = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .where((text) => text?.endsWith('downloaded') ?? false)
        .toList();
    await tester.tap(find.byTooltip('Later by one hour'));
    await tester.pump(const Duration(seconds: 1));
    expect(world.directionalLight!.direction, isNot(lightDirection));
    final sun = camera().sky.sun;
    expect(
      world.directionalLight!.direction.x,
      closeTo(-sun.direction.x, 1e-6),
    );
    expect(
      world.directionalLight!.direction.y,
      closeTo(-sun.direction.y, 1e-6),
    );
    expect(
      world.directionalLight!.direction.z,
      closeTo(-sun.direction.z, 1e-6),
    );
    expect(world.skybox!.source, isA<scene.PhysicalSkySource>());
    final skySource = world.skybox!.source as scene.PhysicalSkySource;
    expect(skySource.sunAngularRadius, sun.angularRadius);
    await capture('linux-solar-day');
    final dayBrightness = await viewportBrightness(tester, captureKey);
    final timeSlider = tester.getRect(
      find.byKey(const ValueKey('utc-day-slider')),
    );
    await tester.tapAt(
      Offset(
        timeSlider.left + 24 + (timeSlider.width - 48) * 390 / 1439,
        timeSlider.center.dy,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(camera().timestamp.day, original.timestamp.day);
    expect(camera().timestamp.hour, 6);
    final beforePlayback = camera().timestamp;
    await tester.tap(
      find.byTooltip('Play time (5 simulated minutes per second)'),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await tester.tap(find.byTooltip('Pause time'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(camera().timestamp.isAfter(beforePlayback), isTrue);
    expect(
      tester.widget<scene.SceneView>(find.byType(scene.SceneView)).scene,
      same(world),
    );
    expect(find.textContaining('America/Los_Angeles'), findsOneWidget);
    expect(
      world.directionalLight!.intensity,
      closeTo(moonlightIntensity(camera().sky), 1e-12),
    );
    expect(
      world.directionalLight!.direction.y,
      closeTo(-camera().sky.moon.direction.y, 1e-6),
    );
    expect(world.environmentIntensity, closeTo(0.04, 1e-12));
    expect(skySource.sunDirection.y, lessThan(0));
    await capture('linux-solar-night');
    // Isolate ambient fill from moonlight: it lifts terrain, not the sky.
    final ambient = world.environmentIntensity;
    final lunarIntensity = world.directionalLight!.intensity;
    world.directionalLight!.intensity = 0;
    await tester.pump(const Duration(milliseconds: 300));
    final filledTerrain = await viewportBrightness(tester, captureKey);
    world.environmentIntensity = 0;
    await tester.pump(const Duration(milliseconds: 300));
    final unfilledTerrain = await viewportBrightness(tester, captureKey);
    expect(filledTerrain, greaterThan(unfilledTerrain + 1));
    expect(filledTerrain, lessThan(dayBrightness * 0.25));
    for (final node in texturedMeshes) {
      node.visible = false;
    }
    await tester.pump(const Duration(milliseconds: 300));
    final unfilledSky = await viewportBrightness(tester, captureKey);
    world.environmentIntensity = ambient;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      await viewportBrightness(tester, captureKey),
      closeTo(unfilledSky, 0.05),
    );
    for (final node in texturedMeshes) {
      node.visible = true;
    }
    world.directionalLight!.intensity = lunarIntensity;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      await viewportBrightness(tester, captureKey),
      lessThan(dayBrightness * 0.5),
    );
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where((text) => text?.endsWith('downloaded') ?? false)
          .toList(),
      counters,
    );
    for (var i = 0; i < meshes.length; i++) {
      expect(
        texturedMeshes[i].mesh!.primitives.single.geometry,
        same(meshes[i]),
      );
    }
    tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .onChanged(camera().copyWith(timestamp: original.timestamp));
    await tester.pump(const Duration(seconds: 1));
    expect(world.directionalLight!.intensity, greaterThan(0));
    final beforeMoon = camera();
    final moonState = beforeMoon.copyWith(
      timestamp: DateTime.utc(2026, 6, 22, 3),
    );
    tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .onChanged(
          moonState.copyWith(
            azimuth: moonState.sky.moon.azimuth,
            pitch: moonState.sky.moon.altitude,
            focalLength: 600,
          ),
        );
    await tester.pump(const Duration(seconds: 1));
    final moonNode = world.root.children.singleWhere(
      (node) => node.name == 'Moon',
    );
    final moonGeometry = moonNode.mesh!.primitives.single.geometry;
    expect(moonNode.shadowCastingMode, scene.ShadowCastingMode.off);
    expect(
      moonNode.scale.x / MoonRenderer.distance,
      closeTo(math.sin(camera().sky.moon.angularRadius), 1e-8),
    );
    final terrainBlocked = await viewportBrightness(tester, captureKey);
    moonNode.visible = false;
    await tester.pump(const Duration(seconds: 1));
    expect(
      await viewportBrightness(tester, captureKey),
      closeTo(terrainBlocked, 0.05),
    );
    moonNode.visible = true;
    // This selected canyon sightline is terrain-blocked. Isolate the sky to
    // validate phase pixels, then independently exercise foreground depth.
    for (final node in texturedMeshes) {
      node.visible = false;
    }
    await tester.pump(const Duration(seconds: 1));
    await capture('linux-moon-phase');
    final moonBrightness = await viewportBrightness(tester, captureKey);
    final phaseColors = moonGeometry.extractMeshData().colors!;
    final phaseImage =
        await (captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final phasePixels = (await phaseImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final center = tester.getCenter(find.byType(scene.SceneView));
    var left = 0, right = 0;
    for (var y = -30; y <= 30; y += 5) {
      for (var x = 15; x <= 45; x += 5) {
        left += phasePixels.getUint8(
          ((center.dy.toInt() + y) * phaseImage.width + center.dx.toInt() - x) *
              4,
        );
        right += phasePixels.getUint8(
          ((center.dy.toInt() + y) * phaseImage.width + center.dx.toInt() + x) *
              4,
        );
      }
    }
    phaseImage.dispose();
    // The Sun lies to the right of the Moon at this northern-site waxing phase.
    expect(right, greaterThan(left * 2));
    moonNode.visible = false;
    await tester.pump(const Duration(seconds: 1));
    expect(
      moonBrightness,
      greaterThan(await viewportBrightness(tester, captureKey) + 0.3),
    );
    moonNode.visible = true;
    // A foreground opaque blocker exercises the same depth test as terrain.
    final moonEye =
        (tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
                as scene.PerspectiveCamera)
            .position;
    final blocker = scene.Node(
      name: 'Moon occlusion test',
      mesh: scene.Mesh(scene.SphereGeometry(radius: 20), scene.UnlitMaterial()),
    )..position = moonEye + (moonNode.position - moonEye).normalized() * 1000;
    world.add(blocker);
    await tester.pump(const Duration(seconds: 1));
    final blocked = await viewportBrightness(tester, captureKey);
    moonNode.visible = false;
    await tester.pump(const Duration(seconds: 1));
    expect(
      await viewportBrightness(tester, captureKey),
      closeTo(blocked, 0.05),
    );
    world.remove(blocker);
    for (final node in texturedMeshes) {
      node.visible = true;
    }
    moonNode.visible = true;
    tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .onChanged(beforeMoon);
    await tester.pump(const Duration(seconds: 1));
    expect(moonNode.mesh!.primitives.single.geometry, same(moonGeometry));
    expect(moonGeometry.extractMeshData().colors, isNot(phaseColors));
    for (var i = 0; i < meshes.length; i++) {
      expect(
        texturedMeshes[i].mesh!.primitives.single.geometry,
        same(meshes[i]),
      );
    }
    // Real native sky rendering: immutable batches rotate, dim in daylight,
    // and depth-test against terrain and a controlled foreground blocker.
    final night = beforeMoon.copyWith(
      timestamp: DateTime.utc(2026, 6, 21, 9),
      target: CelestialTarget.galacticCenter,
      focalLength: 16,
    );
    tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .onChanged(
          night.copyWith(
            azimuth: night.galacticCenter.azimuth,
            pitch: night.galacticCenter.altitude,
          ),
        );
    await tester.pump(const Duration(seconds: 1));
    final nightRoot = world.root.children.singleWhere(
      (node) => node.name == 'Night sky',
    );
    final stars = nightRoot.children.singleWhere(
      (node) => node.name == 'Stars',
    );
    final band = nightRoot.children.singleWhere(
      (node) => node.name == 'Milky Way',
    );
    final marker = nightRoot.children.singleWhere(
      (node) => node.name == 'Galactic center',
    );
    final starGeometry = stars.mesh!.primitives.single.geometry;
    final bandGeometry = band.mesh!.primitives.single.geometry;
    final rotation = nightRoot.localTransform.clone();
    expect(stars.visible, isTrue);
    expect(band.visible, isTrue);
    expect(marker.visible, isTrue);
    expect(find.textContaining('Galactic center: inside FOV'), findsOneWidget);
    await capture('linux-night-sky-terrain');
    moonNode.visible = false;
    marker.visible = false;
    for (final node in texturedMeshes) {
      node.visible = false;
    }
    await tester.pump(const Duration(seconds: 1));
    await capture('linux-night-sky-isolated');
    final visibleStars = await brightSkyPixels(
      tester,
      captureKey,
      threshold: 10,
    );
    stars.visible = false;
    await tester.pump(const Duration(seconds: 1));
    expect(
      visibleStars,
      greaterThan(
        await brightSkyPixels(tester, captureKey, threshold: 10) + 30,
      ),
    );
    final bandBrightness = await viewportBrightness(tester, captureKey);
    band.visible = false;
    await tester.pump(const Duration(seconds: 1));
    expect(
      bandBrightness,
      greaterThan(await viewportBrightness(tester, captureKey) + 0.1),
    );
    // Resolve one bright star at telephoto scale so the actual canyon
    // occlusion check is not dependent on subpixel star sampling.
    final antares = ObserverSkyFrame(
      timestamp: night.timestamp,
      latitude: night.latitude,
      longitude: night.longitude,
    ).position(247.3519 * radians, -26.4320 * radians);
    tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .onChanged(
          night.copyWith(
            // Keep the star away from the UI crosshair excluded by pixel checks.
            azimuth: antares.azimuth + 0.3,
            pitch: antares.altitude,
            focalLength: 600,
            target: CelestialTarget.none,
          ),
        );
    await tester.pump(const Duration(seconds: 1));
    band.visible = false;
    moonNode.visible = false;
    await tester.pump(const Duration(seconds: 1));
    final isolatedStar = await brightSkyPixels(tester, captureKey);
    expect(isolatedStar, greaterThan(30));
    await capture('linux-star-isolated');
    for (final node in texturedMeshes) {
      node.visible = true;
    }
    await tester.pump(const Duration(seconds: 1));
    expect(
      await brightSkyPixels(tester, captureKey),
      lessThan(isolatedStar / 2),
    );
    for (final node in texturedMeshes) {
      node.visible = false;
    }
    tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .onChanged(
          night.copyWith(
            azimuth: night.galacticCenter.azimuth,
            pitch: night.galacticCenter.altitude,
          ),
        );
    await tester.pump(const Duration(seconds: 1));
    marker.visible = false;
    moonNode.visible = false;
    final skyCamera =
        tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
            as scene.PerspectiveCamera;
    final skyBlocker =
        scene.Node(
            name: 'Night sky occlusion test',
            mesh: scene.Mesh(
              scene.SphereGeometry(radius: 990),
              scene.UnlitMaterial()..baseColorFactor.setValues(0, 0, 0, 1),
            ),
          )
          ..position =
              skyCamera.position +
              (skyCamera.target - skyCamera.position).normalized() * 1000
          ..shadowCastingMode = scene.ShadowCastingMode.off;
    world.add(skyBlocker);
    await tester.pump(const Duration(seconds: 1));
    expect(await brightSkyPixels(tester, captureKey), lessThan(5));
    world.remove(skyBlocker);
    for (final node in texturedMeshes) {
      node.visible = true;
    }
    await tester.tap(find.byTooltip('Later by one hour'));
    await tester.pump(const Duration(seconds: 1));
    expect(nightRoot.localTransform, isNot(rotation));
    expect(stars.mesh!.primitives.single.geometry, same(starGeometry));
    expect(band.mesh!.primitives.single.geometry, same(bandGeometry));
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where((text) => text?.endsWith('downloaded') ?? false)
          .toList(),
      counters,
    );
    tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .onChanged(beforeMoon);
    await tester.pump(const Duration(seconds: 1));
    expect(stars.visible, isFalse);
    expect(band.visible, isFalse);
    expect(marker.visible, isFalse);
    for (var i = 0; i < meshes.length; i++) {
      expect(
        texturedMeshes[i].mesh!.primitives.single.geometry,
        same(meshes[i]),
      );
    }
    await tester.drag(find.byType(scene.SceneView), const Offset(100, -20));
    await tester.pump();
    final rotated = camera();
    expect(rotated.azimuth, isNot(aimed.azimuth));
    expect(rotated.latitude, placed.latitude);
    await tester.tap(find.text('APS-C'));
    await tester.pump(const Duration(milliseconds: 300));
    final updatedView = tester.widget<scene.SceneView>(
      find.byType(scene.SceneView),
    );
    expect(updatedView.scene, same(world));
    expect(
      (updatedView.camera! as scene.PerspectiveCamera).fovRadiansY,
      camera().verticalFov,
    );
    expect(camera().sensor, Sensor.apsC);
    await tester.tap(find.byTooltip('Later by one hour'));
    await tester.pump();
    expect(
      tester.widget<scene.SceneView>(find.byType(scene.SceneView)).scene,
      same(world),
    );
    expect(find.text('Real terrain · 9/9 tiles'), findsOneWidget);
    await capture('linux-preview');
    await tester.tap(find.text('Map'));
    await tester.pump(const Duration(seconds: 1));
    expect(camera().azimuth, rotated.azimuth);
    expect(camera().sensor, Sensor.apsC);
    await tester.tap(find.byTooltip('Later by one hour'));
    await tester.pump();
    expect(
      camera().timestamp,
      original.timestamp.add(const Duration(hours: 2)),
    );
    await tester.tap(find.text('3D Preview'));
    for (
      var i = 0;
      i < 120 && find.text('Real terrain · 9/9 tiles').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('9 cached · 0 downloaded'), findsOneWidget);
    await waitForImagery();
    expect(find.text('NAIP: 10 cached · 0 downloaded'), findsOneWidget);
    expect(camera().relitImagery, isTrue);
    expect(camera().groundElevation, isNotNull);
    await tester.tap(find.text('Map'));
    await tester.pump(const Duration(milliseconds: 500));
    final beforeMove = camera();
    await tester.tapAt(
      tester.getCenter(find.byType(FlutterMap)) + const Offset(-200, 80),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(camera().latitude, isNot(beforeMove.latitude));
    expect(camera().groundElevation, isNull);
    await tester.tap(find.text('3D Preview'));
    for (
      var i = 0;
      i < 120 && find.text('Real terrain · 9/9 tiles').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Real terrain · 9/9 tiles'), findsOneWidget);
    expect(camera().groundElevation, isNotNull);
    expect(camera().groundElevation, isNot(beforeMove.groundElevation));
    await waitForImagery();
    await capture('linux-terrain-moved');
    tester
        .widget<CameraInspector>(find.byType(CameraInspector))
        .onChanged(
          camera().copyWith(
            target: CelestialTarget.galacticCenter,
            focalLength: 85,
            height: 4.2,
          ),
        );
    await tester.pump(const Duration(milliseconds: 300));
    final composition = camera();
    await tester.tap(find.byTooltip('Photography plans'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save plan').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextFormField), 'Night ridge');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    for (
      var i = 0;
      i < 30 && find.textContaining('Saved Night ridge').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Saved Night ridge'), findsOneWidget);
    expect((await planStore.loadAll()).plans.single.name, 'Night ridge');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    // Recreate the entire app and repository, not just the workspace.
    await File('${planDirectory.path}/broken.json').writeAsString('{bad');
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: PhotoSimApp(plans: PlanRepository(planDirectory)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(camera().target, CelestialTarget.none);
    await tester.tap(find.byTooltip('Photography plans'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Open plan').last);
    for (
      var i = 0;
      i < 30 && find.text('Night ridge').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('1 unreadable plans left unchanged.'), findsOneWidget);
    await tester.tap(find.text('Night ridge'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      SavedPlan('Compare', camera()).encode(),
      SavedPlan('Compare', composition).encode(),
    );
    expect(camera().groundElevation, isNull);
    expect(
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.initialCenter,
      composition.location,
    );
    await capture('linux-reopened-plan');
    await tester.tap(find.text('3D Preview'));
    for (
      var i = 0;
      i < 120 && find.text('Real terrain · 9/9 tiles').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await waitForImagery();
    expect(find.text('9 cached · 0 downloaded'), findsOneWidget);
    expect(find.text('NAIP: 10 cached · 0 downloaded'), findsOneWidget);
    expect(
      SavedPlan('Compare', camera()).encode(),
      SavedPlan('Compare', composition).encode(),
    );
    expect(camera().groundElevation, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
