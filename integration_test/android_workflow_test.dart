import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/map_workspace.dart';
import 'package:photosim/ui/simulation_workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android map, GPU preview, gallery export and saved plans', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'photosim-android-',
    );
    final plans = PlanRepository(Directory('${directory.path}/plans'));
    final key = GlobalKey();
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
    }

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PhotoSimApp(
            plans: plans,
            rasterCache: RasterCache(Directory('${directory.path}/cache')),
          ),
        ),
      );
      await settle();
      final map = tester.widget<MapWorkspace>(find.byType(MapWorkspace));
      map.onChanged(
        map.state.copyWith(
          timestamp: DateTime.utc(2026, 6, 21, 19),
          renderQuality: RenderQuality.performance,
        ),
      );
      await settle();
      expect(
        Theme.of(tester.element(find.byType(MapWorkspace))).useMaterial3,
        isTrue,
      );
      await tester.tap(find.text('3D Preview').last);
      await settle();
      final export = find.widgetWithText(OutlinedButton, 'Export PNG');
      var ready = false;
      for (var i = 0; i < 180; i++) {
        if (export.evaluate().isNotEmpty &&
            tester.widget<OutlinedButton>(export).onPressed != null) {
          ready = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(
        find.text('3D rendering is unavailable. The map still works.'),
        findsNothing,
      );
      expect(
        ready,
        isTrue,
        reason: 'Real terrain and imagery must finish loading before export.',
      );
      expect(find.byKey(const ValueKey('photo-region')), findsOneWidget);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final photo = tester
            .getRect(find.byKey(const ValueKey('photo-region')))
            .deflate(24);
        final overlays = [
          for (final name in [
            'preview-actions',
            'preview-info',
            'photo-lens-label',
          ])
            tester.getRect(find.byKey(ValueKey(name))).inflate(8),
        ];
        final colors = <int>{};
        for (
          var y = photo.top.toInt() + 48;
          y < photo.bottom.toInt();
          y += 12
        ) {
          for (var x = photo.left.toInt(); x < photo.right.toInt(); x += 12) {
            if (overlays.any(
              (rect) => rect.contains(Offset(x.toDouble(), y.toDouble())),
            )) {
              continue;
            }
            colors.add(pixels.getUint32((y * image.width + x) * 4));
          }
        }
        expect(
          colors.length,
          greaterThan(20),
          reason: 'The actual GPU photo must contain terrain/sky pixels.',
        );
      } finally {
        image.dispose();
      }
      await tester.ensureVisible(export);
      await tester.tap(export);
      await settle();
      expect(find.text('Saved PNG to Pictures/PhotoSim.'), findsOneWidget);
      await expectLater(
        const MethodChannel('photosim/export').invokeMethod<String>('savePng', {
          'bytes': Uint8List.fromList([1]),
          'name': '../invalid.png',
        }),
        throwsA(isA<PlatformException>()),
      );
      final saved = tester
          .widget<SimulationWorkspace>(find.byType(SimulationWorkspace))
          .state;
      await tester.tap(find.byTooltip('Photography plans'));
      await settle();
      await tester.tap(find.text('Save plan'));
      await settle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        'Android composition',
      );
      await tester.tap(find.text('Save'));
      await settle();
      expect(
        (await plans.loadAll()).plans.single.state.timestamp,
        saved.timestamp,
      );
      tester
          .widget<SimulationWorkspace>(find.byType(SimulationWorkspace))
          .onChanged(saved.copyWith(focalLength: 85));
      await settle();
      await tester.tap(find.byTooltip('Photography plans'));
      await settle();
      await tester.tap(find.text('Open plan'));
      await settle();
      await tester.tap(find.text('Android composition'));
      await settle();
      await tester.tap(find.text('Discard changes'));
      await settle();
      final restored = tester
          .widget<MapWorkspace>(find.byType(MapWorkspace))
          .state;
      expect(restored.focalLength, saved.focalLength);
      expect(restored.timestamp, saved.timestamp);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await settle();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
