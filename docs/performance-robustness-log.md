# Performance and robustness work log

Running log of optimisation and hardening work, newest first. Each entry names
the commit, the problem, the change, and the evidence that it is safe and
worthwhile. Anything measured is measured, never estimated, and the method is
recorded next to the number.

Read alongside [performance.md](performance.md) (baseline methodology and
before/after numbers) and [implementation-status.md](implementation-status.md).

## How entries are verified

Every commit in this log passed, before being committed:

```sh
flutter analyze                                    # 0 issues
dart format --output=none --set-exit-if-changed lib test integration_test
flutter test                                       # currently 286 tests
```

Changes touching rendering, GPU state or widgets also run the relevant
`integration_test/*_test.dart` on a real Linux GPU device
(`flutter test integration_test/<file> -d linux`), because those tests assert
pixels, scene-graph state and GPU pass structure that unit tests cannot see.

Where a change is meant to be behaviour-preserving, the output is fingerprinted
before and after: a running hash over the produced bytes (mesh positions,
decoded RGBA, encoded session) is captured on both sides and required to match.
Green tests alone do not prove a mesh or an encoder still emits the same data.

## Environment

Linux desktop, Flutter 3.47.7 / Dart 3.13.5 profile-capable build, NVIDIA GPU
with X11. Absolute timings are debug-JIT unless stated otherwise, so treat
relative deltas as the signal and absolutes as pessimistic.

---

## 2026-10-24 — requested session-warning priority

### `96791bc` fix: prioritize requested session recovery warnings

Clicking “Session recovery warning” appended its explanation behind active
camera Undo feedback. Since Undo is persistent in the current SDK, a deliberate
request for recovery guidance could appear to do nothing indefinitely. Reused
the established active-feedback replacement policy in that button callback:
remove current feedback, then show the unchanged warning. This intentionally
replaces Undo; message copy, Retry eligibility, duration/persistence, layout,
checkpoint writes, warning deduplication and exit consent remain unchanged.

Files: `lib/app/app.dart`, `test/session_restoration_test.dart`,
`integration_test/linux_planning_ui_test.dart`. Four compact/desktop cases at
390×844 and 1600×960, with 1.3 text scaling, failed before editing: requested
warning text was absent behind Undo. Two new startup-warning cases inject the
same disabled-store contract as main's storage-error handler and verify no Retry,
unchanged live edits, and exact old checkpoint JSON through disposal. Two
strengthened checkpoint-failure cases make another camera move while the warning
remains set, request its explanation, then repair the staging path and verify
Retry writes the latest full composition without changing the clean marker.

Native Linux planning additionally clicks the warning icon after another move
during a real blocked staging-path failure. Guidance replaces Undo immediately,
Retry is available, camera/checkpoint remain intact, and the existing phone-scale
scrubbing/retry flow still saves the exact subsequent composition. Inspected
`build/validation/linux-manual-session-warning.png`; controls remain unobscured.

Verified: analyzer 0 issues; format clean; **286 tests pass**. Native
`linux_planning_ui_test` and `linux_workflow_test` pass separately with 180-second
bounds. Normal session round-trip fingerprint remains exactly
**8 sessions / 15850 JSON bytes / 7707460953092100**. Evidence: ignored
`build/validation/manual-warning-{before,after,unit,final-unit,fingerprint,
linux_planning_ui_test,linux_workflow_test}.log` and the existing session probe.
Notification timing intentionally changes; no pixel-identical/performance claim.

Automatic startup warning, fullscreen failure and constellation-load arbitration
remain unaudited candidates, as does more general pending-queue priority. This is
not a completed messenger/failure-path audit. No actual disk-full fault or physical
Android/Windows validation was performed.

---

## 2026-10-24 — large-text local-day slider

### `f53a765` fix: keep the local-day slider usable with large text

The inline endpoint labels could exceed phone width at 200% text scaling,
overflowing the Row and starving its Expanded slider. Give the native slider
its own full-width row, with flexible endpoint labels in a separate legend row.
No text scaling clamp, hidden labels, breakpoint, dependency or new setting.
Align the desktop transport row to the bottom so its controls still line up
with the track; the existing strict alignment test passes unchanged.

Files: `lib/ui/time_slider.dart`, `lib/app/app.dart`,
`test/{time_slider,feedback_layout}_test.dart`,
`integration_test/linux_planning_ui_test.dart`. Four new regressions failed first:
320/390px standalone sliders with 24px side padding, plus collapsed/expanded
390×844 timelines with live feedback, all at 200% text. They now verify usable
track width, visible separate labels, successful scrubbing, UTC output, semantic
formatting and unchanged location/optics. The expanded short-landscape geometry
check now allows an already-minimum 48px canvas to remain at its minimum while
the timeline scrolls; strict shrink remains required above that minimum.

Preserved the actual slider/drag callbacks, supported-year guards and semantic
formatter. Before/after fingerprint over ordinary, spring-gap, fall-fold,
Lord Howe half-hour-shift and Nepal fractional-offset drags matches exactly:
**45 sampled drag/end states / 51859 JSON bytes / 5379452141715050**.
The probe hashes full encoded composition plus range/value/tooltip/semantic
labels, including repeated 24:00 updates and release into the next local day.
Evidence: ignored `build/validation/time_slider_fingerprint_test.dart` and
`time-slider-fingerprint-{before,after}.log`. Layout intentionally changes;
no pixel-identical UI or performance claim.

Native Linux planning additionally resizes the test viewport to 390×844 with
200% text during a real blocked checkpoint write. It checks label/track separation,
scrubs without changing location/optics, keeps the previous checkpoint untouched,
and successfully retries the exact edited composition. Inspected both native
captures: `linux-phone-large-text-timeline.png` and `linux-session-error-feedback.png`
under `build/validation/`. This is Linux-rendered phone emulation, not physical
Android evidence; it does not complete the broader mobile/accessibility audit.

Verified: analyzer 0 issues; format clean; **284 tests pass**. Seven affected native
Linux workflows pass, each with a separate 180-second bound: planning, photography
spec/export, map/GPU camera workflow, WASD, terrain panel, calendar and perf.
Logs: `build/validation/time-slider-{layout-before,layout-after,unit,final-unit,
native-planning,*_test}.log` and `time-slider-integration-summary.txt`.
Remaining startup/manual warning, fullscreen and constellation-load message
priority candidates are still open. Android/Windows hardware remains untested.

---

## 2026-10-24 — layout-occupying workspace feedback

### `a7a6839` fix: reserve workspace space for feedback

Fixed snackbars covered timeline controls; the rejected footer-only prototype
moved that obstruction onto the inspector. Replaced the presentation, not the
messages, with native zero-elevation MaterialBanners. Scaffold now allocates
space above the body instead of overlaying controls. Existing queue/preemption
calls route through one shared adapter; content, actions, persistence and visible
durations remain specified by the existing SnackBar values. Close uses the native
localized affordance and banners provide native live-region/dismiss semantics.
Expiry starts when visible, cancels on replacement/disposal, and uses no
workspace-wide timer rebuild. Long selectable paths/errors scroll within one
third of the window; short expanded timelines scroll while keeping canvas space.
Pane scrollers do not steal the page's primary scroll controller. NavigationRail
uses its native scrolling support when reduced height cannot fit destinations.

Files: `lib/ui/workspace_feedback.dart`, `lib/app/app.dart`,
`lib/ui/{simulation_workspace,export_panel}.dart`,
`test/{feedback_layout,workspace_feedback}_test.dart`, and
`integration_test/{linux_planning_ui,linux_workflow}_test.dart`.
All production snackbar call sites were migrated; no pixel offsets, dependency,
custom notification queue, persistence schema or renderer-quality changes.

The original five compact/desktop overlap cases failed before editing. Seven
passing cases cover collapsed/expanded timelines, safe-area insets, 1.3 scaling,
and 2.0 scaling on landscape/desktop. They click the local-day slider and playback
while feedback stays visible, check inspector/navigation separation, and retain
location/optics. Viewport height intentionally adapts; pixel-identical UI is not
claimed. Six lifecycle cases cover visible-duration expiry, native persistence
with/without accessible navigation, action callbacks, queue/preemption, timer
disposal, dismissal and long selectable content.

**SDK contract correction:** this Flutter's SnackBar defaults `persist` to true
when it has an action. Thus the configured ten-second Undo was already persistent,
not guaranteed to expire after ten seconds as older entries assumed. The adapter
preserves that actual native behavior, including persistent Retry, rather than
quietly shortening acknowledgement time or hiding notifications to pass tests.

Native planning injects a real blocked checkpoint staging path, verifies separate
banner/inspector/timeline bounds, clicks “Later by one hour” during the error,
preserves location/optics and old checkpoint bytes, then retries the exact edited
composition. Inspected `build/validation/linux-session-error-feedback.png`:
message, Retry, inspector, attribution and timeline controls are unobscured.

The GPU workflow initially hit a clipped relighting control after `ensureVisible`.
Checked exact HEAD~ application/test sources first: baseline passed. With allocated
banner space, the scroll jump needs a rendered frame before hit-testing. Added
only `pump()` after `ensureVisible`, not a timed wait, dismissal or weaker material
assertion. The same physically-based-material check and entire workflow now pass.

Verified: analyzer 0 issues; format clean; **280 tests pass**. Every integration
file ran separately with a 180-second bound on Linux: **23 successful invocations /
20 executed / 3 expected platform skips**. After final pane-controller isolation,
planning and WASD passed again. Session round-trip fingerprint matches exactly:
**8 sessions / 15850 JSON bytes / 7707460953092100**. Evidence: ignored
`build/validation/feedback-{layout-before,space-*}.log`,
`feedback-space-integration-summary.txt`, and retained session fingerprint probe.
No performance or physical Android/Windows validation claim.

**Next distinct defect:** a 390px phone at 200% scaling overflows the unchanged
TimeSlider row even before feedback is shown. Isolated it without any feedback
adapter in `build/validation/time_slider_200_percent_probe_test.dart`; that
expected-failing probe and `time-slider-200-percent-before.log` are ignored/local,
not part of the passing suite. Address its label/track width next; do not mark
all large-text/mobile layouts audited. Remaining message-priority candidates
(startup/manual warnings, fullscreen and constellation failure) are still open.

---

## 2026-10-24 — checkpoint-save error priority

### `13c54c7` fix: surface checkpoint failures ahead of camera undo

The common `saveSession` failure handler queued its storage guidance and Retry
behind the ten-second “Camera moved” / Undo prompt. A failed automatic checkpoint
could therefore appear unacknowledged while the user's latest edits were not
recoverable after a crash. Reused the existing plan-error policy: remove active
feedback before showing the unchanged warning. No persistence, message copy,
retry, duration, deduplication, layout, theme, dependency or framework changes.
As with plan errors, this deliberately replaces the transient Undo notification.

Files: `lib/app/app.dart`, `test/session_restoration_test.dart`,
`integration_test/linux_planning_ui_test.dart`. Inspected timer, lifecycle,
exit-consent and Retry callers of the shared handler. Two widget regressions
at 390×844 and 1600×960, both with 1.3 text scaling, failed before editing:
the save warning was absent behind Undo. They now observe the warning and Retry
without advancing through Undo's lifetime, verify the exact previous checkpoint
JSON and unchanged live composition, remove a real blocking staging directory,
and verify Retry saves every composition field without marking the plan clean.

Native Linux planning now uses a real SessionStore and injects the same staging
path obstruction during a lifecycle flush after an inspector move. It checks
immediate warning replacement, unchanged checkpoint/live state, successful Retry,
cleared warning icon and both named plans still readable. Inspected
`build/validation/linux-session-error-feedback.png`: storage guidance and Retry
are visible; **the pre-existing timeline overlap remains visible and unfixed**.

Verified before committing: analyzer 0 issues; format clean; **267 tests pass**;
`linux_planning_ui_test` and `linux_workflow_test` each pass on the real Linux
GPU device with separate 180-second bounds. Normal session round-trip output
matches the prior baseline exactly: **8 sessions / 15850 JSON bytes /
7707460953092100**. Evidence: ignored
`build/validation/session-feedback-{before,after,unit,native,workflow,fingerprint}.log`;
reused `session_restore_fingerprint_test.dart`. Notification timing intentionally
changes; no performance or identical-pixel claim is made.

Reflection: failing-first tests, fingerprints and native workflows are productive;
footer-only experiments are not. This iteration takes a distinct bounded
failure-path fix, not a retry of the rejected layout. Layout protecting timeline
and inspector remains the highest open UI item. Startup/manual warning display,
fullscreen and constellation-load queueing remain unaudited. No actual disk-full
fault or Android/Windows hardware validation was performed.

---

## 2026-10-24 — snackbar footer prototype rejected

### `295a629` docs: record rejected snackbar footer layout

Application/test sources remain unchanged from `a5380a0`.

Reproduced the timeline overlap with a five-case geometry/interaction probe:
390×844 and 844×390 with collapsed/expanded timelines, plus 1280×800, all
with 1.3 text scaling and 24-pixel safe-area insets. Moving the timeline into
`Scaffold.bottomNavigationBar` let the platform put snackbars above it without
per-message offsets. The candidate passed **270 unit/widget tests**, including
slider/play interaction and unchanged map size while feedback was visible.
A scrollable navigation rail was needed for the shorter landscape body.

**Rejected, not shipped:** the native `linux_workflow_test` then failed because
the snackbar intercepted the inspector's “Approximate relighting” tap at
(1073, 881); its material remained Unlit instead of becoming PhysicallyBased.
Restoring the exact `HEAD~` shell first made that unchanged native test pass.
The prototype moved the obstruction from the timeline to inspector controls.
No test assertion was weakened, notification suppressed, or quality setting
changed to make it pass. All application and test edits were reverted.

The candidate's bounded native sweep had six executed passes, this one failure,
and three expected platform skips. After reverting, analyzer has 0 issues,
format is clean, **265 unit/widget tests pass**, and both native Linux planning
and camera/GPU workflow pass. Session round-trip output also matches the prior
baseline exactly: **8 sessions / 15850 JSON bytes / 7707460953092100**.

Only this documentation changes. Reproduction artifacts are ignored/local:
`build/validation/snackbar_layout_probe_test.dart`,
`app-snackbar-footer-candidate.dart`, `snackbar-layout-unit.log`,
`snackbar-layout-linux_workflow_test.log`, `snackbar-layout-baseline-workflow.log`,
`snackbar-layout-restored-{unit,planning}.log`, and
`snackbar-layout-integration-summary.txt`. The probe deliberately still fails
against the restored application; it is not part of the passing test suite.

**The overlap remains unfixed.** Next work must protect timeline *and* inspector
access with live notifications, not merely relocate their overlay. Preserve
Undo/action semantics and do not hide feedback or wait out its timer in tests.
No performance/pixel-identity claim or Android hardware validation is made.

---

## 2026-10-24 — plan-error snackbar priority

### `e704570` fix: surface plan errors ahead of camera undo feedback

The shared plan save/open error handler called `showSnackBar` without removing
an active snackbar. After a camera move, actionable storage failures waited
behind the **ten-second** “Camera moved” / Undo prompt. The user could see no
failure acknowledgement while trying to save or open a plan.

Files: `lib/app/app.dart`, `test/plan_switching_test.dart`,
`integration_test/linux_planning_ui_test.dart`. Reused the existing save-success
pattern: remove the current snackbar, then display the unchanged actionable
plan-error message. One change to the common handler covers save and open
failures. This intentionally replaces the transient Undo prompt; no composition,
save format, message copy, style, dependency or notification framework changes.

Strengthened the failed-save regression to start with a real camera move, and
covered load-error preemption at 390×844 and 1600×960 with 1.3 text scaling.
All three cases failed before the fix (Undo still visible / error absent), and
now pass immediately after settling animations, without advancing through the
undo duration. Tests preserve the same immutable dirty composition and confirm
retry still works. Native Linux planning also changes real plan-directory
permissions to `000`, verifies the error replaces Undo and leaves the camera
state untouched, restores access in `finally`, and reopens the two saved plans.
The native permission phase ran, not skipped, and produced the inspected
`build/validation/linux-plan-error-feedback.png`.

Verified: analyzer 0 issues; format clean; **265 unit/widget tests pass**;
`linux_planning_ui_test` passes on the native Linux device with a 180-second
bound. Normal persisted-plan output still fingerprints identically:
**4 plans / 2 unreadable / 3868 JSON bytes / 4680595913886116**; see
`build/validation/plan-feedback-{unit,native,valid}.log` and the existing
`plan_listing_fingerprint_test.dart` probe. Notification timing intentionally
changes; no pixel-identical UI claim is made.

The call-site scan found remaining queueing candidates in session warnings,
fullscreen failure and constellation-load failure. The native screenshot also
confirms that the fixed snackbar obscures the lowest timeline controls, even
on the desktop capture. **That layout issue is not fixed here and is the next
iteration's target.** This is not a completed messenger/compact-layout audit;
Android hardware feedback/layout remains unverified.

---

## 2026-10-24 — saved-plan permission contract (tests only)

### `067c8ed` fix: add regression coverage for unreadable plan storage

Audited whether `PlanRepository.loadAll` might repeat the session-recovery bug
from `cf271d6`. The proposed production rewrite was unnecessary: on this Linux
system, `Directory.exists` already throws `PathAccessException` / errno 13 for
a plans folder beneath an inaccessible ancestor. The existing UI catches that
failure and explains storage space/permissions without replacing the current
composition. **No production code was changed.** The rejected rewrite is also
recorded below so this audit is not repeated without new evidence.

Files: `test/saved_plans_test.dart`, `test/plan_switching_test.dart`. Added a
real Linux `chmod 000` regression verifying that listing propagates the error,
restored access reveals the original plan, saved bytes are identical, and no
extra files appeared. It ran unskipped as the normal Linux user; other platforms
or users for whom permission bits are not enforced skip that test. Added a
widget regression for the existing actionable storage message, no misleading
“No saved plans found,” unchanged unsaved state, and successful retry after the
injected load failure clears. Only the existing in-memory test fixture gained
a failure switch.

The initial test probe wrongly assumed `Directory.exists` would behave like
`File.exists`; it threw before reaching the repository assertion. After using
the known `File.exists` behavior solely to detect unenforced permission bits,
the permission test correctly passed against the unchanged production code.
This is regression coverage of a working failure path, not a newly fixed runtime
bug or an intentionally failing-before/passing-after production change.

Verified: analyzer 0 issues; format clean; **264 unit/widget tests pass**;
`linux_planning_ui_test` passes on the native Linux device within a 180-second
command bound. Plan listing also retains its exact output fingerprint:
**4 plans / 2 unreadable neighbors / 3868 JSON bytes / hash 4680595913886116**,
and each normal on-disk plan matches its original bytes. Ignored evidence:
`build/validation/plan_listing_fingerprint_test.dart`,
`plan-listing-{before,after}.log`, `plan-permissions-unit.log`,
`plan-permissions-native.log`. Non-Linux permissions and actual disk-full faults
remain unchecked; no performance gain or broad-audit completion is claimed.

---

## 2026-10-24 — unreadable session directory safety

### `cf271d6` fix: distinguish unreadable session storage from first launch

`SessionStore.restore` used `File.exists` to decide whether a checkpoint was
missing. On Linux, an existing checkpoint inside a directory with mode `000`
returns false from that call. Recovery therefore silently returned
`(session: null, warning: null)`, allowing the app to start with defaults and
leaving autosave eligible to replace the previous composition if permissions
later recovered.

Files: `lib/data/app_session.dart`, `test/app_session_test.dart`. Remove the
ambiguous existence check and use the existing size/read operations. Only a
real missing-file/path error is treated as first launch (ENOENT 2; Windows
path-not-found 3 on Windows). Other filesystem failures propagate to the
existing `lib/main.dart` startup handler, which clears the session store,
disables automatic checkpoint writes and displays “Check folder permissions
and restart.” No new UI, save format, API, dependency or concurrency policy.

The new regression creates a valid checkpoint, removes all directory access
with Linux `chmod 000`, and verifies that restore fails rather than reporting
an absent session. It failed before the fix with the silent-null result and
passes after it. Permissions are restored in `finally`; the original file's
bytes are unchanged and no quarantine/staging file appeared. This ran as the
normal non-root Linux user, not a simulated filesystem. The permission test
explicitly skips other platforms and users for whom those bits are not enforced.
A second test confirms a genuinely missing parent directory remains a normal,
non-mutating first launch. Existing corrupt/oversized quarantine, failed-write
preservation and startup-warning/exit-consent tests still pass.

Normal recovery is fingerprint-proven across all four workspaces and both
inspector visibility settings: **8 sessions / 15850 encoded JSON bytes / hash
7707460953092100**, identical before/after. The probe also compares restored
encoding and on-disk checkpoint bytes directly to the original. Ignored evidence:
`build/validation/session_restore_fingerprint_test.dart`,
`session-permissions-{before,after}.log`, `session-permissions-unit.log`.

Verified: analyzer 0 issues; format clean; **262 unit/widget tests pass**.
No GPU integration run was required: this change touches only checkpoint I/O
and its tests, not widgets/rendering/export. Windows/Android permissions and
actual disk-full faults were not newly exercised; the broader persistence audit
remains open. No performance claim is made.

---

## 2026-10-24 — tile projection validation

### `ad52361` fix: validate tile coordinates and zoom before projection

`TileId.coordinates` clamped latitude before checking finiteness, so a NaN or
infinite latitude became a valid-looking northern/southern edge projection.
Nonfinite longitude reached integer conversion in `TileId.at`; unsupported zooms
were shifted before the `TileId` constructor could reject them. Added a shared
finite-coordinate/0–15 zoom guard before projection. The zoom range already
belonged to the tile constructor; the helper now enforces the same contract.

Files: `lib/core/terrain_geo.dart`, `test/terrain_geo_test.dart`. Checked direct
projection callers, `TileId.at`, `TileId.uv`, terrain coverage/LOD, terrain
building/ground lookup and workspace tile selection. All production callers use
supported zooms and validated camera state, so no caller/interface/configuration
change is required. The map engine's independent zoom range is unchanged.

Two invalid-input regressions failed before the fix: nonfinite coordinates
returned a projection instead of `ArgumentError`, and zoom 16 was accepted by
the helper. Tests now cover NaN/±infinity in either coordinate through
projection/tile selection/UV lookup, and zooms −1/16/64/2³¹ through projection
and tile selection. A third test preserves finite pole clamping and date-line
world-copy wrapping at zooms 0/13/15. This does not add stricter bounds to
otherwise finite latitude/longitude values or change Mercator clamping.

Unchanged valid behavior is fingerprint-proven across 180 combinations of
supported zoom, finite latitude (including ±90°), and longitude (including
unwrapped world copies): raw projection, selected key and UV coordinate JSON
matches **13626 bytes / hash 1307761529637644** before/after. Ignored artifacts:
`build/validation/tile_coordinates_fingerprint_test.dart`,
`tile-coordinates-{before,after}.log`.

Verified: analyzer 0 issues; format clean; **260 unit/widget tests pass**.
`linux_wasd_test` and `terrain_panel_test` pass on the real Linux GPU with
180-second command bounds; logs `build/validation/tile-coordinates-*_test.log`.
Only invalid programmatic inputs intentionally change. No performance gain,
Android hardware validation or completion of the broader sweep is claimed.

---

## 2026-10-24 — exact polar destinations

### `b89f3e0` fix: keep exact polar destinations inside the asin domain

The shared spherical `destination` helper produced NaN for valid travel exactly
to a pole. For example, latitude **89.914°**, bearing **0°**, distance
**9562.776900083667 m** produces an intermediate sine of
**1.0000000000000002** through floating-point roundoff. `asin` then returns NaN;
the analogous southern inputs round below −1. Clamp this intermediate value to
`[-1, 1]` before `asin`, without changing the formula, coordinate conventions,
wrapping or the app's separate Mercator/camera latitude limits.

Files: `lib/core/geo.dart`, `test/geo_test.dart`. Added a regression covering
three positive and three negative starting latitudes approaching the respective
pole, with longitude near the date line. It failed before the fix (NaN rather
than 90°) and now returns the expected ±90° latitude and finite wrapped longitude.
Longitude at an exact pole is not unique, so the test does not prescribe one.

Checked every caller: WASD movement, camera/celestial map handles, FOV wedges,
terrain loading circles and the related tests. No API, fixture, configuration,
export schema or UI change is needed. This corrects the generic helper for
valid polar coordinates, not a claim that the UI now supports placing its
camera outside its existing ±85.05112878° range.

Ordinary output is fingerprint-proven: 25 origin positions (including ±85° and
±180°), eight bearings, six distances from zero to 80 km, plus FOV wedges yield
**2050 coordinate pairs / 71875 JSON bytes / hash 3037040543338686**, exactly the
same before and after. Probe/artifacts under ignored `build/validation/`:
`destination_fingerprint_test.dart`, `polar-destination-{before,after}.log`,
`polar_destination_probe.dart`.

Verified: analyzer 0 issues; format clean; **257 unit/widget tests pass**.
`linux_wasd_test` and `linux_workflow_test` pass on the real Linux GPU, each
bounded to 180 seconds; logs `build/validation/polar-destination-*_test.log`.
No performance gain or new Android device verification is claimed. Other public
input-validation and persistence failure-path work remains incomplete.

---

## 2026-10-24 — bounded HTTP header acquisition

### `259b458` fix: bound pending HTTP headers by cancellation and deadline

`downloadBytes` completed its stop signal on deadline/caller cancellation but
still directly awaited `client.send`. A client that had not attached its abort
handler could therefore leave the caller waiting and occupy all three per-origin
slots indefinitely. This is a real transport boundary: the installed http
1.6.0 `IOClient.send` awaits `HttpClient.openUrl` before attaching its abort
handler, so connection setup can precede abort handling.

Files: `lib/data/http_bytes.dart`, `test/http_bytes_test.dart`. Header arrival,
ordinary send errors and the existing stop signal now complete a single result.
If cancellation/deadline wins, the host slot is released through the existing
`finally`; any later response stream is subscribed/cancelled instead of being
left unread. Late transport errors are consumed; timely errors retain their
original exception/stack. No dependency, API, decoder, cache or UI change.

The fix reaches all callers through the shared helper: terrain, imagery,
forecast and atlas downloads. Existing source fallback distinguishes service
abort from caller cancellation, so provider fallback/error messages can now
advance rather than hang waiting for headers.

Three regressions cover 20 ms deadline expiry, explicit cancellation with a
20-second deadline, and ordinary header failures. The two pending-header cases
occupy all three slots with non-cooperative clients and failed before the fix
(their one-second safety timeouts expired); after the fix they finish within
the safety bound, three subsequent requests all start/succeed, and three late
body streams are cancelled. Ordinary send exceptions propagate unchanged.
Existing body-size, cooldown, retry, fallback and empty-cache-on-cancel checks
also pass.

Successful payloads are fingerprint-proven before/after with terrain PNG,
terrain WebP and 256/1024 imagery fixtures, each delivered in chunks of 1, 127
and 4096 bytes: **12 samples / 24603 bytes / hash 250886605207858**. The probe
also compares each returned byte buffer to its fixture. Artifacts under ignored
`build/validation/`: `http_bytes_fingerprint_test.dart`,
`http-headers-{before,after}.log`.

Verified: analyzer 0 issues; format clean; **256 unit/widget tests pass**.
`linux_loading_test` and `startup_test` pass on the real Linux GPU, each with a
180-second command bound; logs `http-headers-final-*_test.log`.
This bounds the app's wait for headers, not the OS's connection teardown:
underlying pending connection work still relies on the transport observing
abort. OS-level DNS fault injection, Android hardware and new power/performance
measurements were not performed.

---

## 2026-10-24 — camera edit validation

### `6082f88` fix: reject nonfinite camera edits before clamping

`SimulationState` rejected nonfinite constructor parameters, but `copyWith`
clamped pitch/focal length first. Dart's `clamp` converted NaN into the upper
limit and ±infinity into a range endpoint, silently accepting invalid edits
(e.g. pitch 85° or focal length 600 mm). Added an explicit finite check for
these two optional inputs before retaining the existing finite-value clamps.

Files: `lib/models/simulation_state.dart`, `test/camera_test.dart`. The new
regression failed on the original implementation and passes after the fix,
covering NaN and both infinities for both fields. Call sites were inspected:
inspector numeric fields already validate finite values, sliders provide bounded
values, and gestures/celestial aiming continue using finite camera values.
Other fields still pass through the existing constructor validation; this is
one fix in the larger input-validation sweep, not a claim that it is complete.

Finite behavior is fingerprint-proven: an ignored probe at
`build/validation/copy_with_fingerprint_test.dart` covers 128 combinations of
omitted/normal/boundary/extreme finite pitch and focal-length edits across two
compositions (including APS-C/portrait, elevation overrides and weather/optics).
Running hash over all encoded plan JSON bytes is identical before and after:
**128 samples / 124880 bytes / 5960327357299264**. Before/after probe logs are
`build/validation/copy-with-{before,after}.log`. Finite out-of-range clamping
and normal edits are unchanged; invalid nonfinite programmatic edits now throw
`ArgumentError` instead of unexpectedly changing the composition.

Verified: analyzer 0 issues; format clean; **253 unit/widget tests pass**;
`integration_test/linux_spec_photography_test.dart` passes on the real Linux GPU
with a 180-second command bound, exercising optics, portrait/roll, fullscreen,
quick PNG export and Export workspace metadata. Native log:
`build/validation/copy-with-finite-native.log`. No performance gain is claimed;
no new Android device validation was performed.

---

## 2026-10-24 — idle renderer cap

### `391aa7e` perf: cap idle scene rendering at five frames per second

`SimulationWorkspace` rendered a static frame at every display refresh. Added a
one-second activity window after composition/fullscreen/workspace changes;
`SceneView.maxFrameRate` is 5 outside that window, and null during loading,
imagery loading and export. Repeated edits/playback keep the renderer uncapped.
Only a local `ValueListenableBuilder` rebuilds when the activity window ends;
photography configuration and imperative scene overrides remain untouched.
The activity timer and notifier are disposed with the workspace.

Files: `lib/ui/simulation_workspace.dart`,
`integration_test/idle_render_test.dart`.

Measured with real engine vsync (`fullyLive` binding), deterministic offline
terrain/imagery fixtures, a fixed UTC composition and the Linux NVIDIA GPU in a
debug build. For each quality tier: wait two wall-clock seconds, then divide the
actual `renderStats.frameCount` delta by elapsed time over two seconds; separately
measure camera edits for two seconds. Baseline was captured before the production
change using `--dart-define=IDLE_CAP_BASELINE=true`; that test flag changes only
assertions/output filenames, not application behavior.

| Tier | Before idle fps | After idle fps | After active edits fps |
|---|---:|---:|---:|
| Balanced | 59.45 | 5.00 | 58.60 |
| High | 58.94 | 4.99 | 59.73 |

This is roughly **12× fewer idle scene renders**, not a measured power or GPU-time
claim. Baseline active rates were 50.49/55.96 fps in the earlier run; active rates
vary with test driving and system load, so no interaction speedup is claimed.
The renderer has no configured cap during edits. Returning the camera to its
original pose reproduces the same image after settling back to idle.

Fingerprint proof: running hash over every rendered raw RGBA byte before/after
matches exactly at both tiers: Balanced **5612850919298858**, High
**8863014974402700**. The final test rerun reproduced both hashes. Captures include
the same native window size and fixed fixture state; no quality settings changed.
Artifacts: `build/validation/idle-render-{before,after}.json`,
`idle-cap-final-idle_render_test.log`, `idle-cap-final-summary.txt`.

Verification: analyzer 0 issues; format clean; **252 unit/widget tests pass**.
All **23 integration-file invocations** succeeded individually on `-d linux`:
20 executed, while Android workflow and the two Windows files platform-skipped.
This includes atmosphere, camera light, clouds, imagery, terrain, Moon/Milky Way,
loading/startup, navigation, quick export, Export workspace and profile harness.
An initial sequential run stalled attaching to startup; it was terminated, and
startup plus the full final suite passed with a per-file 180-second bound.
No Android hardware/frame-rate or power measurement was performed.

The rejected whole-workspace timer variant and its baseline checks are recorded
below so it is not reintroduced.

---

## 2026-10-24 — requested export workspace

### `11cb0c6` fix: give image exports a dedicated review workspace

The user's requested export review/AI-context workflow took priority over the
hardening backlog for this iteration. The old save shortcut offered no dedicated
review surface and no reusable capture metadata for an external image model.

Added the Export bar/rail destination, session destination validation, a PNG
preview using the exact buffer passed to the existing native saver, and an
editable/copyable enhancement prompt. The prompt includes the complete captured
composition, coordinates, UTC and estimated local time, elevations (explicitly
unknown where unavailable), camera/optics/exposure, weather, Sun/Moon/galactic
center positions, render settings, output size and source credits. Privacy and
simulation/forecast/AI limitations are visible; nothing calls an AI service.

Files: `lib/app/app.dart`, `lib/data/app_session.dart`,
`lib/data/enhancement_prompt.dart`, `lib/ui/export_panel.dart`,
`lib/ui/simulation_workspace.dart`, related unit/widget/integration tests and
`README.md`. Existing quick export, quality presets, credit stamp and
no-overwrite saver remain in use. Drafts survive 3D/Export switching, not
Map/Calendar/restart; re-rendering explicitly resets the prompt.

Verification: analyzer 0 issues; format clean; **252 tests pass**. Both
`integration_test/export_workspace_test.dart` and
`integration_test/linux_spec_photography_test.dart` pass on the real Linux GPU
when invoked separately. The new test proves saved bytes equal preview bytes,
output exceeds screen size (fixture capture: **2266×1511** after crop from a
**2518×2042** 2× render), editable clipboard output, stale capture handling and
re-rendering. The hidden scene's frame counter stays unchanged across ten
30 ms pumps after capture (not a wall-clock frame-rate benchmark).

Inspected `build/validation/linux-export-workspace.png` (real geographic imagery,
portrait/roll capture); fixture screenshot `linux-export-tab.png` is deliberately
synthetic. Compact/expanded layouts and 1.3 text scaling are widget-tested.
No Android device/emulator was connected, so fresh native Android screenshots
and MediaStore validation were unavailable. The combined two-file integration
invocation failed to attach to its second app; rerunning that test alone passed.
No performance claim beyond the tested hidden-render stop is made.

---

## 2026-10-24 — hardening loop

### `1e7e640` test: wait for a real render before capturing GPU pixels

`integration_test/atmosphere_test.dart` mutated the scene (fog, light
intensity, environment, ambient occlusion, shadows), pumped a fixed 100 ms, then
captured the `RepaintBoundary`. That is only valid while the preview renders
every single frame: a pump schedules a frame but the ticker decides whether to
draw it, so the capture could silently observe the previous scene state as soon
as frame output is gated for any reason.

Added `pumpUntilRendered(tester, world, {frames})` to
`integration_test/workspace_navigation.dart`. It waits on
`Scene.renderStats.frameCount`, which only advances when a frame actually
rendered, and converted the seven capture sites that relied on one fixed pump.

Verified: `atmosphere_test` passes on `-d linux`, 247 unit tests pass.

This is the prerequisite for the idle frame-rate cap: the cap was previously
rejected only because nine tests depended on render-per-pump determinism.

---

## 2026-10-24 — test suite repair, export quality, terrain LOD

### `08a5509` style: apply dart format to files touched by the perf commits

Four files from the performance commits below wrapped a line past the
formatter's limit and would have failed CI's
`dart format --set-exit-if-changed`. Formatting only.

### `a7ec18b` test: guard the Android workflow and repair the Linux workflow test

`android_workflow_test.dart` asserts the Android gallery export channel and its
"Saved PNG to Pictures/PhotoSim" snackbar, so it fails anywhere else. It was the
only workflow test missing the platform guard the Windows tests already have.
Added `skip: !Platform.isAndroid`.

`linux_workflow_test.dart` had four independent breakages, all found by
bisecting the test against `21e04f9` in a separate `git worktree`:

- The textured-mesh assertion filtered on `name != 'Moon'`, which also matched
  the procedural `Clouds` node added by an earlier feature commit: 10 nodes
  where the test means the 9 terrain tiles. Now filters on the `z-x-y` terrain
  name pattern used elsewhere in the suite.
- A "Camera moved / Undo" snackbar floats over the timeline and swallowed the
  tap on "Later by one hour" — the framework reported
  `derived an Offset (Offset(377.2, 993.0)) that would not hit test`, so the
  sun never moved and the light direction stayed identical. The test now
  dismisses the snackbar before tapping.
- The plan-save confirmation was queued behind that same ten-second snackbar;
  see the app fix below.
- One wait assumed exiting the clean preview completes within one second; it
  now pumps until the AppBar returns.

### `d3b276e` feat: render the saved photograph above screen density

The export captured the screen `RepaintBoundary` at the device pixel ratio, so
the saved file could never contain more pixels than the 3D view had rendered —
raising `toImage(pixelRatio:)` alone only upscales the composited texture. A
typical window produced roughly a 1.5 MP photograph.

`Scene.renderScale` is the render-target multiplier
(`target = viewArea × dpr × renderScale`), so the export now re-renders the
frame at twice the device pixel ratio and captures at the matching ratio.
Because `configurePhotography` resets `renderScale` to the on-screen tier on
every build, the override is applied after it, and the capture waits two frames
(one applies the scale, one renders into the larger target).

- `exportOversample = 2.0`, bounded by 6144 px and 20 MP
- the attribution stamp now scales with image width instead of a fixed 11 px
  line that had become unreadable on large exports
- measured on the portrait export path: **872×848 → 1744×1696 (2.00×)**

### `3a3123c` fix: show the save confirmation ahead of the camera-move undo prompt

`savePlan` queued its confirmation behind whatever `ScaffoldMessenger` was
already showing. `offerCameraUndo` shows a **ten-second** snackbar, so after any
camera move the "Saved *name* · *path*" confirmation waited ten seconds — or
never appeared if another camera move interrupted it. Move-then-save is the
normal flow, so a successful save could produce no acknowledgement at all.
Removed the current snackbar first, as `offerCameraUndo` already does.

### `41b9bcf` perf: step terrain mesh resolution down with camera distance

`terrainMeshResolution` keyed only on zoom: every zoom-13 tile in the requested
coverage got 64 samples (128 at High) whether it sat 1 km or 30 km away, so a
distant ridge burned the same vertex budget as the hillside under the camera.

Samples now follow a tile's apparent size: full neighbourhood resolution until
a tile is more than 2.5 of its own widths from the camera, then halving per
doubling, floored at 16 samples so horizon silhouettes survive. Distance uses
the camera's fractional tile coordinate, so it wraps the date line and needs no
haversine.

Total terrain vertices over the requested coverage:

| Forward reach | Balanced | High |
|---|---|---|
| 0 km (3×3) | 51 748 → 51 748 | 201 764 → 201 764 |
| 20 km | 160 648 → 86 920 | 624 264 → 335 496 |
| 40 km | 223 860 → 95 668 | 867 316 → 366 708 |

−46 % and −57 % vertex load when distant coverage is requested; the default
3×3 view is untouched.

---

## 2026-10-24 — allocation and redundant-work pass

Fixes below were each proven behaviour-preserving with a running hash over the
produced output captured before and after, in addition to the full suite.

### `a17971d` perf: build the session composition map instead of reparsing it

`AppSession.encode()` reached the nested composition through
`jsonDecode(SavedPlan(...).encode())`: pretty-print the whole state to indented
JSON, parse it straight back to a `Map`, re-encode the outer object. Two full
JSON traversals per save for a value it already had. This runs on every
autosave, which is scheduled from `setState` and therefore repeats every 500 ms
during playback or a sustained edit. Encode cost for a 1983-byte session:
**32.5 µs → 24.8 µs**. Saved bytes byte-identical (length and hash matched on
the session, its round trip, the plan and the plan round trip).

### `439fd7a` perf: stop recomputing pure per-build values in the state and map UI

`SimulationState.cameraFrame` rebuilt the ENU basis into seven fresh `Vector3`s
on every read, and five call sites read it per frame: workspace build,
constellation label layout, guide painter, and twice from the timeline readouts.
The state is immutable, so it is now a `late final`: one basis per frame instead
of five to seven. `MapWorkspace.build` also resolved each celestial body's
bearing leg twice (once per layer) — 135 `destination()` calls per map rebuild
became 129.

### `e87fd81` perf: drop allocation churn from terrain mesh construction

`buildTerrainPatch` allocated a throwaway list literal per vertex, per quad and
per skirt edge, and the normal-accumulation loop built a closure plus four
`Vector3`s per triangle (`Vector3.cross` allocates too) — about 7 objects for
each of 132 k triangles at r256. Replaced with the same expressions in the same
order as `vector_math`'s cross, accumulated into `double`s.
**52.0/50.1 ms → 42.3/41.8 ms per r256 patch (~18 %).** Positions, normals, uvs
and indices hashed identically at resolutions 16, 64, 128 and 256.

### `44fadce` perf: reuse one Pixel when scanning decoded imagery

`image`'s `Image.getPixel(x, y)` constructs a fresh `PixelUint8` on every call —
its optional third argument exists precisely so callers can hoist that
allocation. `decodeImagery` called it per pixel, so a 1024×1024 detail tile
churned 1 048 576 short-lived objects before the blending loop even ran. Also
replaced the `List.generate(8, …).every(…)` PNG signature check with plain byte
comparisons and hoisted the repeated `1 - alpha / 255` term.
**38.0 ms → 34.0 ms per 1024² tile.** All seven decode paths (opaque fixture,
retained transparency, indexed palette opaque/transparent, JPEG, RGBA gradient
with a half-transparent band) hashed identically.

### `f64d67a` perf: write star and Milky Way meshes by index, not setRange literals

`starMesh` and `_milkyWayGeometry` fed `TypedData.setRange` a fresh list literal
per vertex. The bundled catalog has 5 044 stars, so ~91 k lists for positions
and colours plus 40 k for index literals, all built on the UI isolate while the
scene is constructed. Direct index writes remove all of them and hoist the
per-star brightness and per-row cos/sin out of the inner loop.
Output byte-identical (`162/216/144/2971911362996459` before and after).

### `d3669a2` perf: hoist cache filename RegExps out of directory scan loops

`RasterCache._index()` and `TileCache._evict()` built a fresh `RegExp` per
directory entry. Dart does not cache RegExp literals, so each entry paid full
pattern-compile cost, and a startup re-index over a 512 MiB budget walks
thousands of files. Named `static final` patterns now compile once per isolate.

---

## Measured and deliberately not changed

Recorded so the same ground is not re-covered. Each was measured; each was
rejected for a stated reason.

### Timeline as Scaffold footer (rejected in hardening iteration 10)

Moving the timeline into `Scaffold.bottomNavigationBar` cleared all five
compact/desktop timeline probes but moved the snackbar over lower inspector
controls. Native `linux_workflow_test` could no longer toggle approximate
relighting; the exact `HEAD~` shell passed. Reverted the entire candidate and
its test edits. Do not retry this footer-only solution, dismiss notifications,
or weaken the inspector test to paper over the obstruction. See the dated
entry above and retained ignored probe/prototype/native failure logs.

### Saved-plan directory existence rewrite (rejected by `067c8ed` audit)

A proposed SessionStore-style replacement of `PlanRepository.loadAll`'s
`Directory.exists` guard was not needed. A real Linux mode-000 ancestor caused
`Directory.exists` to throw `PathAccessException` (errno 13), unlike the
`File.exists` false result in `cf271d6`. The existing repository and UI already
report the failure and preserve data/state. No production edit was made; retain
the added permission/retry regressions instead of duplicating error-policy code.
Revisit only with evidence from another platform or a different failure mode.

### Idle rendering: initial rejection, resolved by `391aa7e`

The historical rejection below is now resolved: frame-aware atmosphere captures,
an uncapped activity window, local renderer-only cadence updates and the full
Linux integration suite passed. The shipped cap is 5 fps; see the measurements
above. Keep the history as the reason not to reintroduce naïve gating.

#### Original observation: ~60 fps of identical frames

`SceneView` is built with no `maxFrameRate` and default `autoTick: true`, so it
repaints every vsync frame. Measured with `Scene.renderStats.frameCount` deltas
against wall time, engine driving vsync, playback paused, zero input, static
scene: **59.9 fps at Balanced, 55.5–60.0 at High.** `build p50` 4.15 ms while
idle.

A `maxFrameRate` idle cap was implemented and validated — **60 → 5.0 fps** idle
at both tiers, interaction unaffected (37.5/41.1 fps vs 37.4/42.2 baseline),
returning to idle correctly. It was **not shipped**: `maxFrameRate` gating makes
renders-per-pump nondeterministic, measured directly as 30 pumps of 20 ms at a
15 fps cap producing **15** renders instead of 30. Nine integration tests
snapshot GPU pixels after a single `pump(100 ms)`, so they go red.

Correct sequence if this is revisited: first add a "pump until a new frame
lands" helper to those tests, then enable the cap. ~12× idle GPU reduction is
available and pixel-identical.

### Whole-workspace idle timer rebuild (rejected while implementing `391aa7e`)

Calling `setState` on `SimulationWorkspace` when the idle timeout expired caused
`configurePhotography` and `NightSkyRenderer.update` to run again. That silently
restored explicit test scene overrides (AO/shadows and hidden stars), breaking
`atmosphere_test` and `linux_workflow_test`. Both tests were rerun with the exact
pre-cap source from HEAD/HEAD~ and passed, proving the regression belonged to the
candidate. Replaced the parent rebuild with a notifier scoped to `SceneView`;
both tests and the entire integration suite then passed. Do not move the cadence
notification back into the workspace's `setState`.

### Shadow pass is re-rendered from scratch every frame

From `renderStats.latest`, per frame:

| Tier | view | ShadowPass | total |
|---|---|---|---|
| Balanced | 867×848 | 18 draws, 811 k verts | 25 draws, 1.00 M verts, CPU 1348 µs |
| High | 1084×1060 | 19 draws, **3.20 M** verts | 37 draws, 4.65 M verts, CPU 1280 µs |

That is 72 % of draw calls and 81 % of vertices at Balanced, 50 %/69 % at High,
for static terrain lit by a sun that only moves when simulation time changes.
`DirectionalLight.cacheStaticShadows` plus `Node.shadowStatic` would remove most
of it — but `DirectionalCascadeCache.slackFactor` is 1.15, so a cached cascade
spreads the same 4096² map over 2.3× the area: roughly **30 % linear shadow texel
density loss**. That is a quality trade, not a free win, so it was rejected
under a "no quality sacrifice" constraint.

### `SimulationState.copyWith` recomputes astronomy on camera-only changes

`sky` and `observerFrame` are per-instance `late final`s, so every `copyWith`
discards them even when timestamp, position and elevation are unchanged — and
`calculateSky` independently redoes the nutation/ΔT/sidereal series that
`ObserverSkyFrame` already computed. Measured **24.9 µs per frame** during a
drag (0.15 % of a 60 fps budget). Sharing them across copies requires
duplicating the effective-elevation resolution (`fixedElevation` /
`groundElevation` / `height`) inside `copyWith`; the regression risk on correct
numerical code outweighs the gain. Revisit behind a profile build.

### Other measured non-issues

- `RasterCache._evict()` full sort per write once over budget: **0.7 ms/write**
  at 1200 entries.
- `SessionStore.save` synchronous `writeAsStringSync(flush: true)`: **97 µs**
  total. Intentional — a test requires backgrounding to flush without waiting
  for autosave.
- `calculateNightCalendar`: 3318 samples/month, each computing the same nutation
  series twice. **19.3 ms per month**, in `compute()` off the UI isolate.
- `RasterCache._index()`: ~144 ms cold for 1200 entries (~140 MiB). Once per
  launch, and async I/O only yields — it does not block frames.
- `loadImagery`: one `setState` per tile, ~30 workspace-subtree rebuilds per
  site load. Each lands in its own frame, so it is CPU waste, not jank;
  batching would change progressive-credit UI semantics.
- `terrainCoverage._intersects` allocation-heavy SAT: once per terrain load
  behind a 400 ms debounce, not per frame.
- `_RainPainter` 266 `drawLine` calls and a fresh `Random(24)` seed per frame:
  only while raining; consolidating to `drawRawPoints` would change drop
  placement.
- `NightCalendar` `rating()` linear scan (≤42 entries), `label.split(' ')` per
  cell, `localClock` per item: all sub-100 µs per build.
