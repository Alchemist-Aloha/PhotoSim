import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photosim/render/moon.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled NASA Moon map has real surface contrast and provenance',
    () async {
      final data = await rootBundle.load('assets/moon/lroc_color_2k.jpg');
      final image = img.decodeJpg(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      )!;
      expect(image.width, 2048);
      expect(image.height, 1024);
      var low = 255.0, high = 0.0;
      for (var y = 256; y < 768; y += 8) {
        for (var x = 512; x < 1536; x += 8) {
          final value = image.getPixel(x, y).r.toDouble();
          low = math.min(low, value);
          high = math.max(high, value);
        }
      }
      expect(high - low, greaterThan(60));
      final provenance = jsonDecode(
        await rootBundle.loadString('assets/moon/provenance.json'),
      ) as Map<String, dynamic>;
      expect(provenance['width'], image.width);
      expect(provenance['height'], image.height);
      expect(provenance['source'], startsWith('https://svs.gsfc.nasa.gov/'));
      expect(
        await rootBundle.loadString('assets/moon/LICENSE.txt'),
        contains('NASA does not endorse PhotoSim'),
      );
    },
  );
  test('near-side prime meridian and north remain correctly oriented without reflections', () {
    for (final direction in [
      Vector3(0, 0, -1),
      Vector3(1, 1, 0).normalized(),
      Vector3(0, 1, 0),
      Vector3(-1, -0.5, 1).normalized(),
    ]) {
      final pole = Vector3(0.1, 0.9, 0.3).normalized();
      final orientation = moonTextureOrientation(direction, pole);
      final front = -direction;
      final projectedNorth = (pole - front * pole.dot(front)).normalized();
      expect(
        (orientation.transformed(Vector3(-1, 0, 0)) - front).length,
        lessThan(1e-12),
      );
      expect(
        (orientation.transformed(Vector3(0, 1, 0)) - projectedNorth).length,
        lessThan(1e-12),
      );
      expect(orientation.determinant(), closeTo(1, 1e-12));
      final light = Vector3(0.3, 0.4, 0.5).normalized();
      final normal = Vector3(0.7, -0.1, 0.2).normalized();
      final localLight = orientation.transposed().transformed(light);
      expect(
        normal.dot(localLight),
        closeTo(orientation.transformed(normal).dot(light), 1e-12),
      );
    }
  });
  test('pole-aligned views have a stable orientation; invalid vectors are rejected', () {
    final pole = Vector3(0, 1, 0);
    expect(moonTextureOrientation(pole, pole).determinant(), closeTo(1, 1e-12));
    expect(
      () => moonTextureOrientation(Vector3.zero(), pole),
      throwsArgumentError,
    );
    expect(
      () => moonTextureOrientation(pole, Vector3(double.nan, 0, 0)),
      throwsArgumentError,
    );
  });
}
