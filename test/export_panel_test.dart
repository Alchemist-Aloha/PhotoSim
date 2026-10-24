import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/ui/export_panel.dart';

import 'imagery_fixture.dart';

void main() {
  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('export preview, editable prompt and copy at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prompt = TextEditingController(text: 'Captured metadata');
      addTearDown(prompt.dispose);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var renders = 0, saves = 0;
      Widget panel({
        bool stale = false,
        bool busy = false,
        bool empty = false,
      }) => MaterialApp(
        home: Scaffold(
          body: ExportPanel(
            bytes: empty ? null : imageryFixture(32),
            prompt: prompt,
            busy: busy,
            ready: !empty,
            stale: stale,
            width: 32,
            height: 32,
            onRender: () => renders++,
            onSave: () => saves++,
          ),
        ),
      );
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('export-image')), findsOneWidget);
      await tester.ensureVisible(find.text('Re-render preview & reset prompt'));
      await tester.tap(find.text('Re-render preview & reset prompt'));
      expect(renders, 1);
      await tester.ensureVisible(find.text('Save PNG'));
      await tester.tap(find.text('Save PNG'));
      expect(saves, 1);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'My edited prompt');
      await tester.ensureVisible(find.text('Copy prompt'));
      await tester.tap(find.text('Copy prompt'));
      await tester.pumpAndSettle();
      expect(copied, 'My edited prompt');
      expect(find.text('Prompt copied.'), findsOneWidget);
      for (final variant in [
        panel(stale: true),
        panel(busy: true),
        panel(empty: true),
      ]) {
        await tester.pumpWidget(variant);
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save PNG'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Copy prompt'),
              )
              .onPressed,
          tester.widget<ExportPanel>(find.byType(ExportPanel)).stale
              ? isNotNull
              : isNull,
        );
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
