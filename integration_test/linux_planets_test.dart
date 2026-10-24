import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/core/planets.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import 'workspace_navigation.dart';

Future<ui.Image> _capture(GlobalKey key) async =>
    (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
        .toImage();

Future<void> _save(ui.Image image, String name) async {
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory('build/validation').create(recursive: true);
    await File('build/validation/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

/// RMS brightness of raw RGBA over [rect] and the brightness-weighted centroid.
Future<({double rms, Offset centroid})> _brightness(
  ui.Image image,
  Rect rect,
) async {
  final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var total = 0.0, count = 0, sumWeight = 0.0, weightedX = 0.0, weightedY = 0.0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y += 3) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x += 3) {
      final offset = (y * image.width + x) * 4;
      final luma =
          raw.getUint8(offset) * 0.2126 +
          raw.getUint8(offset + 1) * 0.7152 +
          raw.getUint8(offset + 2) * 0.0722;
      total += luma * luma;
      count++;
      sumWeight += luma;
      weightedX += x * luma;
      weightedY += y * luma;
    }
  }
  return (
    rms: math.sqrt(total / count),
    centroid: sumWeight == 0
        ? rect.center
        : Offset(weightedX / sumWeight, weightedY / sumWeight),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('planets render, label and aim under a real night sky', (
    tester,
  ) async {
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: capture, child: const PhotoSimApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    CameraInspector inspector() =>
        tester.widget<CameraInspector>(find.byType(CameraInspector));
    void change(SimulationState next) => inspector().onChanged(next);

    // 2026-10-13 23:00 PDT: sun -52 degrees, moon set, Saturn and Neptune high.
    change(
      inspector().state.copyWith(
        timestamp: DateTime.utc(2026, 10, 14, 6),
        pitch: 20,
        azimuth: 150,
      ),
    );
    await tester.pump();
    await openWorkspace(tester, '3D Preview');
    for (var i = 0; i < 240; i++) {
      if (find.text('Imagery 9/9').evaluate().isNotEmpty &&
          tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Export PNG'),
                  )
                  .onPressed !=
              null) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
    final world = tester
        .widget<scene.SceneView>(find.byType(scene.SceneView))
        .scene!;
    final sky = world.root.children.singleWhere(
      (node) => node.name == 'Night sky',
    );
    for (final planet in Planet.values) {
      final node = sky.children.singleWhere(
        (child) => child.name == planet.label,
      );
      expect(node.visible, isTrue, reason: '${planet.label} marker visible');
      expect(node.position.length, closeTo(39500, 1));
      expect(node.scale.x, greaterThan(0));
    }
    expect(
      sky.children.singleWhere((child) => child.name == 'Planet names').visible,
      isTrue,
    );
    expect(
      sky.children.singleWhere((child) => child.name == 'Stars').visible,
      isTrue,
    );

    // Aim at Saturn and confirm the app's own ephemeris agrees with the marker.
    final before = inspector().state;
    final saturn = before
        .copyWith(target: CelestialTarget.saturn)
        .targetPosition!;
    expect(saturn.altitude, greaterThan(20));
    change(
      before.copyWith(
        target: CelestialTarget.saturn,
        azimuth: saturn.azimuth,
        pitch: saturn.altitude,
      ),
    );
    await tester.pump();
    await pumpUntilRendered(tester, world, frames: 4);
    expect(inspector().state.targetAngularOffset!, lessThan(0.01));
    final marker = sky.children.singleWhere((child) => child.name == 'Saturn');
    expect(marker.position.y, greaterThan(0), reason: 'above the horizon');
    final ephemeris = inspector().state.planets.singleWhere(
      (entry) => entry.planet == Planet.saturn,
    );
    final local = marker.position.normalized();
    final equatorial = (
      math.cos(ephemeris.dec) * math.cos(ephemeris.ra),
      math.cos(ephemeris.dec) * math.sin(ephemeris.ra),
      math.sin(ephemeris.dec),
    );
    expect(
      local.x * equatorial.$1 +
          local.y * equatorial.$2 +
          local.z * equatorial.$3,
      greaterThan(0.9999),
      reason: 'marker uses the J2000 ephemeris direction',
    );
    final skyDirection = inspector().state
        .planetPosition(Planet.saturn)
        .direction;
    final forward =
        (tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
                as scene.PerspectiveCamera)
            .forward;
    expect(
      skyDirection.x * forward.x +
          skyDirection.y * forward.y +
          skyDirection.z * forward.z,
      greaterThan(0.9999),
      reason: 'aimed camera looks at Saturn',
    );
    // Neptune's marker must be the neighbouring bright point, not a fixed offset.
    final neptune = inspector().state.planetPosition(Planet.neptune);
    final separation =
        math.acos(
          (skyDirection.x * neptune.direction.x +
                  skyDirection.y * neptune.direction.y +
                  skyDirection.z * neptune.direction.z)
              .clamp(-1.0, 1.0),
        ) /
        radians;
    // 13 degrees of azimuth at ~50 degrees altitude compresses to ~8 degrees.
    expect(separation, closeTo(8.1, 2.0));

    final saturnFrame = await _capture(capture);
    final region = tester
        .getRect(find.byKey(const ValueKey('photo-region')))
        .deflate(4);
    final stars = await _brightness(saturnFrame, region);
    await _save(saturnFrame, 'linux-planets-night-sky');
    // Stars and planets are drawn: a black frame would mean the sky nodes
    // exist but never reach the render.
    expect(stars.rms, greaterThan(1.5));

    // Aim at the galactic center on a moonless July night and require the band
    // to land in the middle of the frame rather than merely exist.
    change(
      before.copyWith(
        timestamp: DateTime.utc(2026, 7, 15, 6),
        target: CelestialTarget.galacticCenter,
      ),
    );
    await tester.pump();
    final center = inspector().state.galacticCenter;
    change(
      inspector().state.copyWith(
        azimuth: center.azimuth,
        pitch: center.altitude,
      ),
    );
    await tester.pump();
    await pumpUntilRendered(tester, world, frames: 4);
    final galacticFrame = await _capture(capture);
    expect(center.altitude, greaterThan(10));
    // Compare drawn pixels against the galactic plane computed from this state:
    // a mirrored or rotated band shows up as no brightness contrast.
    final state = inspector().state;
    final view = tester.getRect(find.byType(scene.SceneView));
    final camera =
        tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
            as scene.PerspectiveCamera;
    final pole = state.observerFrame.direction(
      192.85948 * radians,
      27.12825 * radians,
    );
    final basis = state.cameraFrame;
    final tanY = math.tan(camera.fovRadiansY / 2);
    final tanX = tanY * view.width / view.height;
    final raw = (await galacticFrame.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var bandSum = 0.0, bandCount = 0, offSum = 0.0, offCount = 0;
    for (var y = view.top.toInt(); y < view.bottom.toInt(); y += 4) {
      for (var x = view.left.toInt(); x < view.right.toInt(); x += 4) {
        final nx = 2 * (x - view.center.dx) / view.width;
        final ny = 2 * (view.center.dy - y) / view.height;
        final d = (
          basis.forward.x + basis.right.x * nx * tanX + basis.up.x * ny * tanY,
          basis.forward.y + basis.right.y * nx * tanX + basis.up.y * ny * tanY,
          basis.forward.z + basis.right.z * nx * tanX + basis.up.z * ny * tanY,
        );
        final length = math.sqrt(d.$1 * d.$1 + d.$2 * d.$2 + d.$3 * d.$3);
        final latitude =
            math.asin(
              ((d.$1 * pole.x + d.$2 * pole.y + d.$3 * pole.z) / length).clamp(
                -1.0,
                1.0,
              ),
            ) /
            radians;
        final offset = (y * galacticFrame.width + x) * 4;
        final luma =
            raw.getUint8(offset) * 0.2126 +
            raw.getUint8(offset + 1) * 0.7152 +
            raw.getUint8(offset + 2) * 0.0722;
        if (latitude.abs() < 8) {
          bandSum += luma;
          bandCount++;
        } else if (latitude.abs() > 22 && latitude.abs() < 38) {
          offSum += luma;
          offCount++;
        }
      }
    }
    expect(bandCount, greaterThan(500));
    expect(offCount, greaterThan(500));
    final bandMean = bandSum / bandCount, offMean = offSum / offCount;
    debugPrint(
      'Milky Way luminance band=$bandMean off=$offMean ratio=${(bandMean / offMean).toStringAsFixed(2)}',
    );
    expect(
      bandMean,
      greaterThan(offMean * 1.5),
      reason: 'galactic plane drawn where the ephemeris puts it',
    );
    await _save(galacticFrame, 'linux-milkyway-aim');

    expect(find.byType(SimulationWorkspace), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
