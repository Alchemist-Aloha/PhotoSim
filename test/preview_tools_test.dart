import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/ui/preview_tools.dart';

void main() {
  testWidgets('short-window preview menu keeps every action reachable', (
    tester,
  ) async {
    var guides = 0, exports = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewTools(
            onConstellations: () => guides++,
            onExport: () => exports++,
            constellations: true,
          ),
        ),
      ),
    );
    for (final label in ['Constellations', 'Export PNG']) {
      await tester.tap(find.byTooltip('Preview tools'));
      await tester.pumpAndSettle();
      await tester.tap(
        label == 'Constellations'
            ? find.widgetWithText(CheckedPopupMenuItem<int>, label)
            : find.widgetWithText(PopupMenuItem<int>, label),
      );
      await tester.pumpAndSettle();
    }
    expect([guides, exports], [1, 1]);
    expect(find.text('Terrain range'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewTools(onConstellations: () {}, constellations: false),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Preview tools'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<int>>(
            find.widgetWithText(PopupMenuItem<int>, 'Export PNG'),
          )
          .enabled,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
