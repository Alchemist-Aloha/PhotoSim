# PhotoSim 0.1 — Linux MVP complete

## Release scope

The MVP is now **Linux desktop only**, by explicit product decision. Android,
Web, Windows and macOS are future work, not unfinished Linux acceptance gates.
This scope supersedes the original cross-platform MVP gates in spec.md and
roadmap.md. It does not claim that every feature of the long-term specification
is implemented.

The completed baseline is: synchronized map/3D planning, real streamed/cached
terrain and imagery, offline Sun/Moon/stars/Milky Way, UTC controls and playback,
named save/reopen, PNG export, render-quality selection, manual weather and
aperture-linked depth of field.

## Photography controls

In the 3D toolbar:

| Quality | Render scale | Automatic AA tier | Shadow map | DOF gather |
|---|---:|---|---:|---:|
| Performance | 70% | Low (off) | 1024 | 16 taps |
| Balanced (default) | 100% | Medium (FXAA) | 2048 | 32 taps |
| High | 100% | High (MSAA where supported) | 4096 | 48 taps |

These are explicit backend budgets, not promises of FPS or higher source detail.
Backend capability fallbacks still apply. Shadows are skipped for unlit natural
imagery and the overcast weather presets; clear-sky approximate relighting uses
them. Quality changes preserve resident geographic meshes/textures and do not
fetch new data. Viewport/screen-error terrain and imagery refinement remains future work.

**Weather**: Clear, Cloudy, Fog, Rain. These are deterministic, illustrative manual
presets, not forecasts or observations. Cloudy uses a uniform overcast sky rather
than volumetric cloud shapes. Fog and rain reduce visibility; non-clear modes
attenuate light and obscure the physical night sky. Rain includes animated,
screen-space streaks clipped to the photograph. No weather service, account,
network request, wind simulation, wet-surface reconstruction or precipitation
physics is involved.

In the camera inspector, enable **Depth of field**, set aperture **f/1.4–f/22**,
and select focus distance on a logarithmic **1 m–1,000 km** slider. The far endpoint
approximates infinity. The backend uses depth-buffer thin-lens bokeh, the actual
8–600 mm focal length and selected sensor height. Smaller f-numbers increase blur
away from the focus plane; this is not uniform whole-image blur. DOF quality
follows the selected quality preset. Aperture controls blur only, not calibrated
exposure; diffraction, ISO, shutter-speed exposure and automatic focus are future work.

Natural imagery is display-referred in clear weather with DOF off. Weather/DOF
switch it into the scene-linear effects pipeline; colors can change with tone
mapping and the original photographic shadows remain. Approximate relighting
does not recover physical reflectance from imagery. Rain is a screen overlay
after DOF, not a depth-aware volume.

All five new settings (quality, weather, DOF enabled, aperture and focus distance),
plus existing range/appearance preferences, persist in version-2 plans. Old plans use
Balanced / Clear / DOF off / f/8 / 1 km focus defaults.

## PNG export

Wait for terrain/imagery loading to finish, then press **Export PNG** in 3D.
Playback pauses. Enter an absolute path ending in .png (initially a unique name
in Downloads, falling back to Documents), then **Save PNG**. The destination
directory must exist. Existing files are never overwritten; choose another name.
Cancel writes nothing. Errors are reported without replacing existing images.

The export captures the current photographic viewport, preserving sensor aspect
ratio, current quality, weather and DOF. It excludes toolbars, crosshair and
application panels. Enabled in-scene constellation/target guides remain part of
the preview. Source credits and a UTC/optics/weather caption are burned into the
image. Geographic and celestial sources remain subject to their own terms.

Resolution is the current viewport at display pixel ratio, capped to 4096 pixels
on either axis and 12 megapixels. This is not independent high-resolution/offscreen
export; enlarging the application viewport increases output size up to those limits.
PNG staging and exclusive destination reservation protect existing files, but do
not provide a power-loss durability guarantee. An interrupted reservation can
leave an empty destination that must be removed or renamed before retrying.

## Verification

- Clean Flutter analysis; 113 unit/widget tests.
- Linux workflow: map/camera/time/sky/lighting, save, recreate, reopen and cached geography.
- Linux imagery workflow: live Switzerland, France, Australia and Beijing sources,
  terrain range/FOV replanning and resident-resource invariants.
- Linux photography workflow: all four weather modes and three quality presets,
  physical DOF configuration, aperture-dependent GPU pixels, unchanged geographic
  geometry/download counts and actual PNG export through the UI.
- Linux release bundle builds successfully.

Commands:

```sh
flutter analyze
flutter test
flutter test integration_test/linux_workflow_test.dart -d linux
flutter test integration_test/linux_imagery_test.dart -d linux
flutter test integration_test/linux_photography_test.dart -d linux
flutter build linux --release
```

Inspected artifacts include build/validation/linux-export.png and weather/DOF
captures. Native tests require graphical Linux; the first visit needs public
terrain/imagery services. Distribute the entire Linux release bundle.

## Future work, not Linux MVP blockers

Other platforms/browser storage/mobile layouts; measured FPS and long-run GPU
memory profiling; screen-error mesh/texture LOD; finer source imagery; corrected
height datums and independent terrain horizons; rise/set events and planets;
calibrated exposure, improved atmospheric/night-sky photometry and live forecasts;
plan management/import-export; portrait/roll and independent-resolution image export.
Public data-service usage/redistribution terms must be reviewed before scaling.
