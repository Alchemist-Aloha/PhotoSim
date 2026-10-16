import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openWorkspace(WidgetTester tester, String destination) async {
  await tester.tap(find.byTooltip('Open navigation'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationDrawer),
      matching: find.text(destination),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
