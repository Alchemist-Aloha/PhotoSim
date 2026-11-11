# Static water surfaces

**Settings → Data sources → Static water surfaces** is enabled by default and
saved in plans/session recovery. It is independent of NASA terrain/imagery.
No account or API key is required.

## Lake polygons

Lakes use **HydroLAKES v1.0**, queried from the public
[UNEP-WCMC Ocean+ GIS service](https://data-gis.unep-wcmc.org/server/rest/services/Oceanplus/_Global_lake_distribution_of_HydroLAKES_McGill_University/MapServer/0).
Intersecting full GeoJSON polygons are fetched once per canonical zoom-10 atlas;
no server-side geometry simplification is requested. Polygon/MultiPolygon rings
retain islands. Before tile clipping, shoreline corners are rounded with
quadratic Bézier curves. Corner cutbacks are capped at 10 m and one quarter of
each adjoining edge; curve tessellation targets 2 cm error, with continuous
bounded joins along the shore rim. The water fill,
shore rim and terrain clearance all use this same world-space contour across
tiles and detail levels. This is a small visual approximation, not more accurate
shoreline data; original downloaded geometry is unchanged.
Geometry is then clipped and subdivided for Earth curvature; only actual shores,
never tile clipping edges, receive dark rims.

Each identified lake uses its dataset `elevation` across every render tile and
atlas. This avoids splitting large lakes into separately estimated raster
components, or omitting them because local DEM samples disagree. Coverage no
longer depends on MODIS lake pixels. Missing/invalid elevations are not invented.

**Heights are approximate pour-point elevations, not surveyed lake surfaces or
current observations.** For example, this dataset reports Lake Ontario as 73 m;
that is not a current Rochester gauge reading. Vertical references remain
uncorrected. Negative-elevation lakes are supported. HydroLAKES covers lakes of
at least 10 hectares, with approximately 1:100,000–1:250,000 source mapping;
it is not cadastral shoreline data and small ponds/fine beach details may be absent.

Credit: **Messager et al. (2016), HydroLAKES v1.0, CC BY 4.0**.
See [HydroSHEDS HydroLAKES](https://www.hydrosheds.org/products/hydrolakes).
The UNEP-WCMC service is a third-party public distribution, not an availability guarantee.
Oversized/truncated responses are rejected rather than silently drawing partial coverage.

## River water

Mapped **OpenStreetMap** river polygons come from
[OpenFreeMap](https://openfreemap.org/) static OpenMapTiles vector tiles, without
an API key. The current tile URL is discovered from
`https://tiles.openfreemap.org/planet` (TileJSON), not a pinned weekly snapshot.
Only the `water` layer's `class=river` polygons are used, including mapped canals
and streams; waterway centerlines, lakes, oceans and underground water are excluded.
Island rings are preserved. Invalid/oversized protobuf or geometry is rejected.

Tiles use the existing water atlas zoom (up to 10), so small rivers can be omitted
or simplified by the source. Centerlines are never given invented widths.
Tile-cut edges stay straight and river outlines are omitted: vector features can
be split inside a tile, and outlining those cuts would invent banks. Footprints
are clipped to each rendered terrain triangle and lifted 8 cm above it, retaining
animated reflections without flattening rivers or carving land.
**These are DEM-draped approximations, not surveyed river elevations, hydraulic
flow, flood extents or current water levels.** Terrain errors, cross-channel slopes
and terrain tile seams remain visible; river water does not repair the DEM.

Credit: **OpenFreeMap · © OpenMapTiles · Data from © OpenStreetMap contributors**,
[ODbL 1.0](https://www.openstreetmap.org/copyright).
The shared bounded/cancellable downloader uses at most three requests per origin,
20-second deadlines, Retry-After/backoff and at most two retries. Camera water
loads first. Only viewed coverage is fetched; there is no bulk/offline-area
download. OpenFreeMap's [terms](https://openfreemap.org/tos) limit offline downloads
to 3,000 tiles or 50 MB, at most four parallel requests, with an identifying
User-Agent. Availability and mapped coverage vary; there is no service guarantee.
A river outage preserves available lake/ocean water and shows a retry warning.
Validated cached tiles work offline without contacting TileJSON or Overpass.

## Oceans and outage fallback

Two PNG masks use [NASA EOSDIS GIBS WMS](https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi?SERVICE=WMS&REQUEST=GetCapabilities):

- `MODIS_Terra_L3_Land_Water_Mask`, fixed `TIME=2015-01-01`, about **250 m**
  native resolution. Only the published water palette is accepted.
- `OSM_Land_Mask`, coastline-only coverage from **© OpenStreetMap contributors**.
  Inland lakes are land in this mask. Transparent ocean is intersected with
  MODIS water, never interpreted as an unrestricted sea plane.

Coastline-classified ocean uses approximate **0 m mean sea level**, not DEM
bathymetry. This is not a reconciled tidal/geoid datum. Ocean coverage remains
historical/coarse and may be stair-stepped; it is unchanged by lake polygons.

If polygon retrieval fails, the existing inland MODIS/DEM method remains a
fallback: connected components use robust interior median elevations, rejecting
fewer than four samples or a 90th–10th percentile spread over 4 m. This fallback
can omit large lakes or have seams between zoom-10 atlases. Successful empty
polygon queries do not resurrect raster lakes outside HydroLAKES coverage.
Polygon lakes still render if the mask service fails; ocean then remains absent.

## Rendering, loading and cache

Water follows WGS84 curvature in the terrain's local frame. Under covered water,
DEM ripples within 4 m of the estimated level are lowered in memory only.
For polygon lakes, clearance includes one terrain-mesh cell plus the DEM
interpolation footprint around the shore. This stops coarse terrain triangles
from hiding a smooth polygon behind a staircase, without expanding the water
polygon or filling its islands. Near-shore ground within that narrow band can
also be lowered; hills outside the 4 m tolerance are never excavated.
Original cached terrain is unchanged. Larger DEM/height discrepancies can still
occlude water. Raster ocean/fallback outlines retain their source resolution.
Water surfaces receive animated ripples, sky/cloud reflections and filtered sun
glitter; narrow dark rims distinguish lake/ocean shores (not tile-cut rivers). No tides, hydraulic flow or live
levels are modeled.

Loading is asynchronous after terrain, without blocking imagery. Failed water
requests preserve terrain and expose retry. Navigation, source/detail changes
and disabling water discard stale results; disabling restores original terrain.

Original lake GeoJSON and provenance use `hydrolakes-v10-polygons-v1`; original
OpenFreeMap PBF tiles/provenance use `openfreemap-rivers-v1`. Old Overpass
`osm-riverbanks-v1` entries are never reused but remain eligible for LRU cleanup.
PNG namespaces
are `modis-water-2015-256-v1` and `osm-coast-mask-256-v1`. All count against the
shared **Settings → Storage** LRU budget, including while water is disabled.
Corrupt entries are replaced; cached polygons/masks and fallback DEMs work offline.
Ocean-only/polygon-only coverage needs no extra DEM download. Source credits
appear in preview/export. [OSM attribution](https://www.openstreetmap.org/copyright)
and NASA data terms continue to apply.

## Verification

`test/lake_polygons_test.dart` covers quadratic curves and their bounds,
shared contours across tiles/detail levels, holes/concavity, clipping, cross-atlas
lake levels, real Rochester/Lake Ontario shoreline geometry, cache recovery/offline
reuse and polygons with missing/unavailable MODIS coverage. `test/water_test.dart`
covers ocean classification, raster outage fallback, curvature, bounded terrain
adjustment and cancellation. `test/river_test.dart` covers MVT layer/class
filtering, island rings, straight tile cuts, real Anacostia geometry, triangle-exact
sloping surfaces, malformed protobuf/geometry, validated TileJSON discovery,
offline cache reuse, independent outages, shared atlas requests and cancellation. The storage test includes river cache eviction
across restarts. `integration_test/water_test.dart` renders a polygon lake and
river with an empty raster mask on the Linux GPU, including detail/toggle reloads;
it writes `build/validation/linux-static-water.png` and
`build/validation/linux-river-water.png`.
`integration_test/anacostia_water_test.dart` uses downloaded Anacostia riverbanks
and the real central DC DEM at `38.8805,-76.971`. Synthetic green imagery isolates
the water layer: the test checks that the visible blue river disappears when
water is disabled. It writes `build/validation/anacostia-water.png` and
`build/validation/anacostia-terrain.png`. The regression checks TileJSON discovery
and camera-first tile loading. Fixtures/provenance are in `test/fixtures/README.md`.
To exercise a cold-cache **live** river request instead of the river fixture:

```sh
flutter test integration_test/anacostia_water_test.dart -d linux --dart-define=PHOTOSIM_LIVE_RIVERS=true
```

This opt-in check fetches the camera atlas from the real river endpoint, checks
visible water and its toggle, but does not wait for background neighboring atlases.
It retains deterministic terrain and imagery fixtures; ordinary tests stay offline.
Rebuild the runnable bundle
with `flutter build linux --release` after changing providers.
