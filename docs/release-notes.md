# Release notes

## 1.4.0

Sky and water rendering rework, plus place search.

### Clouds

- Clouds are now two soft, wind-driven procedural decks with separate low and
  high layers, replacing the repeating 3D noise volume. The same noise pattern no
  longer stamps every ~14 km of sky.
- Cumulus, stratocumulus, stratus, cirrus and cumulonimbus keep their own height,
  thickness and form. Amount still controls coverage; type, amount and seed still
  survive save and session recovery.
- Clouds drift continuously and keep moving past 100 seconds of open time. The
  previous wall-clock animation jumped every 100 seconds; animation now uses a
  monotonic clock and can be frozen deterministically in tests.
- Sunrise and sunset add warm underlighting, forward glow near the Sun, cool
  shaded haze and dark moonlit night clouds. Elevated decks stay lit briefly after
  ground sunset.
- Water reflects the same cloud decks, so reflected weather matches the sky.

### Water

- Ripples use three moving noise bands with fading of unresolved detail, producing
  a wind-driven glitter path toward the Sun.
- Reflections now use Fresnel mixing of the reflected sky and clouds with deep
  water color, plus horizon mist. Previously water was lit mostly as a rough
  surface with sky-only reflections.
- Sun glitter is drawn analytically, so the low-resolution sky environment can
  still produce a compact highlight instead of a blurred patch.

### Place search

- Search for a town, landmark or address from the map using the free, keyless
  Photon API. Choosing a result centers the map without changing the current
  composition; search terms are the only data sent.

### Compatibility and limits

- No plan or settings migration is required. Visual appearance of clouds and water
  changes because the rendering model changed; type, amount and seed are unchanged.
- Rendering remains illustrative, not forecast or calibrated photometry. There is
  no weather evolution, rain simulation, cloud shadow map or water simulation.
- Place search needs internet access; the public Photon demo may throttle use.

### Validation

- `flutter analyze` clean; 348 unit and widget tests pass.
- Linux GPU integration tests cover all cloud types, deterministic seed and
  phase, terrain occlusion, high-observer decks, horizon range, sunrise/sunset and
  moonlit nights; water motion, reflection, 100-second continuity and calm water;
  sky color and idle frame pacing.
