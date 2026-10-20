# PhotoSim

Landscape photography simulator for **Linux and Android phones/tablets**, built
with Flutter and Material 3. **The Linux MVP is complete** under the revised
[Linux release scope](docs/linux-mvp.md). Android setup and validation are recorded
in [Android support](docs/android.md); the long-term specification is not a claim
of implemented features.
Implementation beyond that baseline is underway; see the [full Linux spec progress](docs/linux-spec-progress.md)
for delivered features and the explicitly unfinished backlog.

## Run on Linux

Requires Flutter **3.47.1 or newer** (developed with 3.47.6), Clang, CMake,
Ninja, GTK 3 development libraries, and an Impeller-compatible graphics driver.

```sh
flutter pub get
flutter run -d linux
```

The Linux runner enables Flutter GPU permanently; no extra rendering flags
are needed. Under Hyprland and niri, it automatically hides GTK's window header
and client-side decorations using compositor/desktop environment variables;
PhotoSim's own toolbar remains available. Other desktops keep their existing
window-decoration behavior. Direct dependencies are pinned and `pubspec.lock` is included.

## Run on Android

Requires Android **10 / API 29 or newer**, a compatible Impeller graphics driver,
Flutter 3.47.1+, and the Android SDK.

```sh
flutter pub get
flutter run -d <android-device-id>
flutter build apk --release
```

Install `build/app/outputs/flutter-apk/app-release.apk`. Local builds default to
a development signing key; [tagged CI releases](docs/releases.md) require your persistent signing key.
Flutter GPU and internet access are enabled in the release manifest.

Phones use bottom navigation and a controls drawer; larger windows use a
navigation rail and docked controls when there is enough space. Both orientations,
split-window resizing, system light/dark theme, and larger text are supported.
Drag the 3D view to aim and pinch to change focal length. **Export PNG** saves to
**Pictures/PhotoSim** through MediaStore without broad storage permission.
See [Android support](docs/android.md) for tests and device limitations.

## Available now

- **Night calendar** with month/week views, explained Galactic-core observing windows,
  keyless Open-Meteo forecasts and a modeled light-pollution site baseline.
  See [night planning, sources and limits](docs/night-calendar.md).
- Interactive OpenStreetMap map centered on Yosemite.
- Tap/click to place a camera; drag its marker to move it and its green handle to aim.
- Geographic field-of-view wedge calculated from physical sensor and focal length.
- Full-frame / APS-C sensor pills and a single 8–600 mm focal-length slider.
- Shared camera position, azimuth, pitch, height, focal length, and UTC timestamp.
- Automatic [session recovery](docs/session-recovery.md): location, UTC time, unsaved composition and UI preferences survive exit. First launch uses the current time; playback resumes paused.
- Account-free Mapterhorn terrain: Copernicus GLO-30 plus finer open regional
  DEMs, with Mapzen fallback, rendered in a camera-relative WGS84 frame.
- Terrain-derived camera height, progressive loading, distance/FOV quadtree LOD, and tile skirts.
- **Terrain range** inspector section: live surrounding radius, FOV-aware forward fetching and render distance; the map shows a dashed approximate requested-range circle.
- Free automatic imagery: USGS NAIP, IGN France, swisstopo Switzerland and
  a global EOX Sentinel-2 2016 fallback, progressively refined on the camera tile.
- Approximate relighting enabled by default; optional natural imagery, without rebuilding terrain.
- Collapsible inspector sections for optics, position/orientation, depth of field, weather and rendering.
- Editable weather visibility, light transmission and rain intensity, preserved in saved plans.
- Persistent terrain/imagery disk caching with one adjustable size limit under **Storage** (512 MiB default), LRU eviction, corruption recovery and source metadata.
- Drag the 3D preview to look around, with finer aiming when zoomed in; change focal length in whole millimeters to zoom optically.
- Click the 3D preview and hold WASD to move at 100 m/s; the camera climbs/descends with terrain while keeping its height offset.
- Offline Sun/Moon topocentric positions, lunar phase and shared celestial readouts.
- NASA SVS/LRO surface-textured, phase-lit Moon at its calculated position and angular size, with terrain occlusion (offline 2K albedo; no libration or crater relief).
- UTC-driven Sun/Moon lighting, sky-driven indirect lighting, cascaded terrain shadows and sky-colored aerial perspective on approximately relit terrain. Per-state astronomy/observer caching removes duplicate ephemeris work per frame.
- Spherical Rayleigh/Mie sky scattering for twilight and moonlit nights, with air-mass extinction for dimmer, redder sunrise/sunset.
- Blended terrain shadow cascades; High quality adds PCSS/contact shadows, denser 256/128/64 terrain meshes, 1.25× supersampling and terrain-scale GTAO with bent-normal indirect lighting.
- Progressive imagery: 256px previews, then a 1024px camera tile; High refines up to nine nearest rendered tiles with bounded three-request concurrency. Failed detail requests retain previews.
- **Rendering → Camera light**: camera-positioned terrain fill, adjustable 0–100% (off by default), without lighting the sky. Requires approximate relighting; Auto exposure is held while active, with two unfilled metering frames after time/weather changes to avoid retaining the previous lighting's exposure.
- Rendering-panel antialiasing: FXAA by default, MSAA 4× with fallback, Auto or Off.
- Sun/Moon map bearing guides with altitude labels and below-horizontal styling.
- Persistent navigation rail for Map/3D Preview/Calendar; compact floating terrain/stars/export controls and compact top loading status and a fixed single-line bottom credit, with grouped timeline controls and astronomy readouts.
- Collapsible inspector with weather/quality/relighting in the right panel; camera-local date/time controls and a **00:00–24:00 local-day slider** with DST-aware UTC conversion.
- Estimated offline local clock with timezone, UTC offset and daylight-saving rules.
- Play/pause at five simulated minutes per second, with lifecycle/date-limit cleanup.
- 5,044 bundled stars and licensed simplified Milky Way brightness contours.
- Time/location-driven sky rotation, approximate twilight/moonlight visibility and terrain occlusion.
- Sun/Moon/Galactic-center targeting, aim action and rectangular lens-FOV readout.
- Toggleable constellation names and blue connecting figures in 3D, depth-tested against terrain.
- Named versioned JSON snapshots, with local save/open and restoration after app restart.
- **Export PNG**: current photographic viewport with source credits, weather and DOF; no application controls.
- **Performance / Balanced / High** render-quality presets (render scale, AA, shadows and DOF quality).
- Manual **Clear / Cloudy / Fog / Rain** presets, explicitly illustrative rather than forecast weather.
- Depth-buffer **depth of field** linked to aperture (f/1.4–f/22), focal length, sensor and focus distance.
- Enhanced/Manual/Auto exposure with ISO, shutter, exposure compensation and approximate white balance.
- Full-area 3D context preview with a sensor-aspect photo rectangle and focal-length/aperture/DOF label; portrait/roll, composition guides and fullscreen preview (Esc exits).
- Adjustable 1/5/30/60 min/s playback and target angular-offset readout.

See [Linux MVP photography controls and export](docs/linux-mvp.md) for usage, limits and validation.

The inset photo rectangle matches the sensor's aspect ratio and map FOV; the
surrounding 3D context fills the available canvas. Lens/roll controls preserve
position; WASD moves explicitly. PNG export crops to the photo rectangle.

## License

PhotoSim is licensed under the [GNU General Public License, version 3 only](LICENSE)
(`GPL-3.0-only`). Copyright © 2026 PhotoSim contributors.
Bundled third-party components and data retain their own licenses and attribution.

## Automated releases

[GitHub Actions](.github/workflows/build.yml) builds Linux `.deb`, pacman and
AppImage packages plus per-ABI Android APKs. Matching `v<version>` tags upload
`PhotoSim-<version>-<arch>.<ext>` assets and checksums to GitHub Releases.
Configure persistent Android signing secrets first; see [release setup](docs/releases.md).

## Build and verify

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter test integration_test/linux_workflow_test.dart -d linux
flutter test integration_test/linux_imagery_test.dart -d linux
flutter test integration_test/linux_photography_test.dart -d linux
flutter test integration_test/linux_sunlight_test.dart -d linux
flutter test integration_test/linux_spec_photography_test.dart -d linux
flutter test integration_test/linux_wasd_test.dart -d linux
flutter test integration_test/linux_loading_test.dart -d linux
flutter test integration_test/startup_test.dart -d linux
flutter test integration_test/camera_light_test.dart -d linux
flutter test integration_test/linux_planning_ui_test.dart -d linux
flutter build linux --release
./build/linux/x64/release/bundle/photosim
```

`analysis_options.yaml` enables strict casts, inference and raw-type checking,
plus correctness/async lints (including dynamic-call and discarded-future checks).
Warnings and lint infos are fatal in the analysis command above; tests and native
integration tests are analyzed too. No extra lint dependency is required.

Ship the **entire bundle directory**, not just its executable. The integration
test requires a live Linux graphical session and internet access on its first
terrain/imagery visit. Subsequent visits reuse the source-separated disk caches within the shared size limit. It writes screenshots to
`build/validation/`.

Frame-time and cold-start measurements, method and remaining bottlenecks are in the
[performance audit](docs/performance.md).

See [implementation status](docs/implementation-status.md) for validation
evidence, rendering limitations, and future work.

## Important limitations

The 3D surface uses **real elevation and automatically selected free imagery**:
NAIP in the conterminous US, IGN in France, swisstopo in Switzerland, and the
approximately 10 m EOX Sentinel-2 **2016** global mosaic elsewhere or as fallback.
Regional aerial sources can be sub-meter, but current terrain textures downsample
them; native aerial detail is not displayed. High uses more GPU time and texture
memory (about 48 MiB for nine 1024px RGBA textures with mipmaps, plus other tiles
and render targets). Refined textures remain resident when lowering quality until
their terrain tiles unload. GTAO is an approximate, screen-space effect on relit
terrain only; it is not a terrain-horizon visibility calculation. Pixels missing from every source use
a labeled green fallback material. Sun/Moon calculations and solar lighting now
work locally, including a phase-lit lunar sphere and approximate moonlight.
Lunar surface detail remains unimplemented. PNG export captures the current viewport,
not an independent high-resolution render. Night-sky
brightness and stellar point sizes are artistic, not calibrated exposure;
proper motion, aberration and atmospheric extinction are omitted. See
[night-sky data notes](docs/data-sources/night-sky.md). Saved plans are local,
unencrypted JSON snapshots; see [saving and reopening](docs/saved-plans.md).
Map rays indicate bearings, not rise/set or terrain visibility predictions.
UTC dates are limited to 1900–2100. Estimated local display supports only
1970–2037 because the bundled timezone transitions stop in 2037; other dates
show an explicit warning. Coordinate-to-zone boundaries are approximate.
The timeline groups the estimated local date/time with the local-day slider.
**Edit local** opens date/time pickers in the camera location's estimated timezone,
not the computer's timezone. The UTC equivalent is previewed before **Apply time**;
**Cancel** leaves simulation time unchanged. Nonexistent daylight-saving times
are rejected; repeated times require an explicit occurrence choice.
UTC remains the internal time basis. Explicit UTC editing preserves the full
1900–2100 range and is the fallback when local rules are unavailable.
See [astronomy notes](docs/astronomy.md) for reference
tests and accuracy/lighting/timezone limitations.

Natural imagery preserves existing colors and baked-in shadows. Opt-in
relighting is approximate and may double those shadows. Imagery dates do not
follow simulation time; source acquisition dates are not queried yet. See
[imagery data notes](docs/data-sources/imagery.md).

Terrain defaults to the original 3×3 zoom-13 region. The **Terrain range** section
in the right inspector (controls drawer on phones) adjusts
surrounding coverage (1–3 tile rings), forward reach (0–40 km, off by default),
and terrain rendering (2–40 km, whole-tile cutoff plus view-frustum culling).
Forward coverage follows sensor/focal length, pitch and azimuth after a 400 ms
pause; long lenses prefer finer tiles, subject to a 256-tile budget. Overlapping
meshes/textures stay resident. Settings apply live and persist in saved plans/session recovery.
The map's dashed circle approximates the nearby tile envelope or forward reach,
whichever is larger. Zoom out to see its full extent. It is not an exact tile
boundary or download-status indicator; render distance does not shrink the fetch circle.

Terrain and imagery share a persistent LRU disk budget configured under **Storage → Total disk cache limit (MiB)**: 512 MiB by default, 0–65,536 MiB; zero disables disk caching. Where regional tiles are absent, the
loader crops the global zoom-12 parent. Upstream regional grids can be 1–10 m,
but current mesh density does not display their finest native detail. Cached terrain works without network access, but this is not a complete
offline-region feature. Source vertical datums are uncorrected; do not use the
coarse preview for precise distant-horizon predictions. See
[terrain data notes](docs/data-sources/terrain.md).

Map tiles require internet access. This prototype uses the public OSM standard
tile service with attribution and an identifying user agent; it does not bulk
download or prefetch regions. Review [OSM's usage policy](https://operations.osmfoundation.org/policies/tiles/)
before distribution or scaling. No paid API or credentials are required.

Linux remains the completed MVP baseline. The Android phone/tablet version
shares its planning/rendering core and has emulator workflow coverage; physical
Android hardware performance is not yet characterized. Web, Windows, macOS and
iOS remain outside the supported build claims.
