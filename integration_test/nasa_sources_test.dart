import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/simulation_workspace.dart';

import '../test/imagery_fixture.dart';
import '../test/terrain_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'NASA preference reloads resident terrain and imagery in both directions',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'photosim-nasa-live-',
      );
      final cache = RasterCache(
        Directory('${directory.path}/cache'),
        settingsFile: File('${directory.path}/settings.json'),
      );
      final bil = ByteData(256 * 256 * 2);
      for (var i = 0; i < 256 * 256; i++) {
        bil.setInt16(i * 2, 1450, Endian.little);
      }
      final requests = <Uri>[];
      final preview = imageryFixture(256), detail = imageryFixture(1024);
      final client = MockClient((request) async {
        final uri = request.url;
        requests.add(uri);
        if (uri.host == 'tiles.mapterhorn.com') {
          return http.Response('missing', 404);
        }
        if (uri.host == 'worldwind26.arc.nasa.gov') {
          return http.Response.bytes(bil.buffer.asUint8List(), 200);
        }
        if (uri.host == 's3.amazonaws.com') {
          return http.Response.bytes(terrainFixture(), 200);
        }
        return http.Response.bytes(
          uri.queryParameters['WIDTH'] == '1024' ? detail : preview,
          200,
        );
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        client.close();
        await directory.delete(recursive: true);
      });
      var state = SimulationState(
        useNasaData: false,
        latitude: -33.86,
        longitude: 151.21,
        height: 100,
        pitch: -40,
      );
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SimulationWorkspace(
                  state: state,
                  httpClient: client,
                  rasterCache: cache,
                  onChanged: (next) => setState(() => state = next),
                  onGroundElevationChanged: (location, elevation) {
                    if (state.location == location) {
                      setState(
                        () =>
                            state = state.copyWith(groundElevation: elevation),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ),
      );
      Future<void> waitForImages() async {
        for (var i = 0; i < 300; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Terrain 9/9').evaluate().isNotEmpty &&
              find.text('Imagery 9/9').evaluate().isNotEmpty) {
            return;
          }
        }
        fail('Terrain and imagery did not finish loading');
      }

      await waitForImages();
      expect(state.groundElevation, closeTo(1234.5, 0.01));
      expect(requests.any((uri) => uri.host.contains('nasa.gov')), isFalse);
      rebuild(() => state = state.copyWith(useNasaData: true));
      await waitForImages();
      expect(state.groundElevation, closeTo(1450, 0.01));
      expect(
        find.textContaining('ASTER GDEM is a product of METI and NASA'),
        findsOneWidget,
      );
      expect(find.textContaining('NASA EOSDIS GIBS'), findsOneWidget);
      expect(
        requests.any((uri) => uri.host == 'gibs.earthdata.nasa.gov'),
        isTrue,
      );
      final nasaRequests = requests
          .where((uri) => uri.host.contains('nasa.gov'))
          .length;
      rebuild(() => state = state.copyWith(useNasaData: false));
      await waitForImages();
      expect(state.groundElevation, closeTo(1234.5, 0.01));
      expect(
        find.textContaining('ASTER GDEM is a product of METI and NASA'),
        findsNothing,
      );
      expect(find.textContaining('NASA EOSDIS GIBS'), findsNothing);
      expect(
        requests.where((uri) => uri.host.contains('nasa.gov')).length,
        nasaRequests,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
