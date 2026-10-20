import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/render/photo_framing.dart';
import 'package:photosim/ui/photography_overlays.dart';

void main() {
  test('full-canvas projection preserves photo FOV for landscape/portrait and resized windows', () {
    for (final size in [
      const Size(1600, 800),
      const Size(600, 1000),
      const Size(400, 400),
    ]) {
      for (final portrait in [false, true]) {
        for (final focal in [8.0, 35.0, 600.0]) {
          final state = SimulationState(
            portrait: portrait,
            focalLength: focal,
            roll: 45,
          );
          final region = photoRegion(
            size,
            state.sensorWidth / state.sensorHeight,
          );
          expect(
            region.width / region.height,
            closeTo(state.sensorWidth / state.sensorHeight, 1e-12),
          );
          expect(
            (region.center - size.center(Offset.zero)).distance,
            lessThan(1e-9),
          );
          expect(region.left, greaterThan(0));
          expect(region.top, greaterThan(0));
          final vfov = previewVerticalFov(state, size);
          expect(vfov, greaterThan(state.verticalFov));
          expect(
            math.tan(vfov / 2) * region.height / size.height,
            closeTo(math.tan(state.verticalFov / 2), 1e-12),
          );
          expect(
            math.tan(vfov / 2) * region.width / size.height,
            closeTo(math.tan(state.horizontalFov / 2), 1e-12),
          );
        }
      }
    }
    expect(photoRegion(Size.zero, 1.5), Rect.zero);
  });

  testWidgets(
    'photo border and lens/DOF labels stay inside the frame, including clean view',
    (tester) async {
      final state = SimulationState(
        focalLength: 85,
        aperture: 1.4,
        depthOfField: true,
        portrait: true,
        showLevel: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotographyOverlays(state: state, showGuides: false),
          ),
        ),
      );
      final region = tester.getRect(find.byKey(const ValueKey('photo-region')));
      final label = tester.getRect(
        find.byKey(const ValueKey('photo-lens-label')),
      );
      expect(region.contains(label.topLeft), isTrue);
      expect(region.contains(label.bottomRight), isTrue);
      expect(region.width / region.height, closeTo(2 / 3, 1e-12));
      expect(find.text('85 mm · f/1.4\nDOF on'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.textContaining('Roll '), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
