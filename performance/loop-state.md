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
- Loop stopped: no remaining low-risk, measurable UI-thread win was found, and
  GPU-side work cannot be validated on this shared, un-attributable GPU.
