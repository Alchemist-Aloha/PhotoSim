import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/ui/map_workspace.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1600, 960)]) {
    for (final failEntering in [true, false]) {
      testWidgets(
        'fullscreen rejection replaces undo at $size, entering=$failEntering',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          const window = MethodChannel('photosim/window');
          final calls = <bool>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            window,
            (call) async {
              expect(call.method, 'fullscreen');
              final entering = call.arguments as bool;
              calls.add(entering);
              if (entering == failEntering) {
                throw PlatformException(
                  code: 'denied',
                  message: 'Window manager rejected request',
                );
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(window, null),
          );
          await tester.pumpWidget(const PhotoSimApp());
          await tester.pumpAndSettle();
          final map = tester.widget<MapWorkspace>(find.byType(MapWorkspace));
          final moved = map.state.copyWith(
            latitude: map.state.latitude + 0.001,
            focalLength: 135,
          );
          map.onChanged(moved);
          map.onMoveCompleted!(map.state);
          await tester.pumpAndSettle();
          expect(find.text('Camera moved'), findsOneWidget);
          await tester.tap(find.text('3D Preview').last);
          await tester.pumpAndSettle();
          if (size.width < 600) {
            await tester.tap(find.byTooltip('More options'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Fullscreen preview'));
          } else {
            await tester.tap(find.byTooltip('Fullscreen preview'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(AppBar), findsNothing);
          expect(
            find.byTooltip('Exit fullscreen preview (Esc)'),
            findsOneWidget,
          );
          if (!failEntering) {
            expect(find.text('Camera moved'), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          }
          expect(
            find.text(
              'Window fullscreen unavailable: Window manager rejected request',
            ),
            findsOneWidget,
          );
          expect(find.text('Camera moved'), findsNothing);
          if (failEntering) {
            await tester.tap(find.byTooltip('Exit fullscreen preview (Esc)'));
            await tester.pumpAndSettle();
          }
          expect(find.byType(AppBar), findsOneWidget);
          expect(calls, [true, false]);
          await tester.tap(find.text('Map').last);
          await tester.pumpAndSettle();
          expect(
            tester.widget<MapWorkspace>(find.byType(MapWorkspace)).state,
            same(moved),
          );
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
