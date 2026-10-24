# Performance and robustness work log

Running log of optimisation and hardening work, newest first. Each entry names
the commit, the problem, the change, and the evidence that it is safe and
worthwhile. Anything measured is measured, never estimated, and the method is
recorded next to the number.

Read alongside [performance.md](performance.md) (baseline methodology and
before/after numbers) and [implementation-status.md](implementation-status.md).

## How entries are verified

Every commit in this log passed, before being committed:

```sh
flutter analyze                                    # 0 issues
dart format --output=none --set-exit-if-changed lib test integration_test
flutter test                                       # currently 252 tests
```

Changes touching rendering, GPU state or widgets also run the relevant
`integration_test/*_test.dart` on a real Linux GPU device
(`flutter test integration_test/<file> -d linux`), because those tests assert
pixels, scene-graph state and GPU pass structure that unit tests cannot see.

Where a change is meant to be behaviour-preserving, the output is fingerprinted
before and after: a running hash over the produced bytes (mesh positions,
decoded RGBA, encoded session) is captured on both sides and required to match.
Green tests alone do not prove a mesh or an encoder still emits the same data.

## Environment

Linux desktop, Flutter 3.47.7 / Dart 3.13.5 profile-capable build, NVIDIA GPU
with X11. Absolute timings are debug-JIT unless stated otherwise, so treat
relative deltas as the signal and absolutes as pessimistic.

---

## 2026-10-24 — idle renderer cap

### `391aa7e` perf: cap idle scene rendering at five frames per second

`SimulationWorkspace` rendered a static frame at every display refresh. Added a
one-second activity window after composition/fullscreen/workspace changes;
`SceneView.maxFrameRate` is 5 outside that window, and null during loading,
imagery loading and export. Repeated edits/playback keep the renderer uncapped.
Only a local `ValueListenableBuilder` rebuilds when the activity window ends;
photography configuration and imperative scene overrides remain untouched.
The activity timer and notifier are disposed with the workspace.

Files: `lib/ui/simulation_workspace.dart`,
`integration_test/idle_render_test.dart`.

Measured with real engine vsync (`fullyLive` binding), deterministic offline
terrain/imagery fixtures, a fixed UTC composition and the Linux NVIDIA GPU in a
debug build. For each quality tier: wait two wall-clock seconds, then divide the
actual `renderStats.frameCount` delta by elapsed time over two seconds; separately
measure camera edits for two seconds. Baseline was captured before the production
change using `--dart-define=IDLE_CAP_BASELINE=true`; that test flag changes only
assertions/output filenames, not application behavior.

| Tier | Before idle fps | After idle fps | After active edits fps |
|---|---:|---:|---:|
| Balanced | 59.45 | 5.00 | 58.60 |
| High | 58.94 | 4.99 | 59.73 |

This is roughly **12× fewer idle scene renders**, not a measured power or GPU-time
claim. Baseline active rates were 50.49/55.96 fps in the earlier run; active rates
vary with test driving and system load, so no interaction speedup is claimed.
The renderer has no configured cap during edits. Returning the camera to its
original pose reproduces the same image after settling back to idle.

Fingerprint proof: running hash over every rendered raw RGBA byte before/after
matches exactly at both tiers: Balanced **5612850919298858**, High
**8863014974402700**. The final test rerun reproduced both hashes. Captures include
the same native window size and fixed fixture state; no quality settings changed.
Artifacts: `build/validation/idle-render-{before,after}.json`,
`idle-cap-final-idle_render_test.log`, `idle-cap-final-summary.txt`.

Verification: analyzer 0 issues; format clean; **252 unit/widget tests pass**.
All **23 integration-file invocations** succeeded individually on `-d linux`:
20 executed, while Android workflow and the two Windows files platform-skipped.
This includes atmosphere, camera light, clouds, imagery, terrain, Moon/Milky Way,
loading/startup, navigation, quick export, Export workspace and profile harness.
An initial sequential run stalled attaching to startup; it was terminated, and
startup plus the full final suite passed with a per-file 180-second bound.
No Android hardware/frame-rate or power measurement was performed.

The rejected whole-workspace timer variant and its baseline checks are recorded
below so it is not reintroduced.

---

## 2026-10-24 — requested export workspace

### `11cb0c6` fix: give image exports a dedicated review workspace

The user's requested export review/AI-context workflow took priority over the
hardening backlog for this iteration. The old save shortcut offered no dedicated
review surface and no reusable capture metadata for an external image model.

Added the Export bar/rail destination, session destination validation, a PNG
preview using the exact buffer passed to the existing native saver, and an
editable/copyable enhancement prompt. The prompt includes the complete captured
composition, coordinates, UTC and estimated local time, elevations (explicitly
unknown where unavailable), camera/optics/exposure, weather, Sun/Moon/galactic
center positions, render settings, output size and source credits. Privacy and
simulation/forecast/AI limitations are visible; nothing calls an AI service.

Files: `lib/app/app.dart`, `lib/data/app_session.dart`,
`lib/data/enhancement_prompt.dart`, `lib/ui/export_panel.dart`,
`lib/ui/simulation_workspace.dart`, related unit/widget/integration tests and
`README.md`. Existing quick export, quality presets, credit stamp and
no-overwrite saver remain in use. Drafts survive 3D/Export switching, not
Map/Calendar/restart; re-rendering explicitly resets the prompt.

Verification: analyzer 0 issues; format clean; **252 tests pass**. Both
`integration_test/export_workspace_test.dart` and
`integration_test/linux_spec_photography_test.dart` pass on the real Linux GPU
when invoked separately. The new test proves saved bytes equal preview bytes,
output exceeds screen size (fixture capture: **2266×1511** after crop from a
**2518×2042** 2× render), editable clipboard output, stale capture handling and
re-rendering. The hidden scene's frame counter stays unchanged across ten
30 ms pumps after capture (not a wall-clock frame-rate benchmark).

Inspected `build/validation/linux-export-workspace.png` (real geographic imagery,
portrait/roll capture); fixture screenshot `linux-export-tab.png` is deliberately
synthetic. Compact/expanded layouts and 1.3 text scaling are widget-tested.
No Android device/emulator was connected, so fresh native Android screenshots
and MediaStore validation were unavailable. The combined two-file integration
invocation failed to attach to its second app; rerunning that test alone passed.
No performance claim beyond the tested hidden-render stop is made.

---

## 2026-10-24 — hardening loop

### `1e7e640` test: wait for a real render before capturing GPU pixels

`integration_test/atmosphere_test.dart` mutated the scene (fog, light
intensity, environment, ambient occlusion, shadows), pumped a fixed 100 ms, then
captured the `RepaintBoundary`. That is only valid while the preview renders
every single frame: a pump schedules a frame but the ticker decides whether to
draw it, so the capture could silently observe the previous scene state as soon
as frame output is gated for any reason.

Added `pumpUntilRendered(tester, world, {frames})` to
`integration_test/workspace_navigation.dart`. It waits on
`Scene.renderStats.frameCount`, which only advances when a frame actually
rendered, and converted the seven capture sites that relied on one fixed pump.

Verified: `atmosphere_test` passes on `-d linux`, 247 unit tests pass.

This is the prerequisite for the idle frame-rate cap: the cap was previously
rejected only because nine tests depended on render-per-pump determinism.

---

## 2026-10-24 — test suite repair, export quality, terrain LOD

### `08a5509` style: apply dart format to files touched by the perf commits

Four files from the performance commits below wrapped a line past the
formatter's limit and would have failed CI's
`dart format --set-exit-if-changed`. Formatting only.

### `a7ec18b` test: guard the Android workflow and repair the Linux workflow test

`android_workflow_test.dart` asserts the Android gallery export channel and its
"Saved PNG to Pictures/PhotoSim" snackbar, so it fails anywhere else. It was the
only workflow test missing the platform guard the Windows tests already have.
Added `skip: !Platform.isAndroid`.

`linux_workflow_test.dart` had four independent breakages, all found by
bisecting the test against `21e04f9` in a separate `git worktree`:

- The textured-mesh assertion filtered on `name != 'Moon'`, which also matched
  the procedural `Clouds` node added by an earlier feature commit: 10 nodes
  where the test means the 9 terrain tiles. Now filters on the `z-x-y` terrain
  name pattern used elsewhere in the suite.
- A "Camera moved / Undo" snackbar floats over the timeline and swallowed the
  tap on "Later by one hour" — the framework reported
  `derived an Offset (Offset(377.2, 993.0)) that would not hit test`, so the
  sun never moved and the light direction stayed identical. The test now
  dismisses the snackbar before tapping.
- The plan-save confirmation was queued behind that same ten-second snackbar;
  see the app fix below.
- One wait assumed exiting the clean preview completes within one second; it
  now pumps until the AppBar returns.

### `d3b276e` feat: render the saved photograph above screen density

The export captured the screen `RepaintBoundary` at the device pixel ratio, so
the saved file could never contain more pixels than the 3D view had rendered —
raising `toImage(pixelRatio:)` alone only upscales the composited texture. A
typical window produced roughly a 1.5 MP photograph.

`Scene.renderScale` is the render-target multiplier
(`target = viewArea × dpr × renderScale`), so the export now re-renders the
frame at twice the device pixel ratio and captures at the matching ratio.
Because `configurePhotography` resets `renderScale` to the on-screen tier on
every build, the override is applied after it, and the capture waits two frames
(one applies the scale, one renders into the larger target).

- `exportOversample = 2.0`, bounded by 6144 px and 20 MP
- the attribution stamp now scales with image width instead of a fixed 11 px
  line that had become unreadable on large exports
- measured on the portrait export path: **872×848 → 1744×1696 (2.00×)**

### `3a3123c` fix: show the save confirmation ahead of the camera-move undo prompt

`savePlan` queued its confirmation behind whatever `ScaffoldMessenger` was
already showing. `offerCameraUndo` shows a **ten-second** snackbar, so after any
camera move the "Saved *name* · *path*" confirmation waited ten seconds — or
never appeared if another camera move interrupted it. Move-then-save is the
normal flow, so a successful save could produce no acknowledgement at all.
Removed the current snackbar first, as `offerCameraUndo` already does.

### `41b9bcf` perf: step terrain mesh resolution down with camera distance

`terrainMeshResolution` keyed only on zoom: every zoom-13 tile in the requested
coverage got 64 samples (128 at High) whether it sat 1 km or 30 km away, so a
distant ridge burned the same vertex budget as the hillside under the camera.

Samples now follow a tile's apparent size: full neighbourhood resolution until
a tile is more than 2.5 of its own widths from the camera, then halving per
doubling, floored at 16 samples so horizon silhouettes survive. Distance uses
the camera's fractional tile coordinate, so it wraps the date line and needs no
haversine.

Total terrain vertices over the requested coverage:

| Forward reach | Balanced | High |
|---|---|---|
| 0 km (3×3) | 51 748 → 51 748 | 201 764 → 201 764 |
| 20 km | 160 648 → 86 920 | 624 264 → 335 496 |
| 40 km | 223 860 → 95 668 | 867 316 → 366 708 |

−46 % and −57 % vertex load when distant coverage is requested; the default
3×3 view is untouched.

---

## 2026-10-24 — allocation and redundant-work pass

Fixes below were each proven behaviour-preserving with a running hash over the
produced output captured before and after, in addition to the full suite.

### `a17971d` perf: build the session composition map instead of reparsing it

`AppSession.encode()` reached the nested composition through
`jsonDecode(SavedPlan(...).encode())`: pretty-print the whole state to indented
JSON, parse it straight back to a `Map`, re-encode the outer object. Two full
JSON traversals per save for a value it already had. This runs on every
autosave, which is scheduled from `setState` and therefore repeats every 500 ms
during playback or a sustained edit. Encode cost for a 1983-byte session:
**32.5 µs → 24.8 µs**. Saved bytes byte-identical (length and hash matched on
the session, its round trip, the plan and the plan round trip).

### `439fd7a` perf: stop recomputing pure per-build values in the state and map UI

`SimulationState.cameraFrame` rebuilt the ENU basis into seven fresh `Vector3`s
on every read, and five call sites read it per frame: workspace build,
constellation label layout, guide painter, and twice from the timeline readouts.
The state is immutable, so it is now a `late final`: one basis per frame instead
of five to seven. `MapWorkspace.build` also resolved each celestial body's
bearing leg twice (once per layer) — 135 `destination()` calls per map rebuild
became 129.

### `e87fd81` perf: drop allocation churn from terrain mesh construction

`buildTerrainPatch` allocated a throwaway list literal per vertex, per quad and
per skirt edge, and the normal-accumulation loop built a closure plus four
`Vector3`s per triangle (`Vector3.cross` allocates too) — about 7 objects for
each of 132 k triangles at r256. Replaced with the same expressions in the same
order as `vector_math`'s cross, accumulated into `double`s.
**52.0/50.1 ms → 42.3/41.8 ms per r256 patch (~18 %).** Positions, normals, uvs
and indices hashed identically at resolutions 16, 64, 128 and 256.

### `44fadce` perf: reuse one Pixel when scanning decoded imagery

`image`'s `Image.getPixel(x, y)` constructs a fresh `PixelUint8` on every call —
its optional third argument exists precisely so callers can hoist that
allocation. `decodeImagery` called it per pixel, so a 1024×1024 detail tile
churned 1 048 576 short-lived objects before the blending loop even ran. Also
replaced the `List.generate(8, …).every(…)` PNG signature check with plain byte
comparisons and hoisted the repeated `1 - alpha / 255` term.
**38.0 ms → 34.0 ms per 1024² tile.** All seven decode paths (opaque fixture,
retained transparency, indexed palette opaque/transparent, JPEG, RGBA gradient
with a half-transparent band) hashed identically.

### `f64d67a` perf: write star and Milky Way meshes by index, not setRange literals

`starMesh` and `_milkyWayGeometry` fed `TypedData.setRange` a fresh list literal
per vertex. The bundled catalog has 5 044 stars, so ~91 k lists for positions
and colours plus 40 k for index literals, all built on the UI isolate while the
scene is constructed. Direct index writes remove all of them and hoist the
per-star brightness and per-row cos/sin out of the inner loop.
Output byte-identical (`162/216/144/2971911362996459` before and after).

### `d3669a2` perf: hoist cache filename RegExps out of directory scan loops

`RasterCache._index()` and `TileCache._evict()` built a fresh `RegExp` per
directory entry. Dart does not cache RegExp literals, so each entry paid full
pattern-compile cost, and a startup re-index over a 512 MiB budget walks
thousands of files. Named `static final` patterns now compile once per isolate.

---

## Measured and deliberately not changed

Recorded so the same ground is not re-covered. Each was measured; each was
rejected for a stated reason.

### Idle rendering: initial rejection, resolved by `391aa7e`

The historical rejection below is now resolved: frame-aware atmosphere captures,
an uncapped activity window, local renderer-only cadence updates and the full
Linux integration suite passed. The shipped cap is 5 fps; see the measurements
above. Keep the history as the reason not to reintroduce naïve gating.

#### Original observation: ~60 fps of identical frames

`SceneView` is built with no `maxFrameRate` and default `autoTick: true`, so it
repaints every vsync frame. Measured with `Scene.renderStats.frameCount` deltas
against wall time, engine driving vsync, playback paused, zero input, static
scene: **59.9 fps at Balanced, 55.5–60.0 at High.** `build p50` 4.15 ms while
idle.

A `maxFrameRate` idle cap was implemented and validated — **60 → 5.0 fps** idle
at both tiers, interaction unaffected (37.5/41.1 fps vs 37.4/42.2 baseline),
returning to idle correctly. It was **not shipped**: `maxFrameRate` gating makes
renders-per-pump nondeterministic, measured directly as 30 pumps of 20 ms at a
15 fps cap producing **15** renders instead of 30. Nine integration tests
snapshot GPU pixels after a single `pump(100 ms)`, so they go red.

Correct sequence if this is revisited: first add a "pump until a new frame
lands" helper to those tests, then enable the cap. ~12× idle GPU reduction is
available and pixel-identical.

### Whole-workspace idle timer rebuild (rejected while implementing `391aa7e`)

Calling `setState` on `SimulationWorkspace` when the idle timeout expired caused
`configurePhotography` and `NightSkyRenderer.update` to run again. That silently
restored explicit test scene overrides (AO/shadows and hidden stars), breaking
`atmosphere_test` and `linux_workflow_test`. Both tests were rerun with the exact
pre-cap source from HEAD/HEAD~ and passed, proving the regression belonged to the
candidate. Replaced the parent rebuild with a notifier scoped to `SceneView`;
both tests and the entire integration suite then passed. Do not move the cadence
notification back into the workspace's `setState`.

### Shadow pass is re-rendered from scratch every frame

From `renderStats.latest`, per frame:

| Tier | view | ShadowPass | total |
|---|---|---|---|
| Balanced | 867×848 | 18 draws, 811 k verts | 25 draws, 1.00 M verts, CPU 1348 µs |
| High | 1084×1060 | 19 draws, **3.20 M** verts | 37 draws, 4.65 M verts, CPU 1280 µs |

That is 72 % of draw calls and 81 % of vertices at Balanced, 50 %/69 % at High,
for static terrain lit by a sun that only moves when simulation time changes.
`DirectionalLight.cacheStaticShadows` plus `Node.shadowStatic` would remove most
of it — but `DirectionalCascadeCache.slackFactor` is 1.15, so a cached cascade
spreads the same 4096² map over 2.3× the area: roughly **30 % linear shadow texel
density loss**. That is a quality trade, not a free win, so it was rejected
under a "no quality sacrifice" constraint.

### `SimulationState.copyWith` recomputes astronomy on camera-only changes

`sky` and `observerFrame` are per-instance `late final`s, so every `copyWith`
discards them even when timestamp, position and elevation are unchanged — and
`calculateSky` independently redoes the nutation/ΔT/sidereal series that
`ObserverSkyFrame` already computed. Measured **24.9 µs per frame** during a
drag (0.15 % of a 60 fps budget). Sharing them across copies requires
duplicating the effective-elevation resolution (`fixedElevation` /
`groundElevation` / `height`) inside `copyWith`; the regression risk on correct
numerical code outweighs the gain. Revisit behind a profile build.

### Other measured non-issues

- `RasterCache._evict()` full sort per write once over budget: **0.7 ms/write**
  at 1200 entries.
- `SessionStore.save` synchronous `writeAsStringSync(flush: true)`: **97 µs**
  total. Intentional — a test requires backgrounding to flush without waiting
  for autosave.
- `calculateNightCalendar`: 3318 samples/month, each computing the same nutation
  series twice. **19.3 ms per month**, in `compute()` off the UI isolate.
- `RasterCache._index()`: ~144 ms cold for 1200 entries (~140 MiB). Once per
  launch, and async I/O only yields — it does not block frames.
- `loadImagery`: one `setState` per tile, ~30 workspace-subtree rebuilds per
  site load. Each lands in its own frame, so it is CPU waste, not jank;
  batching would change progressive-credit UI semantics.
- `terrainCoverage._intersects` allocation-heavy SAT: once per terrain load
  behind a 400 ms debounce, not per frame.
- `_RainPainter` 266 `drawLine` calls and a fresh `Random(24)` seed per frame:
  only while raining; consolidating to `drawRawPoints` would change drop
  placement.
- `NightCalendar` `rating()` linear scan (≤42 entries), `label.split(' ')` per
  cell, `localClock` per item: all sub-100 µs per build.
