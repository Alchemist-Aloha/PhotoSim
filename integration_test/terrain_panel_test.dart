import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/app_session.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('terrain range inspector and live requested map envelope', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp(
      'photosim-terrain-panel-',
    );
    final capture = GlobalKey();
    Future<void> screenshot(String name) async {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Platform.isAndroid
          ? await getTemporaryDirectory()
          : Directory('build/validation');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    final state = SimulationState(timestamp: DateTime.utc(2026, 6, 15, 22));
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: PhotoSimApp(
            rasterCache: RasterCache(Directory('${dir.path}/cache')),
            initialSession: AppSession(
              state: state,
              cleanComposition: SavedPlan('Composition', state).encode(),
              mapZoom: Platform.isAndroid ? 10.5 : 11,
              expandedSections: {'Optics': false, 'Terrain range': true},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final drawer = find.byTooltip('Camera controls').evaluate().isNotEmpty;
      if (drawer) {
        await tester.tap(find.byTooltip('Camera controls'));
        await tester.pump(const Duration(milliseconds: 350));
      }
      await tester.ensureVisible(find.byKey(const ValueKey('terrain-forward')));
      tester
          .widget<Slider>(find.byKey(const ValueKey('terrain-forward')))
          .onChanged!(12);
      await tester.pump(const Duration(milliseconds: 200));
      final circle = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .last;
      expect(circle.pattern.segments, [8, 6]);
      expect(circle.points, hasLength(97));
      expect(find.text('Forward fetch distance: 12 km'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(find.text('Terrain range'));
      await tester.pump(const Duration(milliseconds: 200));
      await screenshot(
        Platform.isLinux ? 'linux-terrain-panel-map' : 'terrain-panel',
      );
      if (drawer) {
        await tester.tap(find.byTooltip('Close camera controls'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byTooltip('Close camera controls'), findsNothing);
      }
      if (Platform.isAndroid) {
        await screenshot('terrain-map');
        // Allow the host test harness to collect app-private captures before uninstall.
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      await dir.delete(recursive: true);
    }
  });
}
