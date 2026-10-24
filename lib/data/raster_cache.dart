import 'dart:convert';
import 'dart:io';

import 'imagery/imagery_provider.dart';
import 'terrain/terrain_provider.dart';

/// One persistent LRU budget for the existing source-separated raster directories.
class RasterCache {
  RasterCache(this.directory, {this.settingsFile});
  static const defaultLimitMiB = 512;
  static const maxLimitMiB = 65536;
  final Directory directory;
  final File? settingsFile;
  int _limitMiB = defaultLimitMiB;
  int get limitMiB => _limitMiB;
  int get maxBytes => _limitMiB * 1024 * 1024;
  String? warning;
  final _entries = <String, ({int bytes, DateTime used})>{};
  int _bytes = 0;
  // shortcut: one application owns this index; add process locking/rescans for shared writers.
  bool _indexed = false;
  Future<void> _pending = Future.value();
  Future<void>? _initialization;

  // Directory listings use native separators; callers may build paths with '/'.
  static String _key(File file) =>
      file.absolute.uri.normalizePath().toFilePath();

  // Hoisted: Dart re-compiles a RegExp literal at every evaluation.
  static final _stagingName = RegExp(r'^\d+-\d+-\d+\.png(?:\.json)?\.tmp$');
  static final _orphanMetadata = RegExp(r'^\d+-\d+-\d+\.png\.json$');
  static final _rasterName = RegExp(r'^\d+-\d+-\d+\.png$');

  Iterable<Directory> get _directories sync* {
    for (final provider in TerrainProvider.values) {
      yield Directory('${directory.path}/${provider.cacheKey}');
    }
    for (final provider in imageryProviders) {
      for (final size in [256, 1024]) {
        yield Directory('${directory.path}/${provider.cacheKey}-$size-v1');
      }
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final job = _pending.then((_) => action());
    // A failed settings save must not poison subsequent cache writes.
    _pending = job.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return job;
  }

  Future<void> initialize() => _initialization ??= _enqueue(() async {
    final file = settingsFile;
    if (file != null) {
      try {
        if (await file.exists()) {
          if (await file.length() > 4096) {
            throw const FormatException('Oversized settings');
          }
          final Object? json = jsonDecode(await file.readAsString());
          if (json is! Map<String, Object?> || json['version'] != 1) {
            throw const FormatException('Invalid cache settings');
          }
          final limit = json['limitMiB'];
          if (limit is! int || limit < 0 || limit > maxLimitMiB) {
            throw const FormatException('Invalid cache limit');
          }
          _limitMiB = limit;
        }
      } on FormatException {
        warning = 'Invalid cache settings; using the 512 MiB default.';
      } on FileSystemException {
        warning = 'Cache settings unavailable; using the 512 MiB default.';
      }
    }
    try {
      await _index();
      await _evict();
    } on FileSystemException {
      warning = 'Disk cache unavailable; using network data.';
    }
  });

  Future<void> setLimitMiB(int limit) {
    if (limit < 0 || limit > maxLimitMiB) {
      throw ArgumentError('Cache limit must be 0–$maxLimitMiB MiB');
    }
    return _enqueue(() async {
      final file = settingsFile;
      if (file != null) {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(
          jsonEncode({'version': 1, 'limitMiB': limit}),
          flush: true,
        );
        await temporary.rename(file.path);
      }
      _limitMiB = limit;
      warning = null;
      try {
        await _index();
        await _evict();
      } on FileSystemException {
        warning = 'Limit saved, but the disk cache could not be trimmed. Check disk permissions.';
        rethrow;
      }
    });
  }

  void touch(File file) {
    final key = _key(file);
    final entry = _entries[key];
    if (entry != null) {
      _entries[key] = (bytes: entry.bytes, used: DateTime.now());
    }
  }

  Future<void> write(File file, Future<void> Function() persist) => _enqueue(
    () async {
      try {
        await _index();
        if (maxBytes == 0) return;
        final type = await FileSystemEntity.type(
          file.parent.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link) {
          throw FileSystemException('Linked cache directory', file.parent.path);
        }
        await persist();
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) {
          throw FileSystemException('Cache write unavailable', file.path);
        }
        final metadata = File('${file.path}.json');
        final size =
            stat.size + (await metadata.exists() ? await metadata.length() : 0);
        final key = _key(file);
        _bytes -= _entries[key]?.bytes ?? 0;
        _entries[key] = (bytes: size, used: DateTime.now());
        _bytes += size;
        await _evict();
      } on FileSystemException {
        _indexed = false;
        warning = 'Disk cache unavailable; using network data.';
      }
    },
  );

  Future<void> remove(File file) => _enqueue(() async {
    try {
      await _delete(file);
    } on FileSystemException {
      warning = 'Could not remove a corrupt cached tile.';
    }
  });

  Future<void> _index() async {
    if (_indexed) return;
    _entries.clear();
    _bytes = 0;
    for (final folder in _directories) {
      if (await FileSystemEntity.type(folder.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      await for (final entry in folder.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (_stagingName.hasMatch(name) ||
            (_orphanMetadata.hasMatch(name) &&
                !await File(entry.path.substring(0, entry.path.length - 5))
                    .exists())) {
          await entry.delete();
          continue;
        }
        if (!_rasterName.hasMatch(name)) continue;
        final stat = await entry.stat();
        final metadata = File('${entry.path}.json');
        final size =
            stat.size + (await metadata.exists() ? await metadata.length() : 0);
        _entries[_key(entry)] = (bytes: size, used: stat.modified);
        _bytes += size;
      }
    }
    _indexed = true;
  }

  Future<void> _delete(File file) async {
    if (await file.exists()) await file.delete();
    final metadata = File('${file.path}.json');
    if (await metadata.exists()) await metadata.delete();
    _bytes -= _entries.remove(_key(file))?.bytes ?? 0;
  }

  Future<void> _evict() async {
    if (_bytes <= maxBytes) return;
    // An entry larger than the whole budget must not evict useful smaller rasters.
    for (final entry
        in _entries.entries
            .where((entry) => entry.value.bytes > maxBytes)
            .toList()) {
      await _delete(File(entry.key));
    }
    final oldest = _entries.entries.toList()
      ..sort((a, b) => a.value.used.compareTo(b.value.used));
    for (final entry in oldest) {
      if (_bytes <= maxBytes) break;
      await _delete(File(entry.key));
    }
  }
}
