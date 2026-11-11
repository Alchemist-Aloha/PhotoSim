# Geometry fixture provenance

`lake_ontario_rochester.geojson` is Lake Ontario (HydroLAKES v1.0 `hylak_id=7`)
from the UNEP-WCMC Ocean+ global HydroLAKES ArcGIS service, retrieved 2026-11-02:

https://data-gis.unep-wcmc.org/server/rest/services/Oceanplus/_Global_lake_distribution_of_HydroLAKES_McGill_University/MapServer/0/query

Query: GeoJSON, intersecting envelope `-77.65,43.20,-77.50,43.35`, EPSG:4326,
fields `hylak_id,lake_name,elevation`, full geometry. To keep the fixture small,
only Ontario is retained and its rings are clipped to longitude [-77.8,-77.3],
latitude [43.15,43.5] without simplification. Artificial fixture clipping edges
are outside the regression test region. Production fetches full lake geometry.
The dataset's 73 m elevation is retained as an estimate, not an observed level.

Source: Messager et al. (2016), HydroLAKES v1.0, **CC BY 4.0**.
https://www.hydrosheds.org/products/hydrolakes

`anacostia_water.pbf` is the unmodified OpenFreeMap / OpenMapTiles vector tile
`10/293/391`, retrieved 2026-11-11 from:

https://tiles.openfreemap.org/planet/20261101_080013_pt/10/293/391.pbf

`openfreemap_tilejson.json` is the corresponding TileJSON document (JSON formatting normalized)
from https://tiles.openfreemap.org/planet on the same date. Production discovers
the current snapshot through this endpoint instead of pinning the fixture URL.
The tile's `water` layer includes Anacostia river polygons `518587842` and
`622041512`; their feature IDs are OpenMapTiles IDs, not raw OSM way IDs.
It exercises real MVT commands and class filtering; no river height is supplied.

Credit: **OpenFreeMap · © OpenMapTiles · Data from © OpenStreetMap contributors**,
**ODbL 1.0**. https://www.openstreetmap.org/copyright
OpenMapTiles schema: https://openmaptiles.org/schema/water/

`anacostia_terrain.png` is the unmodified Mapzen Terrarium elevation tile
`13/2344/3134`, retrieved 2026-11-11 from:

https://s3.amazonaws.com/elevation-tiles-prod/terrarium/13/2344/3134.png

It supplies the real central DEM in the Anacostia render regression, centered at
`38.8805,-76.971`. Neighboring tiles and solid-green imagery in that test are
synthetic; the green image is deliberately not a satellite photograph, so the
blue river can only come from the water layer.

Terrain credit: **Mapzen Terrain Tiles**, blended source attribution/licenses:
https://github.com/tilezen/joerd/blob/master/docs/attribution.md
This DC tile includes public USGS elevation data; vertical references remain
uncorrected.
