import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';

Future<void> openWorkspace(WidgetTester tester, String destination) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text(destination),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Pumps until the scene has completed [frames] more frames.
///
/// A pump schedules a frame, but the preview's own ticker decides whether to
/// draw it. A capture taken straight after a single `pump(duration)` can
/// therefore still show the previous scene state, and any idle frame-rate cap
/// makes that timing-dependent. Wait on the render counter instead of guessing
/// a duration: the count only advances when a frame actually rendered.
Future<void> pumpUntilRendered(
  WidgetTester tester,
  scene.Scene world, {
  int frames = 1,
  Duration step = const Duration(milliseconds: 20),
  int maxPumps = 200,
}) async {
  final target = world.renderStats.frameCount + frames;
  for (var i = 0; i < maxPumps; i++) {
    if (world.renderStats.frameCount >= target) return;
    await tester.pump(step);
  }
}
