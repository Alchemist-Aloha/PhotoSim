import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/cache_settings_panel.dart';
import 'package:photosim/ui/settings_page.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('NASA switch updates preferences at $size without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var state = SimulationState();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(state: state, onChanged: (next) => state = next),
        ),
      );
      final toggle = find.widgetWithText(
        SwitchListTile,
        'NASA terrain & imagery',
      );
      await tester.ensureVisible(toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(state.useNasaData, isFalse);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(state.useNasaData, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'app bar opens the settings page with rendering and storage controls',
    (tester) async {
      late Directory directory;
      late RasterCache cache;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'photosim-settings-page-',
        );
        cache = RasterCache(
          Directory('${directory.path}/cache'),
          settingsFile: File('${directory.path}/settings.json'),
        );
        await cache.initialize();
      });
      addTearDown(() => directory.delete(recursive: true));
      await tester.pumpWidget(PhotoSimApp(rasterCache: cache));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<RenderQuality>),
        findsOneWidget,
      );
      expect(
        find.byType(DropdownButtonFormField<Antialiasing>),
        findsOneWidget,
      );
      expect(find.byType(CacheSettingsPanel), findsOneWidget);
    },
  );
}
