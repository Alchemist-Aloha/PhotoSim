"""Independent rigid-sky fixtures. Development only: pyerfa 2.0.1.5 + numpy.

Run with PYTHONPATH=build/validation/sky_reference_deps python3 ... after
uv pip install --python /usr/bin/python3 --target build/validation/sky_reference_deps --no-deps pyerfa==2.0.1.5.
These check coordinate transforms, not stellar proper motion or aberration.
"""
import json
import math
from datetime import datetime, timezone
from pathlib import Path
import erfa
import numpy as np

CASES = [
    ("Yosemite Galactic center", "2026-06-21T09:00:00Z", 37.744, -119.59, 266.4051, -28.936175, 69.184),
    ("Yosemite Vega", "2026-06-21T09:00:00Z", 37.744, -119.59, 279.2347, 38.7837, 69.184),
    ("Sydney Sirius", "2026-01-01T12:00:00Z", -33.86, 151.21, 101.2872, -16.7161, 69.184),
    ("London Polaris 1900", "1900-01-01T00:00:00Z", 51.5, 0, 37.9546, 89.2641, -2.79),
    ("Equator 2100", "2100-06-01T12:00:00Z", 0, 0, 0, 0, 200),
    ("North pole 2000", "2000-01-01T12:00:00Z", 90, 180, 266.4051, -28.936175, 63.8),
]
rows = []
for name, timestamp, lat, lon, ra, dec, delta_t in CASES:
    jd = datetime.fromisoformat(timestamp).timestamp() / 86400 + 2440587.5
    tt = jd + delta_t / 86400
    alpha, delta, phi = np.radians([ra, dec, lat])
    equatorial = erfa.pnm80(2400000.5, tt - 2400000.5) @ np.array([
        math.cos(delta) * math.cos(alpha), math.cos(delta) * math.sin(alpha), math.sin(delta)])
    theta = erfa.gmst82(2400000.5, jd - 2400000.5) + erfa.eqeq94(2400000.5, tt - 2400000.5) + math.radians(lon)
    x, y, z = equatorial
    meridian = x * math.cos(theta) + y * math.sin(theta)
    east = -x * math.sin(theta) + y * math.cos(theta)
    north = z * math.cos(phi) - meridian * math.sin(phi)
    up = z * math.sin(phi) + meridian * math.cos(phi)
    rows.append(dict(name=name, timestamp=timestamp, latitude=lat, longitude=lon, ra=ra, dec=dec,
                     deltaT=delta_t, direction=[east, up, -north],
                     azimuth=math.degrees(math.atan2(east, north)) % 360,
                     altitude=math.degrees(math.asin(up))))
output = Path(__file__).resolve().parents[1] / "test/fixtures/sky_rotation.json"
output.write_text(json.dumps(dict(source="ERFA/SOFA pyerfa 2.0.1.5; IAU 1976 precession + IAU 1980 nutation; UTC=UT1", cases=rows), indent=2) + "\n")
print(f"Recorded {len(rows)} independent sky rotation fixtures")
