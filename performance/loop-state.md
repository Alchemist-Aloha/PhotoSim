# Performance loop state

- Original baseline: `4ade6585956dbb64392013f77db8f2996c7954f1`. Pre-existing
  working-tree changes (`pubspec.lock`, `.gitignore`) were preserved throughout.
- Accepted commits: `7397e07` (one planet per ephemeris lookup), `11924cf`
  (resolve `targetPosition` once per state), `098aa06` (planet label atlas after
  the first preview frame), `8865570` (allocation-free star mesh), `a045172`
  (share scene assets across Map ↔ 3D switches). Documentation commits:
  `4feb594`, `4c2d4ae`, `9677e54`.
- Final versus original baseline, 3 interleaved runs each: warm 3D entry
  150.95 → 67.19 ms (−55.5 %), cold entry 212.79 → 154.76 ms (−27.3 %),
  Map → 3D re-entry 157.9 → 84.1 ms (−46.7 %), planet-target aim scrub 9.16 →
  7.54 ms (−17.7 %), planet-target time scrub 9.62 → 8.22 ms (−14.6 %); aim,
  time and high-quality scrubs unchanged.
- Benchmark command: `flutter drive --no-pub --profile -d linux
  --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart`
  (phases: cold/warm entry, Map → 3D re-entry, idle, time scrub, playback, aim
  scrub, high-quality idle/aim, planet-target aim/time scrub). Use medians of ≥3
  interleaved A/B runs; raster/GPU numbers are not comparable on this machine.
- Profiling routes that work: temporary in-app `Stopwatch` probes (deleted before
  each commit), AOT `dart compile exe` microbenchmarks, subtree ablation, and
  `git worktree` checkouts of the baseline. Routes that do not: VM-service CPU
  profiling (sandboxed Dart sockets are redirected to a closed port) and `perf`
  (not installed).
- Pre-existing failures here, reproducible with the tree stashed:
  `integration_test/linux_workflow_test.dart` (star-pixel assertion) and
  `integration_test/atmosphere_test.dart` (pixel-inequality assertion).
- Rejected with measurements, do not retry without new evidence: rebuild-scope
  refactor of the 3D shell (≤1.6 ms of a ~7 ms UI thread), Milky Way index
  preallocation (cost is the upload), explicit star normals to skip
  `generateNormals` (could not prove the unlit shader ignores normals), and
  sharing night-sky meshes across scenes (only −4 % on re-entry, overlapping
  ranges; the mesh build overlaps terrain loading).
- Measured, no action needed: map workspace interaction is cheap (build p50
  0.19 idle / 0.95 pan / 0.22 zoom; raster 3–4.5 ms).
- Remaining costs, ranked: scene asset loading in a cold process (≈78 ms, texture
  and shader bound), third-party GPU work (shadows, clouds, GTAO at High), the
  ~6 ms per-frame framework rebuild of the shell, and the moon colour-buffer
  upload (≈0.31 ms/frame while scrubbing time).
- Also rejected: gating planet-marker ephemerides on star visibility. Probes show
  it removes 0.28 ms/frame of UI-thread work during daytime time scrubs
  (`nightUpdate` 43.3 → 10.3 ms per 120 frames), but the benchmark mean build
  time did not move (7.21 → 7.31 ms), so the frames are not CPU-limited there.
  Revisit on CPU-limited hardware (low-end Android) with a profiler.
- Benchmark tooling now reports `mean` next to `p50/p95/max`; use the mean as the
  primary estimator for small deltas because p95 over ~100 frames is unstable.
- Also measured, no action: export render is ~810–830 ms wall at 2× density but
  keeps the UI thread free (build p50 ≈1 ms, ~23 frames) — engine render/encode
  bound.
- An external commit `a74903b` (dependencies/.gitignore) landed between
  iterations; it carries the pre-existing working-tree changes and is untouched.
- Loop stopped: two consecutive hypotheses failed to produce measurable gains,
  two more are blocked on GPU attribution, and the remainder need reference-image
  validation or CPU-limited hardware. No speculative changes were kept.
