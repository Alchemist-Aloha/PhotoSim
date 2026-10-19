# PhotoSim

## Unified Software Requirements and Technical Architecture

**Specification version:** 1.0 (long-term specification)

**Current release:** Linux MVP complete — see [authoritative release scope](linux-mvp.md).

**Future platforms:** Android, Web, macOS, Windows

**Application framework:** Flutter / Dart  
**Rendering:** Flutter GPU / Impeller with a cross-platform 3D rendering abstraction  
**Primary rendering candidate:** Flutter Scene  
**Project model:** Open-source, offline-capable, cross-platform application

---

# 0. Revised Linux MVP acceptance scope

**Current development target:** implement the remaining required Linux features
of this specification, excluding other-platform support. This is in progress,
not complete; [Linux spec progress](linux-spec-progress.md) records delivered
slices and open Linux requirements. The completed MVP described below is the
baseline, not a claim that these additional requirements have been fulfilled.

By product decision, PhotoSim 0.1 closes the **Linux desktop MVP**, not the original
five-platform MVP. Other platforms and the broader requirements below are future
work. [Linux MVP scope](linux-mvp.md) is authoritative for this release: export the
current photographic viewport as an attributed PNG; provide backend quality
presets, illustrative Clear/Cloudy/Fog/Rain selection and thin-lens depth of field
linked to aperture, focus distance, sensor and focal length. No live weather API
or calibrated exposure is claimed. The original cross-platform phase gates and
broader definition of done below describe the future product, not remaining
Linux 0.1 release blockers.

# 1. Project Overview

## 1.1 Objective

Develop a cross-platform landscape and astrophotography simulation application that allows photographers to preview realistic photographic compositions at any geographic location on Earth.

The software will combine real terrain elevation data, satellite imagery, local astronomical calculations, and GPU-accelerated 3D rendering to simulate what a photographer would see through a particular camera and lens at a selected location, direction, date, and time.

The application must provide two primary, synchronized workspaces:

1. **2D Map View:** A geographic planning interface in which users place a virtual camera, select the viewing direction, set sensor format and focal length, and examine terrain and celestial alignments.
2. **3D Simulation View:** An interactive virtual camera showing the terrain, celestial objects, atmospheric conditions, and simulated lighting from the selected viewpoint.

Both workspaces must share the same simulation state. Switching between them must not reset camera parameters, time, or geographic location.

The application should work without paid APIs by default. Elevation and imagery are downloaded from available free sources and cached locally. Astronomical calculations must run entirely on the user's device.

## 1.2 Core capabilities

The finished application must support:

- Interactive 2D geographic maps.
- Precise camera placement and orientation.
- A pill selector for APS-C and full-frame sensor formats.
- A single continuous focal-length slider spanning 8–600 mm, without lens presets.
- Accurate photographic field-of-view calculation.
- Real 3D terrain reconstructed from elevation data.
- Satellite and aerial imagery projected onto terrain.
- Accurate positions of the Sun, Moon, planets, stars, and Milky Way.
- Real-time terrain illumination driven by the Sun and Moon.
- Realistic atmospheric scattering, twilight, and terrain shadows.
- Photography exposure controls.
- Date/time simulation with continuous playback.
- Optional forecast-driven weather visualization.
- Offline caching.
- Saved photography plans and image export.
- Native GPU acceleration on supported desktop and Android devices.
- GPU rendering in browsers through a compatible web backend.

## 1.3 Fundamental design principles

**Physical accuracy:** Geographic positions, perspective geometry, astronomical positions, and lighting direction must be calculated rather than approximated with arbitrary visual offsets.

**Photographic usability:** The interface should resemble a photography planning tool, not a complex 3D modeling application.

**Cross-platform consistency:** Core calculations and application state must use shared Dart implementations.

**Open-source dependency preference:** Prefer permissively licensed components, open geographic datasets, and documented public APIs.

**Local computation:** Astronomical simulation, camera projection, terrain mesh generation, and image rendering must run locally.

**Progressive rendering:** Show a usable image quickly, then progressively improve terrain and imagery quality.

**Transparency:** Distinguish accurate astronomical geometry from approximated atmospheric, environmental, and photographic effects.

---

# 2. Application Interface and Navigation

## 2.1 Primary workspaces

The application must have exactly two primary workspaces:

- **Map View (2D)**
- **Simulation View (3D)**

Use a persistent workspace selector to switch between them.

On desktop, optional side-by-side viewing may display both workspaces simultaneously. This is a layout variation, not a third workspace.

Both workspaces observe and modify a single shared simulation state.

Secondary functionality—including optics controls, astronomical information, weather, saved plans, and settings—must be presented through toolbars, panels, dialogs, or bottom sheets.

## 2.2 Map View — Geographic planning

The 2D Map View is the primary interface for determining where to take a photograph and where to point the camera.

### Map functionality

The map must support:

- Interactive panning and zooming.
- Location search.
- GPS coordinates.
- Satellite imagery and conventional map layers.
- Terrain shading and optional contour lines.
- Geographic scale and compass.
- Camera location selection by tapping or clicking.
- Camera-marker dragging.
- Camera direction adjustment.
- Geographic elevation display.
- Saved locations and photography plans.

### Camera marker

Display the camera as a geographically positioned marker with a directional indicator.

The marker must indicate:

- Camera location.
- Viewing azimuth.
- Horizontal field of view.
- Optional orientation relative to geographic north.
- Camera height.

The camera's field of view must be displayed as a translucent wedge extending from the camera position.

The wedge angle must correspond to the actual horizontal field of view calculated from the selected camera sensor and focal length.

The wedge must update immediately when the user rotates the camera, changes focal length, or changes sensor format.

A drag handle must allow the camera direction to be rotated without moving the camera position.

The map must distinguish between moving the camera marker and ordinary map navigation.

### Celestial overlays

The map should optionally display:

- Sun direction.
- Moon direction.
- Sunrise and sunset bearings.
- Moonrise and moonset bearings.
- Galactic center direction.
- Milky Way planning indicators.
- Terrain-obstructed celestial alignment indicators.

Celestial objects below the horizon should be visually distinguished from visible objects.

### Camera placement

Users must be able to set:

- Latitude.
- Longitude.
- Ground elevation derived from the terrain model.
- Camera height above ground.
- Viewing azimuth.
- Camera pitch.
- Camera roll.

The application should automatically obtain terrain elevation at the selected camera position.

The user may override camera height or elevation for special scenarios, such as elevated viewpoints or observation decks.

---

# 3. Simulation View — Real-Time 3D Camera

## 3.1 Purpose

The Simulation View renders a realistic photographic preview from the exact position and orientation defined in the Map View.

The 3D scene must use:

- Real terrain elevation.
- Satellite imagery as surface textures.
- A physically consistent perspective camera.
- Astronomically calculated celestial positions.
- Sunlight and moonlight.
- Terrain shadows.
- Sky and atmosphere rendering.
- Exposure and tone mapping.

The simulated image must update interactively when the user modifies camera or simulation settings.

## 3.2 Camera manipulation

Support two control modes.

### Photography mode

The camera remains fixed at its geographic position.

- Drag to adjust yaw and pitch.
- Change focal length to zoom optically.
- Adjust roll.
- Modify camera height explicitly.
- Lock camera orientation to astronomical targets if requested.

Dragging must not accidentally translate the camera.

### Exploration mode

The user may move through the virtual terrain.

- Free camera translation.
- Orbit and look-around controls.
- Optional terrain-relative movement.
- Return to saved photography position.

Photography mode must be the default.

## 3.3 Interactive behavior

The 3D renderer must respond to:

| User change | Required rendering update |
| --- | --- |
| Camera azimuth | Rotate virtual camera |
| Camera pitch | Tilt virtual camera |
| Camera position | Update viewpoint and visible terrain |
| Camera height | Recalculate viewpoint and horizon |
| Focal length | Update perspective projection |
| Sensor format | Update camera field of view |
| Date/time | Recalculate astronomy and lighting |
| Moon phase | Update Moon rendering and moonlight |
| Atmospheric settings | Update sky, haze, and light attenuation |
| Satellite imagery source | Replace surface textures |
| Terrain resolution | Refine or simplify terrain meshes |

Changing time, sensor format, focal length, or camera direction must not reload geographic data unnecessarily.

## 3.4 Visual overlays

The 3D viewport should optionally display:

- Center crosshair.
- Rule-of-thirds grid.
- Horizon leveling indicator.
- Camera azimuth and pitch.
- Focal length.
- Field of view.
- Sun/Moon position markers.
- Galactic center marker.
- Selected-star or constellation labels.

Provide a **Constellations** toggle in the 3D toolbar, off by default. It enables
constellation name labels and highlighted connecting figures together. Use a
licensed offline catalog, with J2000 positions transformed by the same local-sky
rotation as the stars. Figures are illustrative asterisms, not official IAU
boundaries. Names and highlights must depth-test against terrain, remain usable
as planning guides in daylight, and not intercept camera aiming gestures. Preserve
the toggle across workspace changes and saved plans; missing preferences in
older plans default to off.

- Terrain-distance information.
- Current time and date.

Overlays must be individually configurable and hideable.

A clean fullscreen photographic preview must always be available.

---

# 4. Sensor Format and Focal Length

## 4.1 Sensor format selector

Provide one single-selection pill control with two options:

| Format | Sensor width | Sensor height |
| --- | --- | --- |
| APS-C | 23.5 mm | 15.6 mm |
| Full-frame | 36 mm | 24 mm |

Full-frame is selected by default. Changing sensor format must preserve focal length, camera location/orientation, and simulation time while immediately updating the map wedge and 3D projection.

Do not provide a camera-body dropdown, named camera-body database, additional sensor formats, or custom sensor dimensions in the initial optics system.

## 4.2 Simplified optics model

The optics UI consists only of the sensor-format pill and a focal-length slider, with read-only focal-length and field-of-view information.

Do not provide lens selection, prime/zoom categories, lens presets, custom lens definitions, mount compatibility, or per-lens focal-length restrictions. All focal lengths use the same rectilinear projection model.

Exposure controls are separate photography tools, not additional lens-selection controls.

## 4.3 Focal length slider

Provide one continuous slider spanning **8–600 mm**, with **24 mm** as the default. The range is independent of the selected sensor format.

Display the actual focal length in millimeters and the horizontal/vertical field of view. The selected sensor format must remain visible in the pill control.

Changing focal length must immediately modify the virtual camera projection and the 2D map's field-of-view wedge. It must not physically move the virtual camera, change simulation time, or reload geographic data.

Validate that focal length is finite and within 8–600 mm when constructing camera state or importing saved plans.

## 4.4 Perspective calculation

For a rectilinear lens, calculate the horizontal field of view as:

HFOV = 2 × atan(sensorWidth / (2 × focalLength))

Calculate the vertical field of view as:

VFOV = 2 × atan(sensorHeight / (2 × focalLength))

Use the selected sensor format's physical dimensions and the preview's image orientation/aspect ratio. Sensor dimensions are derived from the format, not independently editable.

Build the 3D projection matrix from the calculated camera parameters.

The initial renderer should support rectilinear lenses. Fisheye projections and detailed measured lens-distortion profiles can be introduced later.

## 4.5 Exposure controls

Support:

- Aperture.
- ISO.
- Shutter speed.
- Exposure compensation.
- White balance.
- Automatic exposure.
- Manual exposure.

The first implementation must approximate photographic exposure in the rendered preview.

A later implementation may add:

- Depth of field.
- Sensor noise.
- Lens vignetting.
- Lens distortion.
- Long-exposure star trails.
- Motion blur.
- Sensor-specific color rendering.

The interface must distinguish a realistic exposure preview from a visibility-enhanced simulation.

---

# 5. Geographic Data Architecture

## 5.1 Geographic coordinate system

Use WGS84 latitude and longitude as the geographic reference.

The geographic engine must support:

- WGS84 geodetic coordinates.
- Earth-Centered, Earth-Fixed (ECEF) coordinates.
- Local East-North-Up (ENU) coordinates.
- Web Mercator tile coordinates.
- Elevation-datum transformations where required.

Use double-precision calculations for global coordinate transformations.

GPU geometry must use camera-relative coordinates to avoid floating-point precision problems at Earth-scale distances.

The local rendering origin should be rebased as the camera moves over large geographic distances.

## 5.2 Terrain elevation sources

Support pluggable terrain providers.

| Provider | Approximate resolution | Role |
| --- | --- | --- |
| Mapterhorn | 30 m global; finer regional sources | Primary anonymous tiled terrain service |
| Mapzen Terrain Tiles | Variable by zoom | Independent tiled fallback |
| Copernicus DEM GLO-30 | 30 m | Global baseline through Mapterhorn |
| Copernicus DEM GLO-90 | 90 m | Global fallback |
| USGS 3DEP and open national DEMs | Regionally 0.5–10 m | Available through Mapterhorn where covered |
| User-provided DEM | Arbitrary | Optional custom terrain |

Actual resolution, availability, usage rights, and data coverage must be determined separately for each source.

## 5.3 Tiled terrain interfaces

Prefer Mapterhorn's anonymous `https://tiles.mapterhorn.com/{z}/{x}/{y}.webp`
service: 512×512 lossless WebP with Terrarium-encoded heights. It combines
Copernicus GLO-30 with open national terrain without requiring application users
to register at the original download portals. Retain upstream attribution and
license references; the tile-generation code's license does not license all data.

For the current zoom-13 region, try regional tiles first, then crop the exact
child quadrant of a global zoom-12 parent where needed. On failure, use Mapzen.
Source sampling, native source detail and rendered mesh resolution are distinct;
the current mesh does not expose native 1–5 m detail. Keep service caches separate
within the existing 256 MiB budget. See [terrain sources](data-sources/terrain.md).

Support Mapzen Terrarium tiles through the published tile format:

<https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png>

Decode elevation from RGB values:

elevation = 256 × R + G + B / 256 − 32768

The terrain loader must convert the decoded elevation raster into geographic samples with correct horizontal spacing.

Web Mercator tile spacing varies with latitude and zoom level; do not interpret map pixels as universally fixed-size ground samples.

## 5.4 DEM processing

Terrain data must be converted into a common internal format.

Required processing:

1. Download elevation raster.
2. Decode source format.
3. Determine geographic bounds.
4. Read elevation reference system.
5. Transform to the internal height reference when necessary.
6. Reproject or resample samples if required.
7. Generate mesh vertices and indices.
8. Calculate surface normals.
9. Assign geographic texture coordinates.
10. Upload mesh buffers to the GPU.

Height data must remain available for independent terrain-horizon calculations.

### Terrain surface models

Where relevant, distinguish:

- Digital Elevation Model (DEM).
- Digital Terrain Model (DTM), representing bare ground.
- Digital Surface Model (DSM), potentially including trees or buildings.

Different model types must not be mixed without metadata.

---

# 6. Terrain Mesh Generation and Level of Detail

## 6.1 Mesh generation

Generate 3D meshes dynamically from elevation grids.

Each terrain patch must include:

- Vertex buffer.
- Triangle index buffer.
- Surface normals.
- Texture coordinates.
- Geographic bounding box.
- Elevation bounds.
- LOD identifier.
- Source resolution.
- Reference coordinate origin.

Mesh generation should execute outside the critical UI/rendering path.

## 6.2 Multiresolution terrain

Use a quadtree-based level-of-detail system.

Nearby terrain receives greater geometric detail.

Distant terrain uses lower-resolution geometry while maintaining correct large-scale terrain silhouettes.

LOD selection must consider:

- Camera location.
- Camera direction.
- Camera altitude.
- Camera focal length.
- Viewport resolution.
- Screen-space geometric error.
- Available GPU memory.

High focal lengths may require additional detail in distant terrain, even when the visible geographic area is narrow.

### Current range controls (Linux vertical slice)

The **Terrain range** inspector section controls surrounding fetch radius (1–3 zoom-13
tile rings), forward fetch distance (0–40 km, off by default), and terrain render
radius (2–40 km, default 40). Forward coverage uses the horizontal projection of
the sensor/focal-length FOV and camera pitch/azimuth, with a 400 ms adjustment
debounce. Retain overlapping terrain meshes/textures and cancel obsolete jobs.
Use non-overlapping distance/FOV quadtree leaves with at most 256 patches; long
lenses prefer finer tiles within that budget. Whole-tile distance rejection and
Flutter Scene's actual 3D frustum culling govern rendering without clipping sky
layers. Persist settings; legacy plans keep the original 3×3 region.

This is not yet viewport/screen-error LOD, terrain-aware vertical fetch culling,
exact per-pixel distance clipping, or precise horizon prediction. See
[terrain source limits](data-sources/terrain.md).

## 6.3 Terrain continuity

Avoid visible gaps between terrain patches with different LODs.

Possible implementations:

- Edge stitching.
- Shared border vertices.
- Terrain skirts.
- Neighbor-aware mesh refinement.

Terrain updates must avoid obvious popping and unstable edges.

## 6.4 Earth curvature

The rendering system must account for the curvature of Earth, particularly when simulating distant mountains and astronomical alignments.

Use WGS84 ellipsoid geometry for geographic calculations.

A local planar ENU approximation may be used only where its geometric error is acceptable.

Atmospheric refraction should be supported as an optional adjustment.

## 6.5 Horizon visibility

Implement a horizon-calculation service that determines apparent terrain altitude as a function of azimuth:

horizonAltitude(azimuth)

This service will support:

- Mountain skyline rendering.
- Sunrise behind mountains.
- Moonrise behind terrain.
- Galactic center visibility.
- Star visibility above local terrain.
- Composition alignment predictions.

The horizon service must use actual geographic elevations and account for curvature.

It must be available independently of the current visible terrain mesh, allowing accurate celestial visibility tests beyond the detailed render region.

Uncertainty should be reported when horizon data is insufficient or too coarse.

---

# 7. Satellite and Aerial Imagery

## 7.1 Objective

Use real geographic imagery as the terrain's surface texture.

The imagery system must support globally available sources while allowing higher-resolution regional data.

## 7.2 Primary providers

### USGS NAIP

Preferred for high-resolution imagery where available in the United States.

- Approximately 0.6 m imagery in many areas.
- Aerial orthophotography.
- Public-domain source data.
- Suitable for detailed landscape textures.

### Copernicus Sentinel-2

Default open global imagery option.

- 10 m visible-band resolution.
- Geographic coverage across most global land.
- The current Linux implementation uses EOX's pre-rendered **2016** cloudless
  mosaic (`s2cloudless_3857`, CC BY 4.0), without an account or API key.
- Newer EOX mosaics with non-commercial restrictions are not used by default.
- Custom RGB generation, historical image selection and cloud-cover filtering
  remain future work; imagery acquisition time does not follow simulation UTC.

### IGN BD ORTHO and swisstopo SWISSIMAGE

Free regional aerial imagery is preferred over the global mosaic where covered:

- IGN BD ORTHO for metropolitan France/Corsica and selected overseas territories;
  approximately 20 cm source orthophotos in much of France, Licence Ouverte 2.0.
- swisstopo SWISSIMAGE for Switzerland; original orthophotos 10–25 cm, with
  coarser service products, freely reusable with mandatory swisstopo attribution.
- Use only the Swiss imagery layer, not background groups with third-party imagery.
- Select automatically by approximate coverage bounds, fall through on errors or
  no-data, and fill transparent regional pixels from lower-priority sources.
- Keep contributing source credits visible and caches provider/resolution-specific.

Source resolution is not displayed resolution. The current zoom-13 terrain uses
256-pixel previews and a 1024-pixel camera texture, downsampling aerial imagery.
Native sub-meter display requires future near-camera imagery subdivision.
See [imagery sources and licensing](data-sources/imagery.md).

### MapTiler Satellite

Optional higher-resolution global imagery source.

Requires account and adherence to provider licensing, caching, and usage restrictions.

The application must not depend on MapTiler to function.

## 7.3 Imagery processing pipeline

1. Determine the geographic region required by visible terrain.
2. Request the most suitable imagery.
3. Download a tile or raster subset.
4. Decode the image.
5. Reproject if necessary.
6. Match imagery to terrain geographic coordinates.
7. Generate or use mipmaps.
8. Upload the image to GPU texture memory.
9. Update the corresponding terrain materials.

Elevation and imagery must be cached independently.

## 7.4 Texture quality

The texture system must prioritize visual detail according to screen-space requirements.

Do not load full-resolution aerial imagery for terrain occupying only a few pixels.

Implement texture LOD and progressive replacement.

A higher-resolution texture must replace a lower-resolution one without rebuilding the underlying terrain mesh.

## 7.5 Satellite imagery and lighting

Satellite imagery often contains existing shadows, seasonal colors, haze, and lighting.

The renderer must support at least:

**Natural imagery mode:** Minimal modification of original imagery.

**Relit terrain mode:** Approximate surface reflectance and apply simulated sunlight or moonlight based on terrain normals.

The application must acknowledge that true physically accurate relighting cannot generally be recovered from arbitrary satellite imagery.

## 7.6 Imagery acquisition dates

The application must store imagery acquisition date metadata when available.

Photographic simulation time and imagery acquisition time are independent.

Users must be informed when seasonal or historical appearance may be inconsistent.

---

# 8. Local Astronomy Engine

## 8.1 Objective

Compute the celestial sky locally based on geographic location and simulation time.

Astronomical calculations must not require an internet connection.

The calculation engine must be independent from the rendering engine.

## 8.2 Candidate libraries

Use or evaluate:

- Astronomia — Dart astronomical calculations.
- Astronomy Engine — open-source ephemeris algorithms.
- D3-Celestial — star catalogs and Milky Way outlines.
- Stellarium — reference calculations and rendering approaches.

Prefer Dart-native implementation where practical.

The astronomy service must expose stable application-level interfaces independent of the chosen calculation library.

## 8.3 Observer parameters

Inputs:

- Latitude.
- Longitude.
- Observer elevation.
- UTC date/time.
- Atmospheric pressure.
- Temperature.
- Optional atmospheric refraction model.

The simulation core must use UTC internally and local timezone conversion only for presentation.

## 8.4 Sun

Calculate:

- Apparent topocentric azimuth.
- Apparent topocentric altitude.
- Apparent angular diameter.
- Sunrise and sunset.
- Solar noon.
- Twilight intervals.
- Solar direction vector.
- Approximate solar irradiance.

Sun direction must drive terrain illumination.

## 8.5 Moon

Calculate:

- Apparent topocentric position.
- Lunar phase.
- Illumination fraction.
- Lunar distance.
- Apparent angular diameter.
- Moonrise and moonset.
- Lunar orientation.
- Sunlit-limb direction.
- Approximate moonlight intensity.

Include lunar parallax for accurate positioning.

Render the Moon as a resolved disk with physically appropriate illumination geometry rather than a generic circular icon.

## 8.6 Stars

Provide a local star catalog.

Initial catalog requirements:

- Right ascension.
- Declination.
- Visual magnitude.
- Star identifier.
- Optional color information.
- Optional proper motion.

Support correct coordinate transformation into the observer's local sky.

Apply coordinate epoch handling and relevant astronomical corrections.

Render individual stars using GPU-efficient batched geometry or shaders.

The apparent brightness and visibility of stars must depend on astronomical conditions and camera exposure.

## 8.7 Milky Way

Implement two forms of Milky Way visualization.

### Planning representation

- Galactic plane.
- Galactic center.
- Approximate bright-region outlines.
- Position and orientation.
- Rise/set or visibility windows for selected regions.
- Alignment indicators.

### Photographic representation

Use a licensed panoramic sky brightness texture or Galactic brightness map.

The renderer must orient the texture in the correct celestial coordinate system.

The Milky Way must rotate correctly with date, time, and observer location.

Its apparent brightness must be affected by:

- Atmospheric extinction.
- Solar twilight.
- Lunar illumination.
- Light pollution.
- Camera exposure.

The Galactic center must be available as a selectable photographic target.

## 8.8 Planets

Compute and optionally display the major planets.

Version 1 should at minimum support visually relevant bright planets.

Each planet must have an accurate apparent position and an appropriate representation based on angular size and brightness.

---

# 9. Astronomy Coordinate Transformations

Use astronomical equatorial coordinates and transform them into local horizontal coordinates.

For a star:

- Right ascension: α
- Declination: δ
- Observer latitude: φ
- Local sidereal time: θ
- Hour angle: H = θ − α

The altitude h can be calculated using:

sin(h) = sin(φ)sin(δ) + cos(φ)cos(δ)cos(H)

The azimuth must be calculated using a quadrant-aware formulation.

Convert calculated azimuth and altitude into local ENU vectors.

Use the same coordinate orientation in both workspaces.

The 3D camera must project celestial directions through the same physical camera model used for terrain.

This guarantees that the angular separation between a star, the Moon, and a mountain landmark is geometrically consistent.

Astronomical positions must also be checked against the geographic terrain horizon.

---

# 10. Physically Informed Lighting Engine

## 10.1 Objective

Simulate the illumination of the landscape based on the calculated positions and approximate physical brightness of the Sun and Moon.

Lighting must be recalculated when simulation time changes.

It must not rely on static daytime or nighttime textures.

## 10.2 Solar lighting

Use a calculated solar direction vector as the primary directional light.

The lighting system must consider:

- Sun altitude.
- Sun azimuth.
- Incident angle on terrain.
- Atmospheric transmission.
- Direct solar illumination.
- Diffuse sky illumination.
- Terrain shadows.
- Sunrise/sunset color changes.

Implement direct illumination based on terrain surface normals and the solar direction.

Use a linear-light rendering pipeline.

## 10.3 Terrain shadows

Use shadow mapping appropriate for large outdoor scenes.

Investigate:

- Cascaded shadow maps.
- Directional-light shadow mapping.
- Adjustable shadow-map resolution.
- Terrain self-shadowing.
- Distant terrain occlusion.

Avoid excessive shadow-map recomputation when the scene is unchanged.

## 10.4 Moonlight

Moonlight must be modeled as a secondary illumination source.

Its approximate intensity must depend on:

- Lunar phase.
- Moon elevation.
- Lunar distance.
- Atmospheric attenuation.
- Sky background brightness.

The renderer should show plausible differences between:

- Moonless nights.
- Crescent-moon illumination.
- Half-moon illumination.
- Full-moon illumination.

Moonlight must not have a fixed artificial intensity across all phases.

## 10.5 Atmospheric scattering

Implement an atmospheric sky model supporting:

- Rayleigh scattering.
- Mie scattering.
- Solar disk.
- Twilight transitions.
- Horizon reddening.
- Atmospheric perspective.
- Distance haze.
- Sky brightness.

The atmosphere must change smoothly across daytime, golden hour, twilight, and night.

A precomputed atmospheric lookup-table system may be used to reduce GPU cost.

## 10.6 Night sky brightness

Account for:

- Solar altitude.
- Moon phase and altitude.
- Atmospheric extinction.
- Approximate airglow.
- Optional light-pollution intensity.
- Camera exposure.

The model must not display the Milky Way at unrealistic brightness during strong twilight or moonlight unless enhanced-visibility mode is selected.

## 10.7 HDR and tone mapping

Use a high-dynamic-range rendering pipeline when supported.

The rendering stages should include:

1. Terrain material evaluation.
2. Direct lighting.
3. Ambient sky contribution.
4. Shadows.
5. Atmospheric effects.
6. Celestial objects.
7. Exposure.
8. Tone mapping.
9. Output color conversion.

Provide:

- Automatic exposure.
- Manual exposure.
- Exposure compensation.
- Physically informed preview.
- Enhanced visibility preview.

When GPU capabilities differ between platforms, preserve correct geometry and lighting direction while reducing optional visual effects.

---

# 11. Weather Integration

## 11.1 Scope

Weather simulation is an optional module.

Use Open-Meteo or another suitable free forecast source, subject to the provider's access and licensing terms.

Potential inputs:

- Total cloud cover.
- Low, mid, and high cloud cover.
- Visibility.
- Relative humidity.
- Temperature.
- Atmospheric pressure.
- Precipitation.
- Wind.
- Solar irradiance forecasts.

## 11.2 Weather rendering

Weather data may influence:

- Estimated sky brightness.
- Solar light attenuation.
- Diffuse illumination.
- Atmospheric haze.
- Fog.
- Procedural cloud coverage.
- Apparent night-sky transparency.

Clouds may be procedurally generated from forecast parameters.

However, cloud-cover forecasts generally do not specify exact cloud shapes or positions.

The interface must clearly label procedurally estimated weather visuals.

## 11.3 Offline operation

Weather services must not be required to render the scene.

When forecast data is unavailable, use a configurable clear-sky atmosphere or the most recently cached forecast with an explicit timestamp.

---

# 12. GPU Rendering Architecture

## 12.1 Core technology

Use Flutter as the application and UI framework.

Use a native GPU rendering approach with Flutter Scene as the preferred starting point.

Investigate Dashmap as the reference implementation for streaming geographic terrain in Flutter.

Relevant projects:

- <https://github.com/bdero/flutter_scene>
- <https://github.com/bdero/dashmap>
- <https://docs.flutter.dev/perf/impeller>

### Cross-platform constraint

Flutter GPU and its supporting 3D libraries must not be assumed to provide identical feature support across all target platforms.

The application must use a rendering abstraction and validate platform capabilities before major implementation.

Preferred native path:

- Android: Flutter GPU / Impeller-compatible backend.
- Linux: Flutter GPU / supported native renderer.
- Windows: Flutter GPU / supported native renderer.
- macOS: Flutter GPU / supported native renderer.
- Web: Flutter Scene WebGL2-compatible backend or an equivalent maintained GPU backend.

Use the same camera model, terrain data, astronomy calculations, and scene definitions on every platform.

Do not use a WebView-based renderer on native platforms as the default architecture.

If Flutter Scene cannot meet a required native-platform capability, use a platform-specific GPU backend behind the same rendering interface rather than compromising the scientific simulation core.

## 12.2 Rendering abstraction

Create an internal `RenderBackend` interface providing operations such as:

- Initialize graphics resources.
- Resize viewport.
- Create terrain meshes.
- Upload textures.
- Update terrain LOD.
- Set camera projection.
- Set camera transformation.
- Update astronomical state.
- Update lighting.
- Update atmosphere.
- Render frame.
- Capture image.
- Release resources.

The Flutter UI must never directly manipulate low-level GPU resources.

## 12.3 Frame pipeline

A typical frame should:

1. Read the current immutable simulation state.
2. Determine camera transformation and projection.
3. Update visibility and LOD decisions.
4. Apply available terrain mesh updates.
5. Apply imagery texture updates.
6. Update astronomical positions when necessary.
7. Update solar and lunar lighting.
8. Render terrain and shadows.
9. Render sky and celestial objects.
10. Apply atmospheric effects.
11. Perform exposure and tone mapping.
12. Present the final frame.

Network access must be completely decoupled from frame rendering.

## 12.4 Avoid redundant work

- Camera rotation updates transforms and visibility, not all terrain meshes.
- Focal-length changes update projection and LOD selection.
- Time changes update astronomical and lighting values.
- Weather changes update atmosphere and lighting.
- New DEM data updates only affected terrain meshes.
- New imagery updates only affected textures.

A reactive scene-state system must identify which GPU resources actually require updating.

## 12.5 GPU resources

Manage:

- Vertex buffers.
- Index buffers.
- Texture resources.
- Shader programs.
- Uniform buffers.
- Shadow maps.
- Framebuffers.
- Rendering pipelines.

Support explicit disposal of unused resources and recovery from lost device or browser graphics contexts.

---

# 13. Performance and Multithreading

## 13.1 Performance targets

Target performance:

| Platform | Preferred frame rate |
| --- | --- |
| Android | 30 FPS minimum target; 60 FPS preferred |
| Linux | 60 FPS |
| Windows | 60 FPS |
| macOS | 60 FPS |
| Web | 30–60 FPS |

Targets apply to defined reference hardware and quality settings; they are not guarantees for all devices.

## 13.2 Terrain performance

Implement:

- Quadtree LOD.
- Frustum culling.
- Horizon culling.
- View-dependent tile loading.
- Progressive mesh refinement.
- GPU buffer reuse.
- Mipmapped textures.
- Adaptive texture resolution.
- Background mesh generation.

## 13.3 Asynchronous processing

Keep expensive work outside the UI thread.

Background tasks include:

- Terrain tile downloads.
- Raster decoding.
- DEM resampling.
- Mesh construction.
- Texture decoding and preparation.
- Geographic reprojection.
- Cache maintenance.

Use Dart isolates on native platforms and browser-compatible workers or asynchronous processing where appropriate.

## 13.4 Cache budgets

Initial configurable cache targets:

- Android: 512 MB.
- Desktop: 2 GB.
- Web: Browser-managed storage.

Use cache eviction according to:

- Last access time.
- Distance from active camera locations.
- Download cost.
- Source resolution.
- Data-source usage restrictions.

Do not repeatedly download data already available in a valid local cache.

---

# 14. Shared Application State

## 14.1 State architecture

The two workspaces must share a single authoritative simulation state.

Suggested state models:

### GeoCameraPosition

- Latitude.
- Longitude.
- Ground elevation.
- Camera height above ground.
- Effective observer elevation.

### CameraOrientation

- Azimuth.
- Pitch.
- Roll.

### CameraOptics

- Sensor format (`apsC` or `fullFrame`).
- Sensor dimensions derived from the format.
- Current focal length (8–600 mm).
- Image orientation and derived aspect ratio.
- Rectilinear projection.

Do not store a selected camera-body or lens-preset identifier in the active optics state.

### ExposureState

- Aperture.
- ISO.
- Shutter speed.
- Exposure compensation.
- White balance.
- Exposure mode.

### AstronomyState

- UTC timestamp.
- Sun position.
- Moon position and phase.
- Planetary positions.
- Star-field transformation.
- Milky Way orientation.
- Twilight state.

### TerrainState

- Current elevation source.
- Active terrain tiles.
- Mesh LOD.
- Imagery source.
- Tile loading and cache status.

### WeatherState

- Forecast timestamp.
- Forecast parameters.
- Source metadata.
- Weather visualization mode.

### SimulationSettings

- Graphics quality.
- Maximum render range.
- Atmospheric settings.
- Visibility overlays.
- Data-source preferences.

## 14.2 Synchronization

The shared state must be independent from the two UI workspaces.

Examples:

- Rotating the camera on the map immediately changes the 3D camera.
- Rotating the camera in the 3D view updates the map's directional wedge.
- Changing focal length or sensor format in either workspace updates both without resetting the other optics setting.
- Adjusting simulation time changes celestial overlays and rendered illumination.
- Repositioning the camera on the map updates the 3D scene progressively.

State updates should be granular to avoid rebuilding unrelated Flutter widgets or GPU resources.

---

# 15. Timeline and Astronomy Planning

## 15.1 Time controls

Provide a shared date/time control accessible from both workspaces.

Support:

- Date picker.
- Time picker.
- Continuous time slider.
- Time stepping.
- Playback.
- Adjustable playback speed.
- Local timezone display.
- UTC display option.

Time changes must update lighting and astronomy in real time.

## 15.2 Timeline events

Display relevant astronomical events:

- Sunrise.
- Sunset.
- Solar noon.
- Civil twilight.
- Nautical twilight.
- Astronomical twilight.
- Moonrise.
- Moonset.
- Galactic center visibility windows.

The event markers must use the selected camera location and local horizon where appropriate.

## 15.3 Target alignment

Users should be able to select an astronomical target:

- Sun.
- Moon.
- Galactic center.
- A prominent star.
- A planet.

The map and simulation should show the target's position relative to the camera direction.

Display:

- Target azimuth.
- Target altitude.
- Angular offset from camera center.
- Terrain obstruction status.
- Whether the target is inside the field of view determined by sensor format and focal length.

Automated searches for ideal alignment dates and locations may be added in a later version.

---

# 16. Offline Operation and Data Management

## 16.1 Offline functionality

Once geographic data has been downloaded for a location, users must be able to:

- Display cached terrain.
- Display cached imagery.
- Rotate the camera.
- Change focal length.
- Change camera settings.
- Change date and time.
- Calculate Sun, Moon, stars, and Milky Way locally.
- Render celestial lighting.
- Reopen saved photography plans.

Do not require an internet connection for astronomy calculations.

## 16.2 Storage

Use:

- SQLite for metadata and saved-plan indexing.
- Local binary files for raster tiles and processed resources.
- Versioned JSON for portable photography-plan export.
- A browser-compatible storage implementation for web.

The cache must track:

- Provider.
- Geographic coverage.
- Resolution.
- Acquisition time when available.
- Elevation datum.
- License and attribution.
- Download timestamp.
- Cache expiration conditions.

## 16.3 User data and API security

Never embed confidential API credentials in a distributed web build.

Use public endpoints where possible.

Where authentication is required, support user-provided credentials or a compliant proxy configuration.

The app must remain functional without optional commercial services.

---

# 17. Saved Photography Plans

## 17.1 Plan contents

Users must be able to save a complete photography setup.

A plan includes:

- Name.
- Camera location.
- Camera orientation.
- Camera height.
- Sensor format (`apsC` or `fullFrame`).
- Focal length (8–600 mm).
- Exposure parameters.
- Date and time.
- Selected celestial target.
- Render settings.
- Optional weather parameters.
- Optional preview thumbnail.

## 17.2 Plan management

Support:

- Create.
- Edit.
- Duplicate.
- Delete.
- Search.
- Import.
- Export.

Saved plans must be portable between devices through a versioned JSON format.

New plans use version-2 JSON and omit lens-preset identifiers. Legacy version-1 plans remain readable: ignore their obsolete `lens` field while preserving focal length and sensor format. Validate sensor identifiers and focal-length bounds rather than depending on a preset database. Older application builds are not required to read version-2 plans.

The system must gracefully handle unavailable geographic tiles when opening a saved plan.

---

# 18. UI and Visual Design

## 18.1 Design direction

The interface should prioritize photographic visualization and practical usability.

Design principles:

- Large unobstructed viewports.
- Minimal permanent controls.
- Clear camera and astronomical information.
- Accessible controls.
- Consistent iconography.
- Support for dark and light themes.
- Responsive layouts.
- Touch-friendly interactions.
- No excessive decorative panels.

## 18.2 Desktop layout

Suggested layout:

**Top toolbar**

- Workspace selector.
- Location search.
- Plan controls.
- Export.
- Settings.

**Central viewport**

- Full 2D map or 3D simulation.
- Optional side-by-side layout.

**Right inspector**

Collapsible sections for:

- Camera position.
- Camera optics: sensor-format pill and focal-length slider.
- Exposure.
- Astronomy.
- Atmosphere.
- Weather.
- Rendering quality.

**Bottom timeline**

- Date and time.
- Time slider.
- Playback controls.
- Astronomical event markers.

Panels must be dockable or collapsible where practical.

## 18.3 Android layout

Prioritize one large viewport.

Use:

- Compact Map/3D switcher.
- Floating camera orientation indicators.
- Bottom-sheet camera controls.
- Collapsible time slider.
- Fullscreen preview.
- Direct touch camera manipulation.

The mobile UI must not simply reproduce the desktop interface at a smaller scale.

## 18.4 Web layout

Use the same responsive design principles.

Render the scene with a browser-compatible GPU backend.

Account for:

- WebGL2 availability.
- CORS restrictions.
- Browser storage limitations.
- GPU context loss.
- Lower memory budgets.
- Mobile browser restrictions.

The application must display clear compatibility errors and offer reduced-quality settings when necessary.

---

# 19. Image Export

## 19.1 Supported outputs

Support:

- PNG image export.
- Photography-plan JSON export.
- Optional screenshot with camera metadata overlay.

The exported image must reflect the selected camera projection and aspect ratio.

## 19.2 Image metadata

Optional overlays or accompanying JSON may include:

- Geographic coordinates.
- Simulation date/time.
- Sensor format.
- Focal length.
- Camera direction.
- Camera altitude.
- Sun/Moon positions.
- Imagery and elevation sources.

## 19.3 Rendering resolution

Support export resolutions independent of the interactive viewport when the rendering backend permits offscreen rendering.

High-resolution export must manage GPU memory safely.

For unsupported devices, provide a clear maximum supported export size rather than silently generating an incomplete image.

---

# 20. Verification and Testing

## 20.1 Geographic tests

Validate:

- Coordinate transformations.
- Elevation decoding.
- Tile alignment.
- Texture projection.
- Terrain normals.
- Vertical datum handling.
- Earth curvature.
- Horizon profiles.
- Adjacent LOD mesh continuity.

## 20.2 Astronomical tests

Compare calculated positions with authoritative reference ephemerides.

Initial targets:

- Sun angular position error below 0.1°.
- Moon position error below 0.2°.
- Representative star coordinate error below 0.05°.

These are project targets to be verified against reference implementations, not assumed library guarantees.

Test observations at different latitudes, seasons, and times.

Test topocentric lunar parallax explicitly.

Test atmospheric refraction separately, especially near the horizon.

## 20.3 Photographic projection tests

Verify:

- Horizontal and vertical field of view.
- APS-C and full-frame sensor dimensions.
- Portrait orientation.
- The shared 8–600 mm focal-length range and invalid-input rejection.
- Focal-length preservation when changing sensor format.
- Sensor-format preservation when changing focal length.
- Sensor pills and focal-length slider with no preset dropdowns.
- Legacy-plan compatibility after removal of lens presets.
- Camera pitch and roll.
- Celestial angular separation.
- Agreement between 2D FOV wedge and 3D projection.

## 20.4 Lighting tests

Test deterministic scenes at:

- Solar noon.
- Golden hour.
- Sunset.
- Civil twilight.
- Astronomical twilight.
- Moonless night.
- Full-moon night.

Verify shadow directions and lighting transitions.

Distinguish geometric correctness from approximate photometric accuracy.

## 20.5 Cross-platform tests

Verify builds and rendering on:

- Android.
- Linux.
- Windows.
- macOS.
- Web.

Use shared scene-state fixtures and reference images.

Pixel-identical output is not required across GPUs, but geometry, celestial positioning, and lighting direction must be consistent.

## 20.6 User workflow tests

An automated end-to-end test must cover:

1. Open application.
2. Select map location.
3. Place camera.
4. Set direction.
5. Select APS-C or full-frame using the sensor pill.
6. Adjust focal length using the 8–600 mm slider.
7. Switch to 3D.
8. Change date/time.
9. Observe astronomy and lighting updates.
10. Save photography plan.
11. Reopen plan and verify sensor format and focal length are preserved.
12. Export preview.

---

# 21. Implementation Plan

## Phase 0 — Cross-Platform GPU Feasibility

**Goal:** Validate the rendering architecture before building the full simulator.

Implement:

- Flutter application shell.
- Flutter Scene integration.
- Test 3D scene.
- Procedural terrain mesh.
- Dynamic texture.
- Controllable perspective camera.
- Directional lighting.
- Shadow test.
- Basic image capture.

Build and run on all five target platforms.

Investigate GPU capabilities, dynamic mesh updates, texture upload performance, browser support, and shader compatibility.

**Exit criteria:** A stable GPU-rendered, dynamically lit 3D terrain scene runs on every required platform, potentially through backend-specific rendering adapters.

Do not begin large-scale application development until this milestone is validated.

## Phase 1 — Map and Camera Foundation

**Goal:** Implement the complete two-workspace navigation model.

Features:

- Interactive 2D map.
- Camera marker.
- Direction handle.
- Field-of-view wedge.
- Map/3D switcher.
- Shared camera state.
- APS-C/full-frame sensor-format pill.
- Single 8–600 mm focal-length slider.
- Accurate perspective projection.
- Basic 3D viewport.

**Exit criteria:** Users can place a camera on the map, select sensor format, set direction and focal length, and see the corresponding 3D perspective. Changing optics must not move the camera.

Procedural terrain may still be used at this stage.

## Phase 2 — Real Geographic Terrain

**Goal:** Replace procedural terrain with actual elevation data.

Features:

- Anonymous Mapterhorn terrain with Mapzen fallback.
- Lossless WebP/PNG Terrarium decoding and exact parent-tile cropping.
- ECEF/ENU conversion.
- Mesh generation.
- Quadtree LOD.
- Terrain cache.
- Terrain streaming.
- Geographic camera placement.

**Exit criteria:** The app can render real terrain from arbitrary supported locations.

## Phase 3 — Satellite Imagery

**Goal:** Display real geographic surface imagery.

Features:

- Imagery provider abstraction.
- Basic satellite imagery source.
- Geographic UV projection.
- Texture cache.
- Progressive texture resolution.
- Terrain imagery materials.

**Exit criteria:** Real terrain is rendered with geographically aligned satellite or aerial imagery.

## Phase 4 — Sun, Moon, and Real-Time Lighting

**Goal:** Create the first complete photography simulator.

Features:

- Local astronomy calculation service.
- Sun position.
- Moon position and phase.
- Date/time controls.
- Dynamic solar directional light.
- Terrain shadows.
- Moon rendering.
- Basic moonlight.
- Atmospheric sky and twilight.

**Exit criteria:** Changing time changes celestial positions, landscape illumination, and shadows without reloading terrain.

## Phase 5 — Stars and Milky Way

**Goal:** Enable astrophotography planning.

Features:

- Local star catalog.
- Star coordinate transformation.
- Star field rendering.
- Milky Way orientation.
- Milky Way sky texture.
- Galactic center overlays.
- Night sky brightness.
- Terrain occlusion.

**Exit criteria:** A user can preview the Milky Way relative to real geographic terrain and determine its position within the field of view determined by sensor format and focal length.

## Phase 6 — Photography Tools and Saved Plans

**Goal:** Complete the core user-facing workflow.

Features:

- Simplified sensor-format and focal-length controls.
- Persistence of optics settings, including legacy-plan compatibility.
- Exposure controls.
- Camera overlays.
- Saved plans.
- Image export.
- Responsive desktop and mobile layouts.
- Quality settings.

**Exit criteria:** Users can plan, save, reopen, and export photographic compositions.

## Phase 7 — Data Quality and Optimization

**Goal:** Improve terrain accuracy and production reliability.

Features:

- Copernicus DEM.
- USGS 3DEP.
- USGS NAIP imagery.
- Sentinel-2 integration.
- Source fallback.
- Distant horizon calculations.
- Advanced caching.
- GPU optimization.
- Offline workflows.

**Exit criteria:** High-resolution terrain and imagery work where supported, with clear fallbacks and acceptable performance.

## Phase 8 — Weather and Advanced Rendering

**Goal:** Add optional environmental simulation.

Features:

- Weather API.
- Forecast-based atmosphere.
- Approximate procedural clouds.
- Fog.
- Atmospheric visibility.
- Improved nighttime exposure.
- Enhanced sky scattering.
- Optional light pollution.

**Exit criteria:** Weather information influences the visual preview without being misrepresented as an exact cloud forecast.

---

# 22. Recommended Repository Organization

```text
landscape_simulator/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart
│   │   ├── routing/
│   │   └── theme/
│   ├── ui/
│   │   ├── workspace/
│   │   ├── map_view/
│   │   ├── simulation_view/
│   │   ├── camera_controls/
│   │   ├── optics_controls/
│   │   ├── astronomy_controls/
│   │   ├── timeline/
│   │   ├── saved_plans/
│   │   └── settings/
│   ├── core/
│   │   ├── geo/
│   │   ├── astronomy/
│   │   ├── camera/
│   │   ├── optics/
│   │   ├── lighting/
│   │   └── simulation/
│   ├── data/
│   │   ├── terrain/
│   │   ├── imagery/
│   │   ├── weather/
│   │   ├── cache/
│   │   └── persistence/
│   ├── render/
│   │   ├── backend/
│   │   ├── flutter_scene/
│   │   ├── terrain/
│   │   ├── sky/
│   │   ├── celestial/
│   │   ├── atmosphere/
│   │   ├── shaders/
│   │   └── postprocessing/
│   └── models/
├── assets/
│   ├── astronomy/
│   └── textures/
├── test/
│   ├── geo/
│   ├── astronomy/
│   ├── optics/
│   ├── terrain/
│   └── lighting/
├── integration_test/
├── docs/
│   ├── architecture/
│   ├── data_sources/
│   ├── licensing/
│   └── validation/
└── README.md
```

All core libraries must remain independently testable.

The UI must not contain geographic raster decoding, astronomical ephemeris calculations, or GPU resource-management logic.

---

# 23. Licensing and Open-Source Requirements

The application should use a permissive open-source license where compatible with dependencies.

Requirements:

- Track third-party code licenses.
- Track geographic-data licenses independently.
- Provide imagery and elevation attribution.
- Respect tile caching and redistribution terms.
- Do not bundle proprietary satellite imagery without permission.
- Allow users to configure supported imagery sources.
- Do not make paid services mandatory.
- Document bundled astronomical catalogs and sky textures.
- Avoid including private API credentials in application binaries.

Free API access must not be assumed to imply unrestricted commercial usage.

For release planning, verify quotas, provider access policies, and terms of use for all selected data services.

---

# 24. Engineering Risks

| Risk | Mitigation |
| --- | --- |
| Flutter GPU compatibility differs by platform | Renderer abstraction and mandatory Phase 0 feasibility testing |
| Flutter Scene API changes | Version pinning and isolated backend adapter |
| Large terrain datasets | Quadtree LOD and on-demand downloads |
| High GPU memory usage | Texture LOD, cache budgets, resource eviction |
| Inconsistent terrain datums | Explicit reference-system metadata and conversions |
| Browser GPU limitations | WebGL2-compatible rendering path and adaptive quality |
| Inaccurate image relighting | Separate natural imagery and relit simulation modes |
| Baked-in satellite shadows | Document limitations and provide simplified illumination mode |
| Unrealistic night sky | Exposure-aware celestial brightness and calibrated approximations |
| Missing geographic coverage | Multiple data providers and graceful fallback |
| Weather prediction uncertainty | Explicit approximate-weather classification |
| Public API restrictions | Provider abstractions and source-specific access policies |

---

# 25. Definition of Done

The initial public release is complete when:

1. The application runs on Android, Web, Linux, macOS, and Windows.
2. The 2D Map View allows precise virtual-camera placement.
3. Users can rotate the camera and visualize its field of view on the map.
4. The 3D Simulation View displays the corresponding camera perspective.
5. Users can select APS-C or full-frame with a pill control and adjust focal length with a single 8–600 mm slider; no camera-body or lens-preset selection is required.
6. Focal-length adjustment updates the 2D field-of-view wedge and 3D perspective simultaneously.
7. The application downloads and renders real terrain elevation data.
8. Satellite or aerial imagery is correctly mapped onto the terrain.
9. Sun and Moon positions are computed locally.
10. Real-time solar illumination changes according to astronomical time.
11. Terrain shadows respond to Sun position.
12. Moon position, phase, and approximate moonlight are represented.
13. Stars and Milky Way are correctly positioned.
14. Terrain occludes celestial objects.
15. Date/time adjustments update the preview without unnecessary geographic-data downloads.
16. Previously cached regions remain usable offline.
17. Photography plans can be saved and reopened.
18. Preview images can be exported.
19. The UI is usable on both mobile and desktop.
20. Core geographic, optical, and astronomical calculations pass numerical validation tests.

Weather simulation and high-resolution regional data providers may be completed in later feature releases if necessary, but the initial public release must deliver the full two-workspace terrain-and-astronomy planning experience.

---

# 26. Future Extensions

Potential later features:

- Automated Sun/Moon alignment searches.
- Moonrise behind a selected mountain summit.
- Milky Way composition suggestions.
- Eclipse planning.
- Star-trail simulation.
- Aurora visualization.
- Light-pollution maps.
- Meteor shower radiant tracking.
- Seasonal snow appearance.
- Vegetation and building reconstruction.
- Higher-resolution LiDAR integration.
- Camera-specific lens correction profiles.
- Photographic sensor simulation.
- AR camera matching.
- User-imported GeoTIFF and 3D assets.
- Panorama and 360-degree export.
- High-resolution offline region downloads.
- Automated photography-plan optimization.

These extensions must build on the existing camera, terrain, astronomy, and rendering abstractions.

---

# 27. Technical References

## GPU rendering

- Flutter Scene: <https://github.com/bdero/flutter_scene>
- Dashmap geographic 3D renderer: <https://github.com/bdero/dashmap>
- Flutter Impeller: <https://docs.flutter.dev/perf/impeller>

## Elevation data

- Mapterhorn access: <https://mapterhorn.com/data-access/>
- Mapterhorn upstream credits/licenses: <https://mapterhorn.com/attribution/>
- Mapzen Terrain Tiles: <https://registry.opendata.aws/terrain-tiles/>
- Copernicus DEM: <https://registry.opendata.aws/copernicus-dem/>
- USGS National Map: <https://apps.nationalmap.gov/downloader/>
- OpenTopography: <https://portal.opentopography.org/apidocs/>

## Geographic imagery

- USGS NAIP: <https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer>
- EOX 2016 mosaic / licensing: <https://cloudless.eox.at/pricing>
- IGN BD ORTHO: <https://geoservices.ign.fr/bdortho>
- swisstopo SWISSIMAGE: <https://www.swisstopo.admin.ch/en/orthoimage-swissimage-10>
- Copernicus Data Space: <https://dataspace.copernicus.eu/>
- Element 84 Earth Search: <https://earth-search.aws.element84.com/v1>
- MapTiler: <https://docs.maptiler.com/>

## Astronomy

- Astronomia: <https://github.com/dmvvilela/astronomia>
- Astronomy Engine: <https://github.com/cosinekitty/astronomy>
- D3-Celestial: <https://github.com/ofrohn/d3-celestial>
- Stellarium: <https://github.com/Stellarium/stellarium>

## Weather

- Open-Meteo: <https://open-meteo.com/en/docs>

---

# 28. Final Development Directive

Build the project as an accurate, interactive **landscape and astrophotography planning simulator** with two tightly synchronized workspaces.

The **2D Map View** is used to plan camera location, orientation, sensor format, focal length, geographic framing, and astronomical alignment.

The **3D Simulation View** is used to preview the scene through the selected photographic equipment, using actual terrain, geographic imagery, locally calculated celestial positions, and real-time lighting.

Both workspaces must operate on the same camera and simulation state.

Prioritize the following implementation sequence:

1. Validate the GPU rendering architecture across every target platform.
2. Implement the two synchronized workspaces and accurate sensor/focal-length projection model.
3. Render real geographic terrain with satellite textures.
4. Add locally calculated Sun/Moon positions and physically informed lighting.
5. Integrate stars, the Milky Way, and terrain-aware celestial visibility.
6. Complete the photography-planning workflow, caching, and export features.
7. Refine visual fidelity, regional data resolution, and optional weather rendering.

Maintain strict separation between:

- UI and user interaction.
- Geographic data acquisition.
- Terrain geometry.
- Camera optics.
- Astronomical calculations.
- Physical lighting.
- GPU rendering.
- Data persistence.

The architecture should allow future improvements to scientific accuracy, geographic data resolution, and rendering quality without replacing the application or rewriting its core calculations.

**The primary product goal is to let a photographer choose a location, sensor format, focal length, direction, and time, then immediately see an astronomically and geographically consistent preview of the photograph they could capture.**
