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
