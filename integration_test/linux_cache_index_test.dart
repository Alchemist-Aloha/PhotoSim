import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photosim/data/raster_cache.dart';

/// Guards startup cost: the disk index gates the first terrain/imagery load.
///
/// A previous implementation awaited `list`/`stat`/`exists` per directory entry.
/// On the real engine each of those costs an event-loop round trip, so a 1 625
/// tile cache took 13 342 ms to index and the 3D preview stayed empty for ~14 s
/// even though every raster was already on disk. The same work measured 67 ms
/// as one synchronous pass, so this asserts real-engine wall time rather than
/// the host-VM timing used by `flutter test`, which does not reproduce the cost.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('indexing a warm multi-thousand tile cache stays fast', (
    tester,
  ) async {
    const tilesPerFolder = 220;
    final root = await Directory.systemTemp.createTemp('photosim-cache-index-');
    addTearDown(() => root.delete(recursive: true));
    final raster = Uint8List(1024);
    for (final folder in [
      'mapterhorn-v1',
      'terrain-v1',
      'naip-natural-256-v1',
    ]) {
      final directory = Directory('${root.path}/$folder');
      await directory.create(recursive: true);
      for (var index = 0; index < tilesPerFolder; index++) {
        final file = File(
          '${directory.path}/13-${index ~/ 100}-${index % 100}.png',
        );
        await file.writeAsBytes(raster);
        await File('${file.path}.json').writeAsString('{"tile":true}');
      }
    }
    final total = 3 * tilesPerFolder;
    final budget = RasterCache(Directory(root.path));
    await tester.runAsync(() async {
      final watch = Stopwatch()..start();
      await budget.initialize();
      watch.stop();
      debugPrint(
        'CACHE_INDEX_NATIVE: $total tiles in ${watch.elapsedMilliseconds} ms',
      );
      // Loose bound: the old per-entry await path needed ~3.6 ms per entry here
      // (>2 s for this fixture), while one synchronous pass stays well under it.
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
    expect(budget.warning, isNull);
    expect(
      Directory('${root.path}/mapterhorn-v1')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'))
          .length,
      tilesPerFolder,
    );
  });
}
