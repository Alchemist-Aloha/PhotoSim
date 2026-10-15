import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/terrain_range_dialog.dart';

void main() {
  testWidgets('range controls apply drafts together with accessible labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    ({int rings, double forwardKm, double renderKm})? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected =
                    await showDialog<
                      ({int rings, double forwardKm, double renderKm})
                    >(
                      context: context,
                      builder: (_) =>
                          TerrainRangeDialog(state: SimulationState()),
                    );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Forward fetch distance')),
      findsWidgets,
    );
    for (final entry in [
      ('terrain-rings', 3.0),
      ('terrain-forward', 20.0),
      ('terrain-render', 10.0),
    ]) {
      tester.widget<Slider>(find.byKey(ValueKey(entry.$1))).onChanged!(
        entry.$2,
      );
      await tester.pump();
    }
    expect(selected, isNull);
    expect(find.text('Forward fetch distance: 20 km'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(selected, (rings: 3, forwardKm: 20.0, renderKm: 10.0));
    semantics.dispose();
  });

  testWidgets('cancel discards edits and controls fit a small viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Object? selected = 'not closed';
    final state = SimulationState(
      terrainRings: 2,
      terrainForwardKm: 15,
      terrainRenderKm: 8,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showDialog<Object>(
                  context: context,
                  builder: (_) => TerrainRangeDialog(state: state),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('terrain-forward')))
          .value,
      15,
    );
    tester
        .widget<Slider>(find.byKey(const ValueKey('terrain-rings')))
        .onChanged!(3);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(state.terrainRings, 2);
    expect(tester.takeException(), isNull);
  });
}
