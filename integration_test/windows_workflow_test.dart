import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import '../test/imagery_fixture.dart';
import '../test/terrain_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows GPU preview, fullscreen and PNG export', (tester) async {
    final temporary = await Directory.systemTemp.createTemp(
      'photosim-windows-',
    );
    final output = Directory('build/validation/windows').absolute;
    await output.create(recursive: true);
    final terrain = terrainWebpFixture();
    final preview = imageryFixture(256), detail = imageryFixture(1024);
    final client = MockClient((request) async {
      if (request.url.host == 'tiles.mapterhorn.com') {
        return http.Response.bytes(terrain, 200);
      }
      return http.Response.bytes(
        request.url.queryParameters['size'] == '256,256' ? preview : detail,
        200,
      );
    });
    const channel = MethodChannel('photosim/window');
    addTearDown(() async {
      await channel.invokeMethod<void>('fullscreen', false);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      client.close();
      await temporary.delete(recursive: true);
    });
    expect((await getApplicationSupportDirectory()).isAbsolute, isTrue);
    expect((await getDownloadsDirectory())?.isAbsolute, isTrue);

    var state = SimulationState(
      timestamp: DateTime.utc(2026, 6, 21, 19),
      height: 100,
      pitch: -15,
      cloudAmount: 0,
    );
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: captureKey,
            child: StatefulBuilder(
              builder: (context, update) => SimulationWorkspace(
                state: state,
                cacheDirectory: temporary,
                httpClient: client,
                onChanged: (next) => update(() => state = next),
                onGroundElevationChanged: (location, elevation) {
                  if (state.location == location) {
                    update(
                      () => state = state.copyWith(groundElevation: elevation),
                    );
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 600 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(ready(), isTrue);
    }

    await until(() {
      final views = find.byType(scene.SceneView);
      if (views.evaluate().isEmpty) return false;
      final world = tester.widget<scene.SceneView>(views).scene!;
      return world.renderStats.frameCount > 0 &&
          find.text('Imagery 9/9').evaluate().isNotEmpty;
    });
    expect(state.groundElevation, isNotNull);
    expect(tester.takeException(), isNull);

    final original = tester.view.physicalSize;
    await channel.invokeMethod<void>('fullscreen', true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.view.physicalSize.width * tester.view.physicalSize.height,
      greaterThan(original.width * original.height),
    );
    await channel.invokeMethod<void>('fullscreen', false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.view.physicalSize, original);

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await boundary.toImage();
    try {
      final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
      await File('${output.path}/workflow.png').writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      screenshot.dispose();
    }

    final photo = File('${output.path}/photo.png');
    if (await photo.exists()) await photo.delete();
    final export = find.widgetWithText(OutlinedButton, 'Export PNG');
    await until(() => tester.widget<OutlinedButton>(export).onPressed != null);
    await tester.tap(export);
    await until(() => find.text('Save PNG').evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextFormField), photo.path);
    await tester.tap(find.text('Save PNG'));
    for (var i = 0; i < 300; i++) {
      if (await photo.exists() && await photo.length() > 0) break;
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await photo.exists(), isTrue);
    final decoded = image.decodePng(await photo.readAsBytes());
    expect(decoded, isNotNull);
    expect(decoded!.width, greaterThan(100));
    expect(decoded.height, greaterThan(100));
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
