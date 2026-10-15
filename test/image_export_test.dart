import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photosim/data/image_export.dart';

void main() {
  testWidgets(
    'PNG preserves dimensions and burns credits without changing the source',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xFF336699), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(300, 200);
        final bytes = await encodePreview(
          image,
          '© Test terrain · Test imagery',
        );
        final decoded = img.decodePng(bytes)!;
        expect(decoded.width, 300);
        expect(decoded.height, 200);
        expect(decoded.getPixel(100, 10).r, 51);
        expect(decoded.getPixel(0, 199).r, lessThan(51));
        image.dispose();
        picture.dispose();
      });
    },
  );

  test('exclusive staged PNG writes reject bad paths, preserve existing files and clean staging', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photosim-export-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    final path = '${directory.path}/photo.png';
    final written = await savePreview(path, bytes);
    expect(await written.readAsBytes(), bytes);
    await expectLater(
      savePreview(path, Uint8List.fromList([1])),
      throwsA(isA<FileSystemException>()),
    );
    expect(await written.readAsBytes(), bytes);
    await expectLater(
      savePreview('relative.png', bytes),
      throwsFormatException,
    );
    await expectLater(
      savePreview('${directory.path}/photo.jpg', bytes),
      throwsFormatException,
    );
    await expectLater(
      savePreview('${directory.path}/absent/photo.png', bytes),
      throwsA(isA<FileSystemException>()),
    );
    expect((await directory.list().toList()).map((file) => file.path), [path]);
  });
}
