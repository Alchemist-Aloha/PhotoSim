# PhotoSim

<!-- impeccable:product-schema 1 -->

## Platform

Linux desktop (native Flutter).

Mobile is a future extension of the same product and design language, not a currently supported release. Improve the Linux desktop experience first, while keeping the design extensible to mobile.

Tooling note: Impeccable's current platform schema lists only `web`, `ios`, `android`, and `adaptive`; none accurately describes this Linux-only release. Do not treat this application as a website or claim native mobile support to satisfy that schema.

## Users

Landscape photographers and astrophotographers scouting locations and photographic compositions before visiting in person.

## Product Purpose

Help photographers explore where to stand, where to aim, which camera/lens settings to use, and when to photograph a landscape or celestial alignment. Combine real terrain and imagery with locally calculated astronomy in a photographic preview.

Success is a coherent planning workflow: place and aim a camera on the map, inspect its simulated view, adjust optics and time, and save or export the composition without losing shared state.

## Positioning

A Linux-first photography planning tool combining synchronized geographic and 3D workspaces, physical camera field of view, real terrain and freely available imagery, and local astronomical calculations without requiring paid APIs or credentials.

## Operating Context

- Flutter/Dart Linux desktop application; launch with `flutter run -d linux`. See `README.md` for system requirements.
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
- Linux desktop improvements are the current priority. Carry a similar design language to future mobile layouts without merely shrinking desktop controls. Mobile target OS and implementation scope remain undecided.
- Android, Web, Windows and macOS are not currently supported releases.

## Brand Commitments

Preserve the PhotoSim name and photography-planning terminology. The interface should serve photographic planning rather than expose the complexity of a general 3D modeling application. Future mobile work should extend the desktop's design language.

No new visual direction is established by this product record.

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
5. Improve Linux desktop usability now while making future mobile interaction a considered extension of the same product.
