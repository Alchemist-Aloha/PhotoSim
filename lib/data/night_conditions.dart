import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'http_bytes.dart';

class ForecastHour {
  const ForecastHour(
    this.utc, {
    this.cloud,
    this.highCloud,
    this.visibility,
    this.wind,
    this.gusts,
    this.humidity,
    this.temperature,
    this.dewPoint,
    this.rainProbability,
  });
  final DateTime utc;
  final double? cloud,
      highCloud,
      visibility,
      wind,
      gusts,
      humidity,
      temperature,
      dewPoint,
      rainProbability;
}

class NightForecast {
  const NightForecast(this.hours, this.fetchedAt);
  final List<ForecastHour> hours;
  final DateTime fetchedAt;
}

NightForecast parseNightForecast(String source, DateTime fetchedAt) {
  final Object? json = jsonDecode(source);
  if (json is! Map<String, Object?> ||
      json['hourly'] is! Map<String, Object?> ||
      (json['utc_offset_seconds'] != null && json['utc_offset_seconds'] != 0)) {
    throw const FormatException('Invalid UTC forecast');
  }
  final hourly = json['hourly']! as Map<String, Object?>;
  final times = hourly['time'];
  if (times is! List<Object?> || times.isEmpty || times.length > 1000) {
    throw const FormatException('Invalid forecast times');
  }
  double? value(String name, int i, double min, double max) {
    final column = hourly[name];
    if (column == null) return null;
    if (column is! List<Object?> || column.length != times.length) {
      throw const FormatException('Invalid forecast column');
    }
    final number = column[i];
    if (number == null) return null;
    if (number is! num || !number.isFinite || number < min || number > max) {
      throw const FormatException('Invalid forecast value');
    }
    return number.toDouble();
  }

  final hours = <ForecastHour>[];
  for (var i = 0; i < times.length; i++) {
    final seconds = times[i];
    if (seconds is! int || seconds < -2208988800 || seconds > 4133980800) {
      throw const FormatException('Invalid forecast instant');
    }
    final utc = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    );
    if (hours.isNotEmpty &&
        utc.difference(hours.last.utc) < const Duration(hours: 1)) {
      throw const FormatException('Unordered forecast');
    }
    hours.add(
      ForecastHour(
        utc,
        cloud: value('cloud_cover', i, 0, 100),
        highCloud: value('cloud_cover_high', i, 0, 100),
        visibility: value('visibility', i, 0, 1000000),
        wind: value('wind_speed_10m', i, 0, 500),
        gusts: value('wind_gusts_10m', i, 0, 500),
        humidity: value('relative_humidity_2m', i, 0, 100),
        temperature: value('temperature_2m', i, -100, 80),
        dewPoint: value('dew_point_2m', i, -120, 80),
        rainProbability: value('precipitation_probability', i, 0, 100),
      ),
    );
  }
  return NightForecast(List.unmodifiable(hours), fetchedAt.toUtc());
}

class WindowWeather {
  const WindowWeather({
    required this.coverage,
    this.cloud,
    this.highCloud,
    this.visibility,
    this.gusts,
    this.dewMargin,
    this.rainProbability,
  });
  final double coverage;
  final double? cloud, highCloud, visibility, gusts, dewMargin, rainProbability;
  bool get complete => coverage >= 0.999 && cloud != null;
  int? adjustedScore(int? astronomy) => complete && astronomy != null
      ? (astronomy * (1 - cloud! / 100)).round()
      : null;
}

/// Sample the actual shooting/dark interval, not a calendar-day cloud average.
WindowWeather windowWeather(
  DateTime startUtc,
  DateTime endUtc,
  NightForecast forecast,
) {
  final duration = endUtc.difference(startUtc).inSeconds / 60;
  var covered = 0.0, totalCloud = 0.0;
  double? high, visibility, gusts, dew, rain;
  for (final hour in forecast.hours) {
    final start = hour.utc.isAfter(startUtc) ? hour.utc : startUtc;
    final hourEnd = hour.utc.add(const Duration(hours: 1));
    final end = hourEnd.isBefore(endUtc) ? hourEnd : endUtc;
    if (!end.isAfter(start)) continue;
    final minutes = end.difference(start).inSeconds / 60;
    if (hour.cloud != null) {
      covered += minutes;
      totalCloud += hour.cloud! * minutes;
    }
    if (hour.highCloud != null) high = math.max(high ?? 0, hour.highCloud!);
    if (hour.visibility != null) {
      visibility = math.min(visibility ?? double.infinity, hour.visibility!);
    }
    if (hour.gusts != null) gusts = math.max(gusts ?? 0, hour.gusts!);
    if (hour.rainProbability != null) {
      rain = math.max(rain ?? 0, hour.rainProbability!);
    }
    if (hour.temperature != null && hour.dewPoint != null) {
      dew = math.min(
        dew ?? double.infinity,
        hour.temperature! - hour.dewPoint!,
      );
    }
  }
  return WindowWeather(
    coverage: duration > 0 ? (covered / duration).clamp(0, 1) : 0,
    cloud: covered > 0 ? totalCloud / covered : null,
    highCloud: high,
    visibility: visibility,
    gusts: gusts,
    dewMargin: dew,
    rainProbability: rain,
  );
}

const atlasYear = 2025;
const atlasTileLength = 600 * 600 + 1;

class SiteBrightness {
  const SiteBrightness(this.ratio);
  final double ratio;
  double get sqm => 22 - 2.5 * math.log(1 + ratio) / math.ln10;
}

({int tileX, int tileY, int x, int y})? atlasPoint(
  double latitude,
  double longitude,
) {
  if (!latitude.isFinite ||
      latitude.abs() > 90 ||
      !longitude.isFinite ||
      longitude.abs() > 180) {
    throw ArgumentError('Invalid atlas coordinates');
  }
  if (latitude < -65 || latitude >= 75) return null;
  final lon = (longitude + 180) % 360;
  final lat = latitude + 65;
  final tx = (lon / 5).floor(), ty = (lat / 5).floor();
  return (
    tileX: tx + 1,
    tileY: ty + 1,
    x: (120 * (lon - 5 * tx + 1 / 240)).round().clamp(1, 600),
    y: (120 * (lat - 5 * ty + 1 / 240)).round().clamp(1, 600),
  );
}

class _AtlasSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > atlasTileLength) {
      throw const FormatException('Atlas expands beyond tile size');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

Uint8List decodeAtlasTile(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 31 && bytes[1] == 139) {
    final output = _AtlasSink();
    final decoder = gzip.decoder.startChunkedConversion(
      ByteConversionSink.from(output),
    );
    try {
      decoder.add(bytes);
      decoder.close();
      bytes = output.bytes.takeBytes();
    } finally {
      output.close();
    }
  }
  if (bytes.length != atlasTileLength) {
    throw const FormatException('Invalid atlas tile size');
  }
  return bytes;
}

/// Decode Lorenz's published signed-delta tile scheme; never infer Bortle from palette colors.
SiteBrightness sampleAtlasTile(Uint8List bytes, int x, int y) {
  if (bytes.length != atlasTileLength || x < 1 || x > 600 || y < 1 || y > 600) {
    throw const FormatException('Invalid atlas sample');
  }
  final data = Int8List.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  var compressed = 128 * data[0] + data[1];
  for (var row = 1; row < y; row++) {
    compressed += data[600 * row + 1];
  }
  for (var col = 1; col < x; col++) {
    compressed += data[600 * (y - 1) + 1 + col];
  }
  final ratio = (5 / 195) * (math.exp(0.0195 * compressed) - 1);
  if (!ratio.isFinite || ratio < 0 || SiteBrightness(ratio).sqm < 0) {
    throw const FormatException('Invalid atlas brightness');
  }
  return SiteBrightness(ratio);
}

class NightConditionsRepository {
  NightConditionsRepository(this.client, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final http.Client client;
  final DateTime Function() now;
  final _forecasts = <String, NightForecast>{};
  final _tiles = <String, Uint8List>{};

  Future<NightForecast> forecast(
    double latitude,
    double longitude, {
    required Future<void> abort,
    bool refresh = false,
  }) async {
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      throw ArgumentError('Invalid forecast coordinates');
    }
    final key =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    final cached = _forecasts[key];
    final instant = now().toUtc();
    if (!refresh &&
        cached != null &&
        !instant.difference(cached.fetchedAt).isNegative &&
        instant.difference(cached.fetchedAt) < const Duration(hours: 1)) {
      return cached;
    }
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'forecast_days': '16',
      'timezone': 'GMT',
      'timeformat': 'unixtime',
      'temperature_unit': 'celsius',
      'wind_speed_unit': 'kmh',
      'hourly': 'cloud_cover,cloud_cover_high,visibility,wind_speed_10m,wind_gusts_10m,relative_humidity_2m,temperature_2m,dew_point_2m,precipitation_probability',
    });
    final bytes = await downloadBytes(
      client,
      uri,
      abort: abort,
      maxBytes: 2 * 1024 * 1024,
    );
    final result = parseNightForecast(utf8.decode(bytes), instant);
    if (_forecasts.length >= 4) _forecasts.remove(_forecasts.keys.first);
    _forecasts[key] = result;
    return result;
  }

  Future<SiteBrightness?> brightness(
    double latitude,
    double longitude, {
    required Future<void> abort,
  }) async {
    final point = atlasPoint(latitude, longitude);
    if (point == null) return null;
    final key = '${point.tileX}_${point.tileY}';
    var bytes = _tiles[key];
    if (bytes == null) {
      final uri = Uri.https(
        'djlorenz.github.io',
        '/astronomy/binary_tiles/$atlasYear/binary_tile_$key.dat.gz',
      );
      bytes = decodeAtlasTile(
        await downloadBytes(client, uri, abort: abort, maxBytes: 1024 * 1024),
      );
      if (_tiles.length >= 4) _tiles.remove(_tiles.keys.first);
      _tiles[key] = bytes;
    }
    return sampleAtlasTile(bytes, point.x, point.y);
  }
}
