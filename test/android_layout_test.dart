import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/map_workspace.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(800, 1280),
    const Size(1280, 800),
    const Size(360, 640),
  ]) {
    testWidgets('Material 3 Android layout ${size.width}x${size.height}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const PhotoSimApp());
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(MapWorkspace)));
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(
        find.byType(NavigationBar),
        size.width < 600 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(NavigationRail),
        size.width >= 600 ? findsOneWidget : findsNothing,
      );
      final viewport = tester.getRect(find.byType(MapWorkspace));
      expect(viewport.height, greaterThan(140));
      expect(viewport.width, greaterThan(200));
      await tester.tap(
        find.byTooltip(
          size.width < 1000 ? 'Camera controls' : 'Toggle camera inspector',
        ),
      );
      await tester.pumpAndSettle();
      if (size.width >= 1000) {
        expect(find.byType(CameraInspector), findsNothing);
        await tester.tap(find.byTooltip('Toggle camera inspector'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(CameraInspector), findsOneWidget);
      final original = tester
          .widget<CameraInspector>(find.byType(CameraInspector))
          .state;
      await tester.tap(find.text('APS-C'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CameraInspector>(find.byType(CameraInspector))
            .state
            .sensor,
        Sensor.apsC,
      );
      if (size.width < 1000) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(CameraInspector), findsNothing);
      }
      await tester.tap(find.text('3D Preview').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export').last);
      await tester.pumpAndSettle();
      expect(find.byType(CameraInspector), findsNothing);
      expect(find.byTooltip('Play time'), findsNothing);
      await tester.tap(find.text('Map').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(
          size.width < 1000 ? 'Camera controls' : 'Toggle camera inspector',
        ),
      );
      await tester.pumpAndSettle();
      if (size.width >= 1000) {
        await tester.tap(find.byTooltip('Toggle camera inspector'));
        await tester.pumpAndSettle();
      }
      final restored = tester
          .widget<CameraInspector>(find.byType(CameraInspector))
          .state;
      expect(restored.sensor, Sensor.apsC);
      expect(restored.location, original.location);
      expect(restored.timestamp, original.timestamp);
      if (size.width < 1000) {
        await tester.tap(find.byTooltip('Close camera controls'));
        await tester.pumpAndSettle();
      }
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(MapWorkspace))).brightness,
        Brightness.dark,
      );
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'phone dialogs, timeline and fullscreen respect Back and window resizing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PhotoSimApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand timeline details'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Playback speed'), findsOneWidget);
      await tester.tap(find.byTooltip('Collapse timeline details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(find.text('Edit local shooting time'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('3D Preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fullscreen preview'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(CameraInspector), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(CameraInspector), findsNothing);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );
}
