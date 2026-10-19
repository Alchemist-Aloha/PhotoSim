import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import 'astronomy.dart';
import 'geo.dart';
import 'local_time.dart';
import 'night_sky.dart';

const nightSampleMinutes = 10;
const minimumMoonCoreSeparation = 30.0;

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
  bool get moonDown => lowBandVisible && moonAltitude <= 0;
  bool get usable => moonDown && moonSeparation >= minimumMoonCoreSeparation;
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
  });
  final DateTime date;
  final int? score;
  final String reason;
  final NightWindow? window;
  final ({DateTime start, DateTime end})? darkness;
}

/// A conservative joint window: both ends of each 10-minute interval must qualify.
NightRating rateNight(DateTime date, List<NightSample> samples) {
  NightWindow? best;
  var run = <NightSample>[];
  void finishRun() {
    if (run.length >= 2) {
      final peak = run
          .take(run.length - 1)
          .reduce(
            (a, b) => a.lowMilkyWayFraction >= b.lowMilkyWayFraction ? a : b,
          );
      final window = NightWindow(
        start: run.first.utc,
        end: run.last.utc,
        bestTime: peak.utc,
        coreAltitude: peak.coreAltitude,
        lowMilkyWayFraction: peak.lowMilkyWayFraction,
        moonSeparation: run.map((s) => s.moonSeparation).reduce(math.min),
        moonIllumination: peak.moonIllumination,
      );
      if (best == null ||
          window.minutes > best!.minutes ||
          (window.minutes == best!.minutes &&
              window.lowMilkyWayFraction > best!.lowMilkyWayFraction)) {
        best = window;
      }
    }
    run = [];
  }

  for (final sample in samples) {
    if (!sample.usable ||
        (run.isNotEmpty &&
            sample.utc.difference(run.last.utc) !=
                const Duration(minutes: nightSampleMinutes))) {
      finishRun();
    }
    if (sample.usable) run.add(sample);
  }
  finishRun();
  final window = best;
  final dark = samples.where((sample) => sample.dark).toList();
  final darkness = dark.length >= 2
      ? (start: dark.first.utc, end: dark.last.utc)
      : null;
  if (window == null) {
    final reason = !samples.any((s) => s.dark)
        ? 'No astronomical darkness before 01:00'
        : !samples.any((s) => s.lowBandVisible)
        ? 'No visible Milky Way between 0° and 30°'
        : !samples.any((s) => s.moonDown)
        ? 'Moon above the horizon during low Milky Way visibility'
        : !samples.any((s) => s.usable)
        ? 'Moon less than 30° from the Galactic core'
        : 'No continuous 10-minute observing window';
    return NightRating(date, 0, reason, darkness: darkness);
  }
  final score = window.durationPoints + window.lowBandPoints;
  return NightRating(
    date,
    score,
    score >= 85
        ? 'Excellent geometry'
        : score >= 65
        ? 'Good geometry'
        : score >= 35
        ? 'Limited window'
        : 'Poor geometry',
    window: window,
    darkness: darkness,
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
