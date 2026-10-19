import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  for (final size in [const Size(310, 800), const Size(390, 700)]) {
    testWidgets('inspector terrain controls apply live and fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      var state = SimulationState(
        timestamp: DateTime.utc(2026, 6, 15),
        focalLength: 85,
      );
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return CameraInspector(
                  state: state,
                  onChanged: (next) => setState(() => state = next),
                );
              },
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Terrain range'));
      await tester.tap(find.text('Terrain range'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('terrain-forward')));
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
      expect(state.terrainRings, 3);
      expect(state.terrainForwardKm, 20);
      expect(state.terrainRenderKm, 10);
      expect(state.focalLength, 85);
      final later = state.timestamp.add(const Duration(hours: 1));
      rebuild(() => state = state.copyWith(timestamp: later));
      await tester.pump();
      tester
          .widget<Slider>(find.byKey(const ValueKey('terrain-render')))
          .onChanged!(2);
      await tester.pump();
      expect(state.timestamp, later);
      expect(find.textContaining('requested extent'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
