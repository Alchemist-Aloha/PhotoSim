# PhotoSim

<!-- impeccable:product-schema 1 -->

## Platform

android

Native Flutter on Android phones/tablets and Linux desktop. Android follows Material 3, with size-based phone/tablet layouts and system light/dark theme. Linux retains its established desktop workflow. Android currently targets API 29+; emulator coverage does not establish performance on physical hardware.

## Users

Landscape photographers and astrophotographers scouting locations and photographic compositions before visiting in person.

## Product Purpose

Help photographers explore where to stand, where to aim, which camera/lens settings to use, and when to photograph a landscape or celestial alignment. Combine real terrain and imagery with locally calculated astronomy in a photographic preview.

Success is a coherent planning workflow: place and aim a camera on the map, inspect its simulated view, adjust optics and time, and save or export the composition without losing shared state.

## Positioning

A Linux-first photography planning tool combining synchronized geographic and 3D workspaces, physical camera field of view, real terrain and freely available imagery, and local astronomical calculations without requiring paid APIs or credentials.

## Operating Context

- Shared Flutter/Dart application; launch with `flutter run -d linux` or an Android device ID. See `README.md` and `docs/android.md` for requirements and validation.
- Two primary workspaces: Map and 3D Preview. Camera, optics, location and simulation time remain synchronized when switching.
- Secondary tools include photography controls, astronomy readouts, weather/rendering settings, terrain coverage, storage, saved plans and PNG export.
- Network access supplies map tiles and uncached terrain/imagery. Local raster caching supports reuse, not complete offline-region downloading.
- Saved plans are local, unencrypted JSON snapshots. Astronomy and rendering run locally.

## Capabilities and Constraints

- Preserve physical sensor/focal-length field of view and shared camera/time state across workspaces.
- Available features include terrain/imagery preview, Sun/Moon and night-sky visualization, optics/exposure controls, illustrative weather, depth of field, playback, local plans and attributed viewport PNG export. Consult current implementation rather than assuming the long-term specification is delivered.
- Prefer free data sources and local computation. Preserve provider attribution and licensing obligations, including on image export.
- Explicitly distinguish calculated geometry from approximate lighting, weather, exposure, terrain visibility and night-sky appearance. Do not present the preview as calibrated photography, a forecast or survey-grade horizon prediction.
- Date/time editing defaults to the camera location's estimated local timezone, not the computer's timezone. Convert to UTC internally; reject nonexistent local times and explicitly disambiguate repeated hours. UTC is authoritative; supported simulation dates are 1900–2100. Estimated local time is limited to 1970–2037, with approximate timezone boundaries and explicit UTC editing outside supported local rules.
- Imagery may be old, downsampled and already shadowed; acquisition dates do not follow simulation time. Terrain resolution and vertical datums limit precision.
- Android phones and tablets use Material 3: compact bottom navigation, a navigation rail in larger windows, modal controls below docking width and side-by-side controls on expanded windows. Preserve Linux desktop behavior.
- Android PNG export uses MediaStore Pictures/PhotoSim, with no broad storage permission. App-private saved plans and cache remain local; Android automatic app-data backup is disabled.
- Web, Windows, macOS and iOS remain outside supported build claims.

## Brand Commitments

Preserve the PhotoSim name and photography-planning terminology. The interface should serve photographic planning rather than expose the complexity of a general 3D modeling application. Android extends the desktop's design language through Material 3 components, semantic color roles and touch-appropriate layouts.

## Evidence on Hand

- `README.md`: running instructions, available capabilities and important limitations.
- `docs/linux-mvp.md`: authoritative completed Linux MVP scope.
- `docs/linux-spec-progress.md`: subsequent delivered work and unfinished Linux requirements.
- `docs/spec.md`: long-term product specification, not proof of delivered functionality.
- `docs/implementation-status.md`: recorded validation evidence and rendering limitations.
- `docs/data-sources/`, `docs/astronomy.md` and `docs/saved-plans.md`: provenance, accuracy and persistence constraints.
- `test/` and `integration_test/`: automated checks and native workflow tests; generated visual evidence is described in the project docs under `build/validation/`.

These are repository records, not fresh verification performed during initialization. Do not fabricate performance benchmarks, accuracy guarantees or supported-platform claims.

## Product Principles

1. Keep photographic planning primary; reveal technical controls without making them the main task.
2. Preserve one coherent camera and time state across every workspace.
3. Use real geographic data and calculated camera/astronomical geometry; identify approximations plainly.
4. Keep the core workflow independent of paid services and retain required source credits.
5. Keep Linux desktop and Android phone/tablet interactions coherent while adapting layout and navigation to the actual window size.
