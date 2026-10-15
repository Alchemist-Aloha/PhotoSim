# Local photography plans (version 2)

Use the toolbar folder menu:

1. **Save plan**: name the composition and create a new snapshot.
2. **Open plan**: select a saved snapshot; the app returns to a map centered on
   its camera location. Switching to 3D reloads ground data from the geographic
   caches when available.

Both actions pause playback. Saves are independent of terrain/imagery caches,
so cache eviction does not erase plans. Storage is the platform application
support directory plus `photosim/plans-v1`; the open dialog shows the full path.
Native storage is currently **verified only on Linux**.

Each snapshot is a standalone UTF-8 JSON file containing:

- `version: 2` and a user-provided name (1–80 UTF-16 code units).
- Latitude, longitude, azimuth, pitch and camera height above ground.
- Sensor enum identifier and focal length in millimeters (8–600 mm).
- Canonical UTC ISO-8601 simulation timestamp.
- Selected target (`none`, `sun`, `moon`, `galacticCenter`).
- Natural/approximate-relighting preference.
- Optional `showConstellations` toggle; missing in older plans defaults to off.
- Optional `terrainRings` (integer 1–3), `terrainForwardKm` (0–40) and
  `terrainRenderKm` (2–40). Older plans default to 1 ring, forward off and a
  40 km whole-tile render radius. Missing fields do not require a schema bump.
- Optional `renderQuality` (`performance`, `balanced`, `high`), `weather`
  (`clear`, `cloudy`, `fog`, `rain`), `depthOfField`, `aperture` (1.4–22) and
  `focusDistance` (1–1,000,000 meters). Legacy defaults: Balanced, Clear, off,
  f/8 and 1 km focus. All fields are validated and preserve UTC/camera state.

Legacy version-1 files remain readable: their obsolete `lens` preset field is
ignored, while focal length and sensor are preserved. New version-2 files omit
that field. The existing `plans-v1` storage folder is retained so old plans stay
accessible; older app builds may not support version-2 files.

Ground elevation, downloaded data, playback state and derived sky positions
are not stored. Elevation is recalculated when terrain loads. Copy JSON files
to the displayed storage folder to share or reopen them; no file-picker import,
export, deletion, rename, autosave or cloud account is implemented.

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
