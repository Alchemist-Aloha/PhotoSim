# Linux MVP implementation status

## Current milestone

**The revised Linux desktop MVP is complete.** It includes attributed PNG export,
quality presets, manual weather and aperture-linked depth of field, in addition
to the existing terrain/imagery, astronomy, timeline and save/reopen workflow.
See [authoritative Linux 0.1 scope](linux-mvp.md). Other platforms are future work;
this does not mark every requirement of the long-term specification complete.

Full non-platform spec implementation is now underway. See the authoritative
[Linux spec progress ledger](linux-spec-progress.md), which lists remaining Linux
requirements separately from excluded platform work.

## Available

- Two synchronized map/3D workspaces with camera placement, draggable aim,
  physical sensor/focal-length fields of view, height and UTC timeline controls.
- APS-C/full-frame sensor pills and one 8–600 mm focal-length slider; no lens presets.
  Existing saved-plan focal lengths and sensor selections remain readable.
- Preferred anonymous Mapterhorn tiles combine Copernicus GLO-30 with finer open
  national datasets; Mapzen is the independent fallback. Source credits are visible,
  with 151 upstream catalog entries bundled in the sources dialog.
- Strict 512px lossless WebP and 256px PNG Terrarium decoding; exact child cropping
  from global zoom-12 parents where regional zoom-13 tiles are unavailable.
- Terrarium decoding, pixel-center elevation interpolation, double-precision
  WGS84 ECEF/ENU, meter-scale camera-relative geometry and ellipsoid curvature.
- Default progressive 3×3 zoom-13 terrain, generated normals/UVs, camera ground vertex,
  distance/FOV quadtree LOD, skirts and native LRU elevation caching within the configurable shared
  terrain/imagery disk budget. Native 1–5 m source detail is not displayed by the existing mesh.
- Automatic free imagery selection: NAIP, Swiss-only SWISSIMAGE, IGN BD ORTHO
  and the CC BY EOX Sentinel-2 2016 global mosaic. Exact EPSG:3857 bounds,
  natural-color processing, bounded/cancellable requests and visible source credits.
- Regional errors/no-data fall through; transparent coverage composites over lower
  priority sources. No newer non-commercial EOX layers or paid accounts required.
- **Terrain range** inspector section (live controls): 1–3 surrounding tile rings, 0–40 km FOV-aware forward
  fetching and 2–40 km whole-tile render cutoff plus actual 3D frustum culling.
  Pitch/aim/optics changes debounce 400 ms; non-overlapping distant tiles coarsen
  within a 256-patch budget, long lenses prefer finer tiles, retained patches reuse
  meshes/textures, and settings persist in plans with legacy defaults.
- Progressive 256×256 image previews and a 1024×1024 camera-tile replacement.
- Texture swaps preserve existing geometry; switching natural/relit mode also
  preserves geometry and shared camera/time state.
- Approximate relighting enabled by default for new sessions; saved lighting
  preferences remain authoritative. Optional natural, display-referred imagery.
- Pixels unavailable from every source stay a labeled fallback surface; unavailable
  high-resolution imagery retains a successful preview.
- Terrain/imagery share one persistent LRU disk-cache limit under **Storage**:
  512 MiB default, configurable 0–65,536 MiB. Provider/resolution namespaces stay
  separate on disk without fixed individual quotas; old NAIP paths remain readable. Corruption recovery,
  source metadata, dimension-checked PNG/indexed PNG/JPEG and isolate compositing.
- Pinned Astronomia 1.1.1 behind an application-level calculation interface.
- Topocentric solar/lunar positions and angular sizes, observer-dependent Moon
  illumination and waxing/waning readouts shared by both workspaces.
- UTC-driven directional sunlight and shadows, clear-air RGB air-mass extinction
  for dimmer/redder low Sun, bluer Rayleigh clear sky with reduced aerosol glow,
  sky-driven indirect lighting and sky-colored distance haze on approximately
  relit terrain. Natural imagery is preserved; celestial proxies bypass terrestrial
  fog without bypassing exposure or terrain occlusion. Astronomy/geometry remain unchanged.
- Explicit FXAA (default), MSAA 4× with capability fallback, Off and quality-driven
  Auto controls in Rendering; persisted in plans without geographic reloads.
- Resolved untextured Moon sphere with correct apparent size, phase and limb
  orientation, depth-tested against terrain; phase-dependent approximate moonlight.
- Corrected east/west viewport handedness, with a GPU bright-limb regression test.
- Sun/Moon geodesic map bearing guides with altitude labels, dashed below
  horizontal and explicitly distinguished from terrain visibility predictions.
- Shared 00:00–24:00 local-day slider with UTC conversion, DST gaps/folds,
  minute resolution and a stable date during dragging; camera/appearance preserved.
- Validated 1900–2100 UTC date range, with disabled hour steps at the boundaries.
- Offline estimated local clock for camera coordinates: IANA zone, abbreviation,
  local date/time and UTC offset, including DST and fractional offsets.
- Local clock restricted to 1970–2037 because bundled transition tables end in
  2037; other dates explicitly show unavailable instead of a stale offset.
- Play/pause at five simulated minutes per second, stopping on manual time edits,
  backgrounding, disposal or the date limit; UTC remains authoritative.
- 5,044 offline XHIP stars and five licensed Milky Way brightness contours;
  J2000 precession/nutation/sidereal rotation, immutable GPU batches and terrain depth tests.
- Approximate solar/lunar night-sky visibility, Galactic-center map/3D markers,
  Sun/Moon/Galactic-center selection, explicit aim action and rectangular FOV checks.
- Toggleable 3D constellation names and connecting figures, default off; a shared
  sky rotation, two GPU batches, terrain depth tests and saved layer preference.
- Named version-2 JSON photography snapshots (legacy version-1 files remain readable): camera, optics, UTC, selected target
  and imagery preference; local save/open, fresh-app restoration and corruption warnings.
- Full-area context preview with an inset sensor-aspect photo region and
  focal-length/aperture/DOF label. Projection and DOF scaling preserve the physical
  photo; weather/quality/relighting are only in the right settings panel.
- Desktop navigation drawer switches Map/3D and closes on selection without
  resetting UTC/camera. Ruler/stars/export buttons float in the preview; one
  bottom information card groups loading/cache counts, help and attribution.
  Both cards hide in clean mode, do not shrink the canvas and stay out of exports.
- Attributed, sensor-aspect PNG export cropped to the framed photo, capped to
  4096 px / 12 MP, with no application controls and no overwriting existing files.
- Performance/Balanced/High backend rendering budgets; unnecessary shadows skipped
  for natural imagery/overcast weather. Mesh/texture resources remain resident.
- Manual illustrative Clear/Cloudy/Fog/Rain, with overcast sky, fog, attenuation
  and clipped animated rain; no forecasts or weather network requests.
  Collapsible inspector sections expose preset, visibility, light transmission
  and rain intensity with reset and saved-plan compatibility. Native tests verify
  the parameter uniforms, rain density and no geographic resource reloads.
- Physical depth-buffer DOF linked to aperture, focus distance, focal length and
  sensor, with settings persisted in plans and backward-compatible defaults.
- No paid service, secrets, custom shaders or fabricated geographic imagery.

## Responsibility boundaries

- `lib/core/astronomy.dart`: offline ephemerides and observer/renderer transforms.
- `lib/core/local_time.dart`: approximate offline zone lookup and local presentation.
- `lib/core/night_sky.dart`: catalog parsing, rigid observer sky frame and visibility model.
- `lib/render/night_sky.dart`: immutable star/band geometry and target marker.
- `lib/data/saved_plans.dart`: bounded versioned JSON and native snapshot repository.
- `lib/app/app.dart`: authoritative shared state, playback timer and lifecycle cleanup.
- `lib/render/moon.dart`: lunar geometry, phase shading and approximate moonlight.
- `lib/core/terrain_geo.dart`: XYZ/Web Mercator bounds, WGS84 and local frames.
- `lib/data/terrain/`: PNG/WebP elevations, parent cropping, CPU meshes,
  account-free service selection/fallback and provider-separated elevation repositories.
- `lib/data/imagery/`: regional/global providers, automatic selection/compositing,
  exact raster requests, validation/decode/cache.
- `lib/data/http_bytes.dart`: shared bounded, cancellable HTTP download.
- `lib/data/terrain/tile_cache.dart`: reused provider/resolution-scoped native cache.
- `lib/ui/simulation_workspace.dart`: progressive orchestration and GPU upload.
- `lib/ui/map_workspace.dart`: camera/FOV and celestial bearing guides.
- `lib/ui/time_slider.dart`: chronological local-day scrubbing converted to UTC,
  shared by both workspaces; unavailable rule dates stay disabled.
- `lib/models/simulation_state.dart`: authoritative camera/time/ground and
  imagery appearance preference.

Decode and raster preparation use isolates. There are no network requests in the
render loop. Time/appearance edits do not reload geography. Optics/orientation
changes also preserve it with forward fetching off; when enabled they reconcile
FOV-dependent coverage, retaining overlapping patches.
Mesh reassignment registers material changes with Flutter Scene while reusing the
same resident geometry; mutating a primitive's material alone did not update
the rendered scene in the installed backend.

## Verified locally

Environment: Linux x86_64, Flutter 3.47.6 / Dart 3.13.5.

- Static analysis: no issues.
- 158 passing unit/widget tests: optics/state/geographic precision, elevations,
  normals/edges/ground vertex, lossless WebP validation, all four parent quadrants,
  terrain service fallback/provenance/credits, cache behavior, bounded responses and cancellation,
  imagery export bounds, pixel orientation, no-data handling, independent image
  resolutions/metadata/cache, regional/global routing, PNG/JPEG validation, alpha
  compositing, service timeouts, missing detail, corruption and out-of-coverage behavior.
- Six independent NASA/JPL Horizons fixtures pass Sun <0.1° and Moon <0.2°
  angular separation checks. Phase, observer height, UTC normalization, date
  boundaries and shared readout changes are tested offline.
- Widget tests verify celestial guide bearings/markers and horizon styling;
  the time slider rounds minutes and preserves state at both date boundaries.
- Offline local-clock tests cover multiple zones, fractional offsets, DST gaps/folds,
  southern-hemisphere DST, rollover, instant preservation and unavailable years.
- Widget tests check playback, stopping on edits/backgrounding/disposal, the upper
  date boundary, and the estimated local readout.
- A second native Linux test loads live Mapterhorn terrain and Swiss, French,
  Australian and Beijing imagery. It verifies source credits/the upstream licenses
  dialog, GPU pixel diversity and geography/cache reuse after optics/time edits,
  and captures `linux-imagery-{swiss,ign,eox,beijing}.png`. The Swiss case also
  checks forward fetching, FOV/aim replanning, nearby mesh reuse, frustum rejection,
  render-only changes without downloads, and UTC preservation while editing live range controls.
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
- Six independent ERFA/SOFA sky-rotation fixtures pass <0.01° checks, including
  1900/2100, both hemispheres and a pole; these test transforms, not full stellar astrometry.
- Native pixels verify stars, Milky Way, actual canyon occlusion of Antares,
  a foreground blocker, daylight suppression and resident sky/terrain geometry.
- Target selection/aiming and rectangular FOV tests cover pitch, wrapping and optical zoom.
- Constellation tests cover the 88 constellations (89 label regions), malformed data,
  inward-facing great-circle ribbons, RA wrapping and preference persistence.
  Native pixels verify toggle visibility, readable labels and foreground occlusion,
  while toggling retains GPU geometry and the save/reopen workflow retains the preference.
- Snapshot tests cover all fields, validation, corruption, size limits, concurrent saves
  and failed writes preserving existing data. The native UI saves, destroys/recreates
  the app, reopens every field, recenters the map and restores cached 3D geography.
- Native screenshots captured and inspected:
  `build/validation/linux-naip-natural.png`, `linux-preview.png`,
  `linux-solar-day.png`, `linux-solar-night.png`, `linux-map.png`, and
  `linux-terrain-moved.png`, plus the terrain-isolated `linux-moon-phase.png`,
  `linux-night-sky-terrain.png`, `linux-night-sky-isolated.png`,
  `linux-star-isolated.png`, `linux-constellations.png` and `linux-reopened-plan.png`.
- Linux photography native test exercises all weather/quality presets, DOF and
  aperture-dependent GPU pixels, geography/download invariants, and actual UI PNG
  export with sensor aspect ratio. Screenshots include `linux-weather-*.png`,
  `linux-dof-{open,stopped}.png` and `linux-export.png`.
- A fourth Linux native test verifies red/dimmer sunrise and sunset disks,
  blue clear-sky pixels, actual FXAA edge changes, MSAA/fallback selection and
  unchanged resident geometry/download counts; screenshots include
  `linux-{sunrise,sunset,sun-day,blue-sky}.png` and `linux-aa-{off,fxaa}.png`.
- A fifth Linux native workflow verifies manual GPU exposure/Auto metering,
  white balance, roll/portrait projection, fullscreen/Esc resource reuse and
  portrait PNG export. Numerical/widget tests cover exposure stop ratios,
  persistence/defaults, composition guides and adjustable playback speed.
- A sixth Linux native test covers terrain-following WASD navigation, constant
  camera-height offset, terrain/texture reuse, dialog/map focus, map sync and
  terrain-tile rebasing. Camera elevation follows the higher of raster ground and
  visible mesh triangles, with dedicated slope/coarse-valley/boundary tests.
  Nearby motion uses retained WGS84 frames. This is not general object collision.
- A seventh Linux native workflow holds imagery responses pending and verifies
  all terrain meshes/ground still load; later previews/detail retain geometry.
  Shared HTTP scheduling caps each origin at three streamed requests and applies
  cancellable 429/503 Retry-After/backoff without delaying cached data. Small live
  probes found HTTP 200, not rate-limit errors; EOX detail took 23.35 seconds.
  See [loading diagnostics and policy](loading.md).
- Storage settings persist outside plans, trim immediately and leave resident GPU
  resources untouched. The native loading workflow applies zero through the actual
  inspector, verifies all 19 raster entries are removed, checks persistence and
  confirms unchanged geometry/textures/download counts. Unit/widget tests cover
  global LRU, metadata accounting, bounds, oversized entries, concurrent writes,
  startup migration/cleanup, settings failures and field validation.
- Linux release bundle builds successfully.

Unit tests use generated images and mocked HTTP; the native workflow uses live
public data on a first visit, then cached data. Pixel-diversity and UV/bounds tests
are not a survey-grade landmark alignment or cross-GPU accuracy benchmark.

## Remaining limits

- Bounded distance/FOV quadtree coverage, not viewport/screen-error refinement or
  terrain-aware vertical fetch culling. Render cutoff is whole-tile, not per-pixel.
  Mapterhorn's finer upstream grids still use the original coarse mesh. No standalone
  national GeoTIFF clients, NASA HMA or restricted terrain services are implemented.
- Uncorrected source elevation datums and no precision terrain-horizon service.
- Coarse/unequal tile-edge samples, skirts, blurry distant imagery and stretched
  cliff/foreground textures remain visible.
- Imagery source acquisition dates are unknown; no date filtering or cache refresh UI.
- Global fallback is the old, approximately 10 m 2016 mosaic, not current imagery.
  Native sub-meter regional imagery is downsampled by existing texture footprints;
  adaptive near-camera imagery subdivision and optional paid providers remain open.
- Native-only cache; other platform builds and browser storage remain open.
- Scene warns about depth precision inside ground patches. Shadow accuracy, frame
  time targets, release-mode interaction and long-run GPU-memory stability are unmeasured.
- No lunar albedo/detail, libration, earthshine or atmospheric lunar scattering.
  Moonlight is artistically scaled, not calibrated; daytime moonlight is omitted.
- Night-sky intensity and point sizes are artistic; no calibrated PSF/exposure,
  proper motion, annual aberration/parallax, extinction, light pollution or individual star labels.
  Constellation names have fixed-size placement without collision decluttering.
  Fixed-length celestial guides may overlap or leave the map viewport;
  no rise/set event overlays or terrain visibility classification.
- No atmospheric refraction, rise/set events or measured Earth orientation.
  Accuracy checks cover selected cases, not the entire supported date range.
- Twilight/lunar sky uses spherical single scattering with Earth shadowing, not
  multiple scattering, ozone or calibrated photometry. Natural imagery retains its lighting.
- High quality doubles terrain mesh subdivisions (256/128/64), retains native
  256-pixel peaks and enables PCSS/contact shadows; source accuracy is unchanged
  and physical-device performance remains unmeasured.
- Approximate static timezone boundaries; local display only for 1970–2037.
  Local-day scrubbing converts to UTC; no arbitrary local date/time text input or
  timezone override. Civil-time rules can change.
- Plans are unencrypted native local snapshots; no file-picker import/export,
  cloud storage, editing/deletion UI or power-loss durability guarantee.
- PNG export is viewport-sized; independent-resolution export remains future work.
- Manual weather is illustrative, not live forecasting. Rain is screen-space;
  DOF is a bounded post-process approximation. Manual/Auto exposure and white
  balance now exist, but scene radiance and chromatic adaptation are uncalibrated.

See [astronomy notes](astronomy.md) for the calculation contract, reference
sources and accuracy limits, [night-sky notes](data-sources/night-sky.md) for
catalog/brightness limits, and [saved plans](saved-plans.md) for persistence.
Next: optional improvements and future-platform feasibility, not Linux MVP blockers.

## Future roadmap

The original cross-platform roadmap remains a future-product plan, not the
acceptance contract for Linux 0.1. Deferred work includes responsive mobile UI,
viewport/screen-error LOD, measured FPS and GPU-memory stability, richer exposure
and atmosphere, forecasts, and independent-resolution export. Android, Web/WebGL2,
Windows and macOS need scaffolding and actual-platform validation; none is claimed
supported. The current release is the verified Linux planning/save/reopen/export
workflow documented in [Linux MVP scope](linux-mvp.md).
