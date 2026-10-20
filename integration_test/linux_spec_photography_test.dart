import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'workspace_navigation.dart';

import 'package:photosim/app/app.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/photography_overlays.dart';
import 'package:photosim/render/photo_framing.dart';
import 'package:photosim/ui/simulation_workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Linux exposure, portrait/roll, clean preview and export', (
    tester,
  ) async {
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: capture, child: const PhotoSimApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    const window = MethodChannel('photosim/window');
    await expectLater(
      window.invokeMethod<void>('fullscreen', 'invalid'),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      window.invokeMethod<void>('unknown'),
      throwsA(isA<MissingPluginException>()),
    );
    CameraInspector inspector() =>
        tester.widget<CameraInspector>(find.byType(CameraInspector));
    SimulationState state() => inspector().state;
    void change(SimulationState next) => inspector().onChanged(next);
    change(
      state().copyWith(
        height: 100,
        pitch: -40,
        exposureMode: ExposureMode.manual,
        timestamp: DateTime.utc(2026, 6, 21, 19),
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
    expect(find.text('Imagery 9/9'), findsOneWidget);
    final world = tester
        .widget<scene.SceneView>(find.byType(scene.SceneView))
        .scene!;
    final geometry = {
      for (final node in world.root.children.where(
        (node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name),
      ))
        node: node.mesh!.primitives.single.geometry,
    };
    List<String?> counts() => tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .where((text) => text?.contains(' downloaded') ?? false)
        .toList();
    final oldCounts = counts();
    Future<double> brightness() async {
      final image =
          await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final raw = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final rect = tester.getRect(find.byType(scene.SceneView)).deflate(30);
        var total = 0.0, count = 0;
        for (var y = rect.top.toInt(); y < rect.bottom; y += 5) {
          for (var x = rect.left.toInt(); x < rect.right; x += 5) {
            final offset = (y * image.width + x) * 4;
            total +=
                raw.getUint8(offset) +
                raw.getUint8(offset + 1) +
                raw.getUint8(offset + 2);
            count++;
          }
        }
        return total / count;
      } finally {
        image.dispose();
      }
    }

    final neutral = await brightness();
    expect(world.exposure, 1);
    change(state().copyWith(iso: 200));
    await tester.pump(const Duration(seconds: 1));
    expect(world.exposure, 2);
    expect(await brightness(), greaterThan(neutral * 1.05));
    change(state().copyWith(iso: 50));
    await tester.pump(const Duration(seconds: 1));
    expect(await brightness(), lessThan(neutral * 0.95));
    change(
      state().copyWith(
        iso: 100,
        whiteBalance: 9000,
        portrait: true,
        roll: 30,
        showGrid: true,
        showLevel: true,
        showCrosshair: false,
        showConstellations: true,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(world.postProcess.colorGrading.enabled, isTrue);
    expect(world.postProcess.colorGrading.temperature, greaterThan(0));
    final camera =
        tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
            as scene.PerspectiveCamera;
    expect(camera.up.x, closeTo(state().cameraFrame.up.x, 1e-6));
    expect(camera.up.y, closeTo(state().cameraFrame.up.y, 1e-6));
    final size = tester.getSize(find.byType(scene.SceneView));
    final region = photoRegion(
      size,
      state().sensorWidth / state().sensorHeight,
    );
    expect(camera.fovRadiansY, previewVerticalFov(state(), size));
    expect(world.depthOfField.sensorHeight, 0.036);
    expect(world.depthOfField.blurScale, region.height / size.height);
    expect(size.width, tester.getSize(find.byType(SimulationWorkspace)).width);
    final frame = tester.getRect(find.byKey(const ValueKey('photo-region')));
    expect(frame.width / frame.height, closeTo(2 / 3, 1e-8));
    expect(
      (frame.center - tester.getCenter(find.byType(scene.SceneView))).distance,
      lessThan(1e-6),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('photo-lens-label'))).data,
      contains('${state().focalLength.toStringAsFixed(0)} mm'),
    );
    expect(find.byType(PhotographyOverlays), findsOneWidget);
    change(state().copyWith(exposureMode: ExposureMode.automatic));
    await tester.pump(const Duration(seconds: 1));
    expect(world.autoExposure.enabled, isTrue);
    expect(tester.takeException(), isNull);
    change(state().copyWith(exposureMode: ExposureMode.manual));
    await tester.pump(const Duration(milliseconds: 500));
    final beforeFullscreen = state();
    await tester.tap(find.byTooltip('Fullscreen preview'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(CameraInspector), findsNothing);
    expect(
      tester
          .widget<PhotographyOverlays>(find.byType(PhotographyOverlays))
          .showGuides,
      isFalse,
    );
    expect(find.byKey(const ValueKey('photo-region')), findsOneWidget);
    expect(
      tester.getSize(find.byType(scene.SceneView)),
      tester.getSize(find.byType(Scaffold)),
    );
    expect(find.textContaining('UTC-driven'), findsNothing);
    expect(
      tester.widget<scene.SceneView>(find.byType(scene.SceneView)).scene,
      same(world),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppBar), findsOneWidget);
    expect(state().roll, beforeFullscreen.roll);
    expect(state().portrait, isTrue);
    expect(state().showConstellations, isTrue);
    expect(state().timestamp, beforeFullscreen.timestamp);
    expect(counts(), oldCounts);
    for (final entry in geometry.entries) {
      expect(entry.key.mesh!.primitives.single.geometry, same(entry.value));
    }
    final directory = await Directory.systemTemp.createTemp(
      'photosim-portrait-export-',
    );
    addTearDown(() => directory.delete(recursive: true));
    await tester.tap(find.text('Export PNG'));
    for (var i = 0; i < 40 && find.text('Save PNG').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final path = '${directory.path}/portrait.png';
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      path,
    );
    await tester.tap(find.text('Save PNG'));
    for (var i = 0; i < 40 && !await File(path).exists(); i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final bytes = await File(path).readAsBytes();
    final image = img.decodePng(bytes)!;
    expect(image.width / image.height, closeTo(2 / 3, 0.005));
    await Directory('build/validation').create(recursive: true);
    await File('build/validation/linux-portrait-exposure-export.png')
        .writeAsBytes(bytes);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
