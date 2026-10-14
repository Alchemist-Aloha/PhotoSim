# Offline night sky

## Bundled sources and licensing

The app bundles **5,044 XHIP stars through visual magnitude 6**, from
[D3-Celestial](https://github.com/ofrohn/d3-celestial), and its five Milky Way
brightness contours. Star source: Anderson & Francis (2012), XHIP, VizieR
V/137D. Milky Way source: Jose R. Vieira's Milky Way Outline Catalog.
D3-Celestial redistribution uses **BSD-3-Clause**, copyright Olaf Frohn (2015).
The full notice is bundled in `assets/sky/LICENSE.txt`, registered with Flutter's
license registry, and accessible from the 3D sources dialog.

`assets/sky/provenance.json` records pinned upstream commit
`7e720a3de062059d4c5400a379146a601d9010e0`, exact source URLs and SHA-256 digests.
`tool/build_sky_assets.py` reproduces the compact star rows and 1024×512 RGBA
Milky Way map (development-only Python 3/Pillow; no new app dependency).
The five contours are rasterized, preserve polygon holes and receive slight
feathering. Contour alpha increases in five artistic steps, **not radiometric
measurements**. No network access is used for sky calculations or asset loading.

## Constellation names and highlights

The **Constellations** chip in the 3D toolbar toggles names and blue connecting
figures together, default off. Its shared-state preference survives workspace
switches and version-2 plan saves; older plans without the field default off.
These are explicit planning guides and remain available in daylight when enabled,
not physical light sources or official IAU boundary polygons.

`assets/sky/constellations.json` derives names/anchors and illustrative figures
from the same pinned BSD-licensed D3-Celestial release. There are 88 constellations
and 89 label regions because Serpens Caput/Cauda are labeled separately. Exact
upstream URLs and source digests are recorded in `provenance.json`; the asset
builder reproduces the compact rows.

`lib/core/constellations.dart` validates the catalog and creates short great-circle
ribbons, including across the RA seam. `lib/render/constellations.dart` draws one
immutable highlight mesh and one instanced billboard name batch using a shared
font atlas. Both inherit the existing sky rotation and depth-test against terrain
and foreground objects; neither casts shadows or intercepts camera gestures.
Names are upright, approximately fixed in pixel size as focal length changes,
and omitted below horizontal or outside the optical frustum. Accessibility
semantics list names whose anchors lie in the frustum, with a terrain-occlusion
caveat. No hover selection, boundary fill or collision decluttering is included;
wide-angle names may overlap or be clipped near viewport edges.

Tests cover catalog integrity, malformed data, finite inward-facing geometry,
RA wrapping and persistence. Linux native checks exercise the actual toggle,
label pixels, a foreground occluder and geometry reuse. Inspected screenshot:
`build/validation/linux-constellations.png` (terrain hidden to isolate the layer).

## Coordinates

Star identifiers are Hipparcos IDs; positions are J2000 mean equatorial RA/Dec,
converted to radians by the catalog parser. The map uses RA −180°…180° from
left to right, declination +90°…−90° from top to bottom.

`ObserverSkyFrame` applies IAU-1976/Meeus precession to date, nutation and apparent
sidereal rotation into east +X, up +Y, north −Z. UTC approximates UT1 and modeled
Delta T supplies TT, matching the existing Sun/Moon assumptions. A single rigid
node transform aligns both star geometry and the brightness-map sphere; only
that transform and material brightness change as UTC/location changes.

Galactic-center targeting uses Sgr A* at J2000 RA **266.4051°**, declination
**−28.936175°**. This is not exactly the origin of the IAU Galactic coordinate
system. Violet map bearings and the selected 3D marker use the same rotation.
The marker is a composition aid, not a resolved astronomical object.

Six independent ERFA/SOFA fixtures cover 1900–2100, northern/southern observers,
the equator and a geographic pole. Offline tests require rotation separation
below **0.01°**. `tool/build_sky_fixtures.py` records the reference method and
inputs; development-only pyerfa 2.0.1.5 and numpy generate them. Fixtures check
rigid coordinate transformation, **not actual stellar astrometry across a
century**. Proper motion, annual aberration/parallax, atmospheric refraction
and extinction are omitted; some high-proper-motion stars can shift more than
0.1° across the supported date range. No full-range accuracy claim is made.

## Rendering and targeting

Stars share one immutable batch of inward-facing eight-triangle disks at 40 km.
Magnitude affects approximate intensity and exaggerated angular size; these are
unresolved planning points, **not true stellar disks or a calibrated lens PSF**.
The Milky Way is an inward-facing textured sphere at 45 km. Both depth-test
against the Moon, loaded terrain and foreground objects, and cast no shadows.

Visibility fades from zero at solar altitude −6° to dark-sky visibility at −18°.
Above-horizontal lunar illumination suppresses stars and suppresses the band
more strongly. This is an artistic clear-sky model, without light pollution,
weather, exposure controls, photorealistic Galactic detail or individual star labels.
Occlusion is limited to loaded terrain; no complete Earth/terrain-horizon service
or rise/set windows are provided. Sky meshes can trigger the backend's existing
near-plane/depth-precision warning; long-run GPU profiling remains open.

Choose a target from the toolbar (Sun, Moon, Galactic center), then optionally
**Aim at selected target**. Selection does not lock or continually track camera
orientation. Aiming clamps pitch to the camera's supported ±85° range. The FOV
readout tests the target **center** against the rectangular sensor/lens frustum,
including pitch and wraparound; it does not assert unobstructed terrain visibility.

The Linux native workflow verifies visible stellar and Milky Way pixels,
telephoto Antares occlusion by the actual Yosemite canyon, a controlled opaque
foreground blocker, daylight suppression, and time-driven rotation without
replacing sky/terrain geometry or restarting geographic downloads. Screenshots:
`build/validation/linux-night-sky-terrain.png`, `linux-night-sky-isolated.png`,
and `linux-star-isolated.png` (the latter exaggerates the unresolved star at
telephoto scale to make depth testing deterministic).
