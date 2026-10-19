# Night-planning calendar

Open **Calendar** beside Map and 3D Preview. The top-right button switches
between a month grid and a seven-night agenda. Arrow buttons change the month
or week; the date heading opens a date picker. Select a date for its explanation.
On narrow windows the details are below the calendar; wider windows place them
beside it. Large text can make the month grid horizontally scrollable.

Each date means **that local evening until 01:00 the following local day**,
using the camera location's estimated timezone, not the device timezone.
Browsing does not change the saved composition or simulation clock. **Preview
best geometry** opens 3D for every calculated night, including zero-rated nights.
It aims at the visible Galactic equator near 15° elevation (or its lower peak
when the whole arc stays below 15°), choosing the branch nearest the current
camera bearing. It preserves location and lens and clears the old celestial
target rather than pointing at the core. Framing the entire arch still depends
on the chosen lens and foreground.

With an observing window, preview uses its recommended UTC time, including
weather-aware selection when available. Without a qualifying window, it chooses
the highest low-band percentage before the cutoff: first among astronomically
dark samples, then samples with the Sun below the horizon, otherwise the sampled
last seven hours of the evening. This fallback ignores Moon/weather eligibility
only for preview and **does not improve the rating or override sky lighting**.
The preview time and a zero-rating warning are shown. Unsupported local dates or
failed calculations have no valid geometry preview.

## Astronomy and scoring

Calculations run locally in an isolate, sampling every ten minutes from local
noon to the next 01:00. A joint observing window requires all three conditions:

- Sun center at or below −18° (astronomical darkness).
- A nonzero percentage of the visible Milky Way between 0° and 30° elevation.
- Moon center at or below the horizontal plane.

Every contiguous subwindow competes by score, with longer duration breaking ties,
then earlier start. At least two adjacent samples are needed. The astronomy score
is duration / 120 minutes × 50, capped at 50, plus **mean visible Milky Way percentage
between 0° and 30° × 50**. The mean uses trapezoidal integration: each ten-minute
interval averages its two endpoint percentages, then intervals are averaged over
the window. One brief peak no longer earns full band points for a whole night.
Both components and the mean percentage are displayed. The recommended time starts
the strongest ten-minute interval, always before the window endpoint.
Core altitude is diagnostic only: a core below the horizon does not force a zero
rating or disable the geometry preview.

The band is approximated by the zero-width IAU Galactic equator, weighted by arc
length, not brightness, band area or camera framing. The denominator is its
above-horizon half, excluding the portion below the horizon. For the Galactic
north pole's local vertical component `p`, the circle has vertical amplitude
`A = sqrt(1 − p²)`; its low-band fraction is `2 × asin(0.5 / A) / π`
when `A > 0.5`, otherwise 1. This analytic calculation avoids discretization
along the band; time is still sampled every ten minutes. The labels describe
geometry, not a calibrated probability of a good photograph.

Moon illumination and minimum Moon–core separation are informational: neither
reduces the score or rejects a window when the Moon is below the horizon. The
old 30° separation veto has been removed. Moon-above-horizon samples remain
conservatively excluded regardless of phase, rather than receiving a graded
moonlight penalty. The horizon test uses the **airless Moon center at ≤0°**;
it does not model refraction, upper-limb setting, terrain shielding or lingering
near-horizon atmospheric glow.
A long continuous window and darkness help; terrain,
refraction, smoke, transparency, directional light domes and real sky conditions
still matter. This is an approximate ten-minute planner, not exact rise/set or
terrain-horizon prediction. Existing [astronomy limitations](astronomy.md) apply.

Calendar local-time support is **1970–2037**. An ambiguous 01:00 cutoff uses its first occurrence; a skipped 01:00
normalizes to the next valid instant. A skipped whole date or unavailable rules
produce no rated window. Map/3D retain their wider UTC range. A calendar opened outside
the supported years offers **Show current month** without changing shared time.

## Keyless weather

[Open-Meteo](https://open-meteo.com/en/docs) supplies up to 16 forecast days,
including today (about 15 days ahead). Requests explicitly use UTC Unix timestamps,
Celsius and km/h. Hourly cloud cover is interval-weighted over the selected window;
if no joint window exists, available darkness is used for the weather readout.
High cloud, visibility, gusts, dew margin and rain probability add context.

**A** means astronomy only. **W** uses `clear = 1 − cloud / 100` and scores
`durationPoints × mean(clear) + 50 × mean(bandFraction × clear)`. Band and clear-sky
fractions are paired in the same ten-minute intervals, so good geometry during
cloudy periods cannot borrow clear skies from a different time.

When cloud data covers **every eligible interval that night**, all subwindows are
ranked by W and the recommended time starts the interval with the highest
`bandFraction × clear`. The window's astronomy score is shown separately. Missing
or partial forecasts keep astronomy-only window/time selection and an A label;
unknown intervals are never discarded to manufacture a weather recommendation.
Weather summaries still show available coverage. Hourly clouds are weighted by
their actual overlap with each ten-minute interval. Forecasts do not change illustrative 3D weather
presets. Long-range predictions are tentative; check again before travelling.

The free endpoint is for **non-commercial use**, subject to its usage limits and
[terms](https://open-meteo.com/en/terms). Weather attribution is CC BY 4.0;
PhotoSim modifies the hourly data into summaries and heuristic scores.

Alternative investigated: [MET Norway Locationforecast](https://api.met.no/doc/locationforecast/HowTO)
is also keyless but offers approximately nine days, shorter than the requested
horizon, and requires an identifying User-Agent/contact. It is not integrated;
PhotoSim does not silently switch providers.

## Keyless light-pollution estimate

[David Lorenz's 2025 Light Pollution Atlas](https://djlorenz.github.io/astronomy/lp/)
serves numerical tiles for its [interactive atlas](https://djlorenz.github.io/astronomy/lp/overlay/dark.html).
PhotoSim requests the selected location's 5° tile and decodes its numerical
artificial/natural light ratio at approximately 1/120° resolution. It reports
modeled overhead brightness using the author's conversion:

`SQM = 22 − (2.5 / ln(10)) × ln(1 + ratio)`

This is a **2025 modeled site baseline**, not a live sky measurement or a forecast.
Coverage is 65°S through below 75°N. Outside coverage, corrupt data or service
failure leaves brightness unknown. No account, API key, map-color scraping or
city-center substitution is required.

**Bortle is deliberately not inferred.** Zenith SQM is not a whole-sky visual
Bortle assessment; identical overhead brightness can conceal different light domes
toward the core. The displayed baseline does not silently modify the night score.

## Network and checks

Astronomy works offline. Opening Calendar requests weather for nearby forecast
dates and a regional atlas tile. Open-Meteo receives the selected coordinates
rounded to four decimal places; GitHub Pages receives the atlas tile identifier.
Neither receives saved plans. The in-app **Criteria & sources** explains this.
Requests are abortable, time/size bounded and retain existing HTTP backoff.
Per repository, memory caches retain at most four hourly forecasts (one-hour TTL)
and four decoded atlas tiles; no calendar data is written to disk. Refresh bypasses
the weather TTL. Failed sources remain independently unavailable.

`test/night_rating_test.dart`, `test/night_conditions_test.dart` and
`test/night_calendar_test.dart` cover scoring, UTC/local boundaries, missing data,
weighted coverage, atlas corruption, navigation, shared state and accessible layouts.
`integration_test/calendar_test.dart` exercises native navigation and live sources;
its Linux run writes captures under `build/validation/linux-calendar-*.png`.

The low-band scoring update passed 196 tests and static analysis, and its release
APK compiled. Live Linux rechecks were blocked by an Open-Meteo request timeout,
then a non-JSON `allEndpointsUnavailable` response; those attempts are not native
workflow passes. Logs are under `build/validation/low-band-*.log`.

Removing the core-visibility gate passed 197 tests and static analysis, including
real winter nights with below-horizon cores and positive band ratings. The APK
was rebuilt; native workflows were not rerun for this change. Evidence is under
`build/validation/band-only-*.log`.

The below-horizon Moon correction passed 199 tests and static analysis; its APK
was rebuilt. Tests cover all lunar phases, close core separations and sampled
moonrise/moonset boundaries. Native workflows were not rerun. Evidence is under
`build/validation/moon-rating-*.log`.

Score-first window selection, interval-averaged band geometry and forecast-aware
recommendations passed 202 tests, static analysis and the live Linux calendar
workflow. Desktop month/detail captures were inspected, and the release APK was
rebuilt. Android native workflows were not rerun. Regressions cover shorter but
higher-scoring windows, brief geometry peaks, cloudy versus clear subwindows,
fully cloudy forecasts, partial/missing forecasts and all-clear equivalence.
Evidence is under `build/validation/window-ranking-*.log`.

The all-night geometry preview passed 207 tests, static analysis and the live
Linux calendar workflow; the zero-rated desktop view was visually inspected and
the release APK rebuilt. Tests cover moon-blocked and polar-day zero ratings,
UTC fallback times, flat/horizon band aiming, root navigation and unchanged
location/lens. Android native workflows were not rerun. Evidence is under
`build/validation/geometry-preview-*.log`.
