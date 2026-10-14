# Local astronomy and solar lighting

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

## Rendering

The calculated solar direction drives the existing shadow-casting directional
light. A built-in Flutter Scene `PhysicalSkySource` uses the same direction
and calculated solar angular radius; the skybox draws behind terrain. The
manual test-light slider has been removed.

Direct intensity ramps from zero at solar center altitude 0° to 3 at 15°;
color warms at low altitude. Ambient intensity ramps between 0.005 at −18°
and 0.25 at 0°. These are approximate clear-sky appearance controls, **not
calibrated irradiance, exposure or weather simulation**. The built-in sky
model goes black below the solar horizon; only ambient terrain lighting has
a twilight ramp. Moonlight, stars and a resolved Moon disk are not yet rendered.

Natural NAIP imagery remains unlit and retains captured shadows/colors when
time changes. Enable **Approximate relighting** to see solar shading and
shadows on imagery; baked-in source shadows can still be doubled. Missing
imagery uses the existing lit terrain fallback.

The native Linux workflow checks time-driven solar direction, solar angular
radius, zero nighttime direct intensity and an actual rendered brightness
reduction. It also verifies unchanged terrain geometry and terrain/imagery
download counters across time updates. Screenshots:
`build/validation/linux-solar-day.png` and `linux-solar-night.png`.

Next: resolved Moon disk with phase/limb orientation, approximate moonlight,
map direction overlays, local timezone display and fuller time controls.
