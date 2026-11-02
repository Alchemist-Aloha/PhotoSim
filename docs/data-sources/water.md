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
Smooth opaque PBR surfaces receive scene lighting/specular sky; narrow dark
rims distinguish shores. No waves, flowing rivers, tides or live levels are modeled.

Loading is asynchronous after terrain, without blocking imagery. Failed water
requests preserve terrain and expose retry. Navigation, source/detail changes
and disabling water discard stale results; disabling restores original terrain.

Original GeoJSON and provenance use `hydrolakes-v10-polygons-v1`. PNG namespaces
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
adjustment and cancellation. `integration_test/water_test.dart` renders a polygon
lake with an empty raster mask on the Linux GPU, including detail/toggle reloads;
it writes `build/validation/linux-static-water.png`.
