# PhotoSim performance + robustness hardening (overnight)

Improve performance and robustness. Scan, test, fix edge cases. **One fix per
iteration, verified, committed, and logged in `docs/performance-robustness-log.md`.**

Read `docs/performance-robustness-log.md` first every iteration. It contains the
work already done and a "measured and deliberately not changed" section — do
not redo those, and do not re-litigate a rejected idea without new evidence.

## Non-negotiable verification before every commit

```sh
flutter analyze                                            # must be 0 issues
dart format --output=none --set-exit-if-changed lib test integration_test
flutter test                                               # currently 290 tests, all pass
```

Plus, for anything touching rendering, GPU state, widgets, exports or the scene
graph, run the affected integration test(s) on the real GPU device:

```sh
flutter test integration_test/<file>_test.dart -d linux
```

Known-good baseline: every integration test passes on `-d linux` except
`android_workflow_test` (skips off-device) and the `windows_*` tests (skip off
Windows). If an integration test fails, first check whether it also fails at
`HEAD~` — if it is pre-existing, fix it as its own iteration.

**Behaviour-preserving changes must be fingerprint-proven.** Where a change
should produce identical output, capture a running hash over the produced bytes
before and after (mesh positions/normals/uvs/indices, decoded RGBA, encoded
JSON) and require an exact match. Green tests are not proof that a mesh or an
encoder still emits the same data.

## Commit + log every iteration

1. Commit message: `perf: …`, `fix: …`, `refactor: …` or `docs: …`, then a body
   stating the problem, the change, and the measured or reasoned impact.
2. Append an entry to `docs/performance-robustness-log.md`, newest first, under
   a dated heading. Include: commit hash, file(s), the problem, what changed,
   how it was verified, and the measurement if there is one. Do not write
   "improved performance" — write the number and how it was obtained.
3. If a candidate turns out to be wrong, does not measure up, or would trade
   quality, revert it and record it under "measured and deliberately not
   changed" with the reason.

## Backlog, highest value first

Tick items off in the task file as they land, and add anything new you find.

- [x] **Requested export workspace** — dedicated Export destination, exact
      high-resolution PNG preview, editable/copyable AI-enhancement prompt with
      captured metadata, no automatic AI upload; verified in `11cb0c6`.
- [x] **Idle render cap (the big one).** Shipped in `391aa7e`: ~59 → 5 fps
      idle at Balanced/High, uncapped edits/loading/export, exact before/after
      RGBA hashes. All 23 Linux integration-file invocations succeeded (20
      executed / 3 platform skips). Cadence notification is local to SceneView;
      never use a whole-workspace idle-timeout rebuild. Kept the measured 5 fps
      floor rather than introduce a more aggressive, unverified settling cadence.
- [~] **Robustness sweep: input validation and edge cases.** `copyWith` now
      rejects nonfinite pitch/focal-length edits before clamping (`6082f88`);
      exact polar destinations guard asin roundoff (`b89f3e0`); tile projection
      rejects nonfinite coordinates/unsupported zooms (`ad52361`). Sweep every
      public entry point for NaN/infinity, zero, negative, extreme coordinates (poles,
      date line, ±180/±90), year bounds (1900–2100 UTC, 1970–2037 local),
      DST gaps/folds, empty and single-item collections, and zero-size layout.
      Each fix gets a test that fails without it.
- [~] **Robustness: failure paths.** Pending HTTP headers now honor cancellation
      and deadlines, release origin slots and cancel late streams (`259b458`).
      Inaccessible session directories now fail safely instead of masquerading
      as absent checkpoints (`cf271d6`). Disk full / read-only cache / permission
      denied / corrupt cached raster / oversized response / aborted request /
      malformed JSON / unreadable session. Confirm the app degrades with a
      visible, actionable message and never loses user data or silently
      overwrites a good checkpoint.
- [x] **Non-overlapping workspace feedback** — `a7a6839` uses native layout-
      occupying MaterialBanners, protecting timeline AND inspector without offsets.
      Preserves message/action/persistence/queue contracts; bounded long content,
      scrollable short timelines, safe areas, 13 new tests and full native matrix.
      Footer-only prototype remains rejected; do not return to overlay placement.
- [x] **Phone TimeSlider at 200% text** — `f53a765` gives the slider its own row
      with flexible endpoint labels, retaining native text scaling and all UTC/DST
      drag semantics. Four failing-first regressions, native 390×844/200% scrubbing
      during checkpoint failure, successful Retry, and exact 45-sample fingerprint.
- [~] **Messenger arbitration.** Plan save/open errors preempt active camera Undo
      (`e704570`); checkpoint-save errors do the same (`13c54c7`), with checkpoint/
      live-state and Retry coverage. All now use shared non-overlapping feedback.
      Requested session warnings now replace active Undo (`96791bc`), preserving
      disabled-storage safety and Retry of the latest edits. Fullscreen rejection
      feedback now replaces Undo too (`70e5f96`), with entry/exit and native coverage.
      Remaining candidates: automatic startup warnings, constellation-load failure
      and more general pending-queue priority. Continue the other call-site audit.
      SDK correction: action SnackBars already default to persistent despite the
      configured ten-second Undo duration; a7a6839 preserves actual native behavior.
- [ ] **`loadImagery` rebuild batching** — one `setState` per tile, ~30 per site
      load. Preserve progressive credits.
- [ ] **`SimulationState.copyWith` astronomy sharing** — only if you find a
      low-risk way to keep the effective-elevation resolution identical.
- [ ] **`_RainPainter`**: one `drawRawPoints` instead of 266 `drawLine`, and no
      fresh `Random` seed per frame, if drop placement can be preserved.
- [ ] **`terrainCoverage._intersects`**: replace the allocating SAT with a
      reusable-vector version; hash-verify identical tile selection.
- [ ] **`NightCalendar`**: index `nights` by date instead of the linear scan;
      hoist `Theme.of(context)` and the per-cell `label.split(' ')`.
- [~] **Persistence**: unreadable session-directory recovery now preserves the
      checkpoint and reaches the startup autosave-disable guard (`cf271d6`).
      PlanRepository permission errors/data preservation and UI retry were
      verified without production changes (`067c8ed`). Continue the audit for partial
      writes, orphaned staging files, unbounded growth, and writer assumptions.

## Loop state

Findings, decisions and progress go in the task file below this line.

## Progress

### Current loop, iteration 15 — `70e5f96` — fullscreen failure feedback
- Reproduced fullscreen-rejection messages waiting behind persistent Undo while
  entering and exiting clean preview. Four compact/desktop cases at 1.3 scaling
  failed first; all now pass with Escape recovery and preserved composition.
- Reused existing active-feedback replacement in the existing PlatformException
  handler only. No new framework, copy change, layout change or session write.
  Undo is intentionally replaced; recovery wording in that message stays open.
- Native photography/spec workflow now throws a real PlatformException from the
  window channel. Two setup errors were diagnosed honestly: a debounced terrain
  reload temporarily disabled export after the new camera move, and the first
  capture preceded the banner animation. Exact HEAD~ sources passed, proving both
  belonged to the new test sequence. Added an export-readiness wait and waited on
  the banner's own animation instead of guessing durations.
- Native assertions cover message presence, Undo replacement, minimum banner
  height, no overlap with exit control, unchanged scene reference, Escape return
  and unchanged location/time/focal/roll/portrait, followed by the unchanged PNG
  export. Inspected build/validation/linux-fullscreen-error-feedback.png.
- Verified: analyze 0 issues; format clean; 290 tests; native Linux photography/spec
  and camera/GPU workflow pass separately with 180-second bounds. Session fingerprint
  remains 8/15850/7707460953092100. Ignored fullscreen-feedback-*.log evidence.
- Logged in docs/performance-robustness-log.md. Only notification priority changes;
  no pixel-identity/performance or physical Android/Windows window-manager claim.
- Next: automatic startup warning or constellation-load failure delivery, then
  general pending-queue priority, or one distinct evidenced input/persistence edge.
  Broader persistence and measured performance backlog remains open.

### Current loop, iteration 14 — `96791bc` — requested session warnings
- Reproduced a warning-icon click appearing to do nothing behind persistent Undo.
  Four 390×844/1600×960 cases at 1.3 scaling failed before editing: two new
  disabled-startup-store cases and two strengthened repeated checkpoint failures.
- Applied existing active-feedback replacement policy only to the icon callback.
  No new helper/framework, message/Retry/persistence change, write or layout change.
  Automatic startup delivery remains separate; no claim that all queues are fixed.
- Disabled-store cases retain the old checkpoint through disposal, keep live edits,
  and expose no Retry. Real staging-obstruction cases request warning after a new
  move, preserve checkpoint/latest state, and successfully retry the latest full
  composition without marking the plan clean.
- Native planning now repeats that warning-icon request during real checkpoint
  failure. Message replaces Undo; Retry and state/data are retained. Existing
  phone-scale scrubbing and exact save check still pass. Inspected native image:
  build/validation/linux-manual-session-warning.png.
- Verified: analyze 0; format clean; 286 tests; native Linux planning and camera/GPU
  workflow pass separately with 180-second bounds. Normal session fingerprint
  remains 8/15850/7707460953092100. Ignored manual-warning-*.log evidence.
- Logged in docs/performance-robustness-log.md. Only notification priority changes;
  no pixel-identity/performance or Android/Windows hardware/disk-full claim.
- Next: investigate fullscreen failure delivery with active Undo, or one distinct
  evidenced input/failure case. Automatic-startup/constellation queue hypotheses,
  general pending-queue priority, persistence and performance audits remain open.

### Current loop, iteration 13 — `f53a765` — large-text local-day slider
- Reproduced label Row overflow/track starvation at 200% text: standalone 320/390px
  phones with 24px padding and collapsed/expanded 390×844 feedback layouts. All four
  regressions failed before editing, now pass with full slider width and distinct
  visible labels, actual tap changes, UTC/semantic values and preserved camera state.
- Gave TimeSlider a dedicated track row and flexible legend labels; no font clamp,
  hidden text, breakpoint or new option. Desktop controls align to the track bottom;
  existing strict center-alignment assertions pass without modification.
- All UTC/DST/drag callbacks remain unchanged. Exact before/after fingerprint over
  five ordinary/special local days, including spring/fall transitions, half-hour
  shift, fractional offset, duplicate 24:00 and release: 45/51859/5379452141715050.
  Ignored probe/logs: time_slider_fingerprint_test.dart and fingerprint-{before,after}.
- Adjusted one geometry contract to allow the already-minimum 48px canvas to stay
  fixed while tall timeline details scroll; shrink is still required above minimum.
- Extended native planning with emulated 390×844/200% text during blocked checkpoint
  write. Scrubbing preserves location/optics and old JSON; Retry saves exact edited
  composition. Inspected desktop and phone PNGs under build/validation/:
  linux-session-error-feedback.png / linux-phone-large-text-timeline.png.
- Verified: analyze 0 issues; format clean; 284 tests; seven affected Linux native
  workflows pass (planning, photography spec/export, camera/GPU, WASD, terrain panel,
  calendar, perf), each separately bounded to 180 seconds. Evidence: time-slider-*.log.
- Logged in docs/performance-robustness-log.md. No unchanged-pixel/performance claim;
  phone capture is Linux emulation, not Android hardware or a completed a11y audit.
- Next: audit requested/manual session warning feedback ahead of active Undo, then
  remaining fullscreen/constellation queue cases or one evidenced failure/input
  edge. Keep broader persistence/performance backlog open; no rejected rewrites.

### Current loop, iteration 12 — `a7a6839` — occupied-space feedback
- Replaced overlay presentation using the native MaterialBanner/Scaffold layout
  contract, not the rejected footer-only approach. Migrated all feedback call
  sites in app, SimulationWorkspace and ExportPanel through one shared adapter.
- Preserved content/actions, queue/preemption, visible duration and native persist;
  timers cancel on replacement/disposal. Added native Close/live-region semantics,
  bounded scrollable long messages, short-window timeline scrolling and native
  rail scrolling. Pane scrollers do not steal primary page scrolling.
- Original five geometry cases failed first. Seven layout cases now pass across
  390×844/844×390/1280×800, expanded/collapsed timelines, 24px insets, 1.3 scaling
  and 2.0 landscape/desktop. Sliders/playback work while feedback stays present;
  inspector/navigation are separate and location/optics remain unchanged.
- Six helper tests cover expiry, accessible/non-accessible persistence/actions,
  queue cancellation, disposal, dismissal and long selectable feedback.
- Current SDK defaults action SnackBars to persist=true. The configured ten-second
  Undo was already persistent; earlier timing descriptions were assumptions. This
  preserves actual native persistence, including Retry, rather than hiding feedback.
- Native GPU workflow initially tapped stale geometry after an ensureVisible jump.
  Exact HEAD~ application/test baseline passed. Added one pump(), no timed wait or
  dismissal, after scrolling; unchanged PhysicallyBasedMaterial assertion passes.
- Native planning clicks Later-by-one-hour during real checkpoint failure; confirms
  separate banner/inspector/timeline bounds, same location/optics, old JSON intact,
  then Retry saves the exact updated composition. Inspected native screenshot:
  build/validation/linux-session-error-feedback.png, all controls/attribution clear.
- Verified: analyze 0; format clean; 280 tests; all 23 native integration invocations
  succeeded (20 executed/3 platform skips), separately bounded to 180 seconds.
  After final primary-controller isolation, planning/WASD passed again. Session
  fingerprint remains 8/15850/7707460953092100; ignored feedback-space-* evidence.
- Logged in docs/performance-robustness-log.md. Viewport height intentionally adapts;
  no pixel-identical UI/performance claim or physical Android/Windows verification.
- Next distinct defect: isolated unchanged TimeSlider at 390px/200% scaling already
  overflows without ANY feedback adapter. Expected-failing ignored probe/log:
  time_slider_200_percent_probe_test.dart / time-slider-200-percent-before.log.
  Fix that label/track layout next; do not mark every mobile/a11y layout audited.

### Current loop, iteration 11 — `13c54c7` — checkpoint error priority
- Completed the reflection below, then took a distinct bounded failure path
  rather than repeat the rejected footer-only layout or invent offsets/frameworks.
- Reproduced checkpoint-save warnings waiting behind Camera moved/Undo with
  real staging-path obstruction. Both compact/desktop regressions at 1.3 text
  scale failed before the fix because actionable storage guidance was absent.
- Reused existing plan-error arbitration in the shared saveSession error handler:
  remove active snackbar, then show unchanged guidance/Retry. Timer, lifecycle,
  exit and Retry callers keep persistence/deduplication/consent behavior intact.
- Tests verify immediate feedback without waiting out Undo, exact prior saved
  JSON, unchanged live edits, full composition saved by Retry, and unchanged
  clean-composition marker. Native Linux planning now checks the real filesystem
  failure, lifecycle flush, Retry and continued readability of both named plans.
- Verified: analyze 0 issues; format clean; 267 tests; native Linux planning and
  camera/GPU workflow pass, each bounded to 180 seconds. Session fingerprint
  remains 8/15850/7707460953092100. Logs: ignored session-feedback-*.log.
- Inspected build/validation/linux-session-error-feedback.png. Guidance and Retry
  are visible; timeline obstruction remains. Only notification priority changes,
  deliberately replacing transient Undo. No layout or pixel-identity claim.
- Logged in docs/performance-robustness-log.md. No actual disk-full fault or
  Android/Windows hardware validation. Startup/manual warning, fullscreen and
  constellation-load queue candidates remain separate unfinished items.
- Next: occupancy-aware shared feedback layout protecting timeline AND inspector;
  do not retry the footer-only candidate or hide notifications to pass tests.

### Reflection checkpoint — iteration 11
1. Accomplished: dedicated Export workspace; measured ~59→5 fps idle cap with
   exact RGBA preservation; nonfinite/polar/tile guards; HTTP cancellation;
   session permission safety, plan permission coverage and plan-error priority.
2. Working well: failing-first regressions, exact output fingerprints, native
   GPU workflows, HEAD~ comparisons and one bounded change per iteration.
3. Not working: footer-only notification placement relocated obstruction into
   the inspector. It is rejected, not progress toward a completed layout fix.
   No external blocker; Android/Windows hardware coverage remains unavailable.
4. Adjust: do not spend another pass on footer/offset variants or build a new
   notification framework speculatively. Keep occupancy-aware layout work open;
   take the next distinct, bounded failure-feedback defect this iteration.
5. Priorities: inspect checkpoint-save error arbitration now, with live Undo
   and retry/data-preservation regression coverage. Then revisit shared feedback
   layout protecting timeline AND inspector, followed by remaining queue/input/
   persistence audits and measured performance candidates.

### Current loop, iteration 10 — `295a629` — rejected snackbar footer prototype
- Reproduced timeline obstruction in five cases: 390×844 and 844×390 with
  collapsed/expanded timelines, plus 1280×800; 1.3 text scale and 24px insets.
- Moving the timeline into Scaffold.bottomNavigationBar protected it without
  per-message offsets and passed 270 tests. A scrollable rail was needed in
  short landscape windows, with navigation callers updated accordingly.
- Native root-shell matrix: six executed passes, one real failure, three
  platform skips. linux_workflow_test's relighting control at (1073, 881) was
  intercepted by the newly positioned snackbar. Checked exact HEAD~ shell
  first: the unchanged native workflow passed, proving a candidate regression.
- Rejected and reverted every application/test edit. Did not suppress Undo,
  wait out feedback, weaken assertions or accept an inspector regression.
  This iteration records a rejected approach, **not a shipped UI fix**.
- Retained ignored probe/prototype: build/validation/snackbar_layout_probe_test.dart
  and app-snackbar-footer-candidate.dart. Probe deliberately fails restored
  code; it is outside test/. Logs: snackbar-layout-{unit,linux_workflow_test,
  baseline-workflow,restored-unit,restored-planning}.log and integration-summary.txt.
- Restored tree verified: analyze 0 issues; format clean; 265 tests; native
  Linux planning and camera/GPU workflow pass with per-file 180-second bounds.
  Persisted session fingerprint remains 8/15850/7707460953092100.
- Logged under the dated entry and “Measured and deliberately not changed” in
  docs/performance-robustness-log.md; only documentation is committed.
- **Next iteration:** overlap remains unfixed. Find a shared layout that protects
  timeline AND inspector with live feedback; do not retry the footer-only
  prototype or dismiss/wait out notifications to make interaction tests pass.
  Preserve Undo/actions/durations/accessibility. Android hardware remains untested.

### Current loop, iteration 9 — `e704570` — plan-error snackbar priority
- Scanned all showSnackBar call sites. Reproduced save/open storage errors
  waiting behind the ten-second Camera moved/Undo prompt.
- Applied the existing save-confirmation pattern in managePlans' common error
  handler: remove current snackbar, then show the unchanged storage guidance.
  One shared change covers both save and open failures; state/data is unchanged.
- Strengthened the failed-save test with an actual inspector move, and tested
  open-error preemption at 390×844 and 1600×960 at 1.3 text scale. All three
  cases failed before editing and pass without waiting out the Undo duration.
- Extended native Linux planning validation with a real chmod-000 plan-folder
  failure after a move. Error replaces Undo, exact camera state is retained,
  permissions restore in finally and both saved plans remain readable. Native
  screenshot inspected: `build/validation/linux-plan-error-feedback.png`.
- Verified: analyze 0 issues; format clean; **265 tests pass**; native
  `linux_planning_ui_test` passes within 180 seconds. Persisted-plan fingerprint
  remains **4/2/3868/4680595913886116**. Logs under ignored
  `build/validation/plan-feedback-{unit,native,valid}.log`.
- Logged in `docs/performance-robustness-log.md`. No identical-UI claim: timing
  intentionally changes, and the transient Undo prompt is replaced by the error.
- **Next iteration:** the captured fixed snackbar visibly covers the lowest
  timeline controls; fix this placement/available-space issue as its own item.
  Queue candidates remain in session warnings, fullscreen and constellation
  failures. Broad messenger audit and Android hardware checks remain incomplete.

### Current loop, iteration 8 — `067c8ed` — saved-plan permission audit
- Audited the saved-plan browser for a SessionStore-style false-empty result.
  Hypothesis rejected on real Linux permissions: Directory.exists already
  throws PathAccessException/errno 13 beneath a mode-000 ancestor. The existing
  repository/UI preserve state and give storage/permission guidance.
- No production code was changed. Added a real permission regression checking
  propagated failure, restored listing, exact saved bytes and no extra files;
  it ran unskipped as the normal Linux user.
- Added a widget regression for storage guidance (not false “no saved plans”),
  unchanged dirty composition, and retry after the existing load error clears.
  Only the MemoryPlans test fixture gained a failure switch.
- Initial test setup incorrectly assumed Directory.exists would return false;
  corrected the root-user/unenforced-bits guard to use File.exists. The proper
  repository assertion passes against the original, unchanged implementation.
- Verified: analyze 0 issues; format clean; **264 tests pass**; native
  `linux_planning_ui_test` passes with a 180-second command bound. Plan listing
  fingerprint remains **4 plans / 2 unreadable / 3868 bytes / 4680595913886116**;
  normal plan file bytes match directly. Logs/probe under ignored
  `build/validation/plan-{listing,permissions}*`.
- Logged this as regression coverage, not a runtime fix, and recorded the
  unnecessary existence-check rewrite under “measured and deliberately not
  changed” in `docs/performance-robustness-log.md`.
- Non-Linux permissions/disk-full faults remain unchecked. Next iteration:
  inspect snackbar arbitration or one distinct layout/collection/date edge case;
  do not repeat this rejected PlanRepository rewrite without new evidence.

### Current loop, iteration 7 — `cf271d6` — unreadable checkpoint directory
- Reproduced a real Linux data-safety issue: `File.exists` returns false for an
  existing session beneath a mode-000 directory. Restore silently returned no
  session/no warning, leaving defaults eligible for autosave if access recovered.
- Removed the ambiguous existence guard. Existing size/read operations now
  distinguish ENOENT (plus Windows path-not-found) from other I/O failures.
  Permission errors reach the already-existing main startup handler, which
  disables autosave and asks the user to fix permissions/restart.
- Inspected all restore callers and session warning/exit-consent handling.
  No UI/API/schema/dependency or single-writer policy change needed.
- Added a real `chmod 000` regression, observed the silent-null failure before
  editing, and verified it passes after. It restores permissions in finally,
  checks exact original bytes and absence of extra files; it ran unskipped as
  the normal Linux user. Non-Linux/non-enforcing users skip that permission test.
- Added a genuine missing-parent first-launch test; corrupt/oversized backup,
  failed-save preservation and startup warning tests remain green.
- Normal restore fingerprint matches across 4 workspaces × 2 inspector modes:
  **8 sessions / 15850 JSON bytes / 7707460953092100**. Probe/logs under ignored
  `build/validation/session_restore_fingerprint_test.dart` and
  `session-permissions-{before,after}.log`.
- Verified: analyze 0 issues; format clean; **262 tests pass**. No GPU test needed
  for this checkpoint-I/O-only change. Non-Linux permissions/disk-full hardware
  faults remain unchecked; no performance claim or broad-audit completion.
- Logged in `docs/performance-robustness-log.md`. Next iteration: continue one
  evidenced collection/layout/date or persistence edge case.

### Current loop, iteration 6 — `ad52361` — tile projection validation
- Found that nonfinite latitude was silently clamped to a valid edge tile;
  nonfinite longitude reached floor conversion, and unsupported zooms reached
  shifts before TileId constructor validation. Added one guard in shared
  `TileId.coordinates` for finite coordinates and the existing 0–15 tile range.
- Inspected direct coordinates calls plus at/uv callers in coverage, LOD,
  terrain building/ground lookup and workspace selection. No caller, fixture,
  configuration, map zoom policy or export schema change needed.
- Added two invalid-input regressions and observed both fail before the edit.
  Cover NaN/±infinity in each coordinate through coordinates/at/uv, and
  −1/16/64/2³¹ zooms through coordinates/at. Also pin valid pole clamping and
  date-line world-copy wrapping at zooms 0/13/15.
- Valid behavior fingerprint matches before/after across 180 supported finite
  projection/selection/UV cases: **13626 JSON bytes / 1307761529637644**.
  Probe/logs: ignored `build/validation/tile_coordinates_fingerprint_test.dart`
  and `tile-coordinates-{before,after}.log`.
- Verified: analyze 0 issues; format clean; **260 tests pass**; GPU
  `linux_wasd_test` and `terrain_panel_test` pass individually with 180-second
  bounds. Logs: `build/validation/tile-coordinates-*_test.log`.
- Logged in `docs/performance-robustness-log.md`. Finite coordinate clamping
  remains unchanged; only invalid programmatic inputs change. No Android
  hardware or performance claim; the broad sweep is still incomplete.
- Next iteration: continue one evidenced collection/layout/date or persistence
  issue, without revisiting completed input guards.

### Current loop, iteration 5 — `b89f3e0` — exact polar destinations
- While checking geographic limits, reproduced a valid `destination` call from
  latitude 89.914° northward by 9562.776900083667 m yielding NaN: its intermediate
  sine rounded to `1.0000000000000002`. Southern equivalents rounded below −1.
- Clamp only the computed sine to asin's valid domain. One shared fix reaches
  camera movement, map/celestial handles, terrain loading circles and FOV wedges.
  No coordinate policy/UI expansion, API, export or configuration change.
- Added a six-case North/South Pole regression near the date line; observed it
  fail before the production edit, then pass with finite wrapped longitude and
  expected ±90° latitude. Exact-pole longitude is intentionally not prescribed.
- Fingerprinted ordinary outputs before/after: **2050 coordinate pairs / 71875
  JSON bytes / hash 3037040543338686** across 25 origins, eight bearings, six
  distances (0–80 km) and FOV wedges. Ignored probe/logs under
  `build/validation/destination_fingerprint_test.dart` and
  `polar-destination-{before,after}.log`.
- Verified: analyze 0 issues; format clean; **257 tests pass**; GPU
  `linux_wasd_test` and `linux_workflow_test` pass individually with 180-second
  bounds. Native logs: `build/validation/polar-destination-*_test.log`.
- Logged in `docs/performance-robustness-log.md`. Camera latitude remains
  limited to Mercator's ±85.05112878°; no Android device or performance claim.
- Next iteration: continue one evidenced validation/cache/persistence issue;
  the broad sweep is still incomplete.

### Current loop, iteration 4 — `259b458` — HTTP header deadline/cancellation
- During the cache/failure-path sweep, found that `downloadBytes` signalled
  abort but directly awaited `client.send`. Non-cooperative pending headers
  could hold all three origin slots indefinitely. Installed http 1.6.0's
  IOClient attaches abort handling only after `HttpClient.openUrl` completes.
- Added a single result completer for headers/errors/stop; retain existing
  host-release finally, consume late transport failures, and cancel late
  response body streams. No public API, cache, decoder, fixture or UI change.
- Checked every helper caller: terrain, imagery, forecast and atlas downloads.
  Existing service-timeout fallback/caller-cancellation behavior remains in use.
- Added three regressions: deadline and caller cancellation with three pending
  header requests, plus ordinary header error propagation. Observed both
  pending-header tests fail before the fix (one-second safety timeout). They
  now release slots for three new requests and cancel all three late streams.
- Valid payload fingerprint before/after across PNG/WebP terrain and 256/1024
  imagery, chunk sizes 1/127/4096: **12 samples / 24603 bytes / 250886605207858**.
  Probe/logs: ignored `build/validation/http_bytes_fingerprint_test.dart` and
  `http-headers-{before,after}.log`.
- Verified: analyze 0 issues; format clean; **256 tests pass**; GPU
  `linux_loading_test` and `startup_test` pass individually with 180-second
  bounds. Logs: `build/validation/http-headers-final-*_test.log`.
- Logged in `docs/performance-robustness-log.md`. Underlying OS connection
  teardown still depends on transport abort handling; no actual DNS fault
  injection or Android hardware testing. Broader failure-path sweep incomplete.
- Next iteration: continue one evidenced input/cache/persistence edge case;
  do not duplicate the completed header-cancellation fix.

### Current loop, iteration 3 — `6082f88` — nonfinite camera edit validation
- Found `SimulationState.copyWith` silently accepting NaN/±infinity for pitch
  and focal length because Dart clamps them to valid range endpoints before
  constructor validation. Added one finite guard in the shared method; finite
  out-of-range edits retain their existing clamping behavior.
- Inspected production copyWith callers, especially inspector fields, gestures,
  camera movement and celestial aiming. Numeric inspector inputs already reject
  nonfinite values; no caller, fixture, export schema or config change needed.
- Added a regression for both fields × NaN/positive infinity/negative infinity;
  observed it fail on the original code before making the fix.
- Fingerprinted 128 finite edit combinations across two fixed compositions:
  encoded plan JSON **124880 bytes / hash 5960327357299264** before and after.
  Probe/logs under ignored `build/validation/copy_with_fingerprint_test.dart`
  and `copy-with-{before,after}.log`.
- Verified: analyzer 0 issues; format clean; **253 unit/widget tests pass**;
  `linux_spec_photography_test` passes on the real Linux GPU with a 180-second
  command bound (optics, portrait/roll, fullscreen, PNG and Export metadata).
- Logged in `docs/performance-robustness-log.md`. No Android device check or
  performance claim; only invalid programmatic edits intentionally change.
- Next iteration: continue input/failure-path validation with one evidenced
  fix; the broad robustness sweep remains incomplete.

### Current loop, iteration 2 — `391aa7e` — idle render cap
- Added a one-second activity window, then `SceneView.maxFrameRate: 5` while
  idle. Edits/playback, terrain/imagery loading and export stay uncapped. Dispose
  the activity timer/notifier with the workspace.
- Real Linux GPU, fullyLive engine vsync, deterministic offline fixtures:
  Balanced idle **59.45 → 5.00 fps**, High **58.94 → 4.99 fps**. Final active
  editing measurements 58.60/59.73 fps; no interaction-speedup claim.
- Exact raw-RGBA running hashes match before/after: Balanced
  `5612850919298858`, High `8863014974402700`; camera return-to-origin matches
  each tier's original image too. See ignored `build/validation/idle-render-*.json`.
- Initial whole-workspace setState-on-timeout reset scene overrides; atmosphere
  and workflow failed. Both passed against the exact pre-cap HEAD/HEAD~ source.
  Fixed the root cause by notifying only the SceneView subtree. No integration
  assertions were weakened and no quality setting changed.
- Verified: analyze 0 issues; format clean; 252 tests; every integration file
  invoked separately on Linux, **23 successful / 20 executed / 3 expected
  platform skips**, including the new idle measurement and both export flows.
  Final summary: `build/validation/idle-cap-final-summary.txt`.
- An initial unbounded startup attachment stalled the first sequential sweep;
  terminated it, reran startup successfully, then reran the full matrix with a
  180-second per-file timeout. Do not use an unbounded sweep again.
- Logged the measurements and rejected parent-rebuild approach in
  `docs/performance-robustness-log.md`. No Android hardware/power measurement.
- Next iteration: input-validation/edge-case robustness, one evidenced fix.

### Current loop, iteration 1 — `11cb0c6` — requested export workspace
- Prioritized the user's explicit Export-tab request over the existing hardening
  backlog. Added the fourth bar/rail destination and session recovery support.
- Reused the existing bounded 2× renderer and no-overwrite PNG saver. The tab
  displays the exact bytes saved, an editable/copyable prompt with the full
  captured composition, geographic/time/astronomical metadata and source credits.
- Added explicit privacy/approximation warnings, busy/error/empty/stale states;
  retained prompt edits while switching between 3D and Export; hidden rendering
  stops after capture. Quick-export behavior remains available.
- Verified: analyze 0 issues; format clean; 252 unit/widget tests pass; both
  `export_workspace_test` and `linux_spec_photography_test` pass separately on
  the real Linux GPU. The new test checks exact PNG byte equality, output above
  screen resolution, clipboard edits, unchanged frame counter over ten idle
  pumps, stale metadata and re-render. Screenshot inspected at
  `build/validation/linux-export-workspace.png`.
- Combined integration invocation hit a debug-connection startup failure on
  its second app; the same test passed when invoked alone. No Android devices
  were connected, so no fresh Android native/MediaStore claim.
- No new dependencies or automatic model calls. Draft PNG/prompt is temporary,
  not session-persisted; README documents retention/reset behavior.
- Next iteration: resume the idle render cap prerequisite/backlog. Do not redo
  this export feature or claim the whole hardening loop is complete.


### Iteration 1 — `1e7e640` + `b6183ec`
- Added `pumpUntilRendered(tester, world, {frames})` to
  `integration_test/workspace_navigation.dart`; waits on
  `Scene.renderStats.frameCount` instead of a guessed pump duration.
- Converted the 7 fragile capture sites in `atmosphere_test.dart`.
- Verified: analyze 0, format clean, 247 tests, `atmosphere_test` green on
  `-d linux`. Logged in `docs/performance-robustness-log.md`.
- Next: enable the idle frame cap for real.
