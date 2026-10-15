# Full Linux specification implementation

## Scope and status

The current request targets the full non-platform specification, beyond the
already completed Linux 0.1 MVP. **The full Linux specification is not complete.**
Android, Web, Windows and macOS remain excluded. Optional future extensions in
spec §26 are not treated as already delivered.

This ledger separates working features from remaining work. It supersedes any
interpretation of “Linux MVP complete” as “every Linux feature in spec.md done.”

## Delivered in the first spec-completion slice

| Spec | Feature | Implementation / checks |
|---|---|---|
| §4.5, §10.7 | Enhanced, Manual and Auto exposure | ISO 50–25,600, shutter 1/8000–30 s, f/1.4–22, ±5 EV; GPU luminance metering; validated stop ratios and actual brighter/darker GPU pixels |
| §4.5 | White balance | 2,000–12,000 K approximate backend grading, neutral at 6,500 K; not calibrated chromatic adaptation |
| §2.2, §3.2, §4.4 | Roll and portrait framing | ±180° clockwise camera roll, landscape/portrait sensor dimensions, shared FOV/camera basis, map wedge, forward coverage, target-frustum checks and constellation-label projection |
| §3.4 | Composition overlays | Independently toggleable crosshair, thirds and geometric horizontal level; ignored by gestures and excluded from exported photographs |
| §3.4 | Fullscreen preview | GTK fullscreen request plus clean photographic content, hidden app/scene toolbars, panels, timeline and in-scene planning guides; exit with Esc or exit button; no geographic reload |
| §15.1 | Playback speed | 1, 5, 30 or 60 simulated minutes/second, default 5; pause/lifecycle/bounds behavior retained |
| §15.3 | Target angular offset | Angular separation from the actual rolled camera center, alongside existing azimuth/altitude and FOV information |
| §17.1 | Composition persistence | New camera, exposure and overlay settings stored in v2 plans with validation; old plans retain legacy appearance defaults |
| §19 | Portrait export | PNG keeps the oriented sensor aspect ratio, roll/exposure/effects and credits, without composition UI guides |

Exposure uses real stop ratios relative to the renderer reference f/8, 1/125 s,
ISO 100. Enhanced visibility ignores ISO/shutter; Auto meters rendered luminance.
All modes support exposure compensation and approximate white balance. Manual
exposure is **not a claim of calibrated scene radiance**, nor noise, diffraction,
motion blur or physically calibrated astrophotographic brightness.

Roll and portrait change camera projection/visibility, not the terrain origin.
When forward fetching is enabled they can change required coverage, preserving
overlapping meshes/textures. Time, exposure and guide changes do not fetch or
rebuild geographic data. Fullscreen is transient UI state, not a saved plan field.

## Horizontal WASD navigation

Click the 3D preview to focus it. Hold W/S to move forward/back along the crosshair's
horizontal bearing, A/D to strafe left/right. Pitch, roll and focal length do not
change the travel direction or speed. Movement is 30 m/s with normalized diagonals
and capped frame deltas to prevent jumps after stalls. Keyboard shortcuts with
Ctrl/Alt/Meta are not consumed. Movement stops on focus loss, dialogs, leaving 3D,
backgrounding and disposal; typing in text fields does not move the camera.

The first step captures absolute camera elevation = loaded terrain elevation +
height offset. That value stays unchanged by WASD, regardless of the new terrain
height. The map/astronomy use the actual moved coordinates and the fixed elevation.
An elevation readout and **Resume ground-relative height** are in the inspector;
changing the height offset or moving the camera through the map clears the lock.
The lock persists in plans. No collision/ground-following is applied: horizontal
movement can enter terrain on a rising slope.

Nearby motion retains the geographic mesh origin and one camera-tile height field.
Double-precision WGS84 frame transforms move terrain into the current observer's
ENU frame without rebuilding geometry or changing sky direction conventions.
Coverage updates are throttled; leaving the zoom-13 camera tile rebases/streams
geography and can briefly pause navigation while ground data loads. Missing
camera-ground data disables movement instead of guessing an altitude.

The Linux WASD native workflow covers held W, fixed elevation/height offset,
resource/download reuse, dialog and map focus, map synchronization and a 5 km
terrain rebase that preserves elevation. Unit/widget checks cover all directions,
pitch independence, diagonals, lifecycle/modifiers/disposal, saved lock/defaults,
validation, polar/dateline behavior and WGS84 frame-transform agreement.

## Still required / partial, ordered for subsequent slices

| Spec | Remaining Linux work |
|---|---|
| §17, §19.1 | Plan edit/rename, explicit duplicate/delete/search and portable JSON import/export UI; existing named save/open remains implemented |
| §2.2 | Location search, numeric placement/elevation override, map imagery/terrain layers, compass and scale; optional contours |
| §3.2, §15.3 | Horizontal WASD is implemented; orbit/other exploration controls, return-to-composition and actual astronomical tracking lock remain |
| §5.4, §6.5, §9 | Independent curvature-aware terrain-horizon profiles, uncertainty and target obstruction; authoritative source-datum/model metadata and supported vertical-datum conversions |
| §8, §15.2 | Rise/set, solar-noon/twilight and Galactic visibility event services/timeline; refraction with atmospheric inputs and event-horizon handling |
| §8.8, §15.3 | Bright-planet ephemerides/rendering, prominent-star/planet target selection and labels; independent reference fixtures |
| §6, §7.4, §13 | Viewport/screen-error terrain and texture refinement, neighbor-aware transitions, horizon culling, explicit GPU budgets and measured FPS/latency/memory regressions |
| §7.6, §13.4, §16 | Acquisition dates when available, refresh/expiry/cache settings and restrictions-aware eviction; metadata/indexing storage requirements |
| §10 | Improved below-horizon twilight, atmospheric perspective/extinction/airglow/light pollution, simultaneous physical solar/lunar contributions and better radiometric/color validation |
| §11 | Optional forecast client/cache with UTC/location matching, source/freshness metadata and clear out-of-window/offline behavior; manual weather is implemented |
| §12.2, §12.5 | Extract GPU orchestration behind the renderer interface, explicit resource/lost-device recovery and lifecycle profiling |
| §18 | Light/dark theme control, remaining configurable overlays/distance tools and desktop-responsive validation |
| §19.3 | Bounded independent-resolution/offscreen export and optional richer metadata, rather than current viewport-only PNG |
| §20, §23 | Broader geographic/astronomical/lighting reference validation and provider release-terms verification |

These are open tasks, not silently deferred platform work. Some precision
features require trustworthy source metadata/data; unknown datums and acquisition
dates must remain explicitly unknown rather than invented.

## Verification for this slice

- 128 unit/widget tests (including WASD), including stop ratios, framing/roll, bounds, old/new plan
  formats, exposure controls, overlays and playback rate.
- New Linux native photography-tools workflow verifies GPU exposure response,
  Auto metering, white-balance settings, portrait projection/DOF sensor size,
  rolled camera up, fullscreen/Esc resource reuse and portrait PNG export.
- Existing Linux workflow, imagery, photography-effects and sunlight workflows
  also pass.
- Artifact: build/validation/linux-portrait-exposure-export.png.
- Linux release build and analysis are checked alongside this ledger.

Run the new native workflow with:

```sh
flutter test integration_test/linux_spec_photography_test.dart -d linux
flutter test integration_test/linux_wasd_test.dart -d linux
```
