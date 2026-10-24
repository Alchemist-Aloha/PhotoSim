# PhotoSim performance hardening loop

Goal: recursively scan the Flutter app in `lib/` for real performance issues, fix them one at a time, prove no regression with strict tests, and commit each fix.

## Ground rules (every iteration)

1. **One fix per iteration.** Find the highest-impact issue, fix it, verify, commit. Do not bundle unrelated changes.
2. **Real issues only.** No speculative micro-opts. Every fix must have a stated reason (wasted work per frame, per rebuild, per HTTP request, per pixel, quadratic loop, unbounded cache/leak, blocking I/O on UI isolate, etc.).
3. **Strict verification before every commit** (all must pass):
   - `flutter analyze` → 0 issues
   - `flutter test` → all tests pass (baseline was 247 tests passing)
   - If the change touches rendering/hot paths, add or extend a test that would fail on the old behavior.
4. **Commit message**: `perf: <what> — <why>` plus a short body with the measured or reasoned impact.
5. If a fix turns out to be wrong or breaks tests, revert it (`git checkout -- .`) and mark it rejected with the reason.

## Where to look (recursive scan checklist)

All areas scanned. `[x]` = scanned; see Findings log for the verdict.

- [x] `lib/app/app.dart` — rebuild scope, `setState` fan-out, whole-tree rebuilds, `const`, builder keys
- [x] `lib/ui/simulation_workspace.dart` — per-frame work, listener disposal, expensive `build()`
- [x] `lib/ui/night_calendar.dart` — repeated astronomy/network work, per-item recompute in lists
- [x] `lib/ui/map_workspace.dart` — map layer rebuilds, tile request churn, gesture handler cost
- [x] `lib/render/*` — per-frame allocations, redundant material/uniform updates, texture uploads
- [x] `lib/core/*` — repeated pure-function recomputation, hot math loops
- [x] `lib/data/raster_cache.dart`, `lib/data/terrain/tile_cache.dart` — eviction, double decode, growth, redundant reads
- [x] `lib/data/imagery/*`, `lib/data/terrain/*`, `lib/data/night_conditions.dart` — duplicate HTTP, in-flight dedupe, blocking decodes
- [x] `lib/data/saved_plans.dart`, `lib/data/app_session.dart` — repeated serialization, sync disk I/O
- [x] String/JSON work in hot paths, interpolation in loops, `toList()`/`map()` chains, redundant `.sort()`

## Commits

| commit | fix | measured |
|---|---|---|
| `d3669a2` | hoist cache filename RegExps out of directory scan loops | thousands of pattern compiles removed per startup re-index |
| `f64d67a` | write star + Milky Way meshes by index, not `setRange` literals | ~131k throwaway list allocs removed from scene creation |
| `44fadce` | reuse one `Pixel` when scanning decoded imagery | 38.0 → 34.0 ms per 1024² tile; 1M+ objects gone per tile |
| `e87fd81` | drop allocation churn from terrain mesh construction | 52.0/50.1 → 42.3/41.8 ms per r256 patch (~18%) |
| `439fd7a` | stop recomputing pure per-build values (cameraFrame, map bearings) | 7→1 ENU basis per frame; 135 → 129 `destination()` per map rebuild |
| `a17971d` | build session composition map instead of reparsing it | 32.5 → 24.8 µs per autosave (~24%) |

Every fix above was proven behaviour-preserving with a running hash over its
output captured before and after the change, in addition to the full suite.

## Findings log

Fixed (see Commits table).

Measured and rejected as not worth the risk:

- `lib/models/simulation_state.dart` `copyWith` — rebuilds `sky`/`observerFrame`
  on every copy even for camera-only changes, and `calculateSky` independently
  redoes the nutation/ΔT/sidereal series that `ObserverSkyFrame` already
  computed. Measured **24.9 µs per frame** during a drag (0.15% of a 60 fps
  budget). Sharing requires duplicating the effective-elevation resolution
  (`fixedElevation` / `groundElevation` / `height`) inside `copyWith`; regression
  risk outweighs the gain. Revisit if a profile build shows it.
- `lib/data/raster_cache.dart` `_evict()` — full sort of all entries on every
  write once the budget is reached. Measured **0.7 ms/write** with 1200 entries.
  Fine.
- `lib/data/app_session.dart` `SessionStore.save` — synchronous
  `writeAsStringSync(flush: true)`. Intentional: an explicit test requires
  backgrounding to flush "without waiting for autosave". Total save is 97 µs.
- `lib/core/night_rating.dart` `calculateNightCalendar` — 3318 samples/month,
  each computing the same nutation series twice (`calculateSky` +
  `ObserverSkyFrame`). Measured **19.3 ms per month** and it runs in `compute()`.
  No user-visible impact.
- `lib/data/raster_cache.dart` `_index()` — ~4 async stats per file.
  Measured **144 ms** cold for 1200 entries (~140 MiB); happens once at launch
  and only yields (does not block frames). Reducing it needs error-handling
  contortions for ~30 ms.
- `lib/ui/simulation_workspace.dart` `loadImagery` — one `setState` per tile
  (~30 workspace-subtree rebuilds per site load). Each lands in its own frame,
  so it is CPU waste, not jank. Batching changes progressive-credit UI semantics.
- `lib/ui/night_calendar.dart` — `rating()` linear scan (≤42 entries),
  `label.split(' ')` per cell, `localClock` per item. All sub-100 µs per build.
- `lib/core/terrain_coverage.dart` `_intersects` — allocation-heavy SAT used
  once per terrain load behind a 400 ms debounce, not per frame.
- `lib/ui/rain_overlay.dart` `_RainPainter` — 266 `drawLine` calls per frame,
  and a fresh `Random(24)` seed per paint. Only runs while raining; consolidating
  to `drawRawPoints` would change drop placement.
- `lib/ui/wasd_navigation.dart`, `lib/ui/camera_gestures.dart`,
  `lib/ui/time_slider.dart`, `lib/ui/camera_inspector.dart`,
  `lib/render/{moon,clouds,photography,atmosphere_sky,constellations}.dart`,
  `lib/data/http_bytes.dart` — reviewed, no actionable waste found.

## Pre-existing test failures (not caused by this work)

Both fail identically at baseline `21e04f9` and at HEAD, verified in a clean
`git worktree`:

- `integration_test/linux_photography_test.dart:225` — `world.fog.enabled`
  expected `false` after Visibility→100, got `true`.
- `integration_test/linux_workflow_test.dart:216` — expected `9`, got `10`.

## Verification status

- `flutter analyze` → 0 issues
- `flutter test` → 247/247 pass
- Integration tests on the Linux GPU device → 15 of 17 pass; the 2 failures are
  the pre-existing ones above.
