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

The test reports build and raster p50/p95 over four-second phases: time
scrubbing (one five-minute step per frame tick), playback, camera aim scrubbing,
and high-quality aim scrubbing. Results are written to
`build/validation/render-performance.txt`.

Cold start is the median of five release launches from isolated
`XDG_DATA_HOME` profiles, measuring process start to an X11-visible window
(`build/validation/perf-cold-start.py`). `flutter run --profile --trace-startup`
supplies framework-init and first-frame timings. Network tile latency is excluded
from cold-start numbers. Raw profile runs and traces are in `build/validation/`
(`perf-baseline.log`, `perf-final.log`, `perf-trace-clean-*.log`).

## Results

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

## Remaining bottlenecks and limits

- One `calculateSky` still costs roughly 5–10 ms in profile whenever simulation
  time changes. It is the remaining main-isolate spike during time scrubbing.
  Moving it to an isolate or using a cheaper ephemeris for previews would be the
  next step.
- GPU raster is 1–3 ms in these scenes, so lowering mesh/quality settings would
  not improve frame rate here; High quality geometry and shadows were kept.
- Numbers cover one x86_64 desktop and X11. Wayland, Android phones/tablets,
  integrated GPUs, large High-quality networks and network-bound loading remain
  unmeasured.
- The startup figures measure the Flutter shell; they do not promise when all
  downloaded terrain/imagery becomes visible.
