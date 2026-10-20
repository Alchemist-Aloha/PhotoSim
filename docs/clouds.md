# Procedural clouds

Open **Camera controls → Weather**. Select **Cloud type**, set **Cloud amount**
(0–100%), and use **Randomize clouds** to change the pattern without changing the
camera, time, type or amount. Randomize is disabled at 0%. Types are Cumulus,
Stratocumulus, Stratus, Cirrus and Cumulonimbus; the panel explains their forms.
Amount controls procedural density/coverage, not an observed cloud percentage.

Clouds are independent of the manual Clear/Cloudy/Fog/Rain preset after editing.
Changing a preset or choosing **Reset weather parameters** restores its cloud
type/amount defaults. Cloud type, amount and random seed are preserved in plans
and automatic session recovery. Older plans use their weather preset's defaults.
No cloud control triggers geographic downloads.

## Rendering

`assets/atmosphere/clouds.fmat` ray-marches a spherical cloud layer to **256 km**,
independently of terrain's 2–40 km render range. Earth curvature determines layer
intersections and which cloud heights still receive sunlight. Opaque scene depth
stops clouds at terrain; the sky's empty far-plane depth is not treated as terrain.
Cloud compositing occurs after the Moon, stars and Milky Way, with their proxy
meshes excluded from the opaque-depth limit.

Each type has its own height, thickness, density and shape profile. A bundled,
tileable 64³ fBM/Worley noise volume supplies coherent structure and erosion.
Regenerate it with `python3 tool/build_cloud_noise.py` (NumPy and Pillow are
**development-only** requirements). No noise library or runtime download is added.

Performance/Balanced/High use at most 24/48/64 near-view steps. Distant layers
reduce the count toward 35% (minimum eight); quadratic spacing favors nearby
samples. Fine erosion and extra density/self-shadow samples fade out over
12–48 km. Far clouds retain coarse structure and atmospheric haze.

Sunrise/sunset shading includes elevated cloud illumination, warm lit regions,
cool violet shade and distance haze. Daylight cloud fill fades out by −6° solar
altitude. Deep-night clouds receive only a very small night fill and dim,
phase-squared, altitude-dependent moonlight; day-exposure images can correctly
show almost black silhouettes. Long-exposure/manual settings can brighten them.

## Limits and checks

This is illustrative rendering, **not a forecast, measured cloud field or
calibrated cloud photometry**. Cloud placement is static, with no wind or weather
evolution. Terrain lighting uses average cloud attenuation, not spatial cloud
shadow maps. The baked sky environment does not include the cloud geometry.
There is no water-content simulation, precipitation physics or exact multiple
scattering. Noise and finite view/light sampling limit close-up detail.

`test/cloud_settings_test.dart` covers settings, validation, legacy plans and
large-text controls. `integration_test/clouds_test.dart` checks actual GPU output
for all types, deterministic randomization, zero amount, opaque occlusion,
horizon clouds beyond 64 km, sunrise/sunset and dark moonlit/moonless nights.
`integration_test/cloud_photo_test.dart` exports a reproducible Yosemite camera
photo with its full metadata to `build/validation/cloud-photo/` on Linux.

The optional AI comparison is an external image-model operation, not an app
feature. Its prompt must include the raw image and metadata, preserve attribution,
and label the result as an interpretation; image-provider credentials are required.
