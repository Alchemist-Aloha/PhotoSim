"""Regenerate assets/sky/milky_way.png. Development only: Python 3, NumPy, Pillow, OpenEXR.

Source: NASA/Goddard SVS Deep Star Maps 2020 Milky Way layer (built from Gaia DR2,
ESA/Gaia/DPAC), a linear half-float plate carree in J2000 RA/Dec centred on 0h
with RA increasing to the left. Hipparcos/Tycho stars are already omitted, so the
catalog stars drawn separately are not doubled. Output is the RA/Dec grid the
sphere mesh uses: u spans RA -180..180, v spans Dec +90..-90.
"""
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from urllib.request import urlopen

import numpy as np
import OpenEXR
from PIL import Image

SOURCE = "https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/milkyway_2020_4k.exr"
SHA256 = "2eb802d6e68d170b410f766c7fec07f7518619f6b6708fdc81e9302d93e74fdb"
OUT = Path(__file__).resolve().parents[1] / "assets/sky"
WIDTH, HEIGHT = 4096, 2048


def blur(values, sigma):
    taps = np.arange(-3 * int(sigma), 3 * int(sigma) + 1)
    kernel = np.exp(-taps ** 2 / (2 * sigma * sigma))
    kernel /= kernel.sum()
    rows = sum(k * np.roll(values, t, axis=1) for k, t in zip(kernel, taps))  # RA wraps
    padded = np.pad(rows, ((taps[-1], taps[-1]), (0, 0)), mode="edge")
    return sum(k * padded[taps[-1] + t:taps[-1] + t + values.shape[0]] for k, t in zip(kernel, taps))


def build(radiance):
    # Source RA increases to the left from +180 at x=0; the mesh wants -180 at u=0.
    radiance = np.maximum(radiance[:, ::-1].astype(np.float64), 0)
    assert radiance.shape == (HEIGHT, WIDTH, 3), radiance.shape
    luminance = radiance @ [0.2126, 0.7152, 0.0722]
    # Integrated starlight off the band is fainter than natural airglow and reads as
    # haze across the whole frame; subtract it so the band stands out like a photo.
    floor, peak = np.percentile(luminance, [70, 99.9])
    # Fade in over 4x above the floor (log-smoothstep), so the band ends softly on the
    # black night sky; the ^0.75 body matches the stretch a night photo gets.
    fade = np.clip(np.log(np.maximum(luminance, 1e-12) / floor) / np.log(4), 0, 1)
    alpha = np.clip(luminance / peak, 0, 1) ** 0.75 * fade * fade * (3 - 2 * fade)
    # Faint Gaia stars leave shot-noise grain in the halo (and bloat the PNG): smooth
    # the low-signal outskirts, keep the band and its dust lanes sharp.
    smooth = blur(alpha, 3.0)
    blend = np.clip((alpha - 0.15) / 0.25, 0, 1)
    alpha = smooth + (alpha - smooth) * blend * blend * (3 - 2 * blend)
    # A broad skirt, as scattered light gives a photo, so the tone curve's toe does not
    # crush the fade into an edge.
    alpha = np.rint(np.clip(alpha + 0.3 * blur(alpha, 12.0), 0, 1) * 255) / 255
    # Colour varies slowly; per-pixel chroma is noise the eye cannot resolve.
    chroma = np.dstack([blur(radiance[..., i], 4.0) for i in range(3)])
    chroma /= np.maximum(chroma.max(axis=-1, keepdims=True), 1e-9)
    # The faint fringe's colour is halo noise (it reads green); fade it to neutral.
    grey = np.clip(alpha / 0.15, 0, 1)[..., None]
    chroma = 1 - grey + chroma * grey
    # Source colour is linear sRGB with a D65 white, so the in-app white balance
    # setting (6500 K = neutral) shifts it like a camera. The unlit shader decodes
    # texture RGB as sRGB; encode it or the warm core over-saturates.
    chroma = np.where(chroma <= 0.0031308, 12.92 * chroma, 1.055 * chroma ** (1 / 2.4) - 0.055)
    rgba = np.dstack((chroma * (alpha > 0)[..., None], alpha))
    return Image.fromarray(np.rint(rgba * 255).astype(np.uint8), "RGBA"), alpha


def pixel(ra, dec):
    return int((90 - dec) / 180 * HEIGHT), int(((ra + 180) % 360) / 360 * WIDTH)


if __name__ == "__main__":
    # Optional argument: an already-downloaded copy of SOURCE.
    if len(sys.argv) > 1:
        data = Path(sys.argv[1]).read_bytes()
    else:
        with urlopen(SOURCE, timeout=300) as response:
            data = response.read(64 * 1024 * 1024 + 1)
    assert hashlib.sha256(data).hexdigest() == SHA256, "Unexpected Milky Way map"
    with tempfile.NamedTemporaryFile(suffix=".exr") as exr:
        exr.write(data)
        exr.flush()
        with OpenEXR.File(exr.name) as file:
            image, alpha = build(file.channels()["RGB"].pixels)
    # Sgr A* is lit (dimly: it sits behind dust) and the north galactic pole is dark.
    assert alpha[pixel(266.4168 - 360, -29.0078)] > 0.04 and alpha[pixel(192.8595 - 360, 27.1283)] == 0
    image.save(OUT / "milky_way.png", optimize=True)
    provenance = json.loads((OUT / "provenance.json").read_text())
    provenance.update({
        "milkyWaySource": SOURCE,
        "milkyWaySha256": SHA256,
        "milkyWay": "NASA/Goddard Space Flight Center Scientific Visualization Studio, "
                    "Deep Star Maps 2020 (Gaia DR2: ESA/Gaia/DPAC), https://svs.gsfc.nasa.gov/4851",
        "milkyWayChanges": "Mirrored to RA -180..180, 70th-percentile floor faded in over 4x; alpha is "
                           "luminance^0.75 normalised to the 99.9th percentile, RGB is smoothed source chromaticity, sRGB-encoded",
    })
    (OUT / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Wrote {OUT / 'milky_way.png'}: {WIDTH}x{HEIGHT}")
