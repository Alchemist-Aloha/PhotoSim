# Landscape Photography Simulator — MVP Implementation Plan

**Version:** 1.0  
**Target:** Functional cross-platform Flutter MVP  
**Platforms:** Android, Web, Linux, macOS, Windows  
**Duration estimate:** 6–8 weeks  
**Development approach:** Vertical slices, automated tests, working application at every milestone

---

## 1. MVP Objective

Create a functional landscape photography simulator in Flutter that allows users to:

1. Select a geographic location on a 2D map.
2. Place a virtual camera at that location.
3. Adjust camera direction and viewing angle.
4. Select a camera sensor, lens, and focal length.
5. Switch to a 3D view displaying real terrain with satellite imagery.
6. Change the simulation date and time.
7. See the Sun, Moon, stars, and Milky Way in their calculated positions.
8. See terrain illumination and shadows respond to the Sun and Moon.
9. Save the selected camera location, lens, direction, and simulation time.

The MVP must run on all five target platforms.

Focus on **functional geographic and astronomical accuracy**, rather than photorealistic rendering.

---

## 2. MVP Scope

### 2.1 Required features

**2D Map View**

- Interactive map with geographic coordinates.
- Camera placement through clicking or tapping.
- Draggable camera marker.
- Camera direction handle.
- Horizontal field-of-view wedge.
- Location and orientation readouts.
- Map/3D workspace switching.

**Virtual camera**

- Full-frame and APS-C sensor presets.
- Generic zoom lens presets.
- Custom focal length.
- Adjustable yaw, pitch, and camera height.
- Correct perspective projection.
- Synchronized controls across both workspaces.

**3D terrain**

- Actual elevation data from anonymous Mapterhorn tiles, with Mapzen fallback.
- Real terrain geometry reconstructed locally.
- Satellite/aerial imagery mapped onto terrain.
- Camera-relative geographic coordinates.
- Progressive terrain loading.
- Basic terrain LOD.
- Terrain shading and directional shadows.

**Astronomy**

- Locally calculated Sun position.
- Locally calculated Moon position and phase.
- Local date/time selection.
- Basic star catalog and star-field positioning.
- Galactic center and simplified Milky Way representation.
- Coordinate transformations between celestial and geographic frames.

**Lighting**

- Dynamic directional sunlight.
- Terrain shadows based on solar direction.
- Basic daytime and nighttime sky transition.
- Approximate moonlight intensity.
- Basic atmospheric haze.

**Data management**

- HTTP terrain and imagery fetching.
- Local caching where source licenses allow it.
- Graceful handling of unavailable tiles.
- Save and restore the current photography plan.

### 2.2 Explicitly excluded from MVP

Do not implement the following until after the first functional release:

- Weather API and cloud simulation.
- Full volumetric clouds.
- Detailed atmospheric scattering from first principles.
- High-resolution USGS LiDAR integration.
- Multiple elevation providers.
- Building and vegetation reconstruction.
- Real camera-model database.
- Detailed lens distortion or depth of field.
- Star trails and long-exposure simulation.
- Advanced HDR color grading.
- Automatic astronomical alignment searches.
- Social features, cloud sync, or accounts.
- Advanced image export pipeline.
- Downloading entire offline regions.

Avoid adding unrelated features before the two-workspace photography workflow is functional.

---

## 3. Technology Decisions

| Component | Selected technology |
|---|---|
| Application framework | Flutter |
| 2D map | `flutter_map` |
| 3D rendering | `flutter_scene` |
| GPU acceleration | Flutter GPU / Impeller |
| Web rendering | Flutter Scene WebGL2 backend |
| Terrain rendering reference | Dashmap |
| Elevation data | Mapterhorn (global + regional open DEMs), Mapzen fallback |
| US imagery for prototype | USGS NAIP |
| Free global imagery fallback | EOX Sentinel-2 cloudless 2016 (CC BY 4.0) |
| Free regional aerial imagery | IGN BD ORTHO; swisstopo SWISSIMAGE |
| Optional global satellite imagery | MapTiler with configured key |
| Astronomy calculations | `astronomia` |
| Star data | Small local star catalog |
| Milky Way | Galactic coordinates and simplified visual overlay |
| State management | Riverpod or equivalent |
| HTTP client | Dart HTTP client |
| Native cache | Local files with lightweight metadata |
| Web cache | Browser-compatible storage |
| Saved plans | Versioned JSON |

Pin dependency versions at project initialization.

Do not implement custom GPU shaders unless an existing Flutter Scene material or shader cannot satisfy the MVP requirement.

### 3.1 Data availability policy

The MVP must not require a paid imagery subscription.

Use a small US geographic region with USGS NAIP imagery as the reproducible integration-test location.

Use the freely reusable EOX Sentinel-2 2016 mosaic as a global fallback, with
higher-resolution open regional aerial sources (IGN France, swisstopo Switzerland)
where available. Keep attribution visible and distinguish source resolution from
the downsampled terrain textures. Newer non-commercial EOX mosaics are not the default.

Support MapTiler as an optional source for global high-quality imagery within its permitted free-use conditions.

If high-resolution imagery is unavailable, render actual terrain with a clearly labeled fallback surface material. Never substitute fabricated imagery.

---

# 4. Phase 0 — Rendering Feasibility

**Duration:** 3–5 days

### Goal

Verify that Flutter Scene can render a dynamically controlled 3D terrain scene on the required platforms.

### Tasks

1. Create Flutter project with Android, Web, Linux, macOS, and Windows targets.
2. Add Flutter Scene.
3. Initialize a GPU-rendered 3D viewport.
4. Create a simple procedural heightfield mesh.
5. Add a perspective camera.
6. Implement camera yaw, pitch, and zoom.
7. Apply a terrain texture.
8. Add a directional light.
9. Enable basic shadow casting if supported.
10. Confirm rendering and interaction on each target platform.

### Technical investigation

Inspect Dashmap and identify reusable components:

- Terrain mesh generation.
- GPU resource management.
- Camera controller.
- Coordinate conversion.
- Terrain tile loader.
- LOD logic.
- Terrain textures.
- Sky lighting and shadows.

Reuse or adapt these components where appropriate.

Do not copy Dashmap's satellite imagery source assumptions without reviewing usage rights.

### Acceptance criteria

- A textured terrain mesh renders.
- Camera rotation and zoom operate interactively.
- Light direction can change without rebuilding the mesh.
- GPU rendering works on all target platforms.
- No critical rendering errors or unbounded resource leaks.

**Stop condition:** If the selected graphics backend cannot render the prototype on a required platform, resolve or replace that backend before proceeding.

---

# 5. Phase 1 — 2D Map and Virtual Camera

**Duration:** 4–6 days

### Goal

Build the primary camera-planning interface and the shared camera state.

### Tasks

1. Integrate `flutter_map`.
2. Display an interactive geographic map.
3. Implement camera placement through map interaction.
4. Add a movable camera marker.
5. Add a direction handle.
6. Render a field-of-view wedge.
7. Implement camera body selection.
8. Implement generic lens presets.
9. Add a focal-length slider.
10. Add a Map/3D workspace selector.
11. Connect both workspaces to one camera state.

### Camera state

Create immutable models for:

- Geographic position.
- Camera height.
- Azimuth.
- Pitch.
- Roll.
- Sensor dimensions.
- Focal length.
- Simulation timestamp.

### Field-of-view calculation

Use the physical sensor width and focal length.

Horizontal field of view:

`2 × atan(sensorWidth / (2 × focalLength))`

The same optical model must generate both the 2D field-of-view wedge and the 3D perspective matrix.

### UI requirements

**Desktop**

- Top workspace selector.
- Large central map.
- Collapsible camera/lens inspector.
- Compact timeline placeholder.

**Android**

- Fullscreen map.
- Camera marker and field-of-view cone.
- Bottom-sheet camera/lens controls.
- Map/3D switcher.

### Acceptance criteria

- Clicking the map changes the camera location.
- Dragging the direction handle rotates the camera.
- Changing focal length updates the wedge immediately.
- Full-frame and APS-C sensors produce different field-of-view angles.
- Switching to 3D preserves all camera parameters.
- Rotating the 3D camera updates the map marker direction.

**Deliverable:** Working geographic camera planner with a procedural 3D preview.

---

# 6. Phase 2 — Real Terrain and Satellite Imagery

**Duration:** 7–10 days

### Goal

Replace procedural terrain with actual geographic terrain and imagery.

### Step 1 — Terrain acquisition

Prefer account-free Mapterhorn Terrarium WebP tiles (512 px), combining a
Copernicus GLO-30 baseline with finer open regional sources. Crop zoom-12 parents
where high-zoom regional tiles are absent. Keep service attribution/licenses and
provider-separated caches; do not equate source grid spacing with mesh detail.

Retain Mapzen elevation tile requests as an independent fallback.

Fallback endpoint:

`https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`

Decode Terrarium height values:

`h = 256R + G + B/256 − 32768`

Required handling:

- XYZ tile addressing.
- Geographic bounds.
- Decoding.
- Missing tiles.
- Request failures.
- Download cancellation.
- Caching.

### Step 2 — Geographic positioning

Implement:

- WGS84 geographic coordinates.
- Web Mercator tile transforms.
- Local ENU coordinates.
- Camera-relative terrain geometry.
- Elevation interpolation.

Ensure terrain geometry uses real-world horizontal and vertical scales.

### Step 3 — Terrain meshes

Generate terrain meshes from downloaded heightmaps.

Initial implementation:

- Regular tile-grid geometry.
- Calculated vertex normals.
- Texture UV coordinates.
- Consistent edges between neighboring tiles.
- Simple view-dependent LOD.

Use Dashmap's existing terrain implementation as a reference.

### Step 4 — Satellite imagery

Implement an imagery provider interface.

Support USGS NAIP in a US demonstration area, IGN BD ORTHO in France and
SWISSIMAGE in Switzerland, falling back to the CC BY EOX Sentinel-2 2016 mosaic.
Composite partial coverage without fabricating imagery; keep source caches separate.

Support optional MapTiler satellite tiles through a configured key.

Associate imagery with matching geographic terrain coordinates.

Implement progressive texture loading.

### Step 5 — Camera height

Use terrain elevation at the camera position.

Default the virtual camera to approximately 1.7 m above ground, with a user-adjustable height.

The 3D camera must move correctly when the location changes.

### Step 6 — Background workers and cache

Decode raster data and construct meshes away from the UI-critical frame path.

Implement bounded concurrency and resource eviction.

Provide a minimal native file cache and browser-compatible caching interface.

### Acceptance criteria

- The application renders real mountains and valleys.
- The camera position matches the selected map coordinates.
- The terrain has correct scale and orientation.
- Surface imagery aligns with terrain.
- Moving to another location loads different terrain.
- Reopening the same location reuses permitted cached resources.
- The 3D camera remains responsive during terrain loading.

**Deliverable:** Interactive virtual camera over actual geographic terrain.

---

# 7. Phase 3 — Sun, Moon, and Lighting

**Duration:** 5–7 days

### Goal

Turn the geographic viewer into an astronomical photography simulator.

### Step 1 — Local astronomy service

Integrate `astronomia`.

Create an application-level astronomy service accepting:

- UTC timestamp.
- Latitude.
- Longitude.
- Observer elevation.

Return:

- Solar azimuth and altitude.
- Lunar azimuth and altitude.
- Moon phase and illumination fraction.
- Sun and Moon direction vectors.

Use topocentric lunar position calculations.

### Step 2 — Time controls

Implement:

- Date picker.
- Time picker.
- Continuous time slider.
- Time step forward/backward.
- Optional automatic playback.

Store time internally in UTC.

Display local time with the selected location's timezone.

### Step 3 — Celestial direction vectors

Convert calculated altitude and azimuth into ENU directions.

Project the Sun and Moon into the same 3D camera coordinate system as the terrain.

### Step 4 — Sunlight

Use the solar direction as the primary scene light.

Implement:

- Directional illumination.
- Terrain surface shading.
- Terrain shadows.
- Approximate solar color variation.
- Day-to-night sky transition.

Recalculate the light direction when the simulation time changes.

### Step 5 — Moon rendering

Render the Moon as a disk at the correct angular location.

Represent the illuminated portion using the calculated lunar phase and orientation.

Moonlight should use a simplified brightness model based on lunar phase and altitude.

### Step 6 — Terrain occlusion

Ensure the Sun and Moon can disappear behind rendered mountains using depth testing.

The separate horizon-profile service may remain simplified in the MVP.

### Acceptance criteria

- Solar position changes correctly with date and time.
- Moon position changes correctly.
- Terrain shadow direction follows solar azimuth.
- The scene changes between daytime, twilight, and nighttime.
- The Moon's illuminated appearance changes with lunar phase.
- Celestial objects are hidden when blocked by rendered terrain.
- Changing time does not reload terrain or imagery.

**Deliverable:** A time-aware landscape simulator with accurate Sun/Moon geometry and approximate physical lighting.

---

# 8. Phase 4 — Stars and Milky Way

**Duration:** 4–6 days

### Goal

Enable basic astrophotography composition planning.

### Step 1 — Star catalog

Bundle a small naked-eye star catalog containing:

- Right ascension.
- Declination.
- Visual magnitude.
- Optional color information.

Transform catalog positions into the observer's local sky.

Include epoch handling and relevant coordinate corrections.

### Step 2 — Star rendering

Use GPU-efficient point sprites or equivalent batched rendering.

Provide:

- Approximate magnitude-dependent brightness.
- Optional star labels.
- Time-dependent sky rotation.
- Terrain occlusion.

### Step 3 — Milky Way

Implement a simplified Galactic-plane and Milky Way visualization.

Required outputs:

- Galactic-center position.
- Milky Way orientation.
- Approximate Galactic band.
- Galactic-center marker in 2D and 3D.

Use an open licensed Milky Way outline or brightness representation.

Do not implement photorealistic astrophotography rendering in the MVP.

### Step 4 — Night sky brightness

Adjust star visibility based on approximate solar and lunar conditions.

Use a basic sky brightness model.

### Acceptance criteria

- Stars move correctly as time advances.
- The star field is aligned with geographic directions.
- The Milky Way orientation changes with location and time.
- The Galactic center can be selected as a target.
- The 3D camera shows whether an astronomical target is inside its field of view.
- Terrain can occlude celestial objects.

**Deliverable:** Functional nighttime astronomy planning.

---

# 9. Phase 5 — Integration, Optimization, and Release

**Duration:** 7–10 days

### Goal

Produce a usable and testable cross-platform MVP.

### Tasks

**Application integration**

- Finalize Map/3D switching.
- Synchronize camera changes in both directions.
- Connect the shared timeline.
- Improve loading indicators and error messages.
- Finalize responsive layouts.

**Saved plans**

Implement local saving of:

- Camera coordinates.
- Camera orientation.
- Camera sensor.
- Lens and focal length.
- Simulation time.
- Selected astronomical target.

Use versioned JSON for portability.

**Performance**

- Avoid unnecessary mesh rebuilding.
- Limit concurrent terrain downloads.
- Profile GPU memory use.
- Apply basic frustum culling and LOD.
- Prevent texture and mesh resource leaks.
- Use adaptive quality settings.

**Testing**

- Unit tests for geographic conversions.
- Tests for Terrarium elevation decoding.
- Optical field-of-view tests.
- Astronomical position tests.
- State synchronization tests.
- Terrain tile lifecycle tests.
- Integration tests of the complete user workflow.

**Cross-platform validation**

- Android native build.
- Linux native build.
- Windows native build.
- macOS native build.
- Web build with WebGL2.

Platform builds must be tested on their actual operating systems or suitable CI runners.

### Performance targets

| Metric | MVP target |
|---|---|
| Desktop interaction | 30–60 FPS |
| Android interaction | 30 FPS |
| Browser interaction | 30 FPS |
| UI response to focal-length changes | Immediate, target under 100 ms |
| Astronomy recalculation | Fast enough for smooth timeline interaction |
| Terrain loading | Progressive and nonblocking |
| Repeat visits | Use locally cached data when permitted |

These targets should be tested on defined reference devices.

### Acceptance criteria

- The complete photographic planning workflow functions.
- Switching between workspaces preserves state.
- Terrain and imagery are loaded correctly.
- Astronomy and lighting updates work.
- Saved plans can be reopened.
- The UI remains responsive during loading.
- All five target platforms have working builds.
- Major errors are handled gracefully.

**Deliverable:** First public MVP release.

---

# 10. Recommended Internal Architecture

Use a modular Flutter architecture with distinct responsibilities.

```text
lib/
├── app/
│   ├── app.dart
│   └── state/
├── ui/
│   ├── workspace_shell/
│   ├── map_view/
│   ├── simulation_view/
│   ├── camera_controls/
│   ├── lens_controls/
│   └── time_controls/
├── core/
│   ├── geo/
│   ├── camera/
│   ├── astronomy/
│   ├── lighting/
│   └── simulation/
├── data/
│   ├── terrain/
│   ├── imagery/
│   ├── star_catalog/
│   ├── cache/
│   └── saved_plans/
├── render/
│   ├── backend/
│   ├── terrain/
│   ├── sky/
│   ├── celestial/
│   └── shaders/
└── models/
```

### Architectural rules

1. Maintain a single authoritative `SimulationState`.
2. Both workspaces subscribe to the same state.
3. Keep astronomy and geographic calculations in pure Dart.
4. Keep the GPU backend separate from the UI.
5. Do not perform network calls in the render loop.
6. Do not recreate terrain meshes when only time changes.
7. Keep data providers interchangeable.
8. Use dependency injection so calculations can be unit-tested.
9. Dispose GPU resources explicitly.
10. Keep platform-specific code behind small adapters.

---

# 11. Development Task Management

Each phase should be broken into independent issues, suitable for sequential or parallel coding-agent work.

Suggested initial tasks:

**Foundation**

- MVP-001: Flutter project and platform configuration.
- MVP-002: Flutter Scene rendering spike.
- MVP-003: 3D camera controller.
- MVP-004: Basic GPU lighting.
- MVP-005: Shared simulation state.

**Map and optics**

- MVP-006: 2D map implementation.
- MVP-007: Camera marker and direction handle.
- MVP-008: Field-of-view wedge.
- MVP-009: Camera sensor and focal-length model.
- MVP-010: Dual-workspace synchronization.

**Terrain**

- MVP-011: Terrain tile HTTP client.
- MVP-012: Terrarium raster decoder.
- MVP-013: Geographic coordinate service.
- MVP-014: Terrain mesh generation.
- MVP-015: Imagery texture integration.
- MVP-016: Terrain streaming and caching.

**Astronomy**

- MVP-017: Sun/Moon position service.
- MVP-018: Timeline controls.
- MVP-019: Dynamic solar lighting.
- MVP-020: Moon disk and basic moonlight.
- MVP-021: Star catalog and sky rendering.
- MVP-022: Milky Way planning representation.

**Release**

- MVP-023: Saved photography plans.
- MVP-024: Responsive UI refinement.
- MVP-025: Cross-platform validation.
- MVP-026: Performance and regression testing.

Each issue should include its own acceptance test and should not be considered complete solely because code compiles.

---

# 12. Agent-Based Development Strategy

When using AI coding agents:

- Give each agent a small, testable task.
- Require inspection of existing implementations before adding new components.
- Prefer reusing Dashmap and Flutter Scene features.
- Require runnable tests.
- Require screenshots or render validation for UI and GPU changes.
- Never accept placeholder code presented as a completed feature.
- Keep every merged milestone runnable.
- Use separate Git worktrees for parallel tasks with limited overlap.
- Run integration tests after every merge.

Suitable parallel workstreams after Phase 0:

**Agent A — Geographic data**

Mapzen API, raster decoding, coordinate transforms, and mesh preparation.

**Agent B — Astronomy**

Sun/Moon calculations, coordinate transforms, star catalog, and unit tests.

**Agent C — UI and camera**

Map View, camera state, sensor/lens controls, and timeline.

**Integration agent**

3D scene, rendering backend, state wiring, tests, and build validation.

Avoid having multiple agents simultaneously modify the rendering core or shared state interfaces without an agreed contract.

---

# 13. MVP Demonstration Scenario

The release should include one deterministic demonstration scene.

Suggested location: Shenandoah National Park, Virginia, where terrain is well suited to demonstrating mountain silhouettes, sunlight, and celestial alignments.

### Demo workflow

1. Open Map View.
2. Select a location in the park.
3. Place the virtual camera.
4. Set camera height to 1.7 m.
5. Select a full-frame sensor.
6. Select a 24–70mm zoom lens.
7. Set focal length to 35mm.
8. Rotate camera toward a mountain ridge.
9. Switch to Simulation View.
10. Verify that the actual terrain is rendered.
11. Move the time slider from noon through sunset.
12. Observe Sun position, sky transition, and terrain shadows.
13. Advance to nighttime.
14. Observe stars, Moon, and Milky Way indicators.
15. Change focal length and confirm the field of view changes.
16. Save the photography plan.
17. Close and reopen the application.
18. Reopen the saved scene.

The same scenario should work on Android, desktop, and web.

---

# 14. MVP Completion Criteria

The MVP is finished only when:

- Both Map and Simulation workspaces work.
- The virtual camera can be positioned on the map.
- Camera orientation and lens settings remain synchronized.
- Real terrain is reconstructed from downloaded elevation tiles.
- A real imagery source can texture the terrain.
- Astronomical positions are calculated locally.
- Sunlight and shadow directions change with time.
- The Moon is positioned and illuminated approximately correctly.
- Stars and the Milky Way are available for composition planning.
- The application remains responsive while geographic data loads.
- Camera settings and simulation time can be saved.
- The app operates on Android, Web, Linux, macOS, and Windows.
- Automated tests validate the mathematical core.
- A documented, reproducible end-to-end demonstration passes.

**The MVP must deliver one complete photographic planning workflow before any advanced weather, optics, or photorealistic rendering features are introduced.**

---

# 15. Post-MVP Priorities

After releasing the MVP, prioritize improvements in this order:

1. Higher-resolution terrain and imagery providers.
2. More accurate distant-terrain horizon calculation.
3. Improved atmosphere and night-sky brightness.
4. Weather forecast integration.
5. Photorealistic Milky Way rendering.
6. Extended camera and lens database.
7. Image export and exposure simulation.
8. Automated astronomical alignment searches.

Preserve the existing camera state, geographic data interfaces, and astronomy service while introducing these improvements.

---

## Final Directive

Build the smallest complete cross-platform Flutter application that can:

**Place a camera on a real map → select a lens → render real terrain in 3D → change time → update celestial positions and lighting → save the composition.**

This complete workflow is the primary measure of MVP success.

All other features are secondary to making this workflow reliable, interactive, geographically consistent, and usable across the five required platforms.