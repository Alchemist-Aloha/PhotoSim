# Loading, request limits and backoff

## What was measured

Small local probes of the actual endpoints returned HTTP 200, not 429, with no
Retry-After/rate-limit headers. Three requests for one Mapterhorn tile took
0.13–0.21 seconds each. A USGS NAIP 1024px export took 3.25 seconds; an EOX 2016
1024px WMS image took 23.35 seconds (first byte 0.83 seconds, 2.25 MB total).
These are individual samples, not provider guarantees or a load test. Cached
terrain responses do not establish service-wide capacity; HTTP 200 does not rule
out bandwidth shaping or other server/network delays.

The loader previously awaited the first image batch, including camera-tile detail,
before requesting the remaining terrain. That imposed imagery latency on meshes.
Nearby 256px previews now run alongside the remaining terrain; further previews
and 1024px camera detail follow without holding terrain loading. Existing geometry,
textures, cancellation, source order, provenance and size limits are preserved.

## Application policy

- At most **three streamed HTTP requests per origin** for terrain/imagery, shared
  by their client. This is an application concurrency budget, not a claim about a
  vendor quota. There is no arbitrary fixed requests-per-second delay on success.
- The application owns that client across Map/3D workspace recreation, preserving
  cooldowns and connection reuse. Cooldowns are in memory, not persisted on exit.
- **429 and 503** trigger an origin-wide cooldown. Honor `Retry-After` delta-seconds
  and HTTP-date values. Missing, invalid or past dates use exponential delays of
  1, 2, 4, 8, 16, then at most 32 seconds; success resets the failure count without
  shortening an already announced cooldown. Valid longer server delays win.
- Each download retries at most twice. Its existing 20-second terrain / 40-second
  imagery deadline includes queueing, transfers and retries. Backoff waits and
  queued slots cancel promptly; cancellation never starts a deferred request.
- New uncached calls during cooldown fail fast, allowing the normal source fallback.
  A current request also falls back immediately if its next retry exceeds its
  deadline. Other origins continue independently. Expected missing-tile 404s are
  not retried. Error and oversized response streams are cancelled to release them.
- Disk cache reads/decoding happen before HTTP scheduling, so valid cached data
  remains usable during cooldown. Existing source/parent fallback rules still apply.
- Runtime throttle diagnostics log status, origin and cooldown UTC, without tile
  paths, coordinates or imagery query strings.

No numeric vendor quota was established. Public services can still throttle or
become unavailable; substantial distribution may require hosting/service agreements.
The policy covers terrain/imagery requests, not the separate planning-map client.

## Disk cache settings

Open **Storage** in the right settings/inspector panel. Set **Total disk cache
limit (MiB)** and press **Apply cache limit**. Default: **512 MiB**; range:
**0–65,536 MiB** (64 GiB). Zero disables disk caching and removes existing raster
entries. Changing the limit does not change camera/time, plans or loaded GPU assets.

The limit covers committed original DEM/imagery bytes plus paired JSON provenance,
shared across all existing provider/resolution folders. Existing files are reused;
there is no expiry timer. Reads refresh LRU order; writes evict oldest-used entries
when necessary. A single entry exceeding the entire limit is discarded without
flushing useful smaller entries. Lower limits apply immediately and at startup.

The setting is staged/saved in the application-support directory at
`photosim/cache-settings.json`, not in photography plans. Files remain in the
application-cache directory under `photosim/`. Startup removes stale raster staging
files and orphan JSON only in known source folders; unrelated files and links are
not traversed. File/settings failures show warnings and do not destroy plans.

One shared write/settings/eviction queue protects concurrent downloads. The index
is scanned once at startup, then updated incrementally, avoiding a whole-cache
scan per download. It assumes one application writer, not multiple processes.
The limit excludes GPU/RAM usage and filesystem allocation overhead; staged writes
can temporarily exceed it. The OS/user may still clear the cache. This is not a
permanent offline archive or an imagery freshness guarantee.

## Checks

Mocked tests cover streaming concurrency, pre-cancelled/queued/deadline cancellation,
shared cooldowns and independent origins, retry recovery/exhaustion, numeric/date/
malformed/oversized Retry-After values, source fallback, cache bypass, response size
limits and response-stream cleanup. Fallback-only fixtures provide a long server
Retry-After; retry timing is exercised separately in the HTTP tests.

`integration_test/linux_loading_test.dart` uses an isolated temporary cache and
mocked HTTP with real Linux GPU rendering. It holds all imagery responses pending,
checks that all nine meshes and camera-ground data arrive anyway, then releases
imagery and checks preview/detail completion without rebuilding geometry. No public
service is stress-tested.
