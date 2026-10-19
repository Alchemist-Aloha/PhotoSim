# Local photography plans (version 2)

Use the toolbar folder menu:

1. **Save plan**: name the composition and create a new snapshot.
2. **Open plan**: select a saved snapshot; the app returns to a map centered on
   its camera location. Switching to 3D reloads ground data from the geographic
   caches when available.

The title shows **New plan**, **Unsaved changes**, or the saved plan name.
Opening a snapshot with unsaved changes offers **Save changes**, **Discard
changes**, or **Cancel**. Canceling or failing the protective save keeps the current
composition. Each successful save still creates a new snapshot, never overwrites
an existing one. Changes made while a save is in flight remain marked unsaved;
the pending open is canceled rather than discarding those newer changes.
Derived terrain elevation does not count as a composition edit.

[Automatic session recovery](session-recovery.md) preserves the current workspace,
settings and unsaved composition across exit, without overwriting named plans.
Manual snapshots remain separate; recovered edits retain their unsaved indicator.

Both actions pause playback. Saves are independent of terrain/imagery caches,
so cache eviction does not erase plans. Storage is the platform application
support directory plus `photosim/plans-v1`; the open dialog shows the full path.
Native storage is verified on Linux and Android phone/tablet emulators. Android
keeps snapshots in app-private storage; uninstalling the app deletes them.
Android automatic app-data backup is disabled.

Each snapshot is a standalone UTF-8 JSON file containing:

- `version: 2` and a user-provided name (1–80 UTF-16 code units).
- Latitude, longitude, azimuth, pitch and ground-relative camera-height offset.
- Optional legacy `fixedElevation` in meters (-12,000–10,100, source datum) is
  still readable, preserving older saved viewpoints. New WASD movement clears
  this override and follows the terrain while keeping the saved height offset.
  Editing the height offset, moving the camera on the map, or selecting
  **Resume ground-relative height** also clears the override. New walking plans
  store ground-relative behavior, not a frozen elevation.
- Optional `roll` (±180°), `portrait`, `showCrosshair`, `showGrid` and `showLevel`.
  Legacy defaults: zero roll, landscape, crosshair on, grid/level off.
- Optional `exposureMode` (`enhanced`, `automatic`, `manual`), `iso` (50–25,600),
  `shutterSeconds` (1/8000–30), `exposureCompensation` (±5 EV), `whiteBalance`
  (2,000–12,000 K). Legacy defaults: enhanced, ISO 100, 1/125 s, 0 EV, 6,500 K.
  These are relative exposure/approximate grading, not calibrated radiometry.
- Sensor enum identifier and focal length in millimeters (8–600 mm).
- Canonical UTC ISO-8601 simulation timestamp.
- Selected target (`none`, `sun`, `moon`, `galacticCenter`).
- Optional `cameraLightStrength` (0–100%, default off), the terrain-only camera fill.
- Natural/approximate-relighting preference. New sessions enable approximate
  relighting; opening a plan preserves its stored preference.
- Optional `showConstellations` toggle; missing in older plans defaults to off.
- Optional `terrainRings` (integer 1–3), `terrainForwardKm` (0–40) and
  `terrainRenderKm` (2–40). Older plans default to 1 ring, forward off and a
  40 km whole-tile render radius. Missing fields do not require a schema bump.
- Optional `antialiasing` (`automatic`, `off`, `fxaa`, `msaa`); missing fields
  default to FXAA. This preference is independent of quality and preserves geometry.
- Optional `renderQuality` (`performance`, `balanced`, `high`), `weather`
  (`clear`, `cloudy`, `fog`, `rain`), `depthOfField`, `aperture` (1.4–22) and
  `focusDistance` (1–1,000,000 meters). Legacy defaults: Balanced, Clear, off,
  f/8 and 1 km focus. All fields are validated and preserve UTC/camera state.
- Optional `weatherVisibilityKm` (0.1–100), `weatherLightTransmission` (0–1)
  and `rainIntensity` (0–1). Missing fields use the selected weather preset's
  defaults. Parameter edits persist; changing presets resets their defaults.

Legacy version-1 files remain readable: their obsolete `lens` preset field is
ignored, while focal length and sensor are preserved. New version-2 files omit
that field. The existing `plans-v1` storage folder is retained so old plans stay
accessible; older app builds may not support version-2 files.

Ground elevation, downloaded data, playback state and derived sky positions
are not stored. Elevation is recalculated when terrain loads. Copy JSON files
to the displayed storage folder to share or reopen them; no file-picker import,
export, deletion, rename, automatic named-plan saving or cloud account is implemented.

The loader caps files at **32 KiB**, checks the version, types, UTC date syntax,
enum identifiers and camera/date bounds. It does not silently clamp invalid
inputs. Unreadable/unsupported files are counted in the picker and left intact;
one corrupt file does not prevent valid snapshots from opening. Loading errors
do not replace the current simulation state.

Saves use flushed staging files and a new exclusively reserved destination,
then rename on completion. Existing snapshots are never overwritten. Failed
writes clean up their own temporary state; interrupted staging directories are
ignored, and incomplete destination files are reported as unreadable. This is
not a power-loss durability guarantee or a multi-process plan database.

Plans contain precise camera coordinates and times in **unencrypted local
files**. OS account/directory permissions govern access; sharing a plan shares
those details.

Unit tests cover complete round-trips, UTC normalization, all selected targets'
serialization path, malformed schemas/ranges, concurrent new saves, corruption,
size limits and failed writes preserving existing data. The Linux GPU workflow
saves via the actual UI, destroys the app, recreates it with a fresh repository,
opens the snapshot, verifies every stored field and map centering, then restores
cached terrain/imagery in 3D. Screenshot:
`build/validation/linux-reopened-plan.png`.
