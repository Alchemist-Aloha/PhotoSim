# Night-planning calendar

Open **Calendar** beside Map and 3D Preview. The top-right button switches
between a month grid and a seven-night agenda. Arrow buttons change the month
or week; the date heading opens a date picker. Select a date for its explanation.
On narrow windows the details are below the calendar; wider windows place them
beside it. Large text can make the month grid horizontally scrollable.

Each date means **that local evening until 01:00 the following local day**,
using the camera location's estimated timezone, not the device timezone.
Browsing does not change the saved composition or simulation clock. **Preview
Galactic core** explicitly applies a UTC time inside the selected window, aims
at the core and opens 3D, preserving the location and lens.

## Astronomy and scoring

Calculations run locally in an isolate, sampling every ten minutes from local
noon to the next 01:00. A joint observing window requires all four conditions:

- Sun center at or below −18° (astronomical darkness).
- A nonzero percentage of the visible Milky Way between 0° and 30° elevation.
- Moon center at or below the horizontal plane.
- Moon–core angular separation at least 30°.

The longest continuous qualifying window wins; ties prefer a higher low-band
percentage, then the earlier window. At least two adjacent samples are needed.
The best sampled time maximizes the percentage of the **visible Milky Way between
0° and 30° elevation**, before the window endpoint rather than at the 01:00 cutoff.
The astronomy score is duration / 120 minutes × 50, capped at 50, plus that
low-band fraction × 50. Both components and the percentage are displayed.
Core altitude is diagnostic only: a core below the horizon does not force a zero
rating. The core-preview button is offered only when the core is above the horizon
at the best sampled time; otherwise the report explains that the band is still rated.

The band is approximated by the zero-width IAU Galactic equator, weighted by arc
length, not brightness, band area or camera framing. The denominator is its
above-horizon half, excluding the portion below the horizon. For the Galactic
north pole's local vertical component `p`, the circle has vertical amplitude
`A = sqrt(1 − p²)`; its low-band fraction is `2 × asin(0.5 / A) / π`
when `A > 0.5`, otherwise 1. This analytic calculation avoids discretization
along the band; time is still sampled every ten minutes. The labels describe
geometry, not a calibrated probability of a good photograph.

Moon illumination is shown, but receives no extra penalty in a moon-below-horizon
window. Separation is normally much less important once the Moon has set.
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

**A** means astronomy only. **W** means astronomy × (1 − mean cloud fraction),
only when cloud values cover the entire interval. Missing/partial weather is
unknown, never assumed clear. Forecasts do not change illustrative 3D weather
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
