# Performance loop state

- Original baseline: `4ade6585956dbb64392013f77db8f2996c7954f1`. Preserve the
  pre-existing `pubspec.lock` and `.gitignore` working-tree changes.
- Accepted: `7397e07` — one planet per ephemeris lookup (planet-target aim scrub
  build p50 9.14 → 8.03 ms).
- Accepted: `11924cf` — resolve `targetPosition` once per state (planet-target aim
  scrub 7.92 → 7.60 ms, time scrub 8.53 → 8.09 ms, paired runs).
- Metric: UI-thread `build p50/p95` per phase from
  `flutter drive --no-pub --profile -d linux --driver=test_driver/perf_driver.dart
  --target=integration_test/perf_test.dart`, medians of ≥3 interleaved paired runs.
  GPU-bound phases/raster are not comparable (shared GPU busy with other processes).
- Known environment limits: no VM-service CPU profiling from sandboxed Dart
  (connections are redirected to a closed port), no `perf`. Use temporary in-app
  Stopwatch probes or AOT `dart compile exe` microbenchmarks, and remove them
  before committing (the probes in this session lived in `lib/perf_probe.dart`).
- Known pre-existing failure: `integration_test/linux_workflow_test.dart` star-pixel
  assertion fails on this machine with and without local changes.
- Remaining costs measured, not yet attacked: ~76–97 ms scene asset loading,
  ~15 ms star geometry, ~11–14 ms static GPU resources and ~8–10 ms planet label
  atlas per 3D entry (GPU/shader-bound); ~6 ms per-frame Flutter rebuild of the
  shell with no dominant subtree (rejected: needs stale-closure-safe reducers).
- Next candidates: re-verify that no per-frame caller still resolves planet
  ephemerides more than once (probe `targetPosition`/`planetPosition` in new
  phases); otherwise treat the loop as out of low-risk, measurable UI-thread work
  and stop rather than manufacture refactors.
