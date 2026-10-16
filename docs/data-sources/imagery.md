# Terrain imagery sources

## Automatic source selection and rights

No account, API key or paid service is required. Each terrain tile tries the
following sources in order, skipping regional services outside approximate
coverage bounds. Actual coverage is not guaranteed by those bounds.

| Source | Coverage and source detail | Rights / visible credit |
| --- | --- | --- |
| [USGS NAIP](https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer) | Conterminous US; approximately 0.6 m in many areas | Public-domain NAIP data; **USGS, USDA, The National Map: Orthoimagery** |
| [swisstopo SWISSIMAGE](https://www.swisstopo.admin.ch/en/orthoimage-swissimage-10) | Switzerland; original orthophotos 10 cm in lowlands/major valleys, 25 cm in the Alps; service products may be coarser | [Free geodata terms](https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices) permit processing and commercial use with **©swisstopo** |
| [IGN BD ORTHO](https://geoservices.ign.fr/bdortho) | Metropolitan France/Corsica and selected overseas departments/territories; 20 cm source orthophotos in much of France, varying by area/year | [Licence Ouverte / Etalab 2.0](https://www.etalab.gouv.fr/licence-ouverte-open-licence/); **© IGN · BD ORTHO · Licence Ouverte 2.0**; see [IGN service terms](https://geoservices.ign.fr/cgu-licences) |
| [EOX Sentinel-2 cloudless 2016](https://cloudless.eox.at/pricing) | Global basemap, approximately 10 m Sentinel-2 source data where available; not guaranteed detailed/current imagery everywhere | **EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016)**; [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

EOX's WMS `s2cloudless_3857` layer is explicitly identified as the **2016**
CC BY mosaic in [GetCapabilities](https://tiles.maps.eox.at/wms?SERVICE=WMS&REQUEST=GetCapabilities).
Newer EOX mosaics have non-commercial restrictions and are **not** used. The
2016 pricing exception permits direct use of the public service with attribution,
including commercial applications. This old mosaic must not be mistaken for
current photography or imagery corresponding to the simulated date.

Switzerland uses only `ch.swisstopo.images-swissimage`, not the broader
`ch.swisstopo.swissimage` background group containing third-party SPOT imagery.
France uses `ORTHOIMAGERY.ORTHOPHOTOS`; approximate search bounds cover mainland
France/Corsica, French Guiana, Guadeloupe, Martinique, Saint-Martin/Saint-Barthélemy,
Réunion, Mayotte and Saint-Pierre-et-Miquelon. No claim is made that every pixel
in these regions is covered.

Credits for all sources contributing to the displayed tiles remain visible below
the preview. The sources dialog and disk metadata retain the source/license
information. No imagery is bundled or bulk-prefetched. Public services have no
availability guarantee and may throttle excessive usage; review their current
terms and arrange hosting/service agreements before substantial distribution.

## Geographic alignment and progressive loading

NAIP uses the documented ArcGIS
[exportImage](https://developers.arcgis.com/rest/services-reference/enterprise/export-image/)
operation with `bboxSR=3857`, `imageSR=3857`, `adjustAspectRatio=false` and an
explicit `NaturalColor` rule, not bulk exportTiles or infrared/NDVI templates.
The other sources use WMS 1.3.0 GetMap in **EPSG:3857**, whose axis order remains
Easting/Northing. Endpoints: `https://wms.geo.admin.ch/`,
`https://data.geopf.fr/wms-r/wms`, `https://tiles.maps.eox.at/wms`.

Every export uses the exact existing terrain XYZ tile's Web Mercator bounds.
Row zero maps to north; existing normalized UVs and clamped texture edges are
reused. Each selected terrain patch receives a 256×256 preview (nine by default),
with at most three jobs active. Forward-range coverage can add coarser patches;
preview ground spacing doubles for each lower terrain zoom.
Nearby previews begin alongside the remaining terrain jobs. The camera tile
upgrades to 1024×1024 after terrain and preview loading, without rebuilding geometry;
slow detail exports never block terrain. Remaining tiles retain previews.
Terrain and imagery share [HTTP concurrency/backoff](../loading.md), not a fixed
assumed provider requests-per-second quota. Source selection is automatic; there is no source picker
or new saved-plan setting.

**Native sub-meter aerial resolution is not displayed.** At terrain zoom 13,
1024 pixels span approximately `4.78 × cos(latitude)` meters per pixel, and
256-pixel previews are four times coarser. The effective detail is also limited
by the source itself (about 10 m for Sentinel-2), the service's resampling and
mipmapping. Adaptive near-camera imagery subdivision remains future work.
Coarse meshes, grazing views, cliffs and skirts still stretch imagery.

Fully transparent results, malformed responses and service failures try the next
source. Partial regional coverage is alpha-composited over lower-priority imagery
in an isolate. Pixels unavailable from every source become the explicitly labeled
green fallback material. A failed detail request preserves the successful preview.
The global service can return slightly transparent border pixels; these also
remain labeled partial coverage rather than silently claiming complete imagery.

## Appearance and simulation time

Natural mode preserves display-referred colors and baked-in lighting. Optional
UTC-driven relighting is approximate and can double captured shadows; it cannot
recover physical reflectance. Clear natural imagery with DOF off stays display-referred.
Weather/DOF switch natural imagery to the scene-linear effects pipeline so fog and
physical depth blur apply; tone mapping can shift colors and baked-in shadows remain.
Changing weather, aperture, focus or backend quality does not reload geography. See [astronomy notes](../astronomy.md).

Source acquisition dates vary within mosaics. Exact dates remain unknown/null and
are not queried, even though the global mosaic's 2016 epoch is known from its
source label. Photography does not follow simulation time. Time, sky-layer and
relighting changes neither download imagery nor rebuild geographic geometry.
Optics/aim edits also preserve geography with forward fetching off (the default).
When enabled, they replan FOV-dependent coverage; retained patches keep their images
and only missing previews/details load. Render-radius changes do not fetch imagery.

## Cache and validation

Provider/resolution namespaces reuse the existing native raster cache:

- `photosim/{naip-natural,swissimage,ign-ortho,eox-s2-2016}-256-v1/` for previews.
- Corresponding `*-1024-v1/` for detail.

All imagery and terrain share the configurable disk budget under **Storage**,
default **512 MiB**, rather than fixed per-source/per-resolution quotas. Existing
cache paths remain readable. Lowering the limit evicts oldest-used rasters across
all sources; zero disables disk caching. See [cache settings](../loading.md#disk-cache-settings). Sidecar JSON records
provider, original request URL, dimensions, EPSG:3857, attribution, download time,
partial coverage and unknown exact acquisition time. Only original source rasters,
not generated composites, are cached. Corrupt entries are refetched; failed and
all-no-data responses are not cached. There is no automatic refresh/expiry UI.

Imagery downloads have a **40-second deadline**, explicit cancellation and an
8 MiB encoded limit; elevation retains its 20-second deadline. EOX dynamic detail
exports can take over 20 seconds, while previews remain usable. PNG and JPEG magic
and dimensions are validated before pixel decoding, with decoder pixel limits.
PNG supports 8-bit RGB/RGBA and indexed palettes. Despite a PNG request, EOX can
return JPEG for tile-aligned previews; cached raster files retain the shared
`.png` filename convention, and decoders inspect their actual bytes. Decoding and
compositing execute in isolates. Flutter Scene uploads RGBA and generates mipmaps.
Long-run GPU memory and upload/frame times remain unprofiled.

Tests cover routing, bounds, projection, PNG/JPEG validation, alpha composition,
source-separated preview/detail caching, failure/timeout fallback and cancellation.
`integration_test/linux_imagery_test.dart` checks live Swiss, French, Australian
and Beijing imagery over Mapterhorn terrain, rendered pixel diversity, visible
attribution, and geography/cache reuse on time/optics edits. It writes
`build/validation/linux-imagery-{swiss,ign,eox,beijing}.png`.
These checks are not a global coverage survey or survey-grade alignment benchmark.
