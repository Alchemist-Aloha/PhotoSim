import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/terrain_geo.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/terrain/tile_cache.dart';

void main() {
  late Directory root;
  late File settings;
  late RasterCache budget;
  final a = TileId(13, 1, 1), b = TileId(13, 2, 1), c = TileId(13, 3, 1);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('photosim-cache-budget-');
    settings = File('${root.path}/settings/cache-settings.json');
    budget = RasterCache(
      Directory('${root.path}/rasters'),
      settingsFile: settings,
    );
    await budget.initialize();
  });
  tearDown(() => root.delete(recursive: true));
  TileCache source(String name) => TileCache(
    Directory('${budget.directory.path}/$name'),
    budget: budget,
    maxBytes: 1,
    maxEntryBytes: 8 * 1024 * 1024,
  );
  File raster(TileCache cache, TileId tile) =>
      File('${cache.directory.path}/${tile.key}.png');

  test('one LRU cap across terrain, previews and detail, not old per-source quotas', () async {
    await budget.setLimitMiB(1);
    final terrain = source('mapterhorn-v1');
    final preview = source('naip-natural-256-v1');
    final detail = source('eox-s2-2016-1024-v1');
    final bytes = Uint8List(400 * 1024);
    await terrain.write(a, bytes);
    await preview.write(b, bytes);
    expect(await terrain.read(a), isNotNull);
    await detail.write(c, bytes);
    expect(await raster(terrain, a).exists(), isTrue);
    expect(await raster(preview, b).exists(), isFalse);
    expect(await File('${raster(preview, b).path}.json').exists(), isFalse);
    expect(await raster(detail, c).exists(), isTrue);
  });

  test('JSON metadata counts; an entry larger than the limit does not evict useful tiles', () async {
    await budget.setLimitMiB(1);
    final cache = source('mapterhorn-v1');
    await cache.write(a, Uint8List(512 * 1024));
    await cache.write(b, Uint8List(512 * 1024));
    expect(await raster(cache, a).exists(), isFalse);
    expect(await raster(cache, b).exists(), isTrue);
    await cache.write(c, Uint8List(2 * 1024 * 1024));
    expect(await raster(cache, c).exists(), isFalse);
    expect(await raster(cache, b).exists(), isTrue);
  });

  test(
    'lowering a saved limit trims existing caches and survives restart',
    () async {
      await budget.setLimitMiB(2);
      final terrain = source('terrain-v1'),
          imagery = source('ign-ortho-1024-v1');
      await terrain.write(a, Uint8List(700 * 1024));
      await imagery.write(b, Uint8List(700 * 1024));
      await budget.setLimitMiB(1);
      expect(await raster(terrain, a).exists(), isFalse);
      expect(await raster(imagery, b).exists(), isTrue);
      final reopened = RasterCache(budget.directory, settingsFile: settings);
      await reopened.initialize();
      expect(reopened.limitMiB, 1);
      expect(await raster(imagery, b).exists(), isTrue);
      expect(jsonDecode(await settings.readAsString()), {
        'version': 1,
        'limitMiB': 1,
      });
    },
  );

  test('startup applies the limit to old files while preserving unrelated files and links', () async {
    final folder = Directory('${budget.directory.path}/mapterhorn-v1');
    await folder.create(recursive: true);
    await File('${folder.path}/${a.key}.png')
        .writeAsBytes(Uint8List(700 * 1024));
    await File('${folder.path}/${b.key}.png')
        .writeAsBytes(Uint8List(700 * 1024));
    await File('${folder.path}/${a.key}.png')
        .setLastModified(DateTime.utc(2000));
    await File('${folder.path}/${a.key}.png.tmp').writeAsString('staging');
    await File('${folder.path}/${a.key}.png.json.tmp').writeAsString('staging');
    await File('${folder.path}/${c.key}.png.json').writeAsString('orphan');
    final unrelated = File('${folder.path}/notes.json');
    await unrelated.writeAsString('keep');
    final plans = File('${budget.directory.path}/plans-v1/${c.key}.png');
    await plans.parent.create();
    await plans.writeAsString('not a cache');
    final elsewhere = Directory('${root.path}/elsewhere');
    await elsewhere.create();
    final external = File('${elsewhere.path}/${a.key}.png');
    await external.writeAsString('keep');
    await Link('${budget.directory.path}/terrain-v1').create(elsewhere.path);
    await budget.setLimitMiB(1);
    final reopened = RasterCache(budget.directory, settingsFile: settings);
    await reopened.initialize();
    expect(await File('${folder.path}/${a.key}.png').exists(), isFalse);
    expect(await File('${folder.path}/${b.key}.png').exists(), isTrue);
    expect(await File('${folder.path}/${a.key}.png.tmp').exists(), isFalse);
    expect(await File('${folder.path}/${c.key}.png.json').exists(), isFalse);
    await reopened.setLimitMiB(0);
    expect(await unrelated.readAsString(), 'keep');
    expect(await plans.readAsString(), 'not a cache');
    expect(await external.readAsString(), 'keep');
  });

  test(
    'reopened cache recognizes reads and rewrites across path separators',
    () async {
      await budget.setLimitMiB(1);
      final original = source('mapterhorn-v1');
      final bytes = Uint8List(400 * 1024);
      await original.write(a, bytes);
      await original.write(b, bytes);
      await raster(original, a).setLastModified(DateTime.utc(2000));
      await raster(original, b).setLastModified(DateTime.utc(2001));
      final reopened = RasterCache(budget.directory, settingsFile: settings);
      await reopened.initialize();
      final cache = TileCache(original.directory, budget: reopened);
      expect(await cache.read(a), isNotNull);
      await cache.write(c, bytes);
      expect(await raster(cache, a).exists(), isTrue);
      expect(await raster(cache, b).exists(), isFalse);
      await cache.write(a, bytes);
      expect(await raster(cache, c).exists(), isTrue);
      expect(await cache.read(a), hasLength(bytes.length));
    },
  );

  test('concurrent writes and settings changes serialize; zero disables disk caching', () async {
    final terrain = source('mapterhorn-v1'),
        imagery = source('naip-natural-256-v1');
    await Future.wait([
      terrain.write(a, Uint8List(400 * 1024)),
      budget.setLimitMiB(1),
      imagery.write(b, Uint8List(400 * 1024)),
      budget.setLimitMiB(0),
      terrain.write(c, Uint8List(400 * 1024)),
    ]);
    expect(await terrain.read(a), isNull);
    expect(await terrain.read(c), isNull);
    expect(await imagery.read(b), isNull);
    expect(await raster(terrain, c).exists(), isFalse);
    expect(
      await budget.directory
          .list(recursive: true)
          .where((file) => file is File)
          .toList(),
      isEmpty,
    );
  });

  test(
    'failed settings saves keep the old limit and do not poison cache writes',
    () async {
      final block = File('${root.path}/blocked');
      await block.writeAsString('keep');
      final broken = RasterCache(
        budget.directory,
        settingsFile: File('${block.path}/settings.json'),
      );
      await broken.initialize();
      await expectLater(
        broken.setLimitMiB(1),
        throwsA(isA<FileSystemException>()),
      );
      expect(broken.limitMiB, 512);
      final cache = TileCache(
        Directory('${budget.directory.path}/terrain-v1'),
        budget: broken,
      );
      await cache.write(a, Uint8List(100));
      expect(await cache.read(a), hasLength(100));
      expect(await block.readAsString(), 'keep');
    },
  );

  test('invalid, future and oversized settings fall back safely; bounds are validated', () async {
    await settings.parent.create(recursive: true);
    for (final value in [
      'not json',
      '[]',
      '{"version":2,"limitMiB":1}',
      '{"version":1,"limitMiB":-1}',
      '{"version":1,"limitMiB":65537}',
      '{"version":1,"limitMiB":1.5}',
      ' ' * 4097,
    ]) {
      await settings.writeAsString(value);
      final invalid = RasterCache(budget.directory, settingsFile: settings);
      await invalid.initialize();
      expect(invalid.limitMiB, 512);
      expect(invalid.warning, contains('Invalid cache settings'));
    }
    expect(() => budget.setLimitMiB(-1), throwsArgumentError);
    expect(() => budget.setLimitMiB(65537), throwsArgumentError);
    await budget.setLimitMiB(65536);
    expect(budget.limitMiB, 65536);
  });
}
