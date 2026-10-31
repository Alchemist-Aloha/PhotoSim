# Performance loop state

- Original baseline: `4ade6585956dbb64392013f77db8f2996c7954f1`. Preserve the
  pre-existing `pubspec.lock` and `.gitignore` working-tree changes.
- Accepted: iteration 1 — one planet per ephemeris lookup (`lib/core/planets.dart`,
  `lib/models/simulation_state.dart`). Planet-target aim scrub build p50
  9.14 → 8.03 ms.
- Metric: UI-thread `build p50/p95` from
  `flutter drive --no-pub --profile -d linux --driver=test_driver/perf_driver.dart
  --target=integration_test/perf_test.dart` (now includes `planet-aim-scrub` and
  `planet-time-scrub`). Compare medians of ≥3 interleaved runs; GPU-bound phases
  are not comparable because the shared GPU is busy with other processes.
- Known environment limits: no VM-service CPU profiling from sandboxed Dart
  (connections redirected), no `perf`. Use temporary in-app Stopwatch probes or
  AOT `dart compile exe` microbenchmarks, and remove them before committing.
- Known pre-existing failure: `integration_test/linux_workflow_test.dart` star-pixel
  assertion fails on this machine with and without local changes.
- Next candidates, in order: (a) halve the remaining two single-planet lookups per
  frame with a per-state memo; (b) the per-frame shell rebuild (~6 ms) — the only
  large cost, but no single subtree dominates (viewport ≈1 ms, inspector ≈0.6 ms)
  and avoiding it needs stale-closure-safe state propagation; do not attempt
  without a plan for the azimuth/pitch/roll readouts.
