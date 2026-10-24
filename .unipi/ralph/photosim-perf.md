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

Scan and tick off; add new areas as discovered.

- [ ] `lib/app/app.dart` — rebuild scope, `setState` fan-out, unnecessary whole-tree rebuilds, missing `const`, list builders without `itemExtent`/keys
- [ ] `lib/ui/simulation_workspace.dart` — per-frame work, controllers/listeners not disposed, expensive work in `build()`
- [ ] `lib/ui/night_calendar.dart` — repeated astronomy/network computation, per-item recompute in lists
- [ ] `lib/ui/map_workspace.dart` — map layer rebuilds, tile request churn, gesture handler cost
- [ ] `lib/render/*` — per-frame allocations in render loops, redundant material/uniform updates, texture uploads
- [ ] `lib/core/*` — repeated pure-function recomputation that should be memoized; hot math loops
- [ ] `lib/data/raster_cache.dart`, `lib/data/terrain/tile_cache.dart` — eviction policy, double decode, unbounded growth, redundant disk reads
- [ ] `lib/data/imagery/*`, `lib/data/terrain/*`, `lib/data/night_conditions.dart` — duplicate HTTP requests, missing in-flight dedupe, blocking decodes
- [ ] `lib/data/saved_plans.dart`, `lib/data/app_session.dart` — repeated serialization, sync disk I/O
- [ ] String/JSON work in hot paths, `$` interpolation in loops, repeated `toList()`/`map()` chains, repeated `.sort()` on already-sorted data

## Findings log

(Append findings here each iteration: file:line, problem, status.)
