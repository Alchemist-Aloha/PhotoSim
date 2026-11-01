import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/cache_settings_panel.dart';
import 'package:photosim/ui/settings_page.dart';

void main() {
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
