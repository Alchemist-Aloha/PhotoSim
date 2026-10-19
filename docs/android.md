# Android phones and tablets

## Build and install

Requires Flutter 3.47.1+ (developed with 3.47.6), JDK 17+, the Android SDK,
and Android 10 / API 29 or newer. Flutter GPU and Impeller are enabled in the
main manifest, including release builds. Internet permission is declared there
for map/terrain/imagery and optional calendar conditions; no location, broad storage or media-read permission is used.

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
flutter build apk --release
adb -s <serial> install -r build/app/outputs/flutter-apk/app-release.apk
```

The generated runner currently signs release builds with the development key,
so the APK is installable for testing, **not configured for Play Store publication**.
Use your own release signing configuration before distributing updates.
A compatible Impeller graphics driver is required for 3D; an initialization
failure leaves Map available. The API 29 floor is not a guarantee that every
Android 10 GPU can render this scene.

## Material 3 adaptation

One shared Flutter UI and simulation state, not a separate mobile codebase:

- Below 600 logical pixels: bottom navigation for Map, 3D Preview and Calendar,
  a compact local-time timeline with expandable astronomy/playback details,
  and a modal camera-controls drawer.
- At 600+ logical pixels: navigation rail; controls remain in a drawer until
  the window reaches 1000 logical pixels, then dock beside the viewport.
- Short landscape windows use the compact timeline regardless of width, and
  a Material preview-tools menu keeps terrain, constellation and export actions
  reachable without clipping the photograph.
- Layout follows current window size, including rotation and split-screen,
  not device-model detection. System bars, cutouts and keyboard insets remain respected.
- Material 3 components and seeded color roles follow the Android system
  light/dark setting. Larger text can reflow the wide timeline.
- Drag with one finger to aim in 3D; pinch with two fingers changes the physical
  focal length (8–600 mm). It does not move the camera. Place/drag the camera on
  Map to move. Hardware-keyboard WASD still works in the focused 3D preview.
- System Back dismisses dialogs/drawers and exits clean fullscreen preview
  before exiting the application.
- Calendar has a top-bar month/week toggle, scrollable phone details and a
  side-by-side tablet layout; it hides camera controls and the simulation timeline.
  Its keyless sources and approximation limits are in [night planning](night-calendar.md).
- Android starts with the Performance render preset. Balanced and High remain
  available in the Rendering inspector.

## Local files and export

Plans and bounded raster caches use app-private native directories. The shared
cache limit and corruption recovery are unchanged. Plans are unencrypted and
survive normal app restarts, but not uninstallation. Automatic Android backup
is disabled. Save before quitting; unsaved work is not autosaved.

Export PNG retains the framed photo, attribution and existing resolution limits.
On Android it inserts a pending image into MediaStore, writes on a background
task queue, and publishes only after the write succeeds. Failed writes remove
their pending entry. Images appear in **Pictures/PhotoSim** without requesting
broad storage access. Linux retains its existing destination-path dialog.

## Validation

```sh
flutter test
flutter analyze --fatal-infos --fatal-warnings
flutter test integration_test/calendar_test.dart -d <phone-id>
flutter test integration_test/calendar_test.dart -d <tablet-id>
flutter test integration_test/android_workflow_test.dart -d <phone-id>
flutter test integration_test/android_workflow_test.dart -d <tablet-id>
```

The Android workflow has passed on API 36 Google APIs x86_64 emulators using
Pixel 7 and Pixel Tablet profiles with host GPU acceleration. It loads real
Yosemite terrain and imagery, checks rendered photo pixel variation (excluding
UI overlays), exports through the actual MediaStore channel, validates a bad
export filename, and saves/reopens a local composition. Host `adb shell content
query` confirmed exported files under Pictures/PhotoSim on both devices.

Widget tests exercise 360/390 dp portrait phones, 844 dp short landscape,
800 dp portrait tablets and 1280 dp expanded tablets at 1.3× text scale.
They check navigation adaptation, controls, shared state, light/dark theme,
Back behavior and resizing. Synthesized touch tests cover aim, pinch zoom,
focal-length bounds and cancellation recovery.

The calendar workflow additionally passed on Linux and both API 36 profiles,
including live keyless forecast/atlas requests, month/week navigation, date picking
and unchanged shared camera/time. Calendar widget tests also cover a 360 dp phone
at 2× text scale. The tablet again reported an uninstall warning, and both emulators
disconnected after graphics-context teardown errors; release APK compilation passed,
but a subsequent install attempt could not reach those disconnected emulators.

Native emulator screenshots are under `build/validation/android-*.png`.
Release APKs were also installed and rendered on both profiles, with light/dark,
1.3× text and rotated-window inspection. A short-landscape tools clipping issue
was replaced with the tested Material preview-tools menu.

A later software-rendered phone emulator disconnected during a verification
rerun before completion. The final host-GPU tablet workflow passed, with an adb
uninstall warning during teardown. Earlier host-GPU phone/tablet workflows passed.
Host-emulator logs also recorded graphics-context teardown errors during live APK
replacement; do not treat these runs as driver-stability or physical-device proof.
These are emulator evidence, not physical-device testing or FPS/memory benchmarks.
API 29 runtime, older/adverse GPU drivers, thermal behavior, battery consumption,
long-running GPU stability and physical multitouch remain unverified.
