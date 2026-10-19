import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:photosim/core/geo.dart';
import 'package:photosim/core/astronomy.dart';
import 'package:photosim/core/local_time.dart';
import 'package:photosim/core/night_rating.dart';
import 'package:photosim/core/night_sky.dart';

NightSample sample(
  DateTime utc, {
  double sun = -20,
  double core = 45,
  double lowBand = 1,
  double moon = -10,
  double separation = 90,
  double illumination = 0.2,
}) => NightSample(
  utc: utc,
  sunAltitude: sun,
  coreAltitude: core,
  lowMilkyWayFraction: lowBand,
  moonAltitude: moon,
  moonSeparation: separation,
  moonIllumination: illumination,
);

void main() {
  final date = DateTime.utc(2026, 6, 15);
  test('low-band fraction matches uniform Galactic-equator arc sampling', () {
    final ra = 192.85948 * radians, dec = 27.12825 * radians;
    final pole = Vector3(
      math.cos(dec) * math.cos(ra),
      math.cos(dec) * math.sin(ra),
      math.sin(dec),
    );
    final u = Vector3(-math.sin(ra), math.cos(ra), 0);
    final v = pole.cross(u);
    final fractions = <double>[];
    for (final site in [
      (37.744, -119.59),
      (0.0, 0.0),
      (27.12825, 90.0),
      (-70.0, 60.0),
    ]) {
      for (final hour in [0, 6, 12, 18]) {
        final frame = ObserverSkyFrame(
          timestamp: date.add(Duration(hours: hour)),
          latitude: site.$1,
          longitude: site.$2,
        );
        var visible = 0, low = 0;
        for (var i = 0; i < 3600; i++) {
          final angle = i * 2 * math.pi / 3600;
          final point = u.scaled(math.cos(angle)) + v.scaled(math.sin(angle));
          final direction = frame.direction(
            math.atan2(point.y, point.x),
            math.asin(point.z.clamp(-1.0, 1.0)),
          );
          if (direction.y > 0) {
            visible++;
            if (direction.y < 0.5) low++;
          }
        }
        expect(frame.lowMilkyWayFraction, closeTo(low / visible, 0.001));
        expect(frame.lowMilkyWayFraction, inInclusiveRange(1 / 3, 1));
        fractions.add(frame.lowMilkyWayFraction);
      }
    }
    expect(fractions.any((fraction) => fraction > 0.99), isTrue);
    expect(fractions.any((fraction) => fraction < 0.35), isTrue);
  });
  test('best time and equal-duration windows prefer low-band percentage, not core altitude', () {
    final night = rateNight(date, [
      sample(date, core: 80, lowBand: 0.4),
      sample(date.add(const Duration(minutes: 10)), core: 5, lowBand: 0.8),
      sample(date.add(const Duration(minutes: 20)), core: 85, lowBand: 1),
    ]);
    expect(night.window!.bestTime, date.add(const Duration(minutes: 10)));
    expect(night.window!.coreAltitude, 5);
    expect(night.window!.lowMilkyWayFraction, 0.9);
    expect(night.window!.lowBandPoints, 45);
    expect(night.window!.minutes, 10);
    final tied = rateNight(date, [
      sample(date, core: 80, lowBand: 0.4),
      sample(date.add(const Duration(minutes: 10)), core: 80, lowBand: 0.4),
      sample(date.add(const Duration(minutes: 20)), moon: 10),
      sample(date.add(const Duration(minutes: 30)), core: 5, lowBand: 0.8),
      sample(date.add(const Duration(minutes: 40)), core: 5, lowBand: 0.8),
    ]);
    expect(tied.window!.start, date.add(const Duration(minutes: 30)));
  });
  test(
    'higher score beats a longer window and band points use interval averages',
    () {
      final long = List.generate(
        19,
        (i) => sample(date.add(Duration(minutes: i * 10)), lowBand: 1 / 3),
      );
      final short = List.generate(
        13,
        (i) => sample(date.add(Duration(minutes: 200 + i * 10))),
      );
      final chosen = rateNight(date, [
        ...long,
        sample(date.add(const Duration(minutes: 190)), moon: 10),
        ...short,
      ]);
      expect(chosen.score, 100);
      expect(chosen.window!.start, short.first.utc);
      expect(chosen.window!.minutes, 120);
      final briefPeak = rateNight(
        date,
        List.generate(
          13,
          (i) => sample(
            date.add(Duration(minutes: i * 10)),
            lowBand: i == 0 ? 1 : 1 / 3,
          ),
        ),
      );
      expect(briefPeak.score, 68);
      expect(briefPeak.window!.lowMilkyWayFraction, closeTo(13 / 36, 1e-10));
      final middlePeak = rateNight(date, [
        sample(date, lowBand: 0.5),
        sample(date.add(const Duration(minutes: 10)), lowBand: 1),
        sample(date.add(const Duration(minutes: 20)), lowBand: 0.5),
      ]);
      expect(middlePeak.window!.lowMilkyWayFraction, 0.75);
      expect(middlePeak.window!.lowBandPoints, 38);
    },
  );
  test(
    'zero-rated nights retain geometry previews without relaxing the rating',
    () {
      for (final sun in [-20.0, -12.0]) {
        final night = rateNight(date, [
          sample(date, moon: 20, sun: sun, lowBand: 0.4),
          sample(
            date.add(const Duration(minutes: 10)),
            moon: 20,
            sun: sun,
            lowBand: 0.8,
          ),
          sample(date.add(const Duration(minutes: 20)), moon: 20, sun: sun),
        ]);
        expect(night.score, 0);
        expect(night.window, isNull);
        expect(
          night.geometryPreviewTime,
          date.add(const Duration(minutes: 10)),
        );
        expect(night.geometryPreviewTime!.isUtc, isTrue);
      }
      final daylight = rateNight(
        date,
        List.generate(
          79,
          (i) => sample(
            date.add(Duration(minutes: i * 10)),
            sun: 10,
            lowBand: i < 6 ? 1 : 0.5,
          ),
        ),
      );
      expect(daylight.score, 0);
      expect(daylight.geometryPreviewTime, date.add(const Duration(hours: 6)));
      expect(rateNight(date, []).geometryPreviewTime, isNull);
      final rated = rateNight(
        date,
        List.generate(13, (i) => sample(date.add(Duration(minutes: i * 10)))),
      );
      expect(rated.geometryPreviewTime, rated.window!.bestTime);
    },
  );
  test('Milky Way preview aim stays on the visible low band, not the core', () {
    for (final site in [(37.744, -119.59), (0.0, 0.0), (-60.0, 90.0)]) {
      for (final hour in [0, 6, 12, 18]) {
        final frame = ObserverSkyFrame(
          timestamp: date.add(Duration(hours: hour)),
          latitude: site.$1,
          longitude: site.$2,
        );
        final pole = frame.direction(192.85948 * radians, 27.12825 * radians);
        for (final bearing in [0.0, 90.0, 180.0, 270.0]) {
          final aim = frame.lowMilkyWayAim(bearing);
          expect(aim.altitude, inInclusiveRange(0, 15.000001));
          expect(aim.azimuth, inInclusiveRange(0, 360));
          final vector = Vector3(
            math.sin(aim.azimuth * radians) * math.cos(aim.altitude * radians),
            math.sin(aim.altitude * radians),
            -math.cos(aim.azimuth * radians) * math.cos(aim.altitude * radians),
          );
          expect(vector.dot(pole), closeTo(0, 1e-7));
          final opposite = frame.lowMilkyWayAim((bearing + 180) % 360);
          final facing = Vector3(
            math.sin(bearing * radians),
            0,
            -math.cos(bearing * radians),
          );
          final other = Vector3(
            math.sin(opposite.azimuth * radians) *
                math.cos(opposite.altitude * radians),
            math.sin(opposite.altitude * radians),
            -math.cos(opposite.azimuth * radians) *
                math.cos(opposite.altitude * radians),
          );
          expect(
            vector.dot(facing) + 1e-10,
            greaterThanOrEqualTo(other.dot(facing)),
          );
        }
      }
    }
  });
  test('flat-band preview stays on the horizon or below 15 degrees', () {
    final polarFrame = ObserverSkyFrame(
      timestamp: date,
      latitude: 90,
      longitude: 0,
    );
    final pole = polarFrame.position(192.85948 * radians, 27.12825 * radians);
    final longitude = (360 - pole.azimuth) % 360 - 180;
    final horizontal = ObserverSkyFrame(
      timestamp: date,
      latitude: pole.altitude,
      longitude: longitude,
    );
    final onHorizon = horizontal.lowMilkyWayAim(123);
    expect(onHorizon.altitude, closeTo(0, 1e-6));
    expect(onHorizon.azimuth, closeTo(123, 1e-6));
    final shallow = ObserverSkyFrame(
      timestamp: date,
      latitude: pole.altitude - 5,
      longitude: longitude,
    );
    expect(shallow.lowMilkyWayAim(90).altitude, closeTo(5, 1e-6));
    expect(() => shallow.lowMilkyWayAim(double.nan), throwsArgumentError);
  });
  test('joint criteria reject independently favorable but non-overlapping conditions', () {
    final night = rateNight(date, [
      sample(date, moon: 20),
      sample(date.add(const Duration(minutes: 10)), sun: -5),
    ]);
    expect(night.score, 0);
    expect(night.window, isNull);
    for (final samples in [
      [
        sample(date, sun: -17),
        sample(date.add(const Duration(minutes: 10)), sun: -17),
      ],
      [
        sample(date, lowBand: 0),
        sample(date.add(const Duration(minutes: 10)), lowBand: 0),
      ],
      [
        sample(date, moon: 1),
        sample(date.add(const Duration(minutes: 10)), moon: 1),
      ],
    ]) {
      expect(rateNight(date, samples).window, isNull);
    }
  });
  test(
    'below-horizon Moon never loses points for phase or core separation',
    () {
      for (final moon in [-80.0, -1.0, 0.0]) {
        for (final separation in [0.0, 29.0, 180.0]) {
          for (final illumination in [0.0, 0.5, 1.0]) {
            final night = rateNight(
              date,
              List.generate(
                13,
                (i) => sample(
                  date.add(Duration(minutes: i * 10)),
                  moon: moon,
                  separation: separation,
                  illumination: illumination,
                ),
              ),
            );
            expect(night.score, 100);
            expect(night.window!.minutes, 120);
            expect(night.window!.moonSeparation, separation);
            expect(night.window!.moonIllumination, illumination);
          }
        }
      }
    },
  );
  test(
    'Moon rise and set bound the window; above-horizon Moon remains excluded',
    () {
      final night = rateNight(date, [
        sample(date, moon: 0.01, separation: 0),
        sample(date.add(const Duration(minutes: 10)), moon: 0, separation: 0),
        sample(date.add(const Duration(minutes: 20)), moon: -1, separation: 0),
        sample(
          date.add(const Duration(minutes: 30)),
          moon: 0.01,
          separation: 0,
        ),
      ]);
      expect(night.window!.start, date.add(const Duration(minutes: 10)));
      expect(night.window!.end, date.add(const Duration(minutes: 20)));
      for (final illumination in [0.0, 0.5, 1.0]) {
        final above = rateNight(date, [
          sample(date, moon: 0.01, illumination: illumination),
          sample(
            date.add(const Duration(minutes: 10)),
            moon: 0.01,
            illumination: illumination,
          ),
        ]);
        expect(above.score, 0);
        expect(above.reason, contains('Moon above the horizon'));
      }
    },
  );
  test('duration and low-band points are bounded and missing intervals never bridge', () {
    final samples = List.generate(
      13,
      (i) => sample(date.add(Duration(minutes: 10 * i))),
    );
    final night = rateNight(date, samples);
    expect(night.score, 100);
    expect(night.window!.minutes, 120);
    expect(night.window!.bestTime.isBefore(night.window!.end), isTrue);
    expect(night.window!.bestTime.isUtc, isTrue);
    final moonlit = rateNight(
      date,
      List.generate(
        13,
        (i) => sample(date.add(Duration(minutes: 10 * i)), moon: 10),
      ),
    );
    expect(moonlit.score, 0);
    expect(
      moonlit.darkness!.end.difference(moonlit.darkness!.start).inMinutes,
      120,
    );
    expect(rateNight(date, [samples[0]]).score, 0);
    final gap = rateNight(date, [
      samples[0],
      samples[1],
      samples[4],
      samples[5],
    ]);
    expect(gap.window!.minutes, 10);
    final low = rateNight(
      date,
      List.generate(
        13,
        (i) => sample(date.add(Duration(minutes: 10 * i)), lowBand: 1 / 3),
      ),
    );
    expect(low.score, 67);
    expect(low.window!.lowBandPoints, 17);
    for (final core in [-80.0, 0.0, 5.0]) {
      final lowCore = rateNight(
        date,
        List.generate(
          13,
          (i) => sample(date.add(Duration(minutes: 10 * i)), core: core),
        ),
      );
      expect(lowCore.score, night.score);
      expect(lowCore.window!.lowBandPoints, 50);
    }
  });
  test('real June calendar windows satisfy simultaneous geometry and local 01:00 cutoff', () {
    final nights = calculateNightCalendar(
      NightCalendarRequest(
        startDate: DateTime.utc(2026, 6, 10),
        days: 10,
        latitude: 37.744,
        longitude: -119.59,
        elevation: 1200,
      ),
    );
    expect(nights.any((n) => (n.score ?? 0) >= 65), isTrue);
    for (final night in nights) {
      final window = night.window;
      if (window == null) continue;
      expect(window.bestTime.isBefore(window.end), isTrue);
      final end = localClock(
        timestamp: window.end,
        latitude: 37.744,
        longitude: -119.59,
      ).time!;
      final cutoff = DateTime.utc(
        night.date.year,
        night.date.month,
        night.date.day + 1,
        1,
      );
      final wallEnd = DateTime.utc(
        end.year,
        end.month,
        end.day,
        end.hour,
        end.minute,
      );
      expect(wallEnd.isAfter(cutoff), isFalse);
      for (
        var utc = window.start;
        utc.isBefore(window.end);
        utc = utc.add(const Duration(minutes: 10))
      ) {
        final sky = calculateSky(
          timestamp: utc,
          latitude: 37.744,
          longitude: -119.59,
          elevation: 1200,
        );
        final frame = ObserverSkyFrame(
          timestamp: utc,
          latitude: 37.744,
          longitude: -119.59,
        );
        expect(sky.sun.altitude, lessThanOrEqualTo(-18));
        expect(frame.lowMilkyWayFraction, greaterThan(0));
        expect(sky.moon.altitude, lessThanOrEqualTo(0));
      }
    }
  });
  test('real winter nights receive positive band ratings with the core below the horizon', () {
    final nights = calculateNightCalendar(
      NightCalendarRequest(
        startDate: DateTime.utc(2026, 1, 18),
        days: 7,
        latitude: 37.744,
        longitude: -119.59,
        elevation: 1200,
      ),
    );
    final belowCore = nights
        .where((n) => n.window != null && n.window!.coreAltitude < 0)
        .toList();
    expect(belowCore, isNotEmpty);
    for (final night in belowCore) {
      expect(night.score, greaterThan(0));
      expect(night.window!.lowMilkyWayFraction, greaterThan(0));
    }
  });
  test('polar daylight, skipped civil dates, rule bounds and invalid coordinates are explicit', () {
    final polar = calculateNightCalendar(
      NightCalendarRequest(
        startDate: date,
        days: 1,
        latitude: 69.65,
        longitude: 18.95,
        elevation: 0,
      ),
    ).single;
    expect(polar.score, 0);
    expect(polar.reason, contains('No astronomical darkness'));
    for (final local in [DateTime.utc(1900), DateTime.utc(2038)]) {
      expect(
        calculateNightCalendar(
          NightCalendarRequest(
            startDate: local,
            days: 1,
            latitude: 37,
            longitude: -119,
            elevation: 0,
          ),
        ).single.score,
        isNull,
      );
    }
    expect(
      calculateNightCalendar(
        NightCalendarRequest(
          startDate: DateTime.utc(2011, 12, 30),
          days: 1,
          latitude: -13.83,
          longitude: -171.75,
          elevation: 0,
        ),
      ).single.score,
      isNull,
    );
    expect(
      () => calculateNightCalendar(
        NightCalendarRequest(
          startDate: date,
          days: 43,
          latitude: 0,
          longitude: 0,
          elevation: 0,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => calculateNightCalendar(
        NightCalendarRequest(
          startDate: date,
          days: 1,
          latitude: double.nan,
          longitude: 0,
          elevation: 0,
        ),
      ),
      throwsArgumentError,
    );
  });
  test('local-night dates remain dates across fractional offsets and DST', () {
    for (final site in [
      (DateTime.utc(2026, 11, 1), 37.744, -119.59),
      (DateTime.utc(2026, 10, 3), -31.55, 159.08),
      (date, 27.7172, 85.324),
    ]) {
      final night = calculateNightCalendar(
        NightCalendarRequest(
          startDate: site.$1,
          days: 1,
          latitude: site.$2,
          longitude: site.$3,
          elevation: 0,
        ),
      ).single;
      expect(night.date, site.$1);
      expect(night.score, isNotNull);
      if (night.window != null) {
        final local = localClock(
          timestamp: night.window!.bestTime,
          latitude: site.$2,
          longitude: site.$3,
        ).time!;
        expect(local.hour >= 12 || local.hour < 1, isTrue);
      }
    }
  });
}
