"""Physical/convergence checks for the multiple-scattering bake."""
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from build_atmosphere_lut import bake, density, extinction, RADIUS


class AtmosphereLutTest(unittest.TestCase):
    def test_ozone_is_absorption_only_in_the_stratosphere(self):
        p = np.array([[0, RADIUS + h, 0] for h in (0, 10, 25, 40, 80)])
        np.testing.assert_allclose(density(p)[:, 2], [0, 0, 1, 0, 0])
        ozone = extinction(np.array([0, 0, 15]))
        self.assertGreater(ozone[1], ozone[0])
        self.assertGreater(ozone[0], ozone[2])

    def test_bake_converges_and_matches_bundled_daylight(self):
        coarse = bake(width=9, height=2)
        reference = bake(width=9, height=2, directions=128, steps=40)
        self.assertLess(np.max(np.abs(coarse - reference)), reference.max() * 0.05)
        self.assertGreater(reference[0, -1, 2], reference[0, -1, 0])
        np.testing.assert_array_equal(reference[0, 0], 0)
        target = Path(__file__).resolve().parents[1] / 'assets/atmosphere/multiple_scattering.png'
        image = np.asarray(Image.open(target)) / 255.0
        self.assertEqual(image.shape, (32, 64, 3))
        np.testing.assert_allclose(image[0, -1] ** 2, reference[0, -1], rtol=0.05)
        np.testing.assert_array_equal(image[0, 0], 0)


if __name__ == '__main__':
    unittest.main()
