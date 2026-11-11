"""Regenerate assets/sky/milky_way.png. Development only: Python 3, NumPy, Pillow.

Source: ESO/S. Brunier all-sky panorama (CC BY 4.0), a plate carree in galactic
coordinates centred on l=0 with l increasing to the left. Bright stars are drawn
separately from the catalog, so they are removed here; the diffuse glow, dust
lanes and faint unresolved stars remain. Output is the RA/Dec grid the sphere
mesh uses: u spans RA -180..180, v spans Dec +90..-90.
"""
import hashlib
import io
import json
from pathlib import Path
from urllib.request import urlopen

import numpy as np
from PIL import Image, ImageFilter

SOURCE = "https://cdn.eso.org/images/large/eso0932a.jpg"
SHA256 = "60400c92c54b7c1bd12299c69e83b16e5b6256e7dabacc478c021758ecd28179"
OUT = Path(__file__).resolve().parents[1] / "assets/sky"
WIDTH, HEIGHT = 2048, 1024
CONTRAST, DESATURATE = 1.6, 0.35
# J2000 equatorial -> galactic rotation (Hipparcos, ESA 1997, vol. 1 sec. 1.5.3).
EQ_TO_GAL = np.array([
    [-0.0548755604, -0.8734370902, -0.4838350155],
    [+0.4941094279, -0.4448296300, +0.7469822445],
    [-0.8676661490, -0.1980763734, +0.4559837762],
])


def remove_stars(image):
    # Grey opening (min then max) at twice the output resolution removes features
    # under ~0.45°, i.e. point stars, but keeps the extended glow and dark lanes;
    # the box downsample then hides the square structuring element.
    opened = image.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    return opened.filter(ImageFilter.GaussianBlur(1.0)).resize((WIDTH, HEIGHT), Image.Resampling.BOX)


def galactic_grid(width, height):
    ra = np.radians(-180 + (np.arange(width) + 0.5) / width * 360)
    dec = np.radians(90 - (np.arange(height) + 0.5) / height * 180)
    ra, dec = np.meshgrid(ra, dec)
    eq = np.stack((np.cos(dec) * np.cos(ra), np.cos(dec) * np.sin(ra), np.sin(dec)), axis=-1)
    gal = eq @ EQ_TO_GAL.T
    lon = np.degrees(np.arctan2(gal[..., 1], gal[..., 0]))
    lat = np.degrees(np.arcsin(np.clip(gal[..., 2], -1, 1)))
    return lon, lat


def sample(source, lon, lat):
    h, w = source.shape[:2]
    x = (0.5 - lon / 360) * w - 0.5
    y = (90 - lat) / 180 * h - 0.5
    x0 = np.floor(x).astype(int)
    y0 = np.clip(np.floor(y).astype(int), 0, h - 2)
    fx, fy = (x - x0)[..., None], np.clip(y - y0, 0, 1)[..., None]
    x0, x1 = x0 % w, (x0 + 1) % w
    top = source[y0, x0] * (1 - fx) + source[y0, x1] * fx
    bottom = source[y0 + 1, x0] * (1 - fx) + source[y0 + 1, x1] * fx
    return top * (1 - fy) + bottom * fy


def blur(values, sigma):
    taps = np.arange(-3 * int(sigma), 3 * int(sigma) + 1)
    kernel = np.exp(-taps ** 2 / (2 * sigma * sigma))
    kernel /= kernel.sum()
    rows = sum(k * np.roll(values, t, axis=1) for k, t in zip(kernel, taps))  # RA wraps
    padded = np.pad(rows, ((taps[-1], taps[-1]), (0, 0)), mode="edge")
    return sum(k * padded[taps[-1] + t:taps[-1] + t + values.shape[0]] for k, t in zip(kernel, taps))


def build(panorama):
    starless = remove_stars(panorama.convert("RGB").resize((WIDTH * 2, HEIGHT * 2), Image.Resampling.BOX))
    display = np.asarray(starless, dtype=np.float64) / 255
    lon, lat = galactic_grid(*starless.size)
    # Subtract the photograph's sky background, measured near the galactic poles.
    pole_rows = np.r_[0:HEIGHT // 12, HEIGHT - HEIGHT // 12:HEIGHT]
    display = np.maximum(display - np.median(display[pole_rows].reshape(-1, 3), axis=0), 0)
    radiance = sample(display, lon, lat)
    luminance = radiance @ [0.2126, 0.7152, 0.0722]
    # The panorama is already stretched; a full sRGB decode crushes the faint
    # unresolved-star glow into blotches. A milder power keeps the band continuous
    # while the core and dust lanes keep their contrast.
    level = np.clip(luminance / np.percentile(luminance, 99.9), 0, 1)
    # Low-signal outskirts are grainy after star removal: smooth them, keep the band sharp.
    smooth = blur(level, 3.0)
    blend = np.clip((level - 0.05) / 0.25, 0, 1)
    level = smooth + (level - smooth) * blend * blend * (3 - 2 * blend)
    # Power for core/lane contrast plus a linear toe so the faint halo fades gradually.
    alpha = (level ** CONTRAST + 0.3 * level) / 1.3
    # Unresolved disk stars give a broad halo that background subtraction removed.
    alpha = np.clip(alpha + 0.3 * blur(alpha, 12.0), 0, 1)
    # Wide soft knee on the smoothed glow: the band fades out, with no contour.
    knee = np.clip((blur(alpha, 4.0) - 0.5 / 255) / (24 / 255), 0, 1)
    alpha *= knee * knee * (3 - 2 * knee)
    chroma = radiance / np.maximum(radiance.max(axis=-1, keepdims=True), 1e-9)
    # Faint pixels' colour is mostly noise, and the eye sees the band near-neutral.
    chroma = chroma * (1 - DESATURATE) + (chroma @ [0.2126, 0.7152, 0.0722])[..., None] * DESATURATE
    chroma /= np.maximum(chroma.max(axis=-1, keepdims=True), 1e-9)
    rgba = np.dstack((chroma, alpha))
    return Image.fromarray(np.rint(rgba * 255).astype(np.uint8), "RGBA"), (lon, lat, alpha)


if __name__ == "__main__":
    with urlopen(SOURCE, timeout=120) as response:
        data = response.read(16 * 1024 * 1024 + 1)
    assert hashlib.sha256(data).hexdigest() == SHA256, "Unexpected panorama"
    image, (lon, lat, alpha) = build(Image.open(io.BytesIO(data)))
    # The galactic centre is lit and the north galactic pole is dark.
    centre = np.unravel_index(np.argmin(lon ** 2 + lat ** 2), lon.shape)
    pole = np.unravel_index(np.argmax(lat), lat.shape)
    assert alpha[centre] > 0.1 and alpha[pole] == 0
    image.save(OUT / "milky_way.png", optimize=True)
    provenance = json.loads((OUT / "provenance.json").read_text())
    provenance.update({
        "milkyWaySource": SOURCE,
        "milkyWaySha256": SHA256,
        "milkyWay": "ESO/S. Brunier all-sky panorama (CC BY 4.0), "
                    "https://www.eso.org/public/images/eso0932a/",
        "milkyWayChanges": "Downsampled, point stars removed by grey opening, sky "
                           "background subtracted, reprojected from galactic to J2000 "
                           "RA/Dec; alpha is (luminance^1.6 + 0.3 luminance) / 1.3, RGB is 35%-desaturated chromaticity",
    })
    (OUT / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Wrote {OUT / 'milky_way.png'}: {WIDTH}x{HEIGHT}")
