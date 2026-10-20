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
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/rain_overlay.dart';
import 'package:photosim/render/photo_framing.dart';
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
      var state = SimulationState(
        height: 100,
        pitch: -40,
        relitImagery: false,
        timestamp: DateTime.utc(2026, 6, 21, 19),
      );
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
                  void change(SimulationState next) =>
                      update(() => state = next);
                  return Row(
                    children: [
                      Expanded(
                        child: SimulationWorkspace(
                          state: state,
                          onPausePlayback: () => paused = true,
                          onChanged: change,
                          onGroundElevationChanged: (location, elevation) {
                            if (state.location == location) {
                              update(
                                () => state = state.copyWith(
                                  groundElevation: elevation,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 310,
                        child: CameraInspector(state: state, onChanged: change),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
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
      final inspectorScroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('scene-inspector')),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> toggleSection(String title) async {
        await tester.scrollUntilVisible(
          find.text(title),
          300,
          scrollable: inspectorScroll,
        );
        await tester.tap(find.text(title));
        await tester.pump(const Duration(milliseconds: 400));
      }

      final toolbar = find.byType(SimulationWorkspace);
      expect(
        find.descendant(
          of: toolbar,
          matching: find.byType(DropdownButton<Weather>),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: toolbar,
          matching: find.byType(DropdownButton<RenderQuality>),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: toolbar,
          matching: find.text('Approximate relighting'),
        ),
        findsNothing,
      );
      await toggleSection('Weather');
      final weatherImages = <Weather, Uint8List>{};
      for (final weather in Weather.values) {
        tester
            .widget<DropdownButtonFormField<Weather>>(
              find.byType(DropdownButtonFormField<Weather>),
            )
            .onChanged!(weather);
        await tester.pump(const Duration(seconds: 1));
        expect(state.weather, weather);
        expect(world.fog.enabled, weather != Weather.clear);
        expect(world.skyEnvironment!.source, same(world.skybox!.source));
        expect(world.fog.skyColorInfluence, 0);
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
      for (final edit in [
        ('Visibility', 6.0),
        ('Light transmission', 80.0),
        ('Rain intensity', 25.0),
      ]) {
        tester.widget<Slider>(find.byKey(ValueKey(edit.$1))).onChanged!(
          edit.$2,
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        world.fog.density,
        closeTo(scene.Fog.visibilityDensity(6000), 1e-12),
      );
      expect(
        tester.widget<RainOverlay>(find.byType(RainOverlay)).intensity,
        0.25,
      );
      expect(state.weatherLightTransmission, 0.8);
      expect(counts(), initialCounts);
      await File('build/validation/linux-weather-panel.png')
          .writeAsBytes(await pixels());
      tester
          .widget<DropdownButtonFormField<Weather>>(
            find.byType(DropdownButtonFormField<Weather>),
          )
          .onChanged!(Weather.clear);
      await tester.pump(const Duration(milliseconds: 400));
      tester
          .widget<Slider>(find.byKey(const ValueKey('Visibility')))
          .onChanged!(2);
      await tester.pump(const Duration(milliseconds: 400));
      expect(world.fog.enabled, isTrue);
      expect(
        (nodes.first.mesh!.primitives.single.material as scene.UnlitMaterial)
            .displayReferred,
        isFalse,
      );
      tester
          .widget<Slider>(find.byKey(const ValueKey('Visibility')))
          .onChanged!(100);
      await tester.pump(const Duration(milliseconds: 400));
      expect(world.fog.enabled, isFalse);
      await toggleSection('Weather');
      await toggleSection('Rendering');
      for (final quality in RenderQuality.values) {
        tester
            .widget<DropdownButtonFormField<RenderQuality>>(
              find.byType(DropdownButtonFormField<RenderQuality>),
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
        expect(
          nodes[i].mesh!.primitives.single.geometry,
          isNot(same(geometries[i])),
        );
      }
      await tester.tap(find.text('Export PNG'));
      for (var i = 0; i < 30 && find.text('Save PNG').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(paused, isTrue);
      final path = '${directory.path}/rain.png';
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        path,
      );
      await tester.tap(find.text('Save PNG'));
      for (var i = 0; i < 30 && !await File(path).exists(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(await File(path).exists(), isTrue);
      final exported = img.decodePng(await File(path).readAsBytes())!;
      final size = tester.getSize(find.byType(scene.SceneView));
      expect(exported.width / exported.height, closeTo(1.5, 0.01));
      final region = photoRegion(size, state.sensorWidth / state.sensorHeight);
      expect(exported.width, closeTo(region.width, 1));
      expect(exported.height, closeTo(region.height, 1));
      await File('build/validation/linux-export.png')
          .writeAsBytes(await File(path).readAsBytes());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
