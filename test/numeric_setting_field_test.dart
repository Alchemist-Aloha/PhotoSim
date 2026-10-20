import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/ui/numeric_setting_field.dart';

void main() {
  testWidgets(
    'drafts validate before applying and survive unrelated rebuilds',
    (tester) async {
      var value = 24.0;
      var calls = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return NumericSettingField(
                  label: 'Focal length',
                  value: value,
                  min: 8,
                  max: 600,
                  suffix: 'mm',
                  onChanged: (next) => setState(() {
                    value = next;
                    calls++;
                  }),
                );
              },
            ),
          ),
        ),
      );
      for (final invalid in [
        '',
        'NaN',
        'Infinity',
        '1e999',
        '7.9',
        '600.1',
        'lens',
      ]) {
        await tester.enterText(find.byType(TextFormField), invalid);
        await tester.tap(find.byTooltip('Apply focal length'));
        await tester.pump();
        expect(value, 24);
        expect(calls, 0);
        expect(find.text('Enter a number from 8.0 to 600.0'), findsOneWidget);
      }
      await tester.enterText(find.byType(TextFormField), '35.5');
      rebuild(() {});
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '35.5',
      );
      expect(calls, 0);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, 35.5);
      expect(calls, 1);
      rebuild(() => value = 85);
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '85.0',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
