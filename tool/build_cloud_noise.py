"""Build the tiled 64³ fBM-Worley cloud-noise atlas (NumPy + Pillow, dev only)."""
from itertools import product
from pathlib import Path
import numpy as np
from PIL import Image


def value_noise(size, frequency, rng):
    z, y, x = np.indices((size, size, size), dtype=np.float32) * frequency / size
    ix, iy, iz = x.astype(int), y.astype(int), z.astype(int)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = [f * f * f * (f * (f * 6 - 15) + 10) for f in (fx, fy, fz)]
    grid = rng.random((frequency, frequency, frequency)).astype(np.float32)
    result = np.zeros_like(x)
    for dz, dy, dx in product(range(2), repeat=3):
        weight = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
        result += grid[(iz + dz) % frequency, (iy + dy) % frequency, (ix + dx) % frequency] * weight
    return result


def worley(size, frequency, rng):
    z, y, x = np.indices((size, size, size), dtype=np.float32) * frequency / size
    ix, iy, iz = x.astype(int), y.astype(int), z.astype(int)
    fx, fy, fz = x - ix, y - iy, z - iz
    points = rng.random((frequency, frequency, frequency, 3)).astype(np.float32)
    distance = np.full_like(x, 100)
    for dz, dy, dx in product(range(-1, 2), repeat=3):
        point = points[(iz + dz) % frequency, (iy + dy) % frequency, (ix + dx) % frequency]
        squared = (dx + point[..., 0] - fx) ** 2 + (dy + point[..., 1] - fy) ** 2 + (dz + point[..., 2] - fz) ** 2
        np.minimum(distance, squared, out=distance)
    return np.clip(1 - np.sqrt(distance) / 1.5, 0, 1)


def build_atlas():
    size = 64
    rng = np.random.default_rng(17374)
    fbm = sum(weight * value_noise(size, frequency, rng) for frequency, weight in [(4, .625), (8, .25), (16, .125)])
    base = fbm * .65 + worley(size, 4, rng) * .35
    volume = np.stack([base, worley(size, 8, rng), worley(size, 16, rng), np.ones_like(base)], axis=-1)
    assert volume.shape == (64, 64, 64, 4) and np.isfinite(volume).all()
    assert 0 <= volume.min() <= volume.max() <= 1 and base.std() > .05
    volume = np.rint(volume * 255).astype(np.uint8)
    atlas = np.empty((528, 528, 4), dtype=np.uint8)
    for z in range(64):
        tile = np.pad(volume[z], ((1, 1), (1, 1), (0, 0)), mode='wrap')
        assert np.array_equal(tile[0, 1:-1], volume[z, -1])
        row, col = divmod(z, 8)
        atlas[row * 66:(row + 1) * 66, col * 66:(col + 1) * 66] = tile
    return atlas


if __name__ == '__main__':
    # Small deterministic checks catch indexing/seed regressions before rebuilding the asset.
    for noise in (value_noise, worley):
        assert np.array_equal(noise(8, 2, np.random.default_rng(7)), noise(8, 2, np.random.default_rng(7)))
    out = Path(__file__).resolve().parents[1] / 'assets/atmosphere/cloud_noise.png'
    Image.fromarray(build_atlas()).save(out, optimize=True)
    print(f'Wrote {out} ({out.stat().st_size:,} bytes)')
