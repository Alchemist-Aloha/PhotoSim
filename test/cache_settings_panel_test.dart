import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/ui/cache_settings_panel.dart';

void main() {
  testWidgets(
    'cache settings validate, apply, persist and preserve drafts on rebuild',
    (tester) async {
      late Directory directory;
      late File settings;
      late RasterCache cache;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'photosim-cache-panel-',
        );
        settings = File('${directory.path}/settings.json');
        cache = RasterCache(
          Directory('${directory.path}/cache'),
          settingsFile: settings,
        );
        await cache.initialize();
      });
      addTearDown(() => directory.delete(recursive: true));
      Widget panel() => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ExpansionTile(
                key: const PageStorageKey('test-storage'),
                title: const Text('Storage'),
                initiallyExpanded: true,
                children: [CacheSettingsPanel(cache: cache)],
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(panel());
      await tester.tap(find.text('Storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Storage'));
      await tester.pumpAndSettle();
      final field = find.byKey(const PageStorageKey('cache-limit'));
      for (final value in ['-1', 'abc', '1.5', '65537']) {
        await tester.enterText(field, value);
        await tester.tap(find.text('Apply cache limit'));
        await tester.pump();
        expect(find.text('Enter 0–65536 whole MiB'), findsOneWidget);
        expect(cache.limitMiB, 512);
      }
      await tester.enterText(field, '2048');
      await tester.pumpWidget(panel());
      expect(tester.widget<TextFormField>(field).controller!.text, '2048');
      await tester.tap(find.text('Apply cache limit'));
      for (var i = 0; i < 100 && cache.limitMiB != 2048; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pump();
      expect(cache.limitMiB, 2048);
      expect(find.text('Cache limit saved.'), findsOneWidget);
      final reopened = RasterCache(cache.directory, settingsFile: settings);
      await tester.runAsync(reopened.initialize);
      expect(reopened.limitMiB, 2048);
      await tester.enterText(field, '0');
      await tester.tap(find.text('Apply cache limit'));
      for (var i = 0; i < 100 && cache.limitMiB != 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(cache.limitMiB, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
