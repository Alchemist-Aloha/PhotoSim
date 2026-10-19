import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import 'astronomy.dart';
import 'geo.dart';
import 'local_time.dart';
import 'night_sky.dart';

const nightSampleMinutes = 10;

class NightSample {
  const NightSample({
    required this.utc,
    required this.sunAltitude,
    required this.coreAltitude,
    required this.lowMilkyWayFraction,
    required this.moonAltitude,
    required this.moonSeparation,
    required this.moonIllumination,
  });
  final DateTime utc;
  final double sunAltitude,
      coreAltitude,
      lowMilkyWayFraction,
      moonAltitude,
      moonSeparation,
      moonIllumination;
  bool get dark => sunAltitude <= -18;
  bool get lowBandVisible => dark && lowMilkyWayFraction > 0;
  bool get usable => lowBandVisible && moonAltitude <= 0;
}

class NightWindow {
  const NightWindow({
    required this.start,
    required this.end,
    required this.bestTime,
    required this.coreAltitude,
    required this.lowMilkyWayFraction,
    required this.moonSeparation,
    required this.moonIllumination,
  });
  final DateTime start, end, bestTime;
  final double coreAltitude,
      lowMilkyWayFraction,
      moonSeparation,
      moonIllumination;
  int get minutes => end.difference(start).inMinutes;
  int get durationPoints => (50 * (minutes / 120).clamp(0, 1)).round();
  int get lowBandPoints => (50 * lowMilkyWayFraction.clamp(0, 1)).round();
}

class NightRating {
  const NightRating(
    this.date,
    this.score,
    this.reason, {
    this.window,
    this.darkness,
    this.samples = const [],
    this.weatherScore,
  });
  final DateTime date;
  final int? score;
  final String reason;
  final NightWindow? window;
  final ({DateTime start, DateTime end})? darkness;
  final List<NightSample> samples;
  final int? weatherScore;

  DateTime? get geometryPreviewTime {
    if (window != null) return window!.bestTime;
    final beforeCutoff = samples.take(math.max(0, samples.length - 1)).toList();
    if (beforeCutoff.isEmpty) return null;
    var candidates = beforeCutoff.where((s) => s.dark).toList();
    if (candidates.isEmpty) {
      candidates = beforeCutoff.where((s) => s.sunAltitude <= 0).toList();
    }
    if (candidates.isEmpty) {
      final evening = samples.last.utc.subtract(const Duration(hours: 7));
      candidates = beforeCutoff.where((s) => !s.utc.isBefore(evening)).toList();
      if (candidates.isEmpty) candidates = [beforeCutoff.last];
    }
    return candidates
        .reduce(
          (a, b) => a.lowMilkyWayFraction >= b.lowMilkyWayFraction ? a : b,
        )
        .utc;
  }
}

/// Compare all contiguous sampled intervals; incomplete weather stays astronomy-only.
NightRating rateNight(
  DateTime date,
  List<NightSample> samples, {
  double? Function(DateTime start, DateTime end)? clearFraction,
}) {
  final bands = <double>[], clears = <double>[];
  var completeWeather = clearFraction != null;
  for (var i = 0; i + 1 < samples.length; i++) {
    final a = samples[i], b = samples[i + 1];
    final usable =
        a.usable &&
        b.usable &&
        b.utc.difference(a.utc) == const Duration(minutes: nightSampleMinutes);
    bands.add(
      usable
          ? ((a.lowMilkyWayFraction + b.lowMilkyWayFraction) / 2).clamp(
              0.0,
              1.0,
            )
          : -1,
    );
    final clear = usable ? clearFraction?.call(a.utc, b.utc) : null;
    if (usable && clear == null) completeWeather = false;
    clears.add(clear?.clamp(0.0, 1.0) ?? 0);
  }

  var bestStart = -1, bestEnd = -1, bestTime = -1;
  var bestScore = -1, bestMinutes = -1, bestAstronomy = 0;
  var bestBand = 0.0;
  for (var i = 0; i < bands.length; i++) {
    var sumBand = 0.0, sumClear = 0.0, sumBandClear = 0.0;
    var peak = -1.0, peakIndex = i;
    for (var j = i; j < bands.length && bands[j] >= 0; j++) {
      sumBand += bands[j];
      sumClear += clears[j];
      sumBandClear += bands[j] * clears[j];
      final quality = bands[j] * (completeWeather ? clears[j] : 1);
      if (quality > peak) {
        peak = quality;
        peakIndex = j;
      }
      final count = j - i + 1;
      final minutes = count * nightSampleMinutes;
      final durationPoints = (50 * (minutes / 120).clamp(0, 1)).round();
      final meanBand = sumBand / count;
      final astronomy = durationPoints + (50 * meanBand).round();
      final score = completeWeather
          ? (durationPoints * sumClear / count + 50 * sumBandClear / count)
                .round()
          : astronomy;
      if (score > bestScore || (score == bestScore && minutes > bestMinutes)) {
        bestStart = i;
        bestEnd = j + 1;
        bestTime = peakIndex;
        bestScore = score;
        bestMinutes = minutes;
        bestAstronomy = astronomy;
        bestBand = meanBand;
      }
    }
  }

  final dark = samples.where((sample) => sample.dark).toList();
  final darkness = dark.length >= 2
      ? (start: dark.first.utc, end: dark.last.utc)
      : null;
  final savedSamples = List<NightSample>.unmodifiable(samples);
  if (bestStart < 0) {
    final reason = !samples.any((s) => s.dark)
        ? 'No astronomical darkness before 01:00'
        : !samples.any((s) => s.lowBandVisible)
        ? 'No visible Milky Way between 0° and 30°'
        : !samples.any((s) => s.usable)
        ? 'Moon above the horizon during low Milky Way visibility'
        : 'No continuous 10-minute observing window';
    return NightRating(
      date,
      0,
      reason,
      darkness: darkness,
      samples: savedSamples,
    );
  }
  final peak = samples[bestTime];
  final window = NightWindow(
    start: samples[bestStart].utc,
    end: samples[bestEnd].utc,
    bestTime: peak.utc,
    coreAltitude: peak.coreAltitude,
    lowMilkyWayFraction: bestBand,
    moonSeparation: samples
        .sublist(bestStart, bestEnd + 1)
        .map((s) => s.moonSeparation)
        .reduce(math.min),
    moonIllumination: peak.moonIllumination,
  );
  return NightRating(
    date,
    bestAstronomy,
    bestAstronomy >= 85
        ? 'Excellent geometry'
        : bestAstronomy >= 65
        ? 'Good geometry'
        : bestAstronomy >= 35
        ? 'Limited window'
        : 'Poor geometry',
    window: window,
    darkness: darkness,
    samples: savedSamples,
    weatherScore: completeWeather ? bestScore : null,
  );
}

class NightCalendarRequest {
  const NightCalendarRequest({
    required this.startDate,
    required this.days,
    required this.latitude,
    required this.longitude,
    required this.elevation,
  });
  final DateTime startDate;
  final int days;
  final double latitude, longitude, elevation;
}

/// Runs in an isolate. Calendar dates describe local evenings, never host-local time.
List<NightRating> calculateNightCalendar(NightCalendarRequest request) {
  if (request.days < 1 || request.days > 42) {
    throw ArgumentError('Calendar range must be 1–42 days');
  }
  final clock = localClock(
    timestamp: DateTime.utc(2000),
    latitude: request.latitude,
    longitude: request.longitude,
  );
  final zone = clock.time?.location;
  return List.generate(request.days, (i) {
    final date = DateTime.utc(
      request.startDate.year,
      request.startDate.month,
      request.startDate.day + i,
    );
    NightRating unavailable() => NightRating(
      date,
      null,
      'Local-night rules unavailable (1970–2037 UTC)',
    );
    if (zone == null || date.year < 1970 || date.year > 2037) {
      return unavailable();
    }
    final start = tz.TZDateTime(zone, date.year, date.month, date.day, 12);
    final next = date.add(const Duration(days: 1));
    final candidates = localTimeCandidates(
      wallTime: DateTime.utc(next.year, next.month, next.day, 1),
      latitude: request.latitude,
      longitude: request.longitude,
    );
    // If 01:00 is skipped, its normalized next valid instant is the cutoff.
    final cutoff = candidates.isNotEmpty
        ? tz.TZDateTime.from(candidates.first, zone)
        : tz.TZDateTime(zone, next.year, next.month, next.day, 1);
    if (start.year != date.year ||
        start.month != date.month ||
        start.day != date.day ||
        cutoff.year != next.year ||
        cutoff.month != next.month ||
        cutoff.day != next.day ||
        start.native.year < 1970 ||
        cutoff.native.year > 2037 ||
        !cutoff.isAfter(start)) {
      return unavailable();
    }
    final samples = <NightSample>[];
    for (
      var utc = start.native;
      !utc.isAfter(cutoff.native);
      utc = utc.add(const Duration(minutes: nightSampleMinutes))
    ) {
      final sky = calculateSky(
        timestamp: utc,
        latitude: request.latitude,
        longitude: request.longitude,
        elevation: request.elevation,
      );
      final frame = ObserverSkyFrame(
        timestamp: utc,
        latitude: request.latitude,
        longitude: request.longitude,
      );
      final core = frame.galacticCenter;
      samples.add(
        NightSample(
          utc: utc,
          sunAltitude: sky.sun.altitude,
          coreAltitude: core.altitude,
          lowMilkyWayFraction: frame.lowMilkyWayFraction,
          moonAltitude: sky.moon.altitude,
          moonSeparation:
              math.acos(
                sky.moon.direction.dot(core.direction).clamp(-1.0, 1.0),
              ) /
              radians,
          moonIllumination: sky.moonIllumination,
        ),
      );
    }
    return rateNight(date, samples);
  });
}
