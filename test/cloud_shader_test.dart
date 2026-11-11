import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('visible and reflected clouds use the same procedural shader', () {
    String cloudBlock(String path) {
      final source = File(path).readAsStringSync();
      return source.substring(
        source.indexOf('  // Ported from ref/'),
        source.indexOf('  // End shared reference cloud block.'),
      );
    }

    expect(
      cloudBlock('assets/atmosphere/water.fmat'),
      cloudBlock('assets/atmosphere/clouds.fmat'),
    );
  });
}
