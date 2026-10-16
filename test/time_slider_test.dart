import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/time_slider.dart';

void main() {
  testWidgets('slider spans 00:00–24:00 local and preserves camera state', (
    tester,
  ) async {
    var state = SimulationState(
      timestamp: DateTime.utc(2026, 6, 21, 19, 0, 37),
      groundElevation: 1200,
      relitImagery: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TimeSlider(
              state: state,
              onChanged: (next) => setState(() => state = next),
            ),
          ),
        ),
      ),
    );
    Slider slider() =>
        tester.widget<Slider>(find.byKey(const ValueKey('local-day-slider')));
    expect(slider().value, 720);
    expect(slider().max, 1440);
    expect(slider().semanticFormatterCallback!(59.6), '01:00 PDT');
    expect(find.text('24:00 local'), findsOneWidget);
    for (final value in [0.0, 59.6, 720.0, 1440.0]) {
      slider().onChanged!(value);
      await tester.pump();
      expect(
        state.timestamp,
        DateTime.utc(2026, 6, 21, 7).add(Duration(minutes: value.round())),
      );
      expect(state.timestamp.isUtc, isTrue);
      expect(state.groundElevation, 1200);
      expect(state.relitImagery, isTrue);
      expect(state.latitude, 37.744);
    }
    expect(slider().value, 0); // 24:00 is the next local day's midnight.
  });

  testWidgets('a drag stays on one local day at 24:00, including DST', (
    tester,
  ) async {
    var state = SimulationState(timestamp: DateTime.utc(2026, 3, 8, 19));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TimeSlider(
              state: state,
              onChanged: (next) => setState(() => state = next),
            ),
          ),
        ),
      ),
    );
    Slider slider() =>
        tester.widget<Slider>(find.byKey(const ValueKey('local-day-slider')));
    expect(slider().max, 1380);
    expect(slider().semanticFormatterCallback!(120), '03:00 PDT');
    slider().onChangeStart!(slider().value);
    slider().onChanged!(1380);
    await tester.pump();
    expect(state.timestamp, DateTime.utc(2026, 3, 9, 7));
    expect(slider().value, 1380);
    slider().onChanged!(1380);
    await tester.pump();
    expect(state.timestamp, DateTime.utc(2026, 3, 9, 7));
    slider().onChangeEnd!(1380);
    await tester.pump();
    expect(slider().value, 0);
    expect(slider().max, 1440);
  });

  testWidgets(
    'local slider disables outside supported rules, never falls back to UTC',
    (tester) async {
      for (final timestamp in [
        DateTime.utc(1900),
        DateTime.utc(2100, 12, 31, 23, 59),
        DateTime.utc(1970, 1, 1, 1),
      ]) {
        var changed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TimeSlider(
                state: SimulationState(timestamp: timestamp),
                onChanged: (_) => changed = true,
              ),
            ),
          ),
        );
        final slider = tester.widget<Slider>(
          find.byKey(const ValueKey('local-day-slider')),
        );
        expect(slider.onChanged, isNull);
        expect(slider.semanticFormatterCallback!(0), contains('unavailable'));
        expect(changed, isFalse);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
