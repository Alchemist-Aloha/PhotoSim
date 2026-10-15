import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Bounded, cancellable download shared by elevation and imagery providers.
Future<Uint8List> downloadBytes(
  http.Client client,
  Uri uri, {
  required Future<void> abort,
  required int maxBytes,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final stop = Completer<void>();
  abort.then((_) {
    if (!stop.isCompleted) stop.complete();
  });
  final timer = Timer(timeout, () {
    if (!stop.isCompleted) stop.complete();
  });
  try {
    final request = http.AbortableRequest('GET', uri, abortTrigger: stop.future)
      ..headers['User-Agent'] = 'PhotoSim/0.1 (Linux photography planner)';
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    if ((response.contentLength ?? 0) > maxBytes) {
      throw const FormatException('Raster response exceeds size limit');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (builder.length + chunk.length > maxBytes) {
        throw const FormatException('Raster response exceeds size limit');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    timer.cancel();
    if (!stop.isCompleted) stop.complete();
  }
}
