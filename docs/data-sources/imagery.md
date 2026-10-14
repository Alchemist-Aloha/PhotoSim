# USGS NAIP aerial imagery

## Provider and rights

Source: [USGS NAIP ImageServer](https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer).
The published service description identifies public-domain NAIP orthoimagery
for the conterminous United States, provided through USGS's partnership with USDA.
Credit shown in-app: **USGS, USDA, The National Map: Orthoimagery**.

The app requests the documented
[exportImage operation](https://developers.arcgis.com/rest/services-reference/enterprise/export-image/),
not the disabled bulk exportTiles operation. No imagery is bundled in releases,
no region prefetch is performed, and no paid account or API key is needed.
Review current service availability and usage guidance before public distribution.

## Geographic alignment

Each request uses the exact terrain XYZ tile's Web Mercator bounding box:
`bboxSR=3857`, `imageSR=3857`, `adjustAspectRatio=false`.
The explicit `NaturalColor` rendering rule excludes infrared/NDVI templates.
PNG32 preserves no-data transparency. Row zero maps to the tile's north edge;
the terrain's existing normalized UVs are reused. Texture address mode clamps
edges instead of repeating neighboring edge pixels.

Nine 256×256 previews load progressively, with three jobs active at most, after
terrain geometry is ready. The camera tile then upgrades to 1024×1024 without
rebuilding any vertex/index buffers. Remaining tiles retain their previews.

This is downsampled imagery, not a claim to display the dataset's native 0.6 m
resolution. Ground sample spacing varies with latitude. Coarse geometry and
nadir-only imagery visibly stretch at cliffs and grazing viewing angles; tile
skirts can produce edge bands. Photorealistic cliff reconstruction is not implemented.

Outside the published service extent, requests are skipped. Inside it, coverage
is not guaranteed. Fully transparent results are treated as unavailable; partially
transparent pixels become the explicitly labeled fallback surface. Failures or
unavailable detail do not remove a successful preview or prevent terrain use.

## Appearance and simulation time

Natural mode uses unlit, display-referred imagery to preserve original colors.
Approximate relighting applies UTC-driven solar illumination and shadows.
Natural imagery retains its captured lighting. See [astronomy notes](../astronomy.md).
The preference is shared simulation state and survives workspace switching.

Orthophotos contain baked-in shadows, seasons and lighting. Relighting cannot
recover physically accurate reflectance and may double existing shadows.
The service returns a mosaic whose individual source acquisition dates may vary.
Acquisition dates are currently unknown/null and not queried; they are independent
of the simulation date. Source-catalog date extraction remains open.

## Cache and validation

The same native raster cache is reused in provider/resolution-specific directories:

- `photosim/naip-natural-256-v1/`: 64 MiB preview budget.
- `photosim/naip-natural-1024-v1/`: 192 MiB detail budget.

These budgets are independent of the 256 MiB elevation cache. Sidecar JSON records
provider, request URL, tile identifier, resolution, EPSG:3857, attribution, download
time, partial coverage, and unknown mosaic acquisition time. Corrupt entries are
removed and refetched. No failed or all-no-data image is cached.

HTTP downloads have a 20-second deadline, explicit cancellation, and an 8 MiB
encoded limit. PNG headers are checked against the requested dimensions before
decoding. PNG decoding and no-data handling execute in an isolate. Flutter Scene
uploads the RGBA pixels and creates its mip chain. Texture upload/mipmap frame
times and long-run memory use have not been profiled.

Cached images currently persist until LRU eviction; refresh/expiry and source-date
controls remain future work. No inference that cached imagery reflects a current
or historical simulation date is made.
