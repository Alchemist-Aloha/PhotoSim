import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// One policy per client/origin, shared by terrain and imagery; disk hits never enter it.
final _hosts = Expando<Map<String, _HostRequests>>();

class _HostRequests {
  int active = 0, failures = 0, status = 429;
  DateTime retryAt = DateTime.fromMillisecondsSinceEpoch(0);
  final waiters = <Completer<void>>{};

  Future<void> acquire(
    Completer<void> stop,
    Uri uri,
    DateTime deadline, {
    required bool retry,
  }) async {
    while (true) {
      if (stop.isCompleted || DateTime.now().isAfter(deadline)) {
        throw http.RequestAbortedException(uri);
      }
      if (retryAt.isAfter(deadline) ||
          (!retry && retryAt.isAfter(DateTime.now()))) {
        throw http.ClientException(
          'HTTP $status; service cooldown until ${retryAt.toUtc().toIso8601String()}',
          uri,
        );
      }
      final delay = retryAt.difference(DateTime.now());
      if (active < 3 && delay <= Duration.zero) {
        active++;
        return;
      }
      final ready = Completer<void>();
      waiters.add(ready);
      final timer = delay > Duration.zero
          ? Timer(delay, () {
              if (!ready.isCompleted) ready.complete();
            })
          : null;
      try {
        await Future.any<void>([
          ready.future,
          stop.future.then((_) => throw http.RequestAbortedException(uri)),
        ]);
      } finally {
        timer?.cancel();
        waiters.remove(ready);
      }
    }
  }

  void release() {
    active--;
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    waiters.clear();
  }

  void throttle(int code, String? retryAfter) {
    status = code;
    final now = DateTime.now();
    var until = now.add(Duration(seconds: 1 << failures));
    if (failures < 5) failures++;
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter.trim());
      DateTime? requested;
      if (seconds != null && seconds >= 0) {
        // Saturate absurd deltas without overflowing Duration/DateTime arithmetic.
        final latest = DateTime.utc(9999, 12, 31);
        requested = seconds > latest.difference(now).inSeconds
            ? latest
            : now.add(Duration(seconds: seconds));
      } else {
        try {
          requested = HttpDate.parse(retryAfter);
        } on HttpException {
          // Malformed Retry-After uses the bounded exponential fallback.
        }
      }
      if (requested != null && requested.isAfter(until)) until = requested;
    }
    if (until.isAfter(retryAt)) retryAt = until;
  }
}

/// Bounded, cancellable download shared by elevation and imagery providers.
/// Three streamed requests per origin; 429/503 share Retry-After/backoff, at most two retries.
/// New calls during cooldown fail fast for provider fallback; existing retries may wait.
/// The deadline includes queueing and retries. No fixed requests/second quota is assumed.
Future<Uint8List> downloadBytes(
  http.Client client,
  Uri uri, {
  required Future<void> abort,
  required int maxBytes,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final origins = _hosts[client] ??= {};
  final host = origins.putIfAbsent(uri.origin, _HostRequests.new);
  final stop = Completer<void>();
  final deadline = DateTime.now().add(timeout);
  unawaited(
    abort.then((_) {
      if (!stop.isCompleted) stop.complete();
    }),
  );
  final timer = Timer(timeout, () {
    if (!stop.isCompleted) stop.complete();
  });
  try {
    for (var attempt = 0; ; attempt++) {
      await host.acquire(stop, uri, deadline, retry: attempt > 0);
      try {
        if (stop.isCompleted) throw http.RequestAbortedException(uri);
        final request =
            http.AbortableRequest('GET', uri, abortTrigger: stop.future)
              ..headers['User-Agent'] =
                  'PhotoSim/0.1 (landscape photography planner)';
        // Some clients only attach abort handlers after connecting; bound header acquisition too.
        final headers = Completer<http.StreamedResponse>();
        unawaited(
          stop.future.then((_) {
            if (!headers.isCompleted) {
              headers.completeError(http.RequestAbortedException(uri));
            }
          }),
        );
        unawaited(
          Future.sync(() => client.send(request))
              .then<void>((response) {
                if (headers.isCompleted) {
                  return response.stream.listen(null).cancel();
                }
                headers.complete(response);
              })
              .catchError((Object error, StackTrace stack) {
                if (!headers.isCompleted) headers.completeError(error, stack);
              }),
        );
        final response = await headers.future;
        if (response.statusCode != 200) {
          final throttled =
              response.statusCode == 429 || response.statusCode == 503;
          if (throttled) {
            host.throttle(response.statusCode, response.headers['retry-after']);
            debugPrint(
              'PhotoSim HTTP ${response.statusCode} · ${uri.origin} · cooldown until ${host.retryAt.toUtc().toIso8601String()}',
            );
          }
          await response.stream.listen(null).cancel();
          if (throttled && attempt < 2) continue;
          throw http.ClientException('HTTP ${response.statusCode}', uri);
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          await response.stream.listen(null).cancel();
          throw const FormatException('Raster response exceeds size limit');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (builder.length + chunk.length > maxBytes) {
            throw const FormatException('Raster response exceeds size limit');
          }
          builder.add(chunk);
        }
        if (stop.isCompleted) throw http.RequestAbortedException(uri);
        host.failures = 0;
        return builder.takeBytes();
      } finally {
        host.release();
      }
    }
  } finally {
    timer.cancel();
    if (!stop.isCompleted) stop.complete();
  }
}
