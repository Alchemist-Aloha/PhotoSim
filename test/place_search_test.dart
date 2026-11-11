import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/data/place_search.dart';

Map<String, Object?> placeFeature({
  String name = 'Chamonix-Mont-Blanc',
  Object? longitude = 6.87,
  Object? latitude = 45.923,
}) => {
  'properties': {
    'name': name,
    'city': name,
    'state': 'Auvergne-Rhône-Alpes',
    'country': 'France',
  },
  'geometry': {
    'type': 'Point',
    'coordinates': [longitude, latitude],
  },
};

http.Response placeResponse(List<Object?> features) => http.Response(
  jsonEncode({'features': features}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'Photon request encodes the query and parses names and lon/lat',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.host, 'photon.komoot.io');
        expect(request.url.path, '/api/');
        expect(request.url.queryParameters, {
          'q': 'Chamonix & Megève',
          'limit': '5',
          'lang': 'en',
        });
        expect(request.headers['user-agent'], 'org.photosim.photosim');
        return placeResponse([placeFeature()]);
      });
      addTearDown(client.close);
      final repository = PlaceSearchRepository(client);
      expect(await repository.search('   '), isEmpty);
      expect(calls, 0);
      final results = await repository.search('  Chamonix & Megève  ');
      expect(calls, 1);
      expect(results.single.name, 'Chamonix-Mont-Blanc');
      expect(results.single.description, 'Auvergne-Rhône-Alpes, France');
      expect(results.single.location, const LatLng(45.923, 6.87));
    },
  );

  test(
    'ignores invalid coordinates/features and limits results to five',
    () async {
      final client = MockClient(
        (_) async => placeResponse([
          null,
          {},
          placeFeature(latitude: 91),
          placeFeature(longitude: -181),
          placeFeature(latitude: '45'),
          {
            'properties': <String, Object?>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [0, 0],
            },
          },
          for (var i = 0; i < 7; i++) placeFeature(name: 'Place $i'),
        ]),
      );
      addTearDown(client.close);
      final results = await PlaceSearchRepository(client).search('place');
      expect(results, hasLength(5));
      expect(results.first.name, 'Place 0');
      expect(results.last.name, 'Place 4');
    },
  );

  for (final code in [429, 503]) {
    test('HTTP $code fails once and permits an explicit retry', () async {
      var calls = 0;
      final client = MockClient((_) async {
        return ++calls == 1 ? http.Response('Busy', code) : placeResponse([]);
      });
      addTearDown(client.close);
      final repository = PlaceSearchRepository(client);
      await expectLater(
        repository.search('town').timeout(const Duration(seconds: 1)),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 1);
      expect(await repository.search('town'), isEmpty);
      expect(calls, 2);
    });
  }

  for (final declared in [true, false]) {
    test(
      'oversized search responses (declared: $declared) are cancelled',
      () async {
        var calls = 0, cancelled = 0;
        final body = StreamController<List<int>>(onCancel: () => cancelled++);
        addTearDown(body.close);
        final payload = utf8.encode(
          jsonEncode({
            'features': [placeFeature(name: declared ? 'Town' : 'a' * 1048576)],
          }),
        );
        final client = MockClient.streaming((_, _) async {
          if (++calls > 1) {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"features":[]}')),
              200,
            );
          }
          return http.StreamedResponse(
            body.stream,
            200,
            contentLength: declared ? 1048577 : null,
          );
        });
        addTearDown(client.close);
        final repository = PlaceSearchRepository(client);
        final rejected = expectLater(
          repository.search('town').timeout(const Duration(seconds: 1)),
          throwsFormatException,
        );
        body.add(payload);
        unawaited(body.close());
        await rejected;
        expect(cancelled, 1);
        expect(await repository.search('another town'), isEmpty);
        expect(calls, 2);
      },
    );
  }

  test(
    'supports empty results and reports HTTP and malformed responses',
    () async {
      final responses = [
        placeResponse([]),
        http.Response('Busy', 429),
        http.Response('{"features":{}}', 200),
        http.Response('not JSON', 200),
      ];
      final client = MockClient((_) async => responses.removeAt(0));
      addTearDown(client.close);
      final repository = PlaceSearchRepository(client);
      expect(await repository.search('unknown'), isEmpty);
      await expectLater(
        repository.search('town'),
        throwsA(isA<http.ClientException>()),
      );
      await expectLater(repository.search('town'), throwsFormatException);
      await expectLater(repository.search('town'), throwsFormatException);
    },
  );
}
