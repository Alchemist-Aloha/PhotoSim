# Terrain data and cache

## Account-free sources

PhotoSim prefers **[Mapterhorn](https://mapterhorn.com/)** and retains **Mapzen
Terrain Tiles** as an independent fallback. Neither service requires an account,
API key or paid subscription. This adds access to many open national DEMs through
one existing tile service rather than separate national download/API clients.

### Mapterhorn

- XYZ tiles: `https://tiles.mapterhorn.com/{z}/{x}/{y}.webp`
- [Data access](https://mapterhorn.com/data-access/), [TileJSON](https://tiles.mapterhorn.com/tilejson.json),
  [coverage](https://mapterhorn.com/coverage/), [source attribution](https://mapterhorn.com/attribution/).
- **512×512 lossless WebP, Terrarium encoding**:
  `height = 256R + G + B/256 − 32768` meters.

The service combines **Copernicus GLO-30** with finer regional open elevation
sources. Its published catalog includes, among others:

| Area | Upstream products / nominal source grids |
| --- | --- |
| Global land | Copernicus GLO-30, approximately 30 m |
| United States | USGS 3DEP, 10 m and selected 1 m areas |
| Canada | HRDEM, selected 2 m areas |
| England, Scotland, Wales | Regional 1 m terrain products |
| France | RGE ALTI 5 m, regional 1 m and finer LiDAR products |
| Switzerland | swissALTI3D 2 m and finer regional products |
| Norway, Finland, Sweden | National 1–2 m terrain products |
| Spain | National/regional 2–5 m terrain products |
| Japan | GSI 10 m, 5 m and selected 1 m products |
| Australia | Selected 5 m LiDAR and finer Tasmanian terrain |
| New Zealand | Selected 1 m LiDAR terrain |
| Other regions | Additional open European datasets, Greenland, Rwanda and others |

These are the **service's upstream source grids**, not guaranteed resolution or
coverage at every point. In particular, China does not acquire nationwide 10 m
terrain through this change. Global data remains roughly 30 m outside finer
coverage. The service does not report each tile's exact source blend or acquisition
time, so PhotoSim does not invent per-tile source identity/accuracy metadata.

### Selection and bounded loading

Default coverage remains nine zoom-13 XYZ patches. The **Terrain range** dialog
sets 1–3 surrounding tile rings (3×3 through 7×7), 0–40 km forward reach (default
off), and a 2–40 km horizontal render radius (default 40). Ring distances vary
with latitude and camera position within the tile; the dialog shows approximate km.

Forward fetches use the horizontal envelope of the camera's optical frustum,
including sensor, focal length, pitch and azimuth. If the frustum includes zenith
or nadir, its envelope spans every heading; vertical terrain visibility is not
predicted before downloading. A distance/FOV quadtree keeps nearby rings at zoom
13 and uses coarser, non-overlapping tiles farther away. Long lenses prefer finer
tiles; automatic coarsening enforces a 256-tile budget rather than truncating reach.
This is an observer-scale Mercator approximation, not terrain-aware horizon or
screen-error selection. Web Mercator's polar coverage limit still applies.

Aim, pitch and optics changes debounce for 400 ms when forward fetching is enabled.
Changes reconcile the desired tile set: retained patches preserve geometry/textures,
new patches load near-first, obsolete jobs cancel and unused patches are removed.
The first nearby preview image batch runs alongside the remaining terrain, not
before it. Slow imagery and camera-tile detail cannot hold up mesh loading.
See [loading and HTTP backoff](../loading.md).
Render-distance changes only hide/reveal whole tiles intersecting the radius;
coarse tiles can extend beyond it. Flutter Scene additionally culls against the
actual 3D view frustum. Fetch and render limits are independent (prefetching is
allowed); rendering cannot invent terrain beyond fetched coverage. Sky distances
are unchanged. Settings persist in plans; old plans retain the original defaults.

For each zoom-13 patch:

1. Request a Mapterhorn zoom-13 tile where available.
2. If unavailable/invalid, try its zoom-12 parent. The global mosaic stops at
   zoom 12 outside regional high-resolution archives. Crop the exact 256×256 child
   quadrant from its 512×512 raster, preserving pixel-center registration, north-up
   orientation and the requested patch's geographic bounds. Do not upscale it.
3. If both fail, request the existing Mapzen zoom-13 tile.

Coarser patches request their own zoom directly from Mapterhorn, then Mapzen;
they do not request zoom-13 children or crop an unrelated zoom-12 raster.

Cached detail is preferred; if only the parent is cached, use it without repeating
failed detail probes. A cached coarse tile may consequently remain preferred until
eviction; automatic refresh/new-coverage discovery is not implemented. Neighboring
patches can request the same uncached parent concurrently; downloads remain bounded
to the existing three jobs, but in-flight requests are not deduplicated.

HTTP, decoding and no-data failures fall through; caller cancellation stops the
chain. All-source failure leaves the patch unavailable, never fabricated terrain.
Each request has a 20-second deadline and 1 MiB encoded limit. Only 512×512 canonical
lossless VP8L WebP is accepted for Mapterhorn; dimensions are checked before decoding
and the decoder has a pixel limit. Lossy/animated/unsupported WebP is rejected rather
than corrupting encoded heights. Mapzen retains its strict 256×256 RGB8 PNG checks.
Transparent, void and out-of-range elevations are rejected. Decode/crop/mesh building
run in isolates.

### Mapzen fallback

Endpoint: `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`.
These 256×256 RGB8 PNGs use the same Terrarium height formula.

References: [AWS dataset](https://registry.opendata.aws/terrain-tiles/),
[format](https://github.com/tilezen/joerd/blob/master/docs/formats.md),
[regional data sources](https://github.com/tilezen/joerd/blob/master/docs/data-sources.md),
[attribution/licenses](https://github.com/tilezen/joerd/blob/master/docs/attribution.md).
Existing regional credits remain in the sources dialog when Mapzen is used.

## Attribution and reuse

The preview identifies contributing services, including **© Mapterhorn** and its
attribution URL. The sources dialog includes upstream producer names, product names,
license names and license-reference URLs from the bundled official
`assets/terrain/mapterhorn-attribution.json` snapshot (151 source records).
`assets/terrain/provenance.json` records its origin and SHA-256. It bundles credits,
**not downloaded geographic data**. Review/update this snapshot as the service evolves.

Mapterhorn's BSD-3 code license is **not** the license of all terrain data. Its
catalog retains per-source CC BY, open-government, public-domain and other open-data
terms; preserve the corresponding credits and conditions. Public access alone does
not establish unrestricted redistribution rights. The service can change or become
unavailable; there is no availability guarantee or bulk prefetch.

Some original national download portals require registration or API keys; PhotoSim
does not call them. Access here is through Mapterhorn's anonymous tiled distribution.
Direct NASA HMA, TanDEM-X, restricted Copernicus EEA-10, national GeoTIFF download
clients and standalone ArcticDEM/REMA providers have not been added.

## Geometry, accuracy and appearance limits

At zoom 13, a 512-pixel tile has ground sample spacing of approximately
`9.55 × cos(latitude)` m, versus `19.1 × cos(latitude)` m for 256 pixels. Those are
sampling spacings, not source detail or accuracy guarantees. Meshes use 128
subdivisions on the camera patch, 64 on other zoom-13 patches, and 32 on coarser
patches. Native 1–5 m source detail is not displayed; screen-error geometry
refinement remains open. Time, relighting and sky-layer edits do not download or
rebuild geography. With forward fetching off, optics/aim edits also preserve it;
when enabled they can change coverage, retaining overlapping patches. Imagery
keeps the same independent patch UVs; distant previews are correspondingly coarser.

Both services blend products of different resolution, acquisition dates, DSM/DTM
type and vertical reference systems. PhotoSim passes service elevations through and
labels them **source datum, uncorrected**. These heights are temporarily treated as
ellipsoid heights for local ECEF positioning; that is not a datum conversion.
Curvature is included, but precise observer altitude and distant horizons require
geoid/datum conversion and uncertainty validation. Service and resolution boundaries
can show elevation discontinuities; existing skirts hide some gaps, not datum errors.

The fallback green surface is a material, not satellite imagery or land cover.
Sun/Moon lighting brightness is approximate; see [astronomy notes](../astronomy.md).

## Native cache

The application cache directory contains two provider namespaces:

- `photosim/mapterhorn-v1/`: 128 MiB, raw lossless WebP.
- `photosim/terrain-v1/`: 128 MiB, existing Mapzen PNGs.

Total configured elevation budget remains **256 MiB**, independent of imagery.
Old Mapzen paths remain readable; their former 256 MiB budget shrinks on the next
write/eviction. The shared cache retains `.png` filenames even for WebP; decoding
uses the provider/actual encoding, not the filename. Parent rasters use their true
zoom-12 cache keys and request URLs, not the target child's identity.

Sidecars record provider, source raster tile, original URL, pixel dimensions,
encoding, horizontal CRS, attribution, UTC download time, unknown acquisition time
and the datum warning. Successful original rasters are cached, not generated meshes.
Corrupt entries are removed/refetched; failed responses never populate caches.
PNG/WebP files and metadata are evicted least-recently-used first. Non-tile files
are untouched. Staged writes are renamed; cache filesystem errors preserve network
rendering and usable read-only entries. No cache refresh UI is implemented.

## Validation

Unit tests cover WebP/PNG trust boundaries, fractional/negative heights, quadrant
orientation/cropping, source selection, provenance, separate bounded caches,
corruption, failures, deadline-vs-caller cancellation and bundled credits.
Coverage tests check FOV/pitch/direction, pole/dateline wrapping, non-overlapping
LOD leaves, the tile budget, range validation and legacy plan defaults. Dialog
widget tests cover apply/cancel, semantics and a small viewport.
The Linux native imagery workflow now also checks actual Mapterhorn rendering in
Switzerland, France, Australia and Beijing, source credit display, and geometry/cache
reuse on time/optics edits with forward fetching off. The Swiss case additionally
checks live forward loading, FOV/aim replanning, retained nearby geometry, render-only
reuse, frustum culling, and preserving UTC edits behind the dialog. Beijing exercises the global parent-tile route in the
currently published coverage. The full Yosemite save/reopen/GPU workflow remains
covered. These checks are not a worldwide coverage survey or accuracy benchmark.
