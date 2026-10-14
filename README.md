# PhotoSim

Linux-first landscape photography simulator built with Flutter. This is the
terrain, imagery and Sun/Moon-lighting milestone of [the MVP roadmap](docs/roadmap.md), **not the complete MVP**.

## Run on Linux

Requires Flutter **3.47.1 or newer** (developed with 3.47.6), Clang, CMake,
Ninja, GTK 3 development libraries, and an Impeller-compatible graphics driver.

```sh
flutter pub get
flutter run -d linux
```

The Linux runner enables Flutter GPU permanently; no extra rendering flags
are needed. Direct dependencies are pinned and `pubspec.lock` is included.

## Available now

- Interactive OpenStreetMap map centered on Yosemite.
- Click to place a camera; drag its marker to move it and its green handle to aim.
- Geographic field-of-view wedge calculated from physical sensor and focal length.
- Full-frame / APS-C sensors, three zoom presets, and custom focal lengths.
- Shared camera position, azimuth, pitch, height, focal length, and UTC timestamp.
- Real Mapzen elevation terrain rendered in a camera-relative WGS84 frame.
- Terrain-derived camera height, progressive loading, simple distance LOD, and tile skirts.
- USGS NAIP aerial imagery, progressively refined on the camera tile.
- Natural imagery and opt-in approximate relighting, without rebuilding terrain.
- Independent bounded terrain/imagery caches with corruption recovery and source metadata.
- Drag the 3D preview to look around; change focal length to zoom optically.
- Offline Sun/Moon topocentric positions, lunar phase and shared celestial readouts.
- Phase-lit Moon at its calculated position and angular size, with terrain occlusion.
- UTC-driven Sun/Moon lighting, cascaded terrain shadows and approximate clear sky.
- Sun/Moon map bearing guides with altitude labels and below-horizontal styling.
- Collapsible inspector, UTC date/time controls and shared minute-resolution day slider.
- Estimated offline local clock with timezone, UTC offset and daylight-saving rules.
- Play/pause at five simulated minutes per second, with lifecycle/date-limit cleanup.

The preview maintains the sensor's aspect ratio so map and 3D fields of view
agree. Camera controls never translate the 3D camera implicitly.

## Build and verify

```sh
flutter analyze
flutter test
flutter test integration_test/linux_workflow_test.dart -d linux
flutter build linux --release
./build/linux/x64/release/bundle/photosim
```

Ship the **entire bundle directory**, not just its executable. The integration
test requires a live Linux graphical session and internet access on its first
terrain/imagery visit. Subsequent visits reuse the independent disk caches. It writes screenshots to
`build/validation/`.

See [implementation status](docs/implementation-status.md) for validation
evidence, rendering limitations, and the next roadmap milestone.

## Important limitations

The 3D surface uses **real elevation and USGS NAIP aerial imagery** where
available in the conterminous US. Other regions and missing image pixels use a
labeled green fallback material. Sun/Moon calculations and solar lighting now
work locally, including a phase-lit lunar sphere and approximate moonlight.
Lunar surface detail, stars, saved plans and exports remain unimplemented.
Map rays indicate bearings, not rise/set or terrain visibility predictions.
UTC dates are limited to 1900–2100. Estimated local display supports only
1970–2037 because the bundled timezone transitions stop in 2037; other dates
show an explicit warning. Coordinate-to-zone boundaries are approximate.
All editing remains UTC. See [astronomy notes](docs/astronomy.md) for reference
tests and accuracy/lighting/timezone limitations.

Natural imagery preserves existing colors and baked-in shadows. Opt-in
relighting is approximate and may double those shadows. Imagery dates do not
follow simulation time; source acquisition dates are not queried yet. See
[imagery data notes](docs/data-sources/imagery.md).

Terrain loading covers a fixed 3×3 region at zoom 13, with a 256 MiB LRU disk
cache. Cached terrain works without network access, but this is not a complete
offline-region feature. Source vertical datums are uncorrected; do not use the
coarse preview for precise distant-horizon predictions. See
[terrain data notes](docs/data-sources/terrain.md).

Map tiles require internet access. This prototype uses the public OSM standard
tile service with attribution and an identifying user agent; it does not bulk
download or prefetch regions. Review [OSM's usage policy](https://operations.osmfoundation.org/policies/tiles/)
before distribution or scaling. No paid API or credentials are required.

Only Linux is scaffolded and tested at this stage. Other platforms and the
full Phase 0 cross-platform exit criteria remain open.
