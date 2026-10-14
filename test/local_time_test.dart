import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/core/local_time.dart';

void main() {
  test('offline lookup covers several zones and fractional offsets', () {
    final utc = DateTime.utc(2026, 6, 21, 19);
    for (final entry in [
      (37.744, -119.59, 'America/Los_Angeles', -420),
      (51.5, 0.0, 'Europe/London', 60),
      (27.7172, 85.3240, 'Asia/Kathmandu', 345),
      (-33.86, 151.21, 'Australia/Sydney', 600),
      (35.68, 139.69, 'Asia/Tokyo', 540),
    ]) {
      final clock = localClock(
        timestamp: utc,
        latitude: entry.$1,
        longitude: entry.$2,
      );
      expect(clock.zoneId, entry.$3);
      expect(clock.warning, isNull);
      expect(clock.time!.timeZoneOffset.inMinutes, entry.$4);
      expect(clock.time!.toUtc(), utc);
    }
    final summer = localClock(
      timestamp: utc,
      latitude: 37.744,
      longitude: -119.59,
    ).time!;
    final winter = localClock(
      timestamp: DateTime.utc(2026, 1, 21, 19),
      latitude: 37.744,
      longitude: -119.59,
    ).time!;
    expect(summer.hour, 12);
    expect(summer.timeZoneName, 'PDT');
    expect(winter.hour, 11);
    expect(winter.timeZoneName, 'PST');
  });

  test('US spring gap and autumn fold retain distinct UTC instants', () {
    final before = localClock(
      timestamp: DateTime.utc(2026, 3, 8, 9, 59),
      latitude: 37.744,
      longitude: -119.59,
    ).time!;
    final after = localClock(
      timestamp: DateTime.utc(2026, 3, 8, 10),
      latitude: 37.744,
      longitude: -119.59,
    ).time!;
    expect(before.hour, 1);
    expect(before.minute, 59);
    expect(after.hour, 3);
    expect(after.difference(before), const Duration(minutes: 1));
    final first = localClock(
      timestamp: DateTime.utc(2026, 11, 1, 8, 30),
      latitude: 37.744,
      longitude: -119.59,
    ).time!;
    final second = localClock(
      timestamp: DateTime.utc(2026, 11, 1, 9, 30),
      latitude: 37.744,
      longitude: -119.59,
    ).time!;
    expect(first.hour, 1);
    expect(second.hour, 1);
    expect(first.timeZoneName, 'PDT');
    expect(second.timeZoneName, 'PST');
    expect(second.difference(first), const Duration(hours: 1));
  });

  test('European and southern-hemisphere DST changes use location rules', () {
    final london = localClock(
      timestamp: DateTime.utc(2026, 3, 29, 1),
      latitude: 51.5,
      longitude: 0,
    ).time!;
    expect(london.hour, 2);
    expect(london.timeZoneName, 'BST');
    final sydney = localClock(
      timestamp: DateTime.utc(2026, 10, 3, 16),
      latitude: -33.86,
      longitude: 151.21,
    ).time!;
    expect(sydney.day, 4);
    expect(sydney.hour, 3);
    expect(sydney.timeZoneName, 'AEDT');
  });

  test('local date rollover and offset input leave the instant unchanged', () {
    final utc = DateTime.utc(2026, 1, 1, 1);
    final clock = localClock(
      timestamp: utc,
      latitude: 37.744,
      longitude: -119.59,
    );
    expect(clock.time!.year, 2025);
    expect(clock.time!.day, 31);
    final offset = localClock(
      timestamp: DateTime.parse('2025-12-31T17:00:00-08:00'),
      latitude: 37.744,
      longitude: -119.59,
    );
    expect(offset.time, clock.time);
    expect(offset.time!.toUtc(), utc);
  });

  test(
    'unsupported rule years fail explicitly instead of using a stale offset',
    () {
      for (final year in [1900, 1969, 2038, 2100]) {
        final clock = localClock(
          timestamp: DateTime.utc(year, 7),
          latitude: 37.744,
          longitude: -119.59,
        );
        expect(clock.time, isNull);
        expect(clock.warning, contains('1970–2037'));
        expect(clock.zoneId, 'America/Los_Angeles');
      }
      for (final year in [1970, 2037]) {
        expect(
          localClock(
            timestamp: DateTime.utc(year, 7),
            latitude: 37.744,
            longitude: -119.59,
          ).time,
          isNotNull,
        );
      }
    },
  );

  test('offset formatting includes fractional and historical seconds', () {
    expect(formatUtcOffset(Duration.zero), 'UTC+00:00');
    expect(formatUtcOffset(const Duration(hours: -7)), 'UTC-07:00');
    expect(formatUtcOffset(const Duration(hours: 5, minutes: 45)), 'UTC+05:45');
    expect(
      formatUtcOffset(const Duration(hours: 5, minutes: 41, seconds: 16)),
      'UTC+05:41:16',
    );
  });

  test('invalid geographic inputs are rejected', () {
    for (final p in [
      (double.nan, 0.0),
      (91.0, 0.0),
      (0.0, 181.0),
      (0.0, double.infinity),
    ]) {
      expect(
        () => localClock(
          timestamp: DateTime.utc(2026),
          latitude: p.$1,
          longitude: p.$2,
        ),
        throwsArgumentError,
      );
    }
  });
}
