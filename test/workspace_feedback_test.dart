import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/ui/workspace_feedback.dart';

Future<ScaffoldMessengerState> host(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: Text('Workspace'))),
  );
  return ScaffoldMessenger.of(tester.element(find.text('Workspace')));
}

void main() {
  testWidgets('transient feedback expires after its visible duration', (
    tester,
  ) async {
    final messenger = await host(tester);
    messenger.showWorkspaceFeedback(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
  });

  for (final accessible in [false, true]) {
    testWidgets(
      'native persistence and actions survive with accessibility=$accessible',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(accessibleNavigation: accessible);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final messenger = await host(tester);
        var actions = 0;
        messenger.showWorkspaceFeedback(
          SnackBar(
            content: const Text('Camera moved'),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                actions++;
                messenger.showWorkspaceFeedback(
                  const SnackBar(content: Text('Undone')),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 11));
        expect(find.text('Camera moved'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(actions, 1);
        expect(find.text('Camera moved'), findsNothing);
        expect(find.text('Undone'), findsOneWidget);
        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        expect(find.byType(MaterialBanner), findsNothing);
      },
    );
  }

  testWidgets('preemption cancels expiry before advancing the native queue', (
    tester,
  ) async {
    final messenger = await host(tester);
    messenger.showWorkspaceFeedback(
      const SnackBar(content: Text('Old'), duration: Duration(seconds: 1)),
    );
    messenger.showWorkspaceFeedback(
      const SnackBar(content: Text('Next'), persist: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsNothing);
    messenger.removeWorkspaceFeedback();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('disposing feedback cancels its timer', (tester) async {
    final messenger = await host(tester);
    messenger.showWorkspaceFeedback(const SnackBar(content: Text('Pending')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long selectable feedback scrolls without swallowing the workspace',
    (tester) async {
      tester.view.physicalSize = const Size(390, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messenger = await host(tester);
      messenger.showWorkspaceFeedback(
        SnackBar(content: SelectableText('Long path / ' * 200)),
      );
      await tester.pumpAndSettle();
      final banner = tester.getRect(find.byType(MaterialBanner));
      expect(banner.height, lessThan(195));
      expect(
        tester.getRect(find.text('Workspace')).top,
        greaterThanOrEqualTo(banner.bottom),
      );
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
