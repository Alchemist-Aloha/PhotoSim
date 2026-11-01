# Performance loop state

- Original baseline: `4ade6585956dbb64392013f77db8f2996c7954f1`. Preserve the
  pre-existing `pubspec.lock` and `.gitignore` working-tree changes.
- Accepted commits (in order): `7397e07` (one planet per ephemeris lookup),
  `11924cf` (resolve `targetPosition` once per state), `098aa06` (planet label
  atlas after the first preview frame), `8865570` (allocation-free star mesh).
- Final vs original baseline, 3 interleaved runs each, UI-thread build p50:
  planet-target aim scrub 9.49 → 7.33 ms (−22.8 %), planet-target time scrub
  9.70 → 8.01 ms (−17.4 %), cold 3D entry to first scene 175.8 → 158.6 ms
  (−9.8 %), warm entry 152.6 → 147.5 ms (−3.3 %, weak). Aim scrub, time scrub
  and high-quality aim scrub unchanged.
- Metric and command: `flutter drive --no-pub --profile -d linux
  --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart`;
  use medians of ≥3 interleaved A/B runs. Raster/GPU phases are not comparable on
  this machine (shared GPU, no GPU completion timestamps).
- Profiling tools available: temporary in-app `Stopwatch` probes (removed before
  each commit), AOT `dart compile exe` microbenchmarks, subtree ablation.
  Unavailable: VM-service CPU profiling (sandboxed Dart sockets are redirected to
  a closed port), `perf` (not installed).
- Pre-existing failures on this machine, reproducible with the working tree
  stashed: `integration_test/linux_workflow_test.dart` star-pixel assertion and
  `integration_test/atmosphere_test.dart` pixel-inequality assertion.
- Measured and rejected, do not retry without new evidence:
  - Rebuild-scope refactor of the 3D shell (≤1.6 ms of a ~7 ms UI thread; needs
    stale-closure-safe `onChanged` reducers or lagging aim readouts).
  - Milky Way index preallocation (no measurable change; its cost is the upload).
  - Passing explicit star normals to skip `generateNormals` (~2–3 ms entry CPU)
    — could not validate "unlit shader ignores normals" without pixel references.
- Remaining costs, ranked: scene asset loading ≈76–97 ms per entry
  (texture/shader bound), star/milky-way GPU upload ≈5–6 ms, static GPU resources
  ≈11–14 ms, per-frame shell rebuild ≈6 ms (framework, no dominant subtree),
  moon color upload ≈0.31 ms/frame while scrubbing time, hourly planet refresh
  spikes ≈4.7 ms p95 during time scrub.
