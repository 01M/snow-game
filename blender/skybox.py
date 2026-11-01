# Небо для карты «Дом»: синий час, луна, звёзды, горные хребты за городком. Запуск:
#   blender --background --python skybox.py -- <папка вывода> [размер грани]
# Это не рендер, а расчёт картинки по направлению взгляда, поэтому швы граней совпадают точно.
# Грани: sky_ft (-Z игры), sky_bk (+Z), sky_rt (+X), sky_lf (-X), sky_up, sky_dn.
import math
import os
import sys

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.dirname(os.path.abspath(__file__))
SIZE = int(argv[1]) if len(argv) > 1 else 1024
# Roblox сильно затемняет небо в сумерки, поэтому картинка ярче, чем должна выглядеть в игре
GAIN = float(argv[2]) if len(argv) > 2 else 1.0

MOON_DIR = np.array([0.42, 0.46, -0.78])
MOON_DIR = MOON_DIR / np.linalg.norm(MOON_DIR)
GLOW_DIR = np.array([0.94, 0.0, 0.34])  # закатная сторона неба

ZENITH = np.array([0.16, 0.24, 0.52])
MIDDLE = np.array([0.34, 0.47, 0.78])
HORIZON = np.array([0.72, 0.74, 0.88])
SUNSET = np.array([1.0, 0.68, 0.5])
FAR_RANGE = np.array([0.27, 0.34, 0.54])
NEAR_RANGE = np.array([0.24, 0.31, 0.47])
SNOW_RANGE = np.array([0.74, 0.80, 0.93])


def face_dirs(forward, right, up, n):
    a = (np.arange(n) + 0.5) / n * 2 - 1
    u, v = np.meshgrid(a, a)
    d = forward[None, None, :] + u[:, :, None] * right[None, None, :] - v[:, :, None] * up[None, None, :]
    return d / np.linalg.norm(d, axis=2, keepdims=True)


def hash3(i, j, k):
    x = np.sin(i * 127.1 + j * 311.7 + k * 74.7) * 43758.5453
    return x - np.floor(x)


def value_noise(p):
    i = np.floor(p)
    f = p - i
    f = f * f * (3 - 2 * f)
    ix, iy, iz = i[..., 0], i[..., 1], i[..., 2]
    fx, fy, fz = f[..., 0], f[..., 1], f[..., 2]
    c000, c100 = hash3(ix, iy, iz), hash3(ix + 1, iy, iz)
    c010, c110 = hash3(ix, iy + 1, iz), hash3(ix + 1, iy + 1, iz)
    c001, c101 = hash3(ix, iy, iz + 1), hash3(ix + 1, iy, iz + 1)
    c011, c111 = hash3(ix, iy + 1, iz + 1), hash3(ix + 1, iy + 1, iz + 1)
    x00 = c000 * (1 - fx) + c100 * fx
    x10 = c010 * (1 - fx) + c110 * fx
    x01 = c001 * (1 - fx) + c101 * fx
    x11 = c011 * (1 - fx) + c111 * fx
    y0 = x00 * (1 - fy) + x10 * fy
    y1 = x01 * (1 - fy) + x11 * fy
    return y0 * (1 - fz) + y1 * fz


def fbm(p, octaves=5):
    total, amp, norm = 0.0, 1.0, 0.0
    for _ in range(octaves):
        total = total + value_noise(p) * amp
        norm += amp
        p = p * 2.03 + 11.3
        amp *= 0.5
    return total / norm


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def ridge(az, scale, seed, octaves=6):
    """Высота хребта (0..1) по азимуту: на окружности, поэтому кольцо замыкается."""
    p = np.stack([np.cos(az) * scale + seed, np.sin(az) * scale + seed * 0.7, np.full_like(az, seed * 1.3)], axis=-1)
    n = fbm(p, octaves)
    return 1 - np.abs(n * 2 - 1)


def paint(d):
    el = np.degrees(np.arcsin(np.clip(d[..., 1], -1, 1)))
    az = np.arctan2(d[..., 2], d[..., 0])
    t = np.clip(el / 90, 0, 1)
    # Градиент: от бледного горизонта через синий к тёмному зениту
    col = HORIZON[None, None, :] * (1 - smoothstep(0, 16, el))[..., None]
    col = col + MIDDLE[None, None, :] * (smoothstep(0, 16, el) * (1 - smoothstep(14, 60, el)))[..., None]
    col = col + ZENITH[None, None, :] * smoothstep(14, 60, el)[..., None]
    # Закатная полоса с одной стороны
    glow = np.clip((d * GLOW_DIR).sum(axis=2), 0, 1) ** 3 * (1 - smoothstep(0, 22, el))
    col = col * (1 - glow[..., None] * 0.75) + SUNSET[None, None, :] * glow[..., None] * 0.75
    # Звёзды
    grid = np.floor(d * 520)
    star = hash3(grid[..., 0], grid[..., 1], grid[..., 2])
    bright = hash3(grid[..., 1], grid[..., 2], grid[..., 0])
    fade = smoothstep(18, 40, el)
    stars = (star > 0.9962) * (0.3 + 0.7 * bright ** 2) * fade
    col = col + stars[..., None] * 0.95
    # Лёгкие вытянутые облака, выше 33° их нет, поэтому поворот верхней грани не заметен
    p = np.stack([d[..., 0] * 2.2, d[..., 1] * 7.5, d[..., 2] * 2.2], axis=-1)
    cloud = smoothstep(0.52, 0.8, fbm(p + 4.0, 5)) * smoothstep(16, 24, el) * (1 - smoothstep(25, 33, el))
    cloud_col = MIDDLE[None, None, :] * 0.55 + HORIZON[None, None, :] * 0.45
    col = col * (1 - cloud[..., None] * 0.6) + cloud_col * cloud[..., None] * 0.6
    # Луна с ореолом
    md = np.degrees(np.arccos(np.clip((d * MOON_DIR).sum(axis=2), -1, 1)))
    halo = (np.exp(-(md / 6.0) ** 2) * 0.22 + np.exp(-(md / 3.2) ** 2) * 0.3) * (1 - smoothstep(8, 12, md))
    col = col + (halo * (1 - smoothstep(0, 6, 8 - el)))[..., None] * np.array([0.85, 0.9, 1.0])[None, None, :]
    disc = 1 - smoothstep(2.3, 2.5, md)
    maria = fbm(d * 45.0, 4)
    moon = np.array([1.0, 0.98, 0.9])[None, None, :] * (0.85 + 0.35 * maria[..., None] - 0.2 * smoothstep(0.5, 0.75, maria)[..., None])
    col = col * (1 - disc[..., None]) + moon * disc[..., None]
    # Координаты на цилиндре вокруг наблюдателя: кольцо замыкается, шва по азимуту нет
    cx, cy = np.cos(az), np.sin(az)

    def cyl(freq, el_scale, seed=0.0):
        return np.stack([cx * freq + seed, el * el_scale + seed * 0.5, cy * freq - seed], axis=-1)

    # Дальний хребет: скалы внизу, снег на вершинах, основание тает в дымке
    far = 12.0 + 9.5 * ridge(az, 2.6, 3.0) ** 1.5 + 1.5 * ridge(az, 11.0, 7.0, 4) + 0.45 * ridge(az, 42.0, 2.0, 3)
    far_mask = smoothstep(0, 0.14, far - el)
    t = np.clip((el - 8.0) / np.maximum(far - 8.0, 0.1), 0, 1)
    # Складки склонов идут наискось в обе стороны от хребта, как у настоящих гор
    def sheared(sign, freq):
        a = az + np.radians(el * 1.6 * sign)
        return fbm(np.stack([np.cos(a) * freq + 1.0, el * 0.07, np.sin(a) * freq - 1.0], axis=-1), 4)

    streak = np.maximum(sheared(1, 26.0), sheared(-1, 26.0)) * 0.72 + fbm(cyl(30.0, 0.3, 2.0), 3) * 0.28
    snow = smoothstep(0.6, 0.74, t + (streak - 0.55) * 1.0)
    shade = 0.7 + 0.5 * fbm(cyl(26.0, 0.05, 5.0), 3) + 0.45 * (streak - 0.5)
    far_col = (FAR_RANGE[None, None, :] * (1 - snow[..., None]) + SNOW_RANGE[None, None, :] * snow[..., None]) * shade[..., None]
    far_col = far_col * 0.78 + MIDDLE[None, None, :] * 0.22
    fade_low = smoothstep(6, 16, el)[..., None]
    far_col = far_col * fade_low + HORIZON[None, None, :] * (1 - fade_low)
    col = col * (1 - far_mask[..., None]) + far_col * far_mask[..., None]
    # Ближний хребет с лесом: неровный край и тёмные пятна
    near = 7.5 + 4.5 * ridge(az, 3.8, 9.0, 5) ** 1.2 + 0.9 * ridge(az, 16.0, 5.0, 4) + 0.28 * ridge(az, 90.0, 1.0, 3)
    near_mask = smoothstep(0, 0.12, near - el)
    forest = fbm(cyl(60.0, 2.6, 3.0), 3)
    near_col = NEAR_RANGE[None, None, :] * (0.72 + 0.55 * forest[..., None])
    near_col = near_col * 0.8 + HORIZON[None, None, :] * 0.2
    col = col * (1 - near_mask[..., None]) + near_col * near_mask[..., None]
    # Ниже горизонта и за холмами — тот же тон, что и дымка у подножия
    below = 1 - smoothstep(-1, 1.5, el)
    col = col * (1 - below[..., None]) + NEAR_RANGE[None, None, :] * below[..., None]
    return np.clip(col * GAIN, 0, 1)


def save(name, rgb):
    n = rgb.shape[0]
    img = bpy.data.images.new(name, n, n, alpha=False)
    rgba = np.ones((n, n, 4), dtype=np.float32)
    # Картинка считается в значениях экрана (sRGB), Blender хранит её как есть при Non-Color
    img.colorspace_settings.name = "Non-Color"
    rgba[..., :3] = rgb[::-1, :, :]
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    print("saved", img.filepath_raw)


X, Y, Z = np.array([1.0, 0, 0]), np.array([0, 1.0, 0]), np.array([0, 0, 1.0])
FACES = {
    "sky_ft": (-Z, X, Y),
    "sky_bk": (Z, -X, Y),
    "sky_rt": (X, Z, Y),
    "sky_lf": (-X, -Z, Y),
    "sky_up": (Y, X, Z),
    "sky_dn": (-Y, X, -Z),
}
os.makedirs(OUT, exist_ok=True)
for name, (forward, right, up) in FACES.items():
    save(name, paint(face_dirs(forward, right, up, SIZE)))
print("DONE sky")
