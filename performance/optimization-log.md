# Performance optimization log

Baseline commit: `4ade6585956dbb64392013f77db8f2996c7954f1`. Pre-existing working-tree
changes (`.gitignore` gaining `.unipi/`, `pubspec.lock`) were left untouched.
Read alongside `docs/performance.md` and `docs/performance-robustness-log.md`.

Environment: Linux 7.3.0-4-cachyos, i5-13600K, RTX 3070 (driver 615.78.08),
Flutter 3.47.7 profile builds at the default 1280×720 window.

Method: `flutter drive --no-pub --profile -d linux --driver=test_driver/perf_driver.dart
--target=integration_test/perf_test.dart`, whose `FrameTiming` build/raster
p50/p95 per phase is the app-level metric. Measurements are interleaved A/B runs
on the same machine, reported as ranges. Flutter "raster" duration is not GPU
completion time, and this desktop GPU is shared with other processes (25–49 %
device utilization with PhotoSim closed), so no GPU-bound claim is made.

## Iteration 1 — one planet per lookup instead of seven

- Baseline: `4ade658`.
- Bottleneck: with a celestial planet selected as target, the timeline readouts
  (`WorkspaceShell.timeline` → `state.targetPosition`, `targetAngularOffset`)
  resolve `SimulationState.planetPosition` on every frame, and that resolved the
  whole seven-planet VSOP87 set (1.44 ms AOT per call) to use one body.
- Hypothesis: keeping Earth's VSOP87 anchor per instant and evaluating only the
  requested planet removes six of seven series evaluations from that path.
- Change: `lib/core/planets.dart` gains `PlanetEphemeris` + a one-entry cache
  keyed by the exact UTC instant; `planetPositions` keeps returning all seven in
  the same order, `SimulationState.planetPosition` now asks for one body.
  Planets are geocentric, so the cache depends on time only.
- AOT microbenchmark (`dart compile exe`, 3 runs, same math): single planet
  0.141/0.139/0.141 ms repeated instant, 0.200/0.198/0.201 ms new instant,
  versus 1.443/1.468/1.443 ms for all seven.
- App benchmark, `build p50` (median of 3 baseline runs → median of 4 candidate
  runs), new `planet-aim-scrub` / `planet-time-scrub` phases reuse the existing
  aim/time scrub loops with Jupiter selected:
  - planet-aim-scrub: **9.14 → 8.03 ms (−12.1 %)**; baseline 9.07–9.45,
    candidate 7.79–8.22 (ranges do not overlap).
  - planet-time-scrub: **9.56 → 8.64 ms (−9.6 %)**; baseline 9.46–9.69,
    candidate 6.51–9.00 (overlapping, so treated as supportive only).
  - Unchanged workloads stayed within noise: aim-scrub 6.89 → 6.62,
    time-scrub 7.43 → 7.46, high-aim-scrub 6.17–7.32 → 6.79–7.11.
- Correctness: `test/planets_test.dart` gained checks that one-planet results
  are bit-identical to the full set at three instants across 1900–2100, and that
  the cache refills when the instant changes. All 298 unit/widget tests and
  strict analysis pass.
- Known limitation: `integration_test/linux_workflow_test.dart` fails on this
  machine at the star-pixel-count assertion (`expected > 5716, actual 2476`).
  It failed identically with the change stashed, so it is pre-existing and not
  caused by this optimization; it was not "fixed" here.
- Accepted. The remaining per-frame cost of the same path is one ~0.14 ms
  lookup (two lookups per frame from the timeline readouts); a per-state
  single-entry memo could halve it if a later measurement justifies it.

## Environment caveats found during baseline work

- Function-level VM-service profiling was unusable: every connection from a
  sandboxed Dart process to the app's service port was redirected to an
  unrelated closed port, and `perf` is not installed.
- Attribution was therefore done with temporary in-app `Stopwatch` probes and
  subtree ablation (inspector children, viewport, timeline, rail), all removed
  before committing. Results: app-level Dart work was only ~0.34 ms of a 6.5 ms
  build; ablating the preview viewport saved ~1.0 ms, the inspector ~0.6 ms, and
  the timeline/rail nothing measurable. No single dominant subtree exists, which
  is why the frame path itself was not reworked.
- Existing workload numbers are unstable for loading (live network) and
  GPU-bound phases; only UI-thread build metrics on fixed phases are used for
  before/after verdicts here.
