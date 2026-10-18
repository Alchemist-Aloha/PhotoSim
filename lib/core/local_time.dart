import 'package:lat_lng_to_timezone/lat_lng_to_timezone.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

final _locations = _loadLocations();
Map<String, tz.Location> _loadLocations() {
  data.initializeTimeZones();
  return tz.timeZoneDatabase.locations;
}

/// Local wall clocks require timezone conversion; simulation timestamps remain UTC.
({String zoneId, tz.TZDateTime? time, String? warning}) localClock({
  required DateTime timestamp,
  required double latitude,
  required double longitude,
}) {
  if (!latitude.isFinite ||
      latitude.abs() > 90 ||
      !longitude.isFinite ||
      longitude.abs() > 180) {
    throw ArgumentError('Invalid timezone coordinates');
  }
  // shortcut: static approximate boundary lookup; use maintained polygons for border/offshore accuracy.
  final zoneId = latLngToTimezoneString(latitude, longitude);
  final location = _locations[zoneId];
  final utc = timestamp.toUtc();
  if (location == null) {
    return (
      zoneId: zoneId,
      time: null,
      warning: 'Local time unavailable: timezone rules missing',
    );
  }
  // shortcut: bundled transitions stop in 2037; extend the database before supporting wider local dates.
  if (utc.year < 1970 || utc.year > 2037) {
    return (
      zoneId: zoneId,
      time: null,
      warning: 'Local time unavailable: bundled rules support 1970–2037',
    );
  }
  return (
    zoneId: zoneId,
    time: tz.TZDateTime.from(utc, location),
    warning: null,
  );
}

/// UTC instants matching wall-clock fields at the camera location, never the host timezone.
/// A DST gap has no matches; a repeated hour has two, in chronological order.
List<DateTime> localTimeCandidates({
  required DateTime wallTime,
  required double latitude,
  required double longitude,
}) {
  final clock = localClock(
    timestamp: DateTime.utc(2000),
    latitude: latitude,
    longitude: longitude,
  );
  final location = _locations[clock.zoneId];
  if (location == null) return [];
  final wall = DateTime.utc(
    wallTime.year,
    wallTime.month,
    wallTime.day,
    wallTime.hour,
    wallTime.minute,
    wallTime.second,
    wallTime.millisecond,
    wallTime.microsecond,
  );
  final matches = <DateTime>[];
  for (final offset in location.zones.map((zone) => zone.offset).toSet()) {
    final utc = wall.subtract(offset);
    if (utc.year < 1970 || utc.year > 2037) continue;
    final local = tz.TZDateTime.from(utc, location);
    if (local.timeZoneOffset == offset) matches.add(utc);
  }
  matches.sort();
  return matches;
}

/// Chronological local calendar day: DST gaps are skipped and both folded hours remain reachable.
class LocalDay {
  LocalDay(tz.TZDateTime time)
    : start = tz.TZDateTime(time.location, time.year, time.month, time.day),
      end = tz.TZDateTime(time.location, time.year, time.month, time.day + 1);
  final tz.TZDateTime start, end;
  double get minutes =>
      end.difference(start).inMicroseconds / Duration.microsecondsPerMinute;
  bool get supported =>
      start.native.year >= 1970 && end.native.year <= 2037 && minutes > 0;
  String get date =>
      '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

  DateTime utcAt(double minute) {
    if (!minute.isFinite || minute < 0 || minute > minutes) {
      throw ArgumentError('Minute outside local day');
    }
    if (minute == minutes) return end.native;
    final result = start.native.add(Duration(minutes: minute.round()));
    return result.isAfter(end.native) ? end.native : result;
  }

  double position(DateTime utc) => utc.isAtSameMomentAs(end)
      ? minutes
      : utc.difference(start).inMinutes.toDouble().clamp(0, minutes);

  String label(double minute) {
    final utc = utcAt(minute);
    if (utc == end.native) return '24:00 ${end.timeZoneName}';
    final time = tz.TZDateTime.from(utc, start.location);
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} ${time.timeZoneName}';
  }
}

String formatUtcOffset(Duration offset) {
  final seconds = offset.inSeconds.abs();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'UTC${offset.isNegative ? '-' : '+'}${two(seconds ~/ 3600)}:'
      '${two(seconds ~/ 60 % 60)}${seconds % 60 == 0 ? '' : ':${two(seconds % 60)}'}';
}
