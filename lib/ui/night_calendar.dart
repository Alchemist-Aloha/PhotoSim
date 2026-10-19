import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/local_time.dart';
import '../core/night_rating.dart';
import '../data/night_conditions.dart';
import '../models/simulation_state.dart';

class NightCalendar extends StatefulWidget {
  const NightCalendar({
    super.key,
    required this.state,
    required this.weekView,
    required this.repository,
    required this.onPreview,
    this.initialDate,
    this.onDateChanged,
  });
  final SimulationState state;
  final bool weekView;
  final NightConditionsRepository repository;
  final ValueChanged<DateTime> onPreview;
  final DateTime? initialDate;
  final ValueChanged<DateTime>? onDateChanged;

  @override
  State<NightCalendar> createState() => _NightCalendarState();
}

class _NightCalendarState extends State<NightCalendar> {
  late DateTime selected;
  late DateTime anchor;
  List<NightRating> nights = [];
  final weatherRatings = <DateTime, NightRating>{};
  bool calculating = true, weatherLoading = false, brightnessLoading = true;
  bool weatherRequested = false;
  String? calculationError, weatherError, brightnessError;
  NightForecast? forecast;
  SiteBrightness? brightness;
  int generation = 0, siteGeneration = 0;
  Completer<void> stop = Completer<void>();
  final detailsKey = GlobalKey();

  DateTime dateOf(DateTime time) =>
      DateTime.utc(time.year, time.month, time.day);
  bool get supported => selected.year >= 1970 && selected.year <= 2037;
  DateTime get firstDate {
    final first = widget.weekView
        ? anchor
        : DateTime.utc(anchor.year, anchor.month);
    return first.subtract(Duration(days: first.weekday - 1));
  }

  int get days => widget.weekView
      ? 7
      : ((DateTime.utc(
                      anchor.year,
                      anchor.month + 1,
                    ).difference(firstDate).inDays +
                    6) ~/
                7) *
            7;

  @override
  void initState() {
    super.initState();
    final local = localClock(
      timestamp: widget.state.timestamp,
      latitude: widget.state.latitude,
      longitude: widget.state.longitude,
    ).time;
    selected = dateOf(local ?? widget.state.timestamp);
    if (local != null && local.hour < 1) {
      selected = selected.subtract(const Duration(days: 1));
    }
    selected = widget.initialDate ?? selected;
    anchor = selected;
    unawaited(reload());
    unawaited(loadBrightness());
  }

  @override
  void didUpdateWidget(covariant NightCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.state, next = widget.state;
    if (old.location != next.location) {
      stop.complete();
      stop = Completer<void>();
      siteGeneration++;
      forecast = null;
      weatherRatings.clear();
      brightness = null;
      weatherRequested = false;
      weatherLoading = false;
      weatherError = null;
      brightnessError = null;
      nights = [];
      unawaited(loadBrightness());
      unawaited(reload());
    } else if (oldWidget.weekView != widget.weekView ||
        old.cameraElevation != next.cameraElevation) {
      unawaited(reload());
    }
  }

  Future<void> reload() async {
    final id = ++generation;
    if (!supported) {
      setState(() => calculating = false);
      return;
    }
    setState(() {
      calculating = true;
      calculationError = null;
    });
    unawaited(loadWeather());
    try {
      final result = await compute(
        calculateNightCalendar,
        NightCalendarRequest(
          startDate: firstDate,
          days: days,
          latitude: widget.state.latitude,
          longitude: widget.state.longitude,
          elevation: widget.state.cameraElevation ?? widget.state.height,
        ),
      );
      if (mounted && generation == id) {
        setState(() {
          nights = result;
          weatherRatings.clear();
          calculating = false;
        });
      }
    } catch (_) {
      if (mounted && generation == id) {
        setState(() {
          calculationError =
              'Could not calculate this month. Try another date or retry.';
          calculating = false;
        });
      }
    }
  }

  Future<void> loadWeather({bool refresh = false}) async {
    if (!supported || weatherLoading) return;
    final now = dateOf(widget.repository.now().toUtc());
    if (!firstDate.add(Duration(days: days + 1)).isAfter(now) ||
        firstDate.isAfter(now.add(const Duration(days: 16)))) {
      return;
    }
    if (!refresh &&
        weatherRequested &&
        (forecast == null ||
            widget.repository.now().difference(forecast!.fetchedAt).inMinutes <
                60)) {
      return;
    }
    final id = siteGeneration;
    setState(() {
      weatherLoading = true;
      weatherRequested = true;
      weatherError = null;
    });
    try {
      final result = await widget.repository.forecast(
        widget.state.latitude,
        widget.state.longitude,
        abort: stop.future,
        refresh: refresh,
      );
      if (mounted && id == siteGeneration) {
        setState(() {
          forecast = result;
          weatherRatings.clear();
          weatherLoading = false;
        });
      }
    } catch (_) {
      if (mounted && id == siteGeneration) {
        setState(() {
          weatherLoading = false;
          weatherError = forecast == null
              ? 'Weather unavailable. Check your connection and retry.'
              : 'Refresh failed; the previously fetched forecast is still shown.';
        });
      }
    }
  }

  Future<void> loadBrightness() async {
    final id = siteGeneration;
    setState(() {
      brightnessLoading = true;
      brightnessError = null;
    });
    try {
      final result = await widget.repository.brightness(
        widget.state.latitude,
        widget.state.longitude,
        abort: stop.future,
      );
      if (mounted && id == siteGeneration) {
        setState(() {
          brightness = result;
          brightnessLoading = false;
          if (result == null) {
            brightnessError = 'Outside atlas coverage (65°S–75°N).';
          }
        });
      }
    } catch (_) {
      if (mounted && id == siteGeneration) {
        setState(() {
          brightnessLoading = false;
          brightnessError =
              'Sky brightness unavailable. Check your connection and retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    stop.complete();
    super.dispose();
  }

  void select(DateTime date) {
    if (date.year < 1970 || date.year > 2037) return;
    final oldFirst = firstDate;
    setState(() {
      selected = date;
      anchor = date;
    });
    widget.onDateChanged?.call(selected);
    if (firstDate != oldFirst) unawaited(reload());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = detailsKey.currentContext;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
          ),
        );
      }
    });
  }

  Future<void> pickNight() async {
    final today = localClock(
      timestamp: widget.repository.now(),
      latitude: widget.state.latitude,
      longitude: widget.state.longitude,
    ).time;
    final date = await showDatePicker(
      context: context,
      helpText: 'Choose local evening',
      initialDate: selected,
      currentDate: today == null ? null : dateOf(today),
      firstDate: DateTime(1970),
      lastDate: DateTime(2037, 12, 31),
    );
    if (date != null && mounted) select(dateOf(date));
  }

  DateTime adjacent(int direction) {
    if (widget.weekView) return anchor.add(Duration(days: 7 * direction));
    final month = DateTime.utc(anchor.year, anchor.month + direction);
    return DateTime.utc(
      month.year,
      month.month,
      math.min(selected.day, DateTime.utc(month.year, month.month + 1, 0).day),
    );
  }

  void move(int direction) {
    final next = adjacent(direction);
    if (next.year < 1970 || next.year > 2037) return;
    setState(() {
      selected = next;
      anchor = next;
    });
    widget.onDateChanged?.call(selected);
    unawaited(reload());
  }

  WindowWeather? weather(NightRating? night) {
    final window = night?.window;
    final range = window == null
        ? night?.darkness
        : (start: window.start, end: window.end);
    return range == null || forecast == null
        ? null
        : windowWeather(range.start, range.end, forecast!);
  }

  NightRating? rating(DateTime date) {
    for (final night in nights) {
      if (night.date == date) {
        return forecast == null
            ? night
            : weatherRatings.putIfAbsent(
                date,
                () => rateNightWithForecast(night, forecast!),
              );
      }
    }
    return null;
  }

  String scoreLabel(NightRating? night) {
    final adjusted = night?.weatherScore;
    return adjusted != null
        ? '$adjusted W'
        : night?.score == null
        ? '—'
        : '${night!.score} A';
  }

  String localTime(DateTime utc) {
    final time = localClock(
      timestamp: utc,
      latitude: widget.state.latitude,
      longitude: widget.state.longitude,
    ).time;
    return time == null
        ? '${utc.toIso8601String().substring(0, 16)} UTC'
        : '${time.toIso8601String().substring(0, 16).replaceAll('T', ' ')} ${time.timeZoneName}';
  }

  Widget calendarGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final measure = TextPainter(
        text: TextSpan(
          text: '100',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = math.max(
        7.0 * math.max(48.0, measure.width + 10),
        constraints.maxWidth,
      );
      measure.dispose();
      final localizations = MaterialLocalizations.of(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (width > constraints.maxWidth)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Swipe horizontally to see all weekdays'),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final day in [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              day,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisExtent: math.max(
                        84,
                        MediaQuery.textScalerOf(context).scale(14) * 4 + 16,
                      ),
                    ),
                    itemCount: days,
                    itemBuilder: (context, index) {
                      final date = firstDate.add(Duration(days: index));
                      final night = rating(date);
                      final label = scoreLabel(night);
                      final chosen = date == selected;
                      final colors = Theme.of(context).colorScheme;
                      return Padding(
                        padding: const EdgeInsets.all(1),
                        child: Semantics(
                          button: true,
                          onTap: date.year < 1970 || date.year > 2037
                              ? null
                              : () => select(date),
                          selected: chosen,
                          label:
                              '${localizations.formatFullDate(date)}. ${night?.reason ?? 'Calculation pending'}. Score $label. A means astronomy only; W means weather-adjusted.',
                          excludeSemantics: true,
                          child: Material(
                            color: chosen
                                ? colors.primaryContainer
                                : colors.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: chosen
                                    ? colors.primary
                                    : colors.outlineVariant,
                                width: chosen ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey(
                                'night-${date.toIso8601String().substring(0, 10)}',
                              ),
                              onTap: date.year < 1970 || date.year > 2037
                                  ? null
                                  : () => select(date),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 6,
                                ),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${date.day}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: chosen
                                                ? colors.onPrimaryContainer
                                                : date.month == anchor.month
                                                ? colors.onSurface
                                                : colors.onSurfaceVariant,
                                          ),
                                    ),
                                    Text(
                                      label.split(' ').first,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: chosen
                                                ? colors.onPrimaryContainer
                                                : colors.onSurface,
                                          ),
                                    ),
                                    Text(
                                      label.contains(' ')
                                          ? label.split(' ').last
                                          : ' ',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: chosen
                                                ? colors.onPrimaryContainer
                                                : colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget weekAgenda() => Column(
    children: List.generate(7, (index) {
      final date = firstDate.add(Duration(days: index));
      final night = rating(date);
      final window = night?.window;
      return ListTile(
        key: ValueKey('night-${date.toIso8601String().substring(0, 10)}'),
        selected: date == selected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        title: Text(MaterialLocalizations.of(context).formatMediumDate(date)),
        subtitle: Text(
          window == null
              ? night?.reason ?? 'Calculating…'
              : '${window.minutes} min · ${localTime(window.start)}',
        ),
        trailing: Text(
          scoreLabel(night),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        onTap: () => select(date),
      );
    }),
  );

  Widget details() {
    final night = rating(selected);
    final window = night?.window;
    final previewTime = night?.geometryPreviewTime;
    final conditions = weather(night);
    final adjusted = night?.weatherScore;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      key: detailsKey,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            MaterialLocalizations.of(context).formatFullDate(selected),
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            night == null
                ? calculating
                      ? 'Calculating night…'
                      : calculationError ?? 'Night unavailable'
                : night.reason,
            style: textTheme.titleMedium,
          ),
          if (night?.score != null)
            Text(
              'Astronomy: ${night!.score}/100${adjusted == null ? ' · Weather not rated' : ' · Weather-adjusted: $adjusted/100'}',
            ),
          const SizedBox(height: 16),
          if (window != null) ...[
            Text(
              '${adjusted == null ? 'Best astronomy window' : 'Best weather-adjusted window'} · ${window.minutes} minutes',
              style: textTheme.titleMedium,
            ),
            Text('${localTime(window.start)}\nto ${localTime(window.end)}'),
            Text('Recommended time: ${localTime(window.bestTime)}'),
            const SizedBox(height: 8),
            Text(
              'Mean visible Milky Way at 0–30°: ${(window.lowMilkyWayFraction * 100).toStringAsFixed(1)}%\nCore altitude at that time: ${window.coreAltitude.toStringAsFixed(1)}°\nMoon below horizontal · ${(window.moonIllumination * 100).round()}% illuminated\nMinimum Moon–core separation ${window.moonSeparation.toStringAsFixed(1)}° (not limiting while Moon is below horizon)',
            ),
            const SizedBox(height: 8),
            Text(
              'Calculator: duration ${window.durationPoints}/50 + mean low Milky Way ${window.lowBandPoints}/50. A two-hour window with all the visible band at 0–30° reaches 100. Band percentage averages the interval endpoints by arc length, not brightness or camera framing.',
            ),
          ],
          if (previewTime != null) ...[
            const SizedBox(height: 12),
            Text('Geometry preview time: ${localTime(previewTime)}'),
            FilledButton.icon(
              onPressed: () => widget.onPreview(previewTime),
              icon: const Icon(Icons.landscape),
              label: const Text('Preview best geometry'),
            ),
            if (night?.score == 0 || adjusted == 0)
              const Text(
                'Geometry preview only; this night still has a zero rating.',
              ),
          ],
          if (window != null || night?.darkness != null) ...[
            const SizedBox(height: 16),
            Text(
              window == null
                  ? 'Weather during the dark period'
                  : 'Weather during this window',
              style: textTheme.titleMedium,
            ),
            if (window == null && night?.darkness != null)
              Text(
                '${localTime(night!.darkness!.start)} to ${localTime(night.darkness!.end)}',
              ),
            Text(
              weatherLoading && forecast == null
                  ? 'Fetching forecast…'
                  : conditions?.cloud == null
                  ? 'No forecast for this window. Unknown does not mean clear.'
                  : '${conditions!.complete ? '' : 'Partial coverage · '}${conditions.cloud!.round()}% mean cloud · ${(conditions.coverage * 100).round()}% window covered',
            ),
            if (conditions?.highCloud != null)
              Text('High cloud up to ${conditions!.highCloud!.round()}%'),
            if (conditions?.visibility != null)
              Text(
                'Minimum visibility ${(conditions!.visibility! / 1000).toStringAsFixed(1)} km',
              ),
            if (conditions?.gusts != null)
              Text('Gusts up to ${conditions!.gusts!.toStringAsFixed(0)} km/h'),
            if (conditions?.dewMargin != null)
              Text(
                'Temperature above dew point: at least ${conditions!.dewMargin!.toStringAsFixed(1)}°C${conditions.dewMargin! < 3 ? ' · dew risk' : ''}',
              ),
            if (conditions?.rainProbability != null)
              Text(
                'Rain probability up to ${conditions!.rainProbability!.round()}%',
              ),
            if (conditions?.complete == true)
              Text(
                conditions!.cloud! <= 20
                    ? 'Promising cloud forecast; verify before travel.'
                    : conditions.cloud! >= 60
                    ? 'Clouds are likely to obscure much of the sky.'
                    : 'Cloud cover may limit photography.',
              ),
          ],
          if (forecast != null) ...[
            const SizedBox(height: 8),
            Text(
              'Open-Meteo · fetched ${forecast!.fetchedAt.toIso8601String().substring(0, 16).replaceAll('T', ' ')} UTC',
              style: textTheme.bodySmall,
            ),
            const Text(
              'Hourly predictions, not certainty. Long-range forecasts are tentative. W weights duration by mean clear-sky fraction and band geometry by simultaneous clear-sky fraction; it is not a probability.',
            ),
          ],
          if (weatherError != null)
            Text(
              weatherError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          Text('Light pollution · site baseline', style: textTheme.titleMedium),
          Text(
            brightnessLoading
                ? 'Fetching atlas tile…'
                : brightness == null
                ? brightnessError ?? 'Sky brightness unknown'
                : 'Modeled zenith: ${brightness!.sqm.toStringAsFixed(2)} mag/arcsec²\nArtificial / natural light: ${brightness!.ratio.toStringAsFixed(2)}×',
          ),
          const Text(
            'Bortle: not inferred. Zenith brightness is not the whole-sky Bortle scale. City light domes toward the core may differ.',
          ),
          const SizedBox(height: 8),
          const SelectableText(
            'David Lorenz · $atlasYear Light Pollution Atlas\nhttps://djlorenz.github.io/astronomy/lp/',
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: weatherLoading || brightnessLoading
                    ? null
                    : () {
                        unawaited(loadWeather(refresh: true));
                        unawaited(loadBrightness());
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh conditions'),
              ),
              TextButton(
                onPressed: showMethod,
                child: const Text('Criteria & sources'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void showMethod() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Night rating & sources'),
      content: const SelectableText(
        'Each date means that local evening through 01:00 the next day, not the following morning’s entire night. Preview best geometry aims at the visible Galactic equator near 15° elevation (or lower when the band stays low), on the branch nearest your current bearing. It preserves location and lens. Rated windows use their recommended time. Without a qualifying window, preview uses the strongest low band in darkness, then below-horizon Sun, then the sampled evening; it does not change the rating or override sky lighting.\n\n'
        'At the same time: Sun ≤ −18°, some visible Milky Way at 0–30°, and Moon center ≤ 0°. A below-horizon Moon is not penalized for phase or Moon–core separation; separation is informational only. Moon-above-horizon periods are conservatively excluded, not graded by phase. This uses the airless Moon center, not terrain or refracted upper-limb setting. Score weights are planning heuristics, not calibrated visibility predictions.\n\n'
        'Ten-minute sampling finds continuous qualifying intervals. All subwindows compete by score, with longer duration breaking ties, then earlier start. Band points use the mean of interval-endpoint percentages, not a single peak. The band is the zero-width Galactic equator measured by arc length, not brightness or camera framing. The recommended time starts the interval with the highest band percentage, weighted by clear sky when weather is complete. Core altitude neither earns points nor blocks ratings. A means astronomy only. W requires cloud data for every eligible interval that night, so unknown intervals are not silently discarded. Missing or partial forecasts keep astronomy-only selection.\n\n'
        'Airless geometric positions: no refraction, terrain horizon, tree/building obstruction, smoke or directional light-dome prediction. Prefer a core above 20–30°, dry transparent air, low wind, no thin cloud, and adequate dew protection.\n\n'
        'Weather: Open-Meteo, CC BY 4.0, free non-commercial API; up to 16 days including today, subject to returned data coverage. https://open-meteo.com/\n\n'
        'Sky brightness: David Lorenz’s 2025 numerical atlas tiles, approximately 1/120° resolution, 65°S–75°N. Modeled annual zenith brightness, not live readings or Bortle classes. https://djlorenz.github.io/astronomy/lp/\n\n'
        'Astronomy runs offline. Calendar weather requests send the selected coordinates to Open-Meteo; atlas requests identify a regional 5° tile. No API keys are used.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Local-night calendar supports 1970–2037. Map and 3D retain their full UTC date range.',
              ),
              TextButton(
                onPressed: () {
                  final time = localClock(
                    timestamp: widget.repository.now(),
                    latitude: widget.state.latitude,
                    longitude: widget.state.longitude,
                  ).time;
                  if (time != null) {
                    setState(() {
                      selected = dateOf(time);
                      anchor = selected;
                    });
                    widget.onDateChanged?.call(selected);
                    unawaited(reload());
                  }
                },
                child: const Text('Show current month'),
              ),
            ],
          ),
        ),
      );
    }
    final localizations = MaterialLocalizations.of(context);
    final zone = localClock(
      timestamp: DateTime.utc(2000),
      latitude: widget.state.latitude,
      longitude: widget.state.longitude,
    ).zoneId;
    final title = widget.weekView
        ? '${firstDate.year} · ${localizations.formatMediumDate(firstDate)} – ${localizations.formatMediumDate(firstDate.add(const Duration(days: 6)))}'
        : localizations.formatMonthYear(anchor);
    final calendar = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: widget.weekView ? 'Previous week' : 'Previous month',
                onPressed: adjacent(-1).year < 1970 ? null : () => move(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: pickNight,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: widget.weekView ? 'Next week' : 'Next month',
                onPressed: adjacent(1).year > 2037 ? null : () => move(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${widget.state.latitude.toStringAsFixed(4)}°, ${widget.state.longitude.toStringAsFixed(4)}° · $zone\nLocal evenings → 01:00 · A: astronomy only · W: weather-adjusted',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (calculating) const LinearProgressIndicator(),
        if (calculationError != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton(
              onPressed: reload,
              child: Text(calculationError!),
            ),
          ),
        if (widget.weekView)
          weekAgenda()
        else
          Padding(padding: const EdgeInsets.all(8), child: calendarGrid()),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) => bounds.maxWidth >= 900
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: SingleChildScrollView(child: calendar)),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(child: details()),
                ),
              ],
            )
          : SingleChildScrollView(
              child: Column(children: [calendar, const Divider(), details()]),
            ),
    );
  }
}
