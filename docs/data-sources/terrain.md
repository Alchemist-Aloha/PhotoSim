# Terrain data and cache

## Source

Mapzen Terrain Tiles hosted through AWS Open Data:

`https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`

References:
- [Dataset](https://registry.opendata.aws/terrain-tiles/)
- [Terrarium format](https://github.com/tilezen/joerd/blob/master/docs/formats.md)
- [Provider attribution and licenses](https://github.com/tilezen/joerd/blob/master/docs/attribution.md)
- [Underlying data sources](https://github.com/tilezen/joerd/blob/master/docs/data-sources.md)

The 256×256 RGB8 tiles encode elevation in meters as
`256R + G + B/256 − 32768`. The app never replaces missing data with invented
terrain. The default US demonstration credits USGS; the in-app source dialog
lists the dataset's regional provider attributions for other locations.

The source is a blend of DEM products, with differing resolution and vertical
reference systems. The app preserves the source elevations and labels them
**source datum, uncorrected**. Those values are temporarily used as ellipsoid
heights for local ECEF positioning; this is not a datum conversion. Curvature
is included, but precise observer altitude and distant horizon work require a
geoid/datum conversion and uncertainty validation.

The fallback green surface is a material, not satellite imagery or a
representation of land cover. Light direction follows the locally calculated
Sun; brightness/color remain approximate. See [astronomy notes](../astronomy.md).

## Native cache

Location: Flutter's application cache directory, subdirectory
`photosim/terrain-v1/` (normally beneath XDG_CACHE_HOME on Linux).

Each new entry includes:
- `z-x-y.png`: original validated elevation raster.
- `z-x-y.png.json`: schema version, provider, tile coverage identifier, source
  URL, UTC download time, acquisition time (unknown/null), datum warning, and
  attribution reference.

The PNG modification time is the last successful access time. Entries and
their metadata are evicted least-recently-used first at a 256 MiB combined
budget. Files are atomically replaced from temporary files. Non-tile files
are not removed by eviction. Older valid PNG-only entries remain readable.

Only elevation is cached here, independently of map tiles, the separate NAIP imagery cache,
and future user plans. No bulk region downloads are performed. Failed or
malformed downloads are not cached; corrupted cached rasters are removed
and fetched again. File-system failures do not prevent network terrain from
rendering, and readable read-only cache entries remain usable.

The cache currently treats this static terrain dataset as reusable indefinitely.
Refreshing source versions and a cache-management UI remain future work.
Native cancellation stops HTTP requests; stale isolate results are discarded.
Isolate computation already in progress is allowed to finish.

Review the linked regional terms before redistributing cached geographic data.
The bundled application contains no downloaded terrain tiles. Public access
does not by itself establish unrestricted redistribution rights.
