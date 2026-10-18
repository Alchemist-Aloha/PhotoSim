# Local astronomy and Sun/Moon lighting

## Calculation interface

`lib/core/astronomy.dart` exposes `calculateSky(timestamp, latitude, longitude,
elevation)` through named arguments, independent of Flutter Scene. Inputs use
UTC instants, east-positive longitude and meters above the WGS84 ellipsoid.
Supported dates are 1900–2100 inclusive; the state model, picker and hour-step
controls enforce this range. Offset timestamps are normalized to UTC.

Pinned [Astronomia 1.1.1](https://pub.dev/packages/astronomia) (MIT) supplies
Meeus solar coordinates, the lunar periodic series, nutation, obliquity,
sidereal time and Delta T. Observer subtraction on WGS84 includes solar and
lunar parallax before rotating into local horizontal coordinates. Outputs:

- Airless apparent topocentric Sun/Moon center azimuth and altitude, in degrees.
- Topocentric distances in km and angular radii in radians.
- Unit directions: +X east, +Y up, −Z north, matching the terrain/camera frame.
- Observer-dependent lunar phase angle and illuminated fraction; waxing/waning
  is determined from ecliptic elongation.

`SimulationState.sky` supplies the shared timeline and scene. Unknown ground
height temporarily uses zero plus camera height; terrain loading updates it.
Source terrain datums remain uncorrected and are not reliable ellipsoid heights.

## Reference verification

`test/fixtures/horizons.json` records independent NASA/JPL Horizons DE441
results and the exact request URL for every body and case. Requests use Earth
geodetic observer sites, `APPARENT=AIRLESS`, quantities 4 (azimuth/elevation)
and 10 (illuminated fraction). Tests run entirely offline against these fixtures.

Six cases cover Yosemite day/night, near-horizon London, southern-hemisphere
Sydney, an equatorial site and Arctic winter, from 1992 through 2100. Each Sun
angular separation must be **below 0.1°**, each Moon separation **below 0.2°**,
and lunar illumination error below **0.001** (0.1 percentage point). Additional
tests cover poles, longitude wrapping, observer height, UTC offsets, phases,
finite unit directions, invalid inputs and date limits. These selected cases
are not a comprehensive accuracy guarantee across the full date range.

Limitations: UTC is used as an approximation of UT1; TT is estimated using
Astronomia's Delta T table/polynomial. Measured Earth-orientation parameters,
full light-time/aberration corrections for the Moon and atmospheric refraction
are not implemented. Pre-1962 Horizons fixture times are UT1, treated as the
same clock reading in the tests. These readouts are **not refracted rise/set
times or terrain-horizon visibility predictions**.

## Planning controls

The map shows fixed 1 km geodesic bearing guides from the camera: amber Sun,
blue Moon, with altitude labels. Rays at or below horizontal are dashed; solid
rays indicate centers above horizontal, **not terrain visibility**. Guide length
is a display aid, not celestial distance. They are not rise/set bearings or
terrain-horizon predictions. Labels do not intercept map placement/dragging.
Fixed-length guides can leave the viewport or overlap when zoomed out or when
Sun/Moon directions coincide; screen-spaced labels remain future work.

`lib/ui/time_slider.dart` spans **00:00–24:00 in the camera location's estimated
local calendar day**, converting selections to shared UTC state. It preserves
camera/imagery preferences. The scale is chronological: DST spring days can be
23 hours and autumn days 25 hours; missing hours are skipped and both occurrences
of repeated hours are selectable, distinguished by abbreviation. Fractional-hour
zones/shifts work too. The local date is held during a drag so reaching 24:00
cannot repeatedly advance the date; on release, 24:00 becomes the next local day's
00:00. The tooltip identifies the local date and IANA zone. Date/time pickers and
hour steps remain explicitly UTC and support 1900–2100.

Play/pause advances one simulated minute every 200 ms (five minutes per second).
Playback stops on manual time edits, app backgrounding, disposal, or the upper
date limit. Camera/appearance changes and workspace switching preserve playback.
It changes shared UTC state, not terrain geometry or geographic downloads.

Widget tests check guide bearings, marker alignment, below-horizontal styling,
local-day minute rounding, DST spans, 24:00 dragging, unavailable-rule guards,
UTC conversion and state preservation. The native GPU
workflow uses the actual slider to change lighting while retaining terrain
geometry and terrain/imagery download counters, including during playback.

## Estimated local clock

`lib/core/local_time.dart` maps the camera coordinates to an IANA timezone
using pinned `lat_lng_to_timezone` 0.2.0 (MIT), then converts the UTC instant
with `timezone` 0.11.2 (BSD-2-Clause). Both operate offline. The UI shows the
local date/time, IANA zone, abbreviation and UTC offset; fractional offsets
and daylight-saving transitions are preserved. Moving the camera recomputes
the displayed zone without changing the simulation instant.

The coordinate lookup is an approximate static boundary map, not a maintained
political-boundary dataset; border, offshore and historical-location results
may be wrong. The UI deliberately calls this an **estimated** local time.

The bundled full timezone database is IANA **2026e**, but its transition tables
stop in **2037** and do not apply the future POSIX recurrence rules. A direct
probe incorrectly returned standard time for Los Angeles in July 2050. Rather
than silently displaying a wrong offset, local display is restricted to
**1970–2037**, with an explicit unavailable warning outside that range or for
missing zones. UTC editing and astronomy still support **1900–2100**. Future
political changes also require database updates; this is not a legal guarantee
of future civil time. The local-day slider is disabled outside the supported rules
or when a complete day crosses their boundary; UTC controls remain available.
The date/time editor defaults to the camera location's estimated **local** time,
not the host computer's timezone, and previews the converted UTC instant before
applying it. It rejects nonexistent wall times during spring-forward gaps or
skipped days. When a time occurs twice, the user chooses the occurrence labeled
with its timezone abbreviation and UTC instant. Unchanged repeated times retain
the current occurrence. There is no timezone override.
An explicit **Use UTC instead** action retains the full simulation date range;
UTC editing is the fallback when the current instant has no supported local rules.

Offline tests cover US spring gaps/autumn folds, European and southern-hemisphere
DST, fractional offsets, local date rollover, instant preservation, invalid
coordinates and the supported-year guard. Playback widget tests cover manual
edits, disposal/backgrounding and the upper date boundary. The native Linux
workflow verifies the local readout and actual playback with unchanged terrain
geometry/download counters.

## Rendering

The calculated solar direction drives the existing shadow-casting directional
light. A built-in Flutter Scene `PhysicalSkySource` uses the same direction
and calculated solar angular radius; the skybox draws behind terrain. The
manual test-light slider has been removed.

Direct solar light uses Kasten–Young relative air mass and RGB clear-air extinction
(`lib/core/sunlight.dart`), instead of the old linear intensity/color ramps.
Long atmospheric paths dim the red channel and attenuate green/blue more strongly,
producing dim red/orange low-Sun lighting. A last-solar-diameter fade avoids an
abrupt directional-light switch at 0°; it is not a refracted limb calculation.
The sky uses matching clear-air optical depths: Rayleigh tint (0.058, 0.135,
0.331), coefficient 1, Mie coefficient 0.002, turbidity 2 and eccentricity 0.76.
This gives a bluer clear sky with less washed-out aerosol glow. The built-in sky
shader applies view-path extinction to the actual angular-size solar disk.
Sun/Moon positions, geometry and geographic resources are unchanged.

Ambient intensity ramps between 0.04 at −18°
and 0.25 at 0°. The dim, shadowless night floor keeps lit/fallback and approximately
relit terrain distinguishable from the dark sky, even without moonlight. It does
not brighten the sky or unlit celestial objects; natural imagery still retains
its captured lighting. These are approximate clear-sky appearance controls, **not
calibrated irradiance, exposure or weather simulation**. The built-in sky
model goes black below the solar horizon; only ambient terrain lighting has
a twilight ramp. Stars and a simplified Milky Way brightness map are rendered
by the separate [night-sky module](data-sources/night-sky.md), with their own
solar/lunar visibility approximation.

Linux GPU tests sample the actual Sun disks near 1° altitude on both sunrise
and sunset and compare their RGB/brightness with a 30° Sun. They also verify a
blue clear-sky sample, FXAA edge-pixel changes and MSAA/fallback operation without
geographic reloads. Captures: `linux-{sunrise,sunset,sun-day,blue-sky}.png` and
`linux-aa-{off,fxaa}.png` in `build/validation/`. These are isolated rendering
fixtures, not photometric reference measurements.

`lib/render/moon.dart` renders a 128-segment, 64-ring untextured lunar sphere,
rescaled to 30 km with radius `distance × sin(angularRadius)` to preserve its
apparent size. Observer-derived Moon-to-Sun direction drives Lambertian vertex
colors, so the terminator and bright-limb orientation follow astronomical geometry.
Only colors update when illumination changes; geometry stays resident. It is unlit
by scene lights and does not cast an artificial nearby-object shadow.

The sphere depth-tests against terrain. The geographic viewport corrects Flutter
Scene's +Z-forward camera handedness with a horizontal flip, preserving east/west
and the Moon's bright-limb orientation. Camera/terrain coordinates remain unchanged.
Occlusion is limited to loaded terrain, not a complete Earth/terrain horizon model.
No albedo map, craters, libration, earthshine or atmospheric lunar scattering is
modeled; especially near the Sun, the dark hemisphere can appear too conspicuous.

Below solar center altitude 0°, the existing shadow-casting light switches to
lunar direction. Its intensity is `0.03 × illumination² × max(0, sin(moonAltitude))`
with a darkness ramp from 0° to −6° solar altitude. The blue-white tint and intensity
are artistic approximations, **not the physical Sun/Moon radiance ratio**.
Above solar altitude 0°, the primary light remains solar; simultaneous daytime
moonlight is omitted. Natural imagery remains unaffected by either light.

Natural NAIP imagery remains unlit and retains captured shadows/colors when
time changes. **Approximate relighting**, enabled by default for new sessions,
shows solar shading and shadows on imagery; baked-in source shadows can still be doubled. Missing
imagery uses the existing lit terrain fallback.

The native Linux workflow checks time-driven solar direction, solar angular
radius, phase/altitude-dependent nighttime moonlight and an actual rendered brightness
reduction. It also verifies unchanged terrain geometry and terrain/imagery
download counters across time updates. Screenshots:
`build/validation/linux-solar-day.png`, `linux-solar-night.png` and
`linux-moon-phase.png`. The lunar screenshot deliberately hides terrain to isolate
the disk: the selected canyon sightline is blocked by actual terrain. Pixel checks
verify that blocking, a separate foreground occluder, visible lunar pixels with
terrain hidden and the right-hand bright limb for the selected waxing phase.
The workflow also verifies lunar color changes without replacing its geometry.
Unit tests check phase-lit projected area, limb rotation and brightness ramps.

Stars, Milky Way planning and [saved compositions](saved-plans.md) are now
implemented and verified on Linux. Performance, responsive-layout and actual
cross-platform release gates remain open; the full roadmap is incomplete.
