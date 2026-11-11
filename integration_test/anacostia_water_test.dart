// Inspect the private scene state without adding production test-only APIs.
// ignore_for_file: avoid_dynamic_calls

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/water/water_repository.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import '../test/terrain_fixture.dart';
import '../test/water_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Anacostia riverbanks render over real DC terrain', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'photosim-anacostia-',
    );
    final banks = await File('test/fixtures/anacostia_water.pbf').readAsBytes();
    final dem = await File('test/fixtures/anacostia_terrain.png').readAsBytes();
    final flat = terrainFixture(height: 0);
    final mask = waterFixture(wet: (_, _) => false);
    final land = image.Image(width: 256, height: 256, numChannels: 3);
    image.fill(land, color: image.ColorRgb8(104, 135, 72));
    final landBytes = image.encodePng(land);
    const liveRivers = bool.fromEnvironment('PHOTOSIM_LIVE_RIVERS');
    final liveClient = http.Client();
    final queries = <Uri>[];
    final cache = RasterCache(Directory('${directory.path}/cache'));
    final client = MockClient((request) async {
      if (request.url.host == 'tiles.openfreemap.org') {
        queries.add(request.url);
        if (liveRivers) {
          final response = await liveClient.get(
            request.url,
            headers: request.headers,
          );
          debugPrint(
            'Anacostia live river: HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes',
          );
          return response;
        }
        if (request.url.path == '/planet') {
          return http.Response(
            await File('test/fixtures/openfreemap_tilejson.json')
                .readAsString(),
            200,
          );
        }
        return http.Response.bytes(
          request.url.path.endsWith('/10/293/391.pbf')
              ? banks
              : riverFixture(riverTile(request.url), []),
          200,
        );
      }
      if (request.url.host == 'data-gis.unep-wcmc.org') {
        return http.Response('{"type":"FeatureCollection","features":[]}', 200);
      }
      if (request.url.queryParameters['LAYERS'] == waterProvider.layer) {
        return http.Response.bytes(mask, 200);
      }
      if (request.url.host == 'tiles.mapterhorn.com') {
        return http.Response('unavailable', 404);
      }
      if (request.url.host == 's3.amazonaws.com') {
        // Real central terrain; out-of-view neighboring tiles are synthetic.
        return http.Response.bytes(
          request.url.path.endsWith('/13/2344/3134.png') ? dem : flat,
          200,
        );
      }
      return http.Response.bytes(landBytes, 200);
    });
    var state = SimulationState(
      useNasaData: false,
      latitude: 38.8805,
      longitude: -76.971,
      fixedElevation: 600,
      pitch: -80,
      focalLength: 24,
      timestamp: DateTime.utc(2026, 6, 21, 16),
    );
    final capture = GlobalKey();
    late StateSetter rebuild;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      client.close();
      liveClient.close();
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SimulationWorkspace(
                  state: state,
                  httpClient: client,
                  rasterCache: cache,
                  onChanged: (next) => setState(() => state = next),
                  onGroundElevationChanged: (location, height) {
                    if (location == state.location) {
                      setState(
                        () => state = state.copyWith(groundElevation: height),
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
    final dynamic workspace = tester.state(find.byType(SimulationWorkspace));
    Future<void> ready({required bool water}) async {
      for (var i = 0; i < (liveRivers ? 1800 : 400); i++) {
        if (liveRivers) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 100));
        if (workspace.loading == false &&
            workspace.imageryLoading == false &&
            (water
                ? (liveRivers
                      ? workspace.waterNodes.containsKey(
                              workspace.cameraGroundTile?.key,
                            ) ==
                            true
                      : workspace.waterNodes.length == 9)
                : workspace.waterNodes.isEmpty == true)) {
          return;
        }
      }
      fail(
        'Anacostia did not finish: ${workspace.waterFailure} / ${workspace.error}',
      );
    }

    Future<int> bluePixels(String name) async {
      await tester.pump(const Duration(seconds: 1));
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = await boundary.toImage();
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      await Directory('build/validation').create(recursive: true);
      await File('build/validation/anacostia-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      final decoded = image.decodePng(bytes.buffer.asUint8List())!;
      var blue = 0;
      for (var y = decoded.height ~/ 5; y < decoded.height * 4 ~/ 5; y++) {
        for (var x = decoded.width ~/ 5; x < decoded.width * 4 ~/ 5; x++) {
          final p = decoded.getPixel(x, y);
          if (p.b > p.r + 15 && p.b > p.g) blue++;
        }
      }
      return blue;
    }

    await ready(water: true);
    expect(workspace.error, isNull);
    expect(workspace.waterFailure, isNull);
    expect(queries, isNotEmpty);
    expect(queries.first.path, '/planet');
    expect(
      queries.firstWhere((uri) => uri.path.endsWith('.pbf')).path,
      endsWith('/10/293/391.pbf'),
      reason: 'Load the camera atlas before the western neighbor atlas',
    );
    expect(queries.every((uri) => uri.host == 'tiles.openfreemap.org'), isTrue);
    final wet = await bluePixels('water');
    expect(
      wet,
      greaterThan(5000),
      reason: 'Real Anacostia banks must produce visible reflective water over the real DEM',
    );
    rebuild(() => state = state.copyWith(showWater: false));
    await ready(water: false);
    final dry = await bluePixels('terrain');
    expect(
      dry,
      lessThan(wet * 0.05),
      reason: 'The blue river must come from the water layer, not the imagery or sky',
    );
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
