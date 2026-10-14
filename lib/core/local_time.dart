import 'package:lat_lng_to_timezone/lat_lng_to_timezone.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

final _locations = _loadLocations();
Map<String, tz.Location> _loadLocations() {
  data.initializeTimeZones();
  return tz.timeZoneDatabase.locations;
}

/// Presentation only: never use these wall-clock fields as simulation timestamps.
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

String formatUtcOffset(Duration offset) {
  final seconds = offset.inSeconds.abs();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'UTC${offset.isNegative ? '-' : '+'}${two(seconds ~/ 3600)}:'
      '${two(seconds ~/ 60 % 60)}${seconds % 60 == 0 ? '' : ':${two(seconds % 60)}'}';
}
