import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photosim/data/http_bytes.dart';

void main() {
  test('a download deadline aborts an unresponsive service', () async {
    final client = MockClient.streaming((request, _) async {
      await (request as http.AbortableRequest).abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    addTearDown(client.close);
    await expectLater(
      downloadBytes(
        client,
        Uri.https('example.com', '/imagery'),
        abort: Completer<void>().future,
        maxBytes: 1024,
        timeout: const Duration(milliseconds: 10),
      ).timeout(const Duration(seconds: 1)),
      throwsA(isA<http.RequestAbortedException>()),
    );
  });
}
