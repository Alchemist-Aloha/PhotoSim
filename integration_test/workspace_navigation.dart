import 'package:flutter/material.dart';
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
