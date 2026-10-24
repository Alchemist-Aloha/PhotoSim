# Performance audit

Measured on the Linux desktop build, 2026-10-19.

## Environment and method

- CachyOS (Arch-based), kernel with X11 session.
- Intel i5-13600K, NVIDIA RTX 3070, driver 615.78.08.
- Flutter 3.47.7 profile build, default 1280×720 window.
- Scene: 3D Preview at 37.744, −119.59, 2026-06-21 19:00 UTC,
  balanced quality, 9/9 terrain and imagery tiles warm, 24 mm full frame.

Render numbers come from `dart:ui` `FrameTiming` captured in
`integration_test/perf_test.dart`, driven by:

```bash
flutter drive --profile -d linux \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/perf_test.dart
```

The test first measures Map → 3D Preview readiness with an empty raster cache,
then recreates the app and cache object against the populated directory. It
records milliseconds from workspace selection to the first scene render
(`renderStats.frameCount > 0`), center terrain attached, and center preview
texture attached. These are wall-clock observations sampled with 10 ms pumps
and delays, not GPU presentation timestamps. The warm run re-indexes disk but
reuses process-wide GPU resources and OS caches; neither run is process startup.
Cold-cache terrain/imagery readiness includes live network latency.

The test then reports build and raster p50/p95 over four-second phases: time
scrubbing (one five-minute step per frame tick), playback, camera aim scrubbing,
and high-quality aim scrubbing. Results are written to
`build/validation/render-performance.txt`.

Cold start is the median of five release launches from isolated
`XDG_DATA_HOME` profiles, measuring process start to an X11-visible window
(`build/validation/perf-cold-start.py`). `flutter run --profile --trace-startup`
supplies framework-init and first-frame timings. Network tile latency is excluded
from cold-start numbers. Raw profile runs and traces are in `build/validation/`
(`perf-baseline.log`, `perf-final.log`, `perf-trace-clean-*.log`).

## Results: initial astronomy/cache optimization

| Phase | Before build p50/p95 (ms) | After build p50/p95 (ms) | Before raster p50/p95 | After raster p50/p95 |
|---|---:|---:|---:|---:|
| Balanced aim scrub | 7.74 / 10.16 | **5.33 / 7.57** | 1.56 / 2.73 | 1.56 / 2.70 |
| High aim scrub | 7.89 / 10.25 | **4.88 / 7.91** | 1.48 / 2.43 | 1.27 / 2.29 |
| Idle | 3.14 (one frame) | 1.83 (one frame) | 2.36 | 0.84 |
| Time scrub* | 6.86 / 10.72 (48.57 max) | **5.50 / 9.14** (10.72 max) | 1.55 / 2.60 | 1.29 / 2.58 |
| Playback | — (timer not pumped) | 1.37 / 7.84 | — | 1.20 / 2.39 |

\* Time scrub was added after the first caching changes. Its “before” column is
the first instrumented run, before the duplicate-sky and Moon-buffer fixes; the
48.57 ms outlier disappeared after those. Other rows compare against the original
pre-optimization build.

Astronomy within a frame:

- `SimulationState.sky`: **10.171 ms → 0.001 ms** per access after caching.
- Rebuilding the observer frame for the lunar pole and star rotation was removed
  from the frame path.

Cold start (release, five launches):

- X11 window mapped: **343.6 ms → 322.0 ms median**.
- Profile first frame: 145.6 ms → **135–140 ms** (three clean runs);
  rasterized at 199–205 ms.
- Restored 3D session shell first frame: 144.8 ms.

## Changes that produced the gain

1. **Per-state astronomy cache.** `SimulationState.sky`, `observerFrame` and
   `galacticCenter` are immutable, lazily computed once per state instead of
   being recalculated by the lunar pole, shadow setup, night-sky rotation and UI
   readouts. Caches remain valid because every edit produces a new state.
2. **Shared sky through the frame.** `configurePhotography`,
   `NightSkyRenderer.update` and shadow configuration accept the already-computed
   sky/frame, avoiding duplicate Meeus calculations in one build.
3. **Moon upload reduction.** The phase color buffer is reused instead of
   reallocated per update, and color uploads are skipped when the lighting
   direction changes by less than 0.0001 rad. This removed the 48 ms time-scrub
   outlier caused by buffer churn during playback.
4. **Cold-start I/O deferral.** The raster-cache index is no longer scanned while
   opening Map or Calendar. Opening the 3D workspace publishes the cache
   immediately and overlaps indexing with GPU and world setup.
5. **Progressive 3D entry.** Terrain loading no longer blocks the first scene
   frame. The sky/tiles render as they arrive instead of waiting for all nine
   tiles, and the center-tile spinner is only an error state now.

## Follow-up: 3D workspace startup

The scene now initializes independently of the disk index. Terrain waits for
cache settings/indexing and source attribution, preserving the saved disk budget
and source credits. Atmosphere, Moon texture, star catalog and Milky Way texture
load concurrently after static GPU initialization.

Constellation data and its name atlas load only when guides are enabled, after
the scene is published. Existing enabled-guide sessions also load them after the
first frame. A failed guide load leaves the scene usable and can be retried by
toggling guides. The loaded renderer is reused on subsequent toggles.

Center preview imagery starts as soon as the center mesh arrives, without
waiting for the other two terrain jobs in its batch. Generation-scoped in-flight
tracking prevents duplicate imagery requests while nearby previews continue.

One Linux profile run of the updated benchmark (not a before/after comparison):

| Raster cache | First scene (ms) | Center terrain ready (ms) | Center imagery ready (ms) |
|---|---:|---:|---:|
| Empty | 195.8 | 616.6 | 3818.7 |
| Populated, fresh cache index | 121.8 | 226.1 | 226.1 |

These single-run observations establish the new measurement path, not a speedup
claim. Repeat runs are needed to separate startup changes from network and
machine-load variance.

Validation:

```bash
flutter test integration_test/startup_test.dart -d linux
flutter test integration_test/linux_loading_test.dart -d linux
flutter test integration_test/linux_workflow_test.dart -d linux
```

The startup regression deliberately holds cache initialization until a scene
frame renders, then holds neighboring terrain until center imagery is requested.
It also checks lazy guide loading, renderer reuse and no duplicate center preview.
The existing loading test verifies that slow imagery still cannot block terrain.
All 230 unit/widget tests, all three Linux integration tests above, and the
profile benchmark passed. The workflow test now waits for guides to load on
first enable and retains its rendering/occlusion checks.

## 2026-10-24: idle GPU work and 24-hour commit review

Reviewed the 50 commits from `d3669a2` through `33c5a8e` in the preceding
24 hours. Two renderer-lifetime issues matter; reverting the feature commits is
not necessary:

- `391aa7e` reduced idle **scene** draws to 5 FPS, but kept the vsync ticker
  alive. It also disabled the cap throughout terrain/imagery downloads, even
  when there was no new data to draw. The scene now uses `TickerMode` to sleep
  after one second without changes. Local scene updates (including downloaded
  tiles), camera edits and export wake it. A separate repaint boundary keeps
  animated rain from repainting the static 3D scene.
- `d3b276e` added above-screen-density exports. The existing export flag stayed
  true through the save-path dialog; `11cb0c6` split rendering/saving state but
  retained that lifetime. This kept drawing at export scale while waiting for
  a filename. Rendering now ends as soon as the PNG capture is ready; saving
  no longer holds the oversampled renderer open.

Other reviewed changes: `d05999c` adds seven small planet markers and one label
node, hidden in daylight, with renderer ephemerides refreshed at most hourly.
The export supersampling override is otherwise limited to active capture.
`41b9bcf` lowers distant terrain detail. The cache, allocation, coordinate,
feedback and session changes do not introduce continuous GPU work. The expensive
cloud shader (up to 64 view steps plus light samples), High's 1.25 render scale,
GTAO and four 4096-pixel shadow cascades predate this 24-hour window and remain
unchanged. High-quality interaction can still saturate the GPU; this fix removes
unnecessary work, not image detail.

Measurement: RTX 3070, Linux XWayland, Flutter 3.47.7. An ordinary release launch
with the saved High/cloudy scene was allowed eight seconds to settle, then
sampled eight times, once per second, using `nvidia-smi pmon -s um -d 1 -c 8`.
Before: PhotoSim's seven numeric SM-utilization samples ranged **4–24%** (one
sample was `-`). After: all eight samples were `-`, i.e. no measurable process
activity, not proof of exactly zero whole-device utilization. Other desktop
processes continue to use the GPU. Device-wide utilization is not app attribution.

The profile idle regression now includes cumulonimbus clouds and asserts zero
scene draws **and zero app ticker callbacks** after settling. Its fully-live
Flutter test binding forces compositor frames itself, so engine-frame counts
from that harness must not be mistaken for ordinary app idle FPS.

| Profile test, cloudy fixture | Before | After |
|---|---:|---:|
| Balanced idle scene FPS | 4.96 | 0 |
| High idle scene FPS | 4.96 | 0 |
| Balanced active aim FPS | 52.1 | 51.0 |
| High active aim FPS | 20.6 | 20.6 |
| Rain over a settled scene | not measured | 0 scene FPS; rain still animates |

These are single-run observations, not hardware-independent FPS guarantees.
Within the updated test, returning to the same camera preserves its settled
RGBA hash. No cross-version pixel-identity claim is made: the settling schedule
has changed. Quality presets, cloud samples and export resolution are unchanged.

Regressions also hold imagery responses pending and verify that the renderer
sleeps and wakes when data arrives, and keep a quick-export save dialog open
while checking that preview scale is restored and the scene ticker is muted.
Validation: 297 unit/widget tests, strict analysis, debug native idle/loading/
startup/export/clouds/camera-light workflows, and the profile idle benchmark.
Android/Windows hardware and active GPU shader optimizations were not tested.

## Remaining bottlenecks and limits

- One `calculateSky` still costs roughly 5–10 ms in profile whenever simulation
  time changes. It is the remaining main-isolate spike during time scrubbing.
  Moving it to an isolate or using a cheaper ephemeris for previews would be the
  next step.
- The earlier 1–3 ms raster figures measure Flutter's raster thread, not GPU
  execution. They do not rule out GPU-bound High/cloudy scenes; geometry,
  shadows and shader quality have not been reduced.
- Numbers cover one x86_64 desktop and X11. Wayland, Android phones/tablets,
  integrated GPUs, large High-quality networks and network-bound loading remain
  unmeasured.
- The original cold-start figures measure the Flutter shell, not downloaded
  terrain/imagery. The follow-up readiness figures separately measure 3D entry;
  Android hardware and repeated startup measurements remain unverified.
