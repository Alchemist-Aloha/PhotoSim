"""Regenerate bundled sky data. Development only: Python 3 + Pillow.

Source: D3-Celestial (BSD-3-Clause), pinned below. No runtime downloads.
"""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

COMMIT = "7e720a3de062059d4c5400a379146a601d9010e0"
BASE = f"https://raw.githubusercontent.com/ofrohn/d3-celestial/{COMMIT}/"
OUT = Path(__file__).resolve().parents[1] / "assets/sky"
OUT.mkdir(parents=True, exist_ok=True)
MILKY_WAY_NOTICE = b"""
milky_way.png is derived from the Deep Star Maps 2020 Milky Way layer.
Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio.
Gaia DR2: ESA/Gaia/DPAC. https://svs.gsfc.nasa.gov/4851 (NASA media guidelines:
https://www.nasa.gov/multimedia/guidelines/index.html)
Changes: tone-mapped to 8-bit alpha, colour smoothed, mirrored to the app's RA grid.
"""


def download(path):
    with urlopen(BASE + path, timeout=30) as response:
        data = response.read(2 * 1024 * 1024 + 1)
    assert len(data) <= 2 * 1024 * 1024, "Unexpected asset size"
    return data


stars_raw = download("data/stars.6.json")
stars = json.loads(stars_raw)["features"]
rows = [[s["id"], *s["geometry"]["coordinates"], s["properties"]["mag"]]
        for s in stars]
assert len(rows) == 5044
assert all(-180 <= r[1] <= 180 and -90 <= r[2] <= 90 and r[3] <= 6 for r in rows)
assert next(r for r in rows if r[0] == 32349)[3] == -1.44  # Sirius
(OUT / "stars.json").write_text(json.dumps(rows, separators=(",", ":")) + "\n")

names_raw = download("data/constellations.json")
lines_raw = download("data/constellations.lines.json")
names = json.loads(names_raw)["features"]
lines = json.loads(lines_raw)["features"]
assert len(names) == len(lines) == 89  # Serpens has two separately labeled halves.
assert all(n["id"] == line["id"] for n, line in zip(names, lines))
constellations = [[n["properties"]["name"], *n["geometry"]["coordinates"],
                   line["geometry"]["coordinates"]] for n, line in zip(names, lines)]
assert len({n["id"] for n in names}) == 88
(OUT / "constellations.json").write_text(json.dumps(constellations, separators=(",", ":")) + "\n")
(OUT / "LICENSE.txt").write_bytes(download("LICENSE") + MILKY_WAY_NOTICE)
# The Milky Way raster and its provenance keys come from build_milky_way.py.
previous = json.loads((OUT / "provenance.json").read_text())
milky_way = {k: v for k, v in previous.items() if k.startswith("milkyWay")}
(OUT / "provenance.json").write_text(json.dumps({**milky_way, **{
    "commit": COMMIT,
    "starsSource": BASE + "data/stars.6.json",
    "starsSha256": hashlib.sha256(stars_raw).hexdigest(),
    "constellationNamesSource": BASE + "data/constellations.json",
    "constellationNamesSha256": hashlib.sha256(names_raw).hexdigest(),
    "constellationLinesSource": BASE + "data/constellations.lines.json",
    "constellationLinesSha256": hashlib.sha256(lines_raw).hexdigest(),
    "constellations": "IAU names and D3-Celestial illustrative connecting figures (not IAU boundaries)",
    "epoch": "J2000.0",
    "stars": "XHIP (Anderson & Francis, 2012), via D3-Celestial",
    "changes": "Compact star and constellation rows",
    "license": "D3-Celestial BSD-3-Clause; Milky Way NASA SVS / ESA Gaia credit; see LICENSE.txt",
}}, indent=2) + "\n")
print(f"Bundled {len(rows)} stars")
