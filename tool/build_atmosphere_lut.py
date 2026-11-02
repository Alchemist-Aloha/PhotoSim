"""Bake Earth multiple scattering. Development only: Python 3, NumPy, Pillow.

Isotropic higher-order closure from Hillaire (2020), section 5:
https://sebh.github.io/publications/egsr2020.pdf
Stores mean incident sky radiance per unit solar irradiance, sqrt-encoded RGB.
Run from any directory; constants must match core/sunlight.dart and sky.fmat.
"""
from pathlib import Path

import numpy as np
from PIL import Image

RADIUS, TOP = 6371.0, 6451.0
RAYLEIGH = np.array([0.0058, 0.0135, 0.0331])
MIE = np.array([0.69, 0.73, 0.81]) * (2 * 0.0005 * 0.434)
OZONE = np.array([0.000650, 0.001881, 0.000085])
G = 0.76
WIDTH, HEIGHT = 64, 32


def density(p):
    height = np.maximum(np.linalg.norm(p, axis=-1) - RADIUS, 0)
    return np.stack((np.exp(-height / 8.4), np.exp(-height / 1.25),
                     np.maximum(0, 1 - np.abs(height - 25) / 15)), axis=-1)


def extinction(column):
    return column[..., 0, None] * RAYLEIGH + column[..., 1, None] * MIE + column[..., 2, None] * OZONE


def exit_distance(p, direction):
    b = np.sum(p * direction, axis=-1)
    return -b + np.sqrt(np.maximum(b * b + TOP * TOP - np.sum(p * p, axis=-1), 0))


def light_transmission(p, sun, steps=16):
    b = np.sum(p * sun, axis=-1)
    shadow = (b < 0) & (np.sum(p * p, axis=-1) - b * b < RADIUS * RADIUS)
    distance = exit_distance(p, sun)
    column = np.zeros((*distance.shape, 3))
    previous = np.zeros_like(distance)
    for i in range(steps):
        next_distance = distance * ((i + 1) / steps) ** 2
        column += density(p + sun * ((previous + next_distance) * 0.5)[..., None]) * (next_distance - previous)[..., None]
        previous = next_distance
    return np.where(shadow[..., None], 0, np.exp(-extinction(column)))


def bake(width=WIDTH, height=HEIGHT, directions=64, steps=24):
    # Equal-solid-angle Fibonacci quadrature over the entire sphere.
    index = np.arange(directions) + 0.5
    y = 1 - 2 * index / directions
    phi = index * np.pi * (3 - np.sqrt(5))
    rays = np.stack((np.sqrt(1 - y * y) * np.cos(phi), y,
                     np.sqrt(1 - y * y) * np.sin(phi)), axis=-1)[None, ...]
    coordinate = np.linspace(-1, 1, width)
    mu = np.sign(coordinate) * coordinate ** 2
    sun = np.stack((np.sqrt(1 - mu * mu), mu, np.zeros(width)), axis=-1)[:, None, :]
    cosine = np.sum(rays * sun, axis=-1)
    phase_r = 3 * (1 + cosine * cosine) / (16 * np.pi)
    phase_m = (1 - G * G) / (4 * np.pi * (1 + G * G - 2 * G * cosine) ** 1.5)
    output = np.zeros((height, width, 3))
    for row in range(height):
        altitude = max(0.002, 80 * (row / (height - 1)) ** 2)
        origin = np.array([0.0, RADIUS + altitude, 0.0])
        b = np.sum(origin * rays, axis=-1)
        discriminant = b * b + RADIUS * RADIUS - np.sum(origin * origin)
        ground = (b < 0) & (discriminant >= 0)
        ground_distance = -b - np.sqrt(np.maximum(discriminant, 0))
        distance = np.where(ground, ground_distance, exit_distance(origin, rays))
        optical = np.zeros((width, directions, 3))
        radiance = np.zeros_like(optical)
        feedback = np.zeros_like(optical)
        previous = np.zeros_like(distance)
        for i in range(steps):
            next_distance = distance * ((i + 1) / steps) ** 2
            ds = (next_distance - previous)[..., None]
            p = origin + rays * ((previous + next_distance) * 0.5)[..., None]
            column = density(p) * ds
            tau = extinction(column)
            segment = -np.expm1(-tau) / np.maximum(tau, 1e-12)
            view = np.exp(-extinction(optical)) * segment
            scattering = column[..., 0, None] * RAYLEIGH + column[..., 1, None] * MIE
            source = column[..., 0, None] * RAYLEIGH * phase_r[..., None] + column[..., 1, None] * MIE * phase_m[..., None]
            radiance += view * light_transmission(p, sun) * source
            feedback += view * scattering
            optical += column
            previous = next_distance
        # Lambertian ground bounce, neutral Earth-average albedo 0.1.
        p = origin + rays * distance[..., None]
        up = p / np.linalg.norm(p, axis=-1)[..., None]
        bounce = 0.1 / np.pi * np.maximum(np.sum(up * sun, axis=-1), 0)
        radiance += np.exp(-extinction(optical)) * light_transmission(p + up * 0.002, sun) * (bounce * ground)[..., None]
        mean_feedback = np.mean(feedback, axis=1)
        assert np.all(mean_feedback < 1), "Multiple scattering must conserve energy"
        output[row] = np.mean(radiance, axis=1) / (1 - mean_feedback)
    assert np.all(np.isfinite(output)) and np.all(output >= 0)
    assert np.max(output) < 1, "LUT sqrt encoding would clip"
    # At ground level, indirect daylight is blue and disappears deep at night.
    assert output[0, -1, 2] > output[0, -1, 0]
    assert np.max(output[0, 0]) < 1e-8
    return output


if __name__ == '__main__':
    result = bake()
    target = Path(__file__).resolve().parents[1] / 'assets/atmosphere/multiple_scattering.png'
    Image.fromarray(np.rint(np.sqrt(result) * 255).astype(np.uint8)).save(target)
    print(f'Wrote {target}: {WIDTH}x{HEIGHT}, radiance range {result.min():.6g}–{result.max():.6g}')
