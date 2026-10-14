import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  testWidgets(
    'shared UTC timeline updates astronomy and respects date bounds',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PhotoSimApp());
      final sunBefore = tester
          .widget<Text>(find.textContaining('Sun az '))
          .data;
      final moonBefore = tester
          .widget<Text>(find.textContaining('Moon az '))
          .data;
      await tester.tap(find.byTooltip('Later by one hour'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.textContaining('Sun az ')).data,
        isNot(sunBefore),
      );
      expect(
        tester.widget<Text>(find.textContaining('Moon az ')).data,
        isNot(moonBefore),
      );
      for (final entry in [
        (DateTime.utc(1900), 'Earlier by one hour'),
        (DateTime.utc(2100, 12, 31, 23), 'Later by one hour'),
      ]) {
        final inspector = tester.widget<CameraInspector>(
          find.byType(CameraInspector),
        );
        inspector.onChanged(inspector.state.copyWith(timestamp: entry.$1));
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == entry.$2,
                ),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inspector edits the shared sensor and optical model', (
    tester,
  ) async {
    var state = SimulationState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CameraInspector(
              state: state,
              onChanged: (next) => setState(() => state = next),
            ),
          ),
        ),
      ),
    );
    final initialFov = state.horizontalFov;
    await tester.tap(find.text('Full-frame'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APS-C').last);
    await tester.pumpAndSettle();
    expect(state.sensor, Sensor.apsC);
    expect(state.horizontalFov, lessThan(initialFov));
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pump();
    expect(state.focalLength, greaterThan(24));
    expect(tester.takeException(), isNull);
  });
}
