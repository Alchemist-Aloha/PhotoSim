import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';
import 'package:photosim/ui/rain_overlay.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Linux quality, manual weather, aperture DOF and exclusive PNG export',
    (tester) async {
      final capture = GlobalKey();
      final directory = await Directory.systemTemp.createTemp(
        'photosim-photo-native-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var state = SimulationState(height: 100, pitch: -40);
      late StateSetter rebuild;
      var paused = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: StatefulBuilder(
                builder: (context, update) {
                  rebuild = update;
                  return SimulationWorkspace(
                    state: state,
                    onPausePlayback: () => paused = true,
                    onChanged: (next) => update(() => state = next),
                  );
                },
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 240; i++) {
        if (find.text('Imagery · 9/9 textures').evaluate().isNotEmpty &&
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
      expect(find.text('Imagery · 9/9 textures'), findsOneWidget);
      final view = tester.widget<scene.SceneView>(find.byType(scene.SceneView));
      final world = view.scene!;
      final nodes = world.root.children
          .where((node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name))
          .toList();
      final geometries = [
        for (final node in nodes) node.mesh!.primitives.single.geometry,
      ];
      List<String?> counts() => tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where((text) => text?.contains(' downloaded') ?? false)
          .toList();
      final initialCounts = counts();
      Future<Uint8List> pixels() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      }

      await Directory('build/validation').create(recursive: true);
      final weatherImages = <Weather, Uint8List>{};
      for (final weather in Weather.values) {
        tester
            .widget<DropdownButton<Weather>>(
              find.byType(DropdownButton<Weather>),
            )
            .onChanged!(weather);
        await tester.pump(const Duration(seconds: 1));
        expect(state.weather, weather);
        expect(world.fog.enabled, weather != Weather.clear);
        expect(
          find.byType(RainOverlay),
          weather == Weather.rain ? findsOneWidget : findsNothing,
        );
        weatherImages[weather] = await pixels();
        await File('build/validation/linux-weather-${weather.name}.png')
            .writeAsBytes(weatherImages[weather]!);
        expect(tester.takeException(), isNull);
      }
      expect(
        weatherImages[Weather.fog],
        isNot(orderedEquals(weatherImages[Weather.clear]!)),
      );
      for (final quality in RenderQuality.values) {
        tester
            .widget<DropdownButton<RenderQuality>>(
              find.byType(DropdownButton<RenderQuality>),
            )
            .onChanged!(quality);
        await tester.pump(const Duration(seconds: 1));
        expect(
          world.renderScale,
          quality == RenderQuality.performance ? 0.7 : 1,
        );
        expect(
          world.directionalLight!.shadowMapResolution,
          quality == RenderQuality.performance
              ? 1024
              : quality == RenderQuality.balanced
              ? 2048
              : 4096,
        );
        expect(tester.takeException(), isNull);
      }
      rebuild(
        () => state = state.copyWith(
          weather: Weather.clear,
          renderQuality: RenderQuality.balanced,
          depthOfField: true,
          aperture: 1.4,
          focalLength: 200,
          focusDistance: 10,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(world.depthOfField.enabled, isTrue);
      expect(world.depthOfField.fStop, 1.4);
      expect(world.depthOfField.focalLength, 0.2);
      expect(world.depthOfField.sensorHeight, 0.024);
      expect(world.depthOfField.focusDistance, 10);
      expect(
        (nodes.first.mesh!.primitives.single.material as scene.UnlitMaterial)
            .displayReferred,
        isFalse,
      );

      // Controlled out-of-focus target: changing aperture must change GPU pixels, not just state.
      final camera =
          tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
              as scene.PerspectiveCamera;
      final target =
          scene.Node(
              name: 'DOF target',
              mesh: scene.Mesh(
                scene.SphereGeometry(radius: 0.07),
                scene.UnlitMaterial(),
              ),
            )
            ..position =
                camera.position +
                (camera.target - camera.position).normalized() * 20;
      world.add(target);
      void isolateTarget() {
        for (final node in world.root.children) {
          node.visible = node == target;
        }
        world.skybox = scene.Skybox(
          scene.GradientSkySource(
            zenithColor: vm.Vector3.zero(),
            horizonColor: vm.Vector3.zero(),
            groundColor: vm.Vector3.zero(),
            sunColor: vm.Vector3.zero(),
          ),
        );
      }

      isolateTarget();
      await tester.pump(const Duration(seconds: 1));
      final open = img.decodePng(await pixels())!;
      await File('build/validation/linux-dof-open.png')
          .writeAsBytes(img.encodePng(open));
      rebuild(() => state = state.copyWith(aperture: 22));
      await tester.pump(const Duration(seconds: 1));
      isolateTarget();
      await tester.pump(const Duration(seconds: 1));
      final stopped = img.decodePng(await pixels())!;
      await File('build/validation/linux-dof-stopped.png')
          .writeAsBytes(img.encodePng(stopped));
      final center = tester.getCenter(find.byType(scene.SceneView));
      var difference = 0;
      for (var y = center.dy.toInt() - 40; y < center.dy.toInt() + 40; y++) {
        for (var x = center.dx.toInt() - 40; x < center.dx.toInt() + 40; x++) {
          difference +=
              (open.getPixel(x, y).r.toInt() - stopped.getPixel(x, y).r.toInt())
                  .abs();
        }
      }
      expect(difference, greaterThan(1000));
      expect(world.depthOfField.fStop, 22);
      world.remove(target);
      for (final node in world.root.children) {
        node.visible = true;
      }
      rebuild(
        () => state = state.copyWith(
          weather: Weather.rain,
          focalLength: 24,
          aperture: 8,
          focusDistance: 1000,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(counts(), initialCounts);
      for (var i = 0; i < nodes.length; i++) {
        expect(nodes[i].mesh!.primitives.single.geometry, same(geometries[i]));
      }
      await tester.tap(find.text('Export PNG'));
      for (var i = 0; i < 30 && find.text('Save PNG').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(paused, isTrue);
      final path = '${directory.path}/rain.png';
      await tester.enterText(find.byType(TextFormField), path);
      await tester.tap(find.text('Save PNG'));
      for (var i = 0; i < 30 && !await File(path).exists(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(await File(path).exists(), isTrue);
      final exported = img.decodePng(await File(path).readAsBytes())!;
      final size = tester.getSize(find.byType(scene.SceneView));
      expect(exported.width / exported.height, closeTo(1.5, 0.01));
      expect(exported.width, closeTo(size.width, 1));
      expect(exported.height, closeTo(size.height, 1));
      await File('build/validation/linux-export.png')
          .writeAsBytes(await File(path).readAsBytes());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
