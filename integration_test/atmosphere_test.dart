import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/render/celestial_material.dart';
import 'package:photosim/render/atmosphere_sky.dart';
import 'package:photosim/ui/simulation_workspace.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'workspace_navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'sky lighting and aerial perspective affect GPU pixels without reloading terrain',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-atmosphere-',
      );
      final capture = GlobalKey();
      var state = SimulationState(
        timestamp: DateTime.utc(2026, 6, 21, 19),
        pitch: -15,
        height: 100,
        showCrosshair: false,
        showGrid: false,
        showLevel: false,
      );
      late StateSetter rebuild;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: capture,
                child: StatefulBuilder(
                  builder: (context, update) {
                    rebuild = update;
                    return SimulationWorkspace(
                      state: state,
                      cacheDirectory: directory,
                      onChanged: (next) => update(() => state = next),
                      onGroundElevationChanged: (location, elevation) {
                        if (state.location == location) {
                          update(
                            () => state = state.copyWith(
                              groundElevation: elevation,
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 240 && find.text('Imagery 9/9').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.text('Imagery 9/9'), findsOneWidget);
        final world = tester
            .widget<scene.SceneView>(find.byType(scene.SceneView))
            .scene!;
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
        Future<void> settleLighting() async {
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
        }

        Future<Uint8List> pixels([String? name]) async {
          debugPrint('Atmosphere capture: ${name ?? 'celestial probe'}');
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
            if (name != null && Platform.isLinux) {
              await Directory('build/validation').create(recursive: true);
              await File('build/validation/atmosphere-$name.png')
                  .writeAsBytes(bytes);
            }
            return bytes;
          } finally {
            image.dispose();
          }
        }

        await settleLighting();
        expect(world.skyEnvironment!.source, same(world.skybox!.source));
        expect(
          world.skyEnvironment!.refresh,
          scene.SkyEnvironmentRefresh.manual,
        );
        expect(world.skyEnvironment!.faceResolution, 64);
        expect(world.environment, isNotNull);
        expect(world.fog.enabled, isTrue);
        expect(world.fog.skyColorInfluence, 1);
        expect(
          world.fog.density,
          closeTo(scene.Fog.visibilityDensity(500000), 1e-12),
        );
        final hazed = await pixels('haze');
        world.fog.enabled = false;
        await pumpUntilRendered(tester, world);
        final unhazed = await pixels('no-haze');
        expect(hazed, isNot(orderedEquals(unhazed)));
        world.directionalLight!.intensity = 0;
        await pumpUntilRendered(tester, world);
        final skyLit = await pixels('sky-lit');
        world.environmentIntensity = 0;
        await pumpUntilRendered(tester, world);
        expect(await pixels('no-sky-light'), isNot(orderedEquals(skyLit)));
        world.environmentIntensity = 1;

        // Terrestrial range fog must not attenuate the Moon/stars at proxy mesh distances.
        final camera =
            tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
                as scene.PerspectiveCamera;
        final forward = (camera.target - camera.position).normalized();
        final probe = scene.Node(
          name: 'Celestial fog probe',
          mesh: scene.Mesh(
            scene.SphereGeometry(radius: 2),
            CelestialMaterial()..baseColorFactor = vm.Vector4(1, 0, 0, 1),
          ),
        )..position = camera.position + forward * 20;
        world.add(probe);
        await pumpUntilRendered(tester, world);
        final beforeFog = img.decodePng(await pixels())!;
        world.fog
          ..enabled = true
          ..density = 1;
        await pumpUntilRendered(tester, world);
        final afterFog = img.decodePng(await pixels())!;
        final viewRect = tester.getRect(find.byType(scene.SceneView));
        final origin = tester.getTopLeft(find.byKey(capture));
        final point = viewRect.center - origin;
        final a = beforeFog.getPixel(point.dx.round(), point.dy.round());
        final b = afterFog.getPixel(point.dx.round(), point.dy.round());
        expect(a.r, greaterThan(a.g + 20));
        expect(b.r, closeTo(a.r, 1));
        expect(b.g, closeTo(a.g, 1));
        expect(b.b, closeTo(a.b, 1));
        world.remove(probe);

        final source = world.skybox!.source as AtmosphereSky;
        final visibility = {
          for (final node in world.root.children) node: node.visible,
        };
        for (final node in visibility.keys) {
          node.visible = false;
        }
        final horizontal = vm.Vector3(forward.x, 0, forward.z).normalized();
        vm.Vector3 atAltitude(double altitude) =>
            horizontal * math.cos(altitude * math.pi / 180) +
            vm.Vector3(0, math.sin(altitude * math.pi / 180), 0);
        num skyBrightness(Uint8List bytes) {
          final image = img.decodePng(bytes)!;
          final point =
              Offset(
                viewRect.center.dx,
                viewRect.top + viewRect.height * 0.25,
              ) -
              origin;
          final pixel = image.getPixel(point.dx.round(), point.dy.round());
          return pixel.r + pixel.g + pixel.b;
        }

        final twilight = <int, num>{};
        source.lunarRadiance = 0;
        for (final altitude in [2, -2, -6, -18, -24]) {
          source.sunDirection = atAltitude(altitude.toDouble());
          world.skyEnvironment!.invalidate();
          await settleLighting();
          twilight[altitude] = skyBrightness(
            await pixels('twilight-$altitude'),
          );
        }
        expect(twilight[-2]!, greaterThan(twilight[-18]! + 3));
        expect(twilight[-6]!, lessThan(twilight[-2]!));
        final moonless = twilight[-24]!;
        source
          ..moonDirection = atAltitude(20)
          ..lunarRadiance = 0.2;
        world.skyEnvironment!.invalidate();
        await settleLighting();
        final moonlit = skyBrightness(await pixels('moonlit-sky'));
        expect(moonlit, greaterThan(moonless + 1));
        source.moonDirection = atAltitude(-60);
        world.skyEnvironment!.invalidate();
        await settleLighting();
        expect(
          skyBrightness(await pixels('moon-below-horizon')),
          closeTo(moonless, 1),
        );
        for (final entry in visibility.entries) {
          entry.key.visible = entry.value;
        }
        final oldEnvironment = world.environment;
        rebuild(
          () => state = state.copyWith(
            timestamp: state.timestamp.add(const Duration(hours: 6)),
          ),
        );
        await settleLighting();
        expect(world.environment, isNot(same(oldEnvironment)));
        await pixels('evening');
        rebuild(
          () => state = state.copyWith(
            weather: Weather.cloudy,
            weatherLightTransmission: 0.5,
            renderQuality: RenderQuality.performance,
          ),
        );
        await settleLighting();
        expect(world.skyEnvironment!.source, same(world.skybox!.source));
        expect(world.skyEnvironment!.source, isA<AtmosphereSky>());
        expect(
          world.root.children
              .singleWhere((node) => node.name == 'Clouds')
              .visible,
          isTrue,
        );
        expect(world.skyEnvironment!.faceResolution, 32);
        await pixels('overcast');
        rebuild(
          () => state = state.copyWith(
            weather: Weather.clear,
            relitImagery: false,
          ),
        );
        await settleLighting();
        expect(world.fog.enabled, isFalse);
        expect(world.fog.skyColorInfluence, 0);
        expect(
          (nodes.first.mesh!.primitives.single.material as scene.UnlitMaterial)
              .displayReferred,
          isTrue,
        );
        expect(counts(), initialCounts);
        for (var i = 0; i < nodes.length; i++) {
          expect(
            nodes[i].mesh!.primitives.single.geometry,
            same(geometries[i]),
          );
        }
        // High replaces geometry in-place and progressively refines nearby textures.
        int textureWidth(scene.Node node) =>
            (node.mesh!.primitives.single.material as scene.UnlitMaterial)
                .baseColorTexture!
                .sampledTexture!
                .width;
        rebuild(
          () => state = state.copyWith(renderQuality: RenderQuality.high),
        );
        for (var i = 0; i < 200; i++) {
          if (List.generate(
            nodes.length,
            (j) => !identical(
              nodes[j].mesh!.primitives.single.geometry,
              geometries[j],
            ),
          ).every((v) => v)) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        for (
          var i = 0;
          i < 240 && nodes.any((node) => textureWidth(node) != 1024);
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(world.renderScale, 1.25);
        expect(world.ambientOcclusion.enabled, isFalse); // Natural imagery.
        expect(nodes.map(textureWidth), everyElement(1024));
        for (var i = 0; i < nodes.length; i++) {
          expect(
            nodes[i].mesh!.primitives.single.geometry,
            isNot(same(geometries[i])),
          );
        }
        final originalMaterials = [
          for (final node in nodes) node.mesh!.primitives.single.material,
        ];
        final highGeometry = [
          for (final node in nodes) node.mesh!.primitives.single.geometry,
        ];
        rebuild(
          () => state = state.copyWith(renderQuality: RenderQuality.balanced),
        );
        for (var i = 0; i < 200; i++) {
          if (List.generate(
            nodes.length,
            (j) => !identical(
              nodes[j].mesh!.primitives.single.geometry,
              highGeometry[j],
            ),
          ).every((v) => v)) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        for (var i = 0; i < nodes.length; i++) {
          expect(
            nodes[i].mesh!.primitives.single.geometry,
            isNot(same(highGeometry[i])),
          );
          expect(
            nodes[i].mesh!.primitives.single.material,
            same(originalMaterials[i]),
          );
        }
        rebuild(
          () => state = state.copyWith(
            renderQuality: RenderQuality.high,
            relitImagery: true,
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await settleLighting();
        expect(
          world.directionalLight!.shadowFilter,
          scene.DirectionalShadowFilter.pcss,
        );
        expect(world.directionalLight!.contactShadows, isTrue);
        expect(world.directionalLight!.cascadeOverlap, 0.12);
        expect(world.ambientOcclusion.enabled, isTrue);
        expect(world.ambientOcclusion.bentNormals, isTrue);
        final shadowed = await pixels('high-terrain-shadows');
        world.ambientOcclusion.enabled = false;
        await pumpUntilRendered(tester, world);
        expect(
          await pixels('high-terrain-no-ao'),
          isNot(orderedEquals(shadowed)),
        );
        world.ambientOcclusion.enabled = true;
        world.directionalLight!
          ..castsShadow = false
          ..contactShadows = false;
        await pumpUntilRendered(tester, world);
        expect(
          await pixels('high-terrain-no-shadows'),
          isNot(orderedEquals(shadowed)),
        );
        // A camera-positioned point illuminates geometry, never the sky or Auto's meter.
        rebuild(
          () => state = state.copyWith(
            timestamp: DateTime.utc(2026, 6, 30, 7),
            pitch: 85,
            renderQuality: RenderQuality.balanced,
            exposureMode: ExposureMode.automatic,
            cameraLightStrength: 0,
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await settleLighting();
        final nightCamera =
            tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
                as scene.PerspectiveCamera;
        final nightForward = (nightCamera.target - nightCamera.position)
            .normalized();
        final fillProbe = scene.Node(
          name: 'Camera fill probe',
          mesh: scene.Mesh(
            scene.SphereGeometry(radius: 30),
            scene.PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.5, 0.5, 0.5, 1)
              ..metallicFactor = 0
              ..roughnessFactor = 1,
          ),
        )..position = nightCamera.position + nightForward * 300;
        world.add(fillProbe);
        for (var i = 0; i < 90; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        world.autoExposure
          ..speedUp = 0
          ..speedDown = 0;
        final torchOff = img.decodePng(await pixels('camera-light-off'))!;
        final rect = tester.getRect(find.byType(scene.SceneView));
        final skyPoint =
            Offset(
              rect.left + rect.width * 0.15,
              rect.top + rect.height * 0.2,
            ) -
            origin;
        final centerPoint = rect.center - origin;
        final skyOff = torchOff.getPixel(
          skyPoint.dx.round(),
          skyPoint.dy.round(),
        );
        final probeOff = torchOff.getPixel(
          centerPoint.dx.round(),
          centerPoint.dy.round(),
        );
        num? previousFill;
        for (final strength in [10.0, 50.0]) {
          rebuild(() => state = state.copyWith(cameraLightStrength: strength));
          await settleLighting();
          final image = img.decodePng(
            await pixels('camera-light-${strength.round()}'),
          )!;
          final skyOn = image.getPixel(
            skyPoint.dx.round(),
            skyPoint.dy.round(),
          );
          final probeOn = image.getPixel(
            centerPoint.dx.round(),
            centerPoint.dy.round(),
          );
          expect(world.autoExposure.enabled, isTrue);
          expect(world.autoExposure.speedUp, 0);
          expect(world.autoExposure.speedDown, 0);
          expect(skyOn.r, closeTo(skyOff.r, 1));
          expect(skyOn.g, closeTo(skyOff.g, 1));
          expect(skyOn.b, closeTo(skyOff.b, 1));
          final fill = probeOn.r + probeOn.g + probeOn.b;
          expect(fill, greaterThan(probeOff.r + probeOff.g + probeOff.b + 5));
          if (previousFill != null) expect(fill, greaterThan(previousFill));
          previousFill = fill;
        }
        final lightNode = world.root.children.singleWhere(
          (n) => n.name == 'Camera light',
        );
        expect(lightNode.position, nightCamera.position);
        expect(
          lightNode
              .getComponent<scene.PointLightComponent>()!
              .light
              .castsShadow,
          isFalse,
        );
        rebuild(() => state = state.copyWith(cameraLightStrength: 0));
        await settleLighting();
        expect(
          lightNode.getComponent<scene.PointLightComponent>()!.light.intensity,
          0,
        );
        expect(world.autoExposure.speedDown, 1);
        world.remove(fillProbe);
        rebuild(
          () => state = state.copyWith(
            pitch: -15,
            exposureMode: ExposureMode.enhanced,
          ),
        );
        await settleLighting();
        final darkTerrain = await pixels('night-terrain-light-off');
        rebuild(() => state = state.copyWith(cameraLightStrength: 20));
        await settleLighting();
        expect(
          await pixels('night-terrain-light-on'),
          isNot(orderedEquals(darkTerrain)),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await directory.delete(recursive: true);
      }
    },
  );
}
