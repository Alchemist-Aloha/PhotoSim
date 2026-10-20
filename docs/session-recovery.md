# Automatic session recovery

PhotoSim resumes the previous session on launch, including unsaved composition
changes. This is separate from **Save plan**: automatic recovery replaces one
checkpoint and never creates or overwrites named snapshots.

## What is restored

- Camera location, bearing, pitch, roll, height override, lens and sensor.
- Simulation UTC date/time, target, exposure, overlays, orientation, depth of
  field, weather controls, terrain ranges and rendering preferences: the same
  validated composition fields as [saved plans](saved-plans.md).
- Last Map / 3D / Calendar workspace, map center and zoom, inspector visibility
  and expanded sections, timeline expansion, calendar month/week mode and the
  selected calendar date, playback speed, dismissed map-guidance state and
  fullscreen-preview preference. Older checkpoints default to showing guidance.
- Plan name and its saved baseline, so recovered edits still show **Unsaved
  changes** and retain Save/Discard/Cancel protection when opening another plan.

Playback always resumes **paused**. Terrain-derived ground height and downloaded
resources are reloaded normally. Open dialogs, gestures, temporary loading/error
states, scroll offsets and OS window size/position are not session preferences
and are not restored. The cache budget continues to use its existing separate
persistent settings file. Theme continues to follow the existing platform policy.
Opening a named plan deliberately recenters Map on that plan and resets the
calendar selection; it does not erase other preferences.

## Saving and failure handling

The checkpoint is `photosim/session-v1.json` inside the platform application
support directory. Startup restores it before constructing the workspace, so a
late disk read cannot replace newly entered changes. First launch without a
checkpoint uses the current system time and existing platform defaults.

Changes are coalesced at most every 500 ms. Backgrounding, widget disposal and
normal framework exit requests flush immediately. The small JSON checkpoint is
validated, written to a flushed sibling temporary file, then atomically renamed.
Unchanged checkpoints do not cause repeated writes. A failed save keeps the old
file and exposes a **Session recovery warning** with Retry. A failed normal exit
save offers Cancel or **Exit without saving** rather than silently losing edits.

Unreadable/oversized checkpoints are moved into a uniquely named
`unreadable-session-*` folder beside the checkpoint before starting with defaults.
The startup warning identifies that backup. If storage cannot be accessed or the
bad checkpoint cannot be preserved, recovery/autosave is disabled for that run
with a warning; fix permissions and restart. Session JSON is size-limited to
64 KiB and validates composition, enums, coordinate ranges and preference types.

This is single-instance local recovery, not cloud synchronization, versioned
history or a multi-process database. It cannot guarantee the latest edit after
power loss or a forced kill during the 500 ms interval or a disk operation.
Manual snapshots remain useful for independent, durable compositions.

The checkpoint contains precise coordinates and times in **unencrypted local
storage**. OS directory permissions apply. Android uses app-private storage,
automatic backup remains disabled, and uninstalling deletes the session.

## Checks

`test/app_session_test.dart` covers full round-trips, invalid input, atomic-write
failure and preserved corrupt files. `test/session_restoration_test.dart` covers
quick disposal, changed location/lens/time, map framing, calendar state, inspector
sections, dirty-plan recovery, paused playback, background flush, visible save
failure and explicit exit-without-saving consent.

Linux production-entry-point testing uses an isolated `XDG_DATA_HOME`, closes
with a real WM_DELETE_WINDOW request before the autosave interval, then launches
a fresh process and verifies the recovered composition/preferences. Evidence:
`build/validation/session-cold-start.log` and `session-cold-native.log`.

Validation passed 215 tests and static analysis; Linux debug and Android release
builds passed. The release APK also passed a Pixel 7 / API 36 emulator check:
change camera location, switch to Calendar/week, exit via Back, force-stop and
cold-launch; composition and workspace/mode were retained. Evidence is in
`build/validation/session-android-check.log`. That emulator later disconnected
after teardown, so a later screenshot rerun was unavailable; this is not
physical-device or long-running driver-stability evidence.
