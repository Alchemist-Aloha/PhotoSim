import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/map_workspace.dart';
import 'package:photosim/ui/numeric_setting_field.dart';

void main() {
  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PhotoSimApp());
    await tester.pumpAndSettle();
  }

  CameraInspector inspector(WidgetTester tester) =>
      tester.widget(find.byType(CameraInspector));

  Finder field(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is NumericSettingField && widget.label == label,
    ),
    matching: find.byType(TextFormField),
  );

  testWidgets('exact coordinates validate, recenter, and undo only the move', (
    tester,
  ) async {
    await openApp(tester);
    final original = inspector(tester).state;
    await tester.tap(find.text('Optics'));
    await tester.tap(find.text('Position & orientation'));
    await tester.pumpAndSettle();
    for (final input in [
      ('Latitude', '90'),
      ('Latitude', 'NaN'),
      ('Longitude', '181'),
    ]) {
      await tester.ensureVisible(field(input.$1));
      await tester.enterText(field(input.$1), input.$2);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(inspector(tester).state.location, original.location);
      expect(find.textContaining('Enter a number from'), findsOneWidget);
      await tester.enterText(
        field(input.$1),
        input.$1 == 'Latitude'
            ? '${original.latitude}'
            : '${original.longitude}',
      );
    }
    await tester.enterText(field('Latitude'), ' 35.68 ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(inspector(tester).state.latitude, 35.68);
    expect(inspector(tester).state.longitude, original.longitude);
    expect(inspector(tester).state.groundElevation, isNull);
    expect(
      tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .camera
          .center
          .latitude,
      35.68,
    );
    inspector(tester)
        .onChanged(inspector(tester).state.copyWith(focalLength: 85));
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(inspector(tester).state.location, original.location);
    expect(inspector(tester).state.focalLength, 85);
    expect(inspector(tester).state.timestamp, original.timestamp);
    await tester.ensureVisible(field('Longitude'));
    await tester.enterText(field('Longitude'), '-180');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(inspector(tester).state.longitude, -180);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'map tap and whole marker drag each offer one undo, including cancel',
    (tester) async {
      await openApp(tester);
      await tester.tap(find.byTooltip('Hide map guidance'));
      await tester.pumpAndSettle();
      final original = inspector(tester).state;
      final mapRect = tester.getRect(find.byType(FlutterMap));
      await tester.tapAt(mapRect.center + const Offset(180, 120));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(inspector(tester).state.location, isNot(original.location));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(inspector(tester).state.location, original.location);
      final marker = find.bySemanticsLabel('Camera location. Drag to move.');
      for (final cancel in [true, false]) {
        final gesture = await tester.startGesture(tester.getCenter(marker));
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump();
        expect(find.text('Undo'), findsNothing);
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(inspector(tester).state.location, isNot(original.location));
        expect(find.text('Undo'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(inspector(tester).state.location, original.location);
      }
      final direction = find.bySemanticsLabel(
        'Camera direction. Drag to rotate.',
      );
      await tester.drag(direction, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(inspector(tester).state.azimuth, isNot(original.azimuth));
      expect(inspector(tester).state.location, original.location);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(inspector(tester).state.azimuth, original.azimuth);
      expect(inspector(tester).state.location, original.location);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dismissed map guidance stays dismissed across workspaces and can reopen',
    (tester) async {
      await openApp(tester);
      await tester.tap(find.byTooltip('Hide map guidance'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MapWorkspace>(find.byType(MapWorkspace)).guideDismissed,
        isTrue,
      );
      expect(find.textContaining('requested terrain extent'), findsOneWidget);
      await tester.tap(find.text('3D Preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide map guidance'), findsNothing);
      await tester.tap(find.byTooltip('Map guide'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show map guidance'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide map guidance'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
