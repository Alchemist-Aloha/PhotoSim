import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/terrain_geo.dart';

/// Bounded raster storage; each provider/resolution uses a separate directory.
class TileCache {
  TileCache(
    this.directory, {
    this.maxBytes = 256 * 1024 * 1024,
    this.maxEntryBytes = 1024 * 1024,
  });
  final Directory directory;
  final int maxBytes, maxEntryBytes;
  String? warning;
  Future<void> _writes = Future.value();

  File _file(TileId tile) => File('${directory.path}/${tile.key}.png');

  Future<Uint8List?> read(TileId tile) async {
    try {
      final file = _file(tile);
      if (!await file.exists()) return null;
      if (await file.length() > maxEntryBytes) {
        await remove(tile);
        return null;
      }
      final bytes = await file.readAsBytes();
      try {
        await file.setLastModified(DateTime.now());
      } on FileSystemException {
        warning = 'Read-only disk cache; cached terrain is still available.';
      }
      return bytes;
    } on FileSystemException {
      warning = 'Disk cache unavailable; using network data.';
      return null;
    }
  }

  Future<void> remove(TileId tile) async {
    try {
      final file = _file(tile);
      if (await file.exists()) await file.delete();
      final metadata = File('${file.path}.json');
      if (await metadata.exists()) await metadata.delete();
    } on FileSystemException {
      warning = 'Could not remove a corrupt cached tile.';
    }
  }

  Future<void> write(
    TileId tile,
    Uint8List bytes, {
    Map<String, Object?> metadata = const {},
  }) {
    // Serialize writes/eviction so concurrent tile downloads cannot race cache maintenance.
    _writes = _writes.then((_) async {
      try {
        await directory.create(recursive: true);
        final file = _file(tile);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
        final metadataFile = File('${file.path}.json.tmp');
        await metadataFile.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'provider': 'Mapzen Terrarium',
            'tile': [tile.z, tile.x, tile.y],
            'url': tile.uri.toString(),
            'downloadedAt': DateTime.now().toUtc().toIso8601String(),
            'acquisitionTime': null,
            'verticalDatum': 'source dependent; uncorrected',
            'attribution': 'https://github.com/tilezen/joerd/blob/master/docs/attribution.md',
            ...metadata,
          }),
          flush: true,
        );
        await metadataFile.rename('${file.path}.json');
        await _evict();
      } on FileSystemException {
        warning = 'Disk cache unavailable; using network data.';
      }
    });
    return _writes;
  }

  Future<void> _evict() async {
    final files = <({File file, FileStat stat, int bytes})>[];
    var total = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File ||
          !RegExp(r'/\d+-\d+-\d+\.png$').hasMatch(entry.path)) {
        continue;
      }
      final stat = await entry.stat();
      final metadata = File('${entry.path}.json');
      final bytes =
          stat.size + (await metadata.exists() ? await metadata.length() : 0);
      total += bytes;
      files.add((file: entry, stat: stat, bytes: bytes));
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final item in files) {
      if (total <= maxBytes) break;
      await item.file.delete();
      final metadata = File('${item.file.path}.json');
      if (await metadata.exists()) await metadata.delete();
      total -= item.bytes;
    }
  }
}
