import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photosim/core/night_rating.dart';
import 'package:photosim/data/night_conditions.dart';

String forecastFixture(
  DateTime first, {
  List<Object?> clouds = const [20, 40, 60],
}) => jsonEncode({
  'utc_offset_seconds': 0,
  'hourly': {
    'time': List.generate(
      clouds.length,
      (i) => first.add(Duration(hours: i)).millisecondsSinceEpoch ~/ 1000,
    ),
    'cloud_cover': clouds,
    'cloud_cover_high': List.filled(clouds.length, 10),
    'visibility': List.filled(clouds.length, 25000),
    'wind_gusts_10m': List.filled(clouds.length, 22),
    'temperature_2m': List.filled(clouds.length, 12),
    'dew_point_2m': List.filled(clouds.length, 10),
  },
});

void main() {
  final first = DateTime.utc(2026, 6, 15, 22);
  final window = NightWindow(
    start: first.add(const Duration(minutes: 30)),
    end: first.add(const Duration(hours: 2, minutes: 30)),
    bestTime: first.add(const Duration(hours: 1)),
    coreAltitude: 45,
    lowMilkyWayFraction: 1,
    moonSeparation: 90,
    moonIllumination: 0.1,
  );
  test('forecast joins the actual cross-midnight UTC window and preserves unknowns', () {
    final forecast = parseNightForecast(forecastFixture(first), first);
    final result = windowWeather(window.start, window.end, forecast);
    expect(result.complete, isTrue);
    expect(result.cloud, 40);
    expect(result.adjustedScore(100), 60);
    expect(result.dewMargin, 2);
    expect(result.visibility, 25000);
    final partial = windowWeather(
      window.start,
      window.end,
      parseNightForecast(forecastFixture(first, clouds: [20, null, 60]), first),
    );
    expect(partial.coverage, 0.5);
    expect(partial.adjustedScore(100), isNull);
    final none = windowWeather(
      window.start,
      window.end,
      parseNightForecast(
        forecastFixture(first, clouds: [null, null, null]),
        first,
      ),
    );
    expect(none.cloud, isNull);
    expect(none.complete, isFalse);
    final outside = NightWindow(
      start: first.subtract(const Duration(days: 2)),
      end: first.subtract(const Duration(days: 1)),
      bestTime: first,
      coreAltitude: 45,
      lowMilkyWayFraction: 1,
      moonSeparation: 90,
      moonIllumination: 0,
    );
    expect(windowWeather(outside.start, outside.end, forecast).cloud, isNull);
    expect(
      windowWeather(
        window.start,
        window.end,
        parseNightForecast(
          forecastFixture(first, clouds: [100, 100, 100]),
          first,
        ),
      ).adjustedScore(100),
      0,
    );
  });
  test(
    'malformed, non-UTC, overlapping or out-of-range forecasts are rejected',
    () {
      for (final source in [
        '{}',
        '<html>error</html>',
        forecastFixture(first, clouds: [-1, 50, 50]),
        forecastFixture(first, clouds: [101, 50, 50]),
        forecastFixture(first, clouds: ['0', 0, 0]),
      ]) {
        expect(() => parseNightForecast(source, first), throwsFormatException);
      }
      final decoded =
          jsonDecode(forecastFixture(first)) as Map<String, dynamic>;
      expect(
        () => parseNightForecast(
          jsonEncode({...decoded, 'utc_offset_seconds': 3600}),
          first,
        ),
        throwsFormatException,
      );
      final hourly = decoded['hourly'] as Map<String, dynamic>;
      final times = hourly['time'] as List<Object?>;
      times[1] = times[0];
      expect(
        () => parseNightForecast(jsonEncode(decoded), first),
        throwsFormatException,
      );
      times[1] = (times[0]! as int) + 1800;
      expect(
        () => parseNightForecast(jsonEncode(decoded), first),
        throwsFormatException,
      );
    },
  );
  test(
    'atlas maps longitude seams and coverage without claiming polar data',
    () {
      expect(atlasPoint(0, -180), atlasPoint(0, 180));
      expect(atlasPoint(-65, -180), (tileX: 1, tileY: 1, x: 1, y: 1));
      expect(atlasPoint(74.999999, 179.999999), (
        tileX: 72,
        tileY: 28,
        x: 600,
        y: 600,
      ));
      expect(atlasPoint(75, 0), isNull);
      expect(atlasPoint(-65.01, 0), isNull);
      expect(() => atlasPoint(double.nan, 0), throwsArgumentError);
    },
  );
  test('published signed-delta atlas decoding, bounded gzip and unknown/corrupt tiles', () {
    final bytes = Uint8List(atlasTileLength)
      ..[0] = 1
      ..[1] = 2
      ..[601] = 3
      ..[602] = 254;
    final raw = decodeAtlasTile(Uint8List.fromList(gzip.encode(bytes)));
    final result = sampleAtlasTile(raw, 2, 2);
    final expected = (5 / 195) * (math.exp(0.0195 * 131) - 1);
    expect(result.ratio, closeTo(expected, 1e-10));
    expect(
      result.sqm,
      closeTo(22 - 2.5 * math.log(1 + expected) / math.ln10, 1e-10),
    );
    expect(() => decodeAtlasTile(Uint8List(10)), throwsFormatException);
    expect(
      () => decodeAtlasTile(
        Uint8List.fromList(gzip.encode(Uint8List(atlasTileLength + 1))),
      ),
      throwsFormatException,
    );
    expect(() => sampleAtlasTile(raw, 0, 1), throwsFormatException);
    expect(
      () => sampleAtlasTile(Uint8List(atlasTileLength)..[0] = 255, 1, 1),
      throwsFormatException,
    );
  });
  test(
    'keyless sources cache weather for an hour and reuse regional tiles',
    () async {
      var instant = first, weatherCalls = 0, atlasCalls = 0;
      final client = MockClient((request) async {
        expect(
          request.headers.keys.any(
            (key) => key.toLowerCase().contains('api-key'),
          ),
          isFalse,
        );
        if (request.url.host == 'api.open-meteo.com') {
          weatherCalls++;
          expect(request.url.queryParameters['forecast_days'], '16');
          expect(request.url.queryParameters['timezone'], 'GMT');
          expect(request.url.queryParameters['timeformat'], 'unixtime');
          return http.Response(forecastFixture(first), 200);
        }
        atlasCalls++;
        expect(request.url.path, contains('/2025/binary_tile_'));
        return http.Response.bytes(
          gzip.encode(Uint8List(atlasTileLength)),
          200,
        );
      });
      addTearDown(client.close);
      final repository = NightConditionsRepository(client, now: () => instant);
      final stop = Completer<void>();
      addTearDown(stop.complete);
      final forecast = await repository.forecast(
        37.744,
        -119.59,
        abort: stop.future,
      );
      expect(
        await repository.forecast(37.744, -119.59, abort: stop.future),
        same(forecast),
      );
      expect(weatherCalls, 1);
      instant = instant.add(const Duration(hours: 1));
      await repository.forecast(37.744, -119.59, abort: stop.future);
      expect(weatherCalls, 2);
      await repository.forecast(
        37.744,
        -119.59,
        abort: stop.future,
        refresh: true,
      );
      expect(weatherCalls, 3);
      expect(
        (await repository.brightness(37.744, -119.59, abort: stop.future))!.sqm,
        22,
      );
      await repository.brightness(37.75, -119.58, abort: stop.future);
      expect(atlasCalls, 1);
      expect(await repository.brightness(80, 0, abort: stop.future), isNull);
      expect(atlasCalls, 1);
    },
  );
  test('failed responses are never cached as dark skies', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('not an atlas', 200);
    });
    addTearDown(client.close);
    final repository = NightConditionsRepository(client);
    final stop = Completer<void>();
    addTearDown(stop.complete);
    await expectLater(
      repository.brightness(37.744, -119.59, abort: stop.future),
      throwsFormatException,
    );
    await expectLater(
      repository.brightness(37.744, -119.59, abort: stop.future),
      throwsFormatException,
    );
    expect(calls, 2);
  });
}
