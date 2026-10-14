# Linux-first implementation status

## Current milestone

Real Mapzen/NAIP terrain now has **offline Sun/Moon calculations and UTC-driven
Sun/Moon lighting, estimated local-time display and automatic playback**,
advancing Phase 3 after terrain/imagery and cache streaming.
The public MVP, full astronomy phase and cross-platform Phase 0 gate remain incomplete.

## Available

- Two synchronized map/3D workspaces with camera placement, draggable aim,
  physical sensor/lens fields of view, height and UTC timeline controls.
- Terrarium decoding, pixel-center elevation interpolation, double-precision
  WGS84 ECEF/ENU, meter-scale camera-relative geometry and ellipsoid curvature.
- Progressive 3×3 zoom-13 terrain, generated normals/UVs, camera ground vertex,
  coarse distance LOD, skirts and native LRU elevation caching.
- NAIP provider interface and exact EPSG:3857 raster export bounds, explicit
  natural-color processing, bounded/cancellable requests and source attribution.
- Progressive 256×256 image previews and a 1024×1024 camera-tile replacement.
- Texture swaps preserve existing geometry; switching natural/relit mode also
  preserves geometry and shared camera/time state.
- Natural, display-referred imagery by default; opt-in approximate relighting.
- Transparent/missing imagery stays a labeled fallback surface; unavailable
  high-resolution imagery retains a successful preview.
- Independent 256 MiB imagery cache (64 MiB previews, 192 MiB detail), in addition
  to the existing 256 MiB elevation cache. Corruption recovery and source metadata.
- Pinned Astronomia 1.1.1 behind an application-level calculation interface.
- Topocentric solar/lunar positions and angular sizes, observer-dependent Moon
  illumination and waxing/waning readouts shared by both workspaces.
- UTC-driven directional sunlight and shadows, approximate color/brightness
  ramps and Flutter Scene's built-in clear-sky background.
- Resolved untextured Moon sphere with correct apparent size, phase and limb
  orientation, depth-tested against terrain; phase-dependent approximate moonlight.
- Corrected east/west viewport handedness, with a GPU bright-limb regression test.
- Sun/Moon geodesic map bearing guides with altitude labels, dashed below
  horizontal and explicitly distinguished from terrain visibility predictions.
- Shared UTC-day slider at minute resolution, retaining camera and appearance state.
- Validated 1900–2100 UTC date range, with disabled hour steps at the boundaries.
- Offline estimated local clock for camera coordinates: IANA zone, abbreviation,
  local date/time and UTC offset, including DST and fractional offsets.
- Local clock restricted to 1970–2037 because bundled transition tables end in
  2037; other dates explicitly show unavailable instead of a stale offset.
- Play/pause at five simulated minutes per second, stopping on manual time edits,
  backgrounding, disposal or the date limit; UTC remains authoritative.
- No paid service, secrets, custom shaders or fabricated imagery.

## Responsibility boundaries

- `lib/core/astronomy.dart`: offline ephemerides and observer/renderer transforms.
- `lib/core/local_time.dart`: approximate offline zone lookup and local presentation.
- `lib/app/app.dart`: authoritative shared state, playback timer and lifecycle cleanup.
- `lib/render/moon.dart`: lunar geometry, phase shading and approximate moonlight.
- `lib/core/terrain_geo.dart`: XYZ/Web Mercator bounds, WGS84 and local frames.
- `lib/data/terrain/`: raster elevations, CPU meshes, elevation repository.
- `lib/data/imagery/`: provider interface, NAIP requests, validation/decode/cache.
- `lib/data/http_bytes.dart`: shared bounded, cancellable HTTP download.
- `lib/data/terrain/tile_cache.dart`: reused provider/resolution-scoped native cache.
- `lib/ui/simulation_workspace.dart`: progressive orchestration and GPU upload.
- `lib/ui/map_workspace.dart`: camera/FOV and celestial bearing guides.
- `lib/ui/time_slider.dart`: selected UTC-day scrubbing, shared by both workspaces.
- `lib/models/simulation_state.dart`: authoritative camera/time/ground and
  imagery appearance preference.

Decode and raster preparation use isolates. There are no network requests in the
render loop, and camera optics/orientation/time changes do not reload source data.
Mesh reassignment registers material changes with Flutter Scene while reusing the
same resident geometry; mutating a primitive's material alone did not update
the rendered scene in the installed backend.

## Verified locally

Environment: Linux x86_64, Flutter 3.47.6 / Dart 3.13.5.

- Static analysis: no issues.
- Fifty-four passing unit/widget tests: optics/state/geographic precision, elevations,
  normals/edges/ground vertex, cache behavior, bounded responses and cancellation,
  imagery export bounds, pixel orientation, no-data handling, independent image
  resolutions/metadata/cache, missing detail, corruption and out-of-coverage behavior.
- Six independent NASA/JPL Horizons fixtures pass Sun <0.1° and Moon <0.2°
  angular separation checks. Phase, observer height, UTC normalization, date
  boundaries and shared readout changes are tested offline.
- Widget tests verify celestial guide bearings/markers and horizon styling;
  the time slider rounds minutes and preserves state at both date boundaries.
- Offline local-clock tests cover multiple zones, fractional offsets, DST gaps/folds,
  southern-hemisphere DST, rollover, instant preservation and unavailable years.
- Widget tests check playback, stopping on edits/backgrounding/disposal, the upper
  date boundary, and the estimated local readout.
- Native workflow loads nine real Yosemite terrain patches and nine NAIP textures;
  the camera patch receives an additional higher-resolution image.
- Returning to 3D reports **9 cached / 0 downloaded** elevation patches and
  **10 cached / 0 downloaded** imagery entries.
- Integration assertions verify unchanged geometry during texture updates,
  natural/relit material switching, shared preference preservation, camera height,
  camera controls, projection synchronization, timeline changes and teardown.
- Using the actual shared time slider changes solar direction and GPU-rendered brightness;
  nighttime light follows the Moon with phase/elevation-dependent intensity.
  Native playback advances shared UTC time, the estimated local readout is visible,
  and geometry and download counters stay unchanged.
- Native pixel checks verify the lunar bright limb, visible phase pixels with
  terrain isolated, actual canyon occlusion and a foreground depth blocker.
  Moon phase updates preserve its geometry; numerical tests check illuminated area.
- A native screenshot pixel-diversity assertion catches the previous
  loaded-but-still-green rendering regression.
- Moving the camera loads rebased terrain and aligned imagery at the new location.
- Native screenshots captured and inspected:
  `build/validation/linux-naip-natural.png`, `linux-preview.png`,
  `linux-solar-day.png`, `linux-solar-night.png`, `linux-map.png`, and
  `linux-terrain-moved.png`, plus the terrain-isolated `linux-moon-phase.png`.
- Linux release bundle builds successfully.

Unit tests use generated images and mocked HTTP; the native workflow uses live
public data on a first visit, then cached data. Pixel-diversity and UV/bounds tests
are not a survey-grade landmark alignment or cross-GPU accuracy benchmark.

## Remaining limits

- Fixed regional extent and distance LOD, not screen-error quadtree refinement.
- Uncorrected source elevation datums and no precision terrain-horizon service.
- Coarse/unequal tile-edge samples, skirts, blurry distant imagery and stretched
  cliff/foreground textures remain visible.
- Imagery source acquisition dates are unknown; no date filtering or cache refresh UI.
- Optional MapTiler/global imagery providers are not implemented.
- Native-only cache; other platform builds and browser storage remain open.
- Scene warns about depth precision inside ground patches. Shadow accuracy, frame
  time targets, release-mode interaction and long-run GPU-memory stability are unmeasured.
- No lunar albedo/detail, libration, earthshine or atmospheric lunar scattering.
  Moonlight is artistically scaled, not calibrated; daytime moonlight is omitted.
- No stars or Milky Way. Fixed-length celestial guides may overlap or leave
  the map viewport; no rise/set event overlays or terrain visibility classification.
- No atmospheric refraction, rise/set events or measured Earth orientation.
  Accuracy checks cover selected cases, not the entire supported date range.
- Solar brightness/color and ambient twilight are approximate; the built-in
  sky becomes black below the solar horizon. Natural imagery retains its lighting.
- Approximate static timezone boundaries; local display only for 1970–2037.
  No local-wall-time input or timezone override. Civil-time rules can change.
- Saved plans and exports remain open.

See [astronomy notes](astronomy.md) for the calculation contract, reference
sources and accuracy limits. Next: stars and the Milky Way, then saved plans.

## Remaining roadmap gates

The roadmap is **not complete**. Remaining MVP work includes:

1. A licensed offline star catalog, epoch corrections, batched star rendering,
   sky rotation, terrain occlusion and solar/lunar visibility approximation.
2. A licensed simplified Milky Way representation, Galactic-center position,
   map/3D markers, target selection and field-of-view checks.
3. Versioned JSON saved plans with reopen support, including selected target.
4. Responsive-layout validation, adaptive quality, frustum/LOD improvements,
   defined-device FPS/latency profiling and long-running GPU-resource checks.
5. Android, Web/WebGL2, Windows and macOS scaffolding and actual-platform
   build/render validation. Linux success does not close the Phase 0 gate.
6. The documented Shenandoah save/close/reopen demonstration and complete
   workflow regression tests on all five target platforms.

Post-MVP priorities in the roadmap, including advanced weather and photographic
exports, are not part of the MVP completion claim. Windows/macOS verification
requires those operating systems or suitable CI runners; none has been verified
in this Linux session.
