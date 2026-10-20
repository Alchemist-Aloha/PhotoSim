import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'workspace_navigation.dart';

import 'package:photosim/app/app.dart';
import 'package:photosim/core/camera_movement.dart';
import 'package:photosim/core/geo.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/map_workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Linux WASD follows terrain, reuses meshes and stops for dialogs/map',
    (tester) async {
      await tester.pumpWidget(const PhotoSimApp());
      await tester.pump(const Duration(seconds: 2));
      CameraInspector inspector() =>
          tester.widget<CameraInspector>(find.byType(CameraInspector));
      SimulationState state() => inspector().state;
      inspector().onChanged(
        state().copyWith(
          height: 100,
          pitch: -40,
          timestamp: DateTime.utc(2026, 6, 21, 19),
        ),
      );
      await tester.pump();
      await openWorkspace(tester, '3D Preview');
      Future<void> waitForImagery() async {
        for (var i = 0; i < 240; i++) {
          if (find.text('Imagery 9/9').evaluate().isNotEmpty &&
              tester
                      .widget<OutlinedButton>(
                        find.widgetWithText(OutlinedButton, 'Export PNG'),
                      )
                      .onPressed !=
                  null) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.text('Imagery 9/9'), findsOneWidget);
      }

      await waitForImagery();
      final original = state();
      final world = tester
          .widget<scene.SceneView>(find.byType(scene.SceneView))
          .scene!;
      final nodes = world.root.children
          .where((node) => RegExp(r'^\d+-\d+-\d+$').hasMatch(node.name))
          .toList();
      final geometry = [
        for (final node in nodes) node.mesh!.primitives.single.geometry,
      ];
      List<String?> counts() => tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where((text) => text?.contains(' downloaded') ?? false)
          .toList();
      final beforeCounts = counts();
      await tester.tap(find.byType(scene.SceneView));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pump(const Duration(milliseconds: 500));
      final moved = state();
      expect(moved.latitude, greaterThan(original.latitude));
      expect(
        (bearing(original.location, moved.location) + 180) % 360 - 180,
        closeTo(0, 0.1),
      );
      expect(moved.fixedElevation, isNull);
      expect(moved.cameraElevation, moved.groundElevation! + original.height);
      expect(moved.height, original.height);
      expect(moved.timestamp, original.timestamp);
      expect(moved.pitch, original.pitch);
      final camera =
          tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
              as scene.PerspectiveCamera;
      expect(camera.position.y, closeTo(moved.cameraElevation!, 0.001));
      expect(counts(), beforeCounts);
      expect(nodes.first.localTransform.getTranslation().z, greaterThan(0));
      for (var i = 0; i < nodes.length; i++) {
        expect(nodes[i].mesh!.primitives.single.geometry, same(geometry[i]));
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Export PNG'));
      for (var i = 0; i < 40 && find.text('Save PNG').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      final stopped = state().location;
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        '/tmp/wasd-focus-test.png',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      expect(state().location, stopped);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      await openWorkspace(tester, 'Map');
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<MapWorkspace>(find.byType(MapWorkspace)).state.location,
        stopped,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      expect(state().location, stopped);
      await openWorkspace(tester, '3D Preview');
      await waitForImagery();
      expect(
        state().cameraElevation,
        state().groundElevation! + original.height,
      );
      // Crossing a tile must sample the new ground before enabling terrain-follow navigation.
      inspector().onChanged(moveCamera(state(), 5000, 0));
      await tester.pump();
      await waitForImagery();
      expect(state().fixedElevation, isNull);
      expect(
        state().cameraElevation,
        state().groundElevation! + original.height,
      );
      final rebased =
          tester.widget<scene.SceneView>(find.byType(scene.SceneView)).camera!
              as scene.PerspectiveCamera;
      expect(rebased.position.y, closeTo(state().cameraElevation!, 0.001));
      inspector().onChanged(state().copyWith(clearFixedElevation: true));
      await tester.pump();
      expect(
        state().cameraElevation,
        state().groundElevation! + state().height,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
