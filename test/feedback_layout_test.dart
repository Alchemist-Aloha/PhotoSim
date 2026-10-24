import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/ui/map_workspace.dart';
import 'package:photosim/ui/time_slider.dart';
import 'package:photosim/ui/workspace_feedback.dart';
import 'package:photosim/ui/camera_inspector.dart';

void main() {
  for (final (size, expanded, textScale) in [
    (const Size(390, 844), false, 1.3),
    (const Size(390, 844), true, 1.3),
    (const Size(844, 390), false, 1.3),
    (const Size(844, 390), true, 1.3),
    (const Size(1280, 800), false, 1.3),
    (const Size(844, 390), true, 2.0),
    (const Size(1280, 800), false, 2.0),
  ]) {
    testWidgets(
      'feedback reserves space at $size, expanded=$expanded, text=$textScale',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(
          left: 24,
          right: 24,
          bottom: 24,
        );
        tester.view.viewPadding = const FakeViewPadding(
          left: 24,
          right: 24,
          bottom: 24,
        );
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(const PhotoSimApp());
        await tester.pumpAndSettle();
        MapWorkspace map() =>
            tester.widget<MapWorkspace>(find.byType(MapWorkspace));
        map().onChanged(
          map().state.copyWith(timestamp: DateTime.utc(2026, 6, 21, 19)),
        );
        await tester.pumpAndSettle();
        if (expanded) {
          await tester.tap(find.byTooltip('Expand timeline details'));
          await tester.pumpAndSettle();
        }
        final viewportSize = tester.getSize(find.byType(MapWorkspace));
        const message =
            'Could not save or open the plan. Your current composition is unchanged. Check storage space and folder permissions, then try again.';
        ScaffoldMessenger.of(tester.element(find.byType(MapWorkspace)))
            .showWorkspaceFeedback(
              const SnackBar(
                content: Text(message),
                duration: Duration(seconds: 10),
              ),
            );
        await tester.pumpAndSettle();
        final snack = tester.getRect(find.byType(MaterialBanner));
        final slider = tester.getRect(find.byType(TimeSlider));
        final play = find.byTooltip(
          'Play time (5 simulated minutes per second)',
        );
        expect(slider.overlaps(snack), isFalse);
        expect(tester.getRect(play).overlaps(snack), isFalse);
        expect(slider.left, greaterThanOrEqualTo(24));
        expect(slider.right, lessThanOrEqualTo(size.width - 24));
        final available = tester.getSize(find.byType(MapWorkspace));
        expect(available.width, viewportSize.width);
        expect(available.height, greaterThan(0));
        expect(available.height, lessThan(viewportSize.height));
        expect(
          tester.getRect(find.byType(MapWorkspace)).top,
          greaterThanOrEqualTo(snack.bottom),
        );
        if (size.width >= 1000) {
          expect(
            tester.getRect(find.byType(CameraInspector)).overlaps(snack),
            isFalse,
          );
        }
        if (size.width < 600) {
          expect(
            tester.getRect(find.byType(NavigationBar)).overlaps(snack),
            isFalse,
          );
        }
        final before = map().state;
        await tester.ensureVisible(
          find.byKey(const ValueKey('local-day-slider')),
        );
        await tester.pumpAndSettle();
        final track = tester.getRect(
          find.byKey(const ValueKey('local-day-slider')),
        );
        await tester.tapAt(
          Offset(track.left + track.width * 0.75, track.center.dy),
        );
        await tester.pumpAndSettle();
        expect(map().state.timestamp, isNot(before.timestamp));
        expect(map().state.location, before.location);
        expect(map().state.focalLength, before.focalLength);
        expect(find.text(message), findsOneWidget);
        await tester.ensureVisible(play);
        await tester.pumpAndSettle();
        await tester.tap(play);
        await tester.pump();
        expect(find.byTooltip('Pause time'), findsOneWidget);
        await tester.tap(find.byTooltip('Pause time'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
        expect(tester.takeException(), isNull);
      },
    );
  }
}
