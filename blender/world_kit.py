# Набор моделей для карты «Дом»: заборы, соседи, дальний лес, предметы для зон. Запуск:
#   blender --background --python world_kit.py -- <папка вывода> [render]
# Предметы стоят рядами, каждый со своим смещением (PROPS); перед смотрит в -Y (в игре +Z).
# Меш называется Kit_<предмет>_<материал>. world_kit.json — центры мешей и смещения: по ним предметы собираются в Studio.
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modellib import R, S, T, blob, box, buckets, finish, hexa, lathe, solid, use_materials

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.dirname(os.path.abspath(__file__))
RENDER = "render" in argv

PALETTE = {
    "Trim": ((246, 240, 228), 0.0, 0.6, 0),
    "Snow": ((244, 249, 255), 0.0, 0.75, 0),
    "Wood": ((150, 108, 72), 0.0, 0.75, 0),
    "WoodDark": ((96, 66, 44), 0.0, 0.8, 0),
    "Iron": ((40, 44, 50), 0.7, 0.5, 0),
    "Wall": ((196, 170, 140), 0.0, 0.7, 0),
    "Roof": ((70, 76, 92), 0.0, 0.85, 0),
    "Light": ((255, 196, 110), 0.0, 0.5, 5),
    "Paint": ((170, 50, 44), 0.2, 0.3, 0),
    "Glass": ((40, 60, 84), 0.1, 0.1, 0),
    "Rubber": ((28, 28, 32), 0.0, 0.9, 0),
    "Leaf": ((44, 78, 58), 0.0, 0.9, 0),
    "Tree": ((176, 192, 222), 0.0, 0.9, 0),
    "Hill": ((206, 218, 240), 0.0, 0.9, 0),
    "Red": ((186, 44, 34), 0.0, 0.5, 0),
    "Metal": ((120, 128, 138), 0.7, 0.45, 0),
}

# Предмет: ((смещение X, Y), материалы)
PROPS = {
    "Far": ((0, 0), ("Tree", "Hill")),
    "Picket": ((-110, 0), ("Trim", "Snow")),
    "Plank": ((-90, 0), ("Wood", "Snow")),
    "HouseA": ((-50, 50), ("Wall", "Roof", "Snow", "Trim", "Light")),
    "HouseB": ((10, 50), ("Wall", "Roof", "Snow", "Trim", "Light")),
    "Car": ((-70, 0), ("Paint", "Glass", "Rubber", "Snow", "Light")),
    "Bush": ((-55, 0), ("Leaf", "Snow")),
    "Bench": ((-45, 0), ("Wood", "Iron", "Snow")),
    "Sled": ((-35, 0), ("Wood", "Red")),
    "Woodpile": ((-22, 0), ("Wood", "WoodDark", "Snow")),
    "Bins": ((-8, 0), ("Metal", "Snow")),
    "GardenLamp": ((2, 0), ("Iron", "Light", "Snow")),
    "Snowbank": ((20, 0), ("Snow",)),
}
MATERIALS = {}
for prop, (_, mats) in PROPS.items():
    for mat in mats:
        MATERIALS[f"{prop}_{mat}"] = PALETTE[mat]
use_materials(MATERIALS)

rng = random.Random(21)


def O(prop):
    ox, oy = PROPS[prop][0]
    return T(ox, oy, 0)


# ============================================================
# Заборы: секции вдоль X, начало координат в центре секции
# ============================================================
SECTION_PICKET = 8.0
SECTION_PLANK = 12.0


def picket():
    m = O("Picket")
    w, n = 0.55, 9
    for i in range(n):
        x = -SECTION_PICKET / 2 + SECTION_PICKET * (i + 0.5) / n
        solid(
            "Picket_Trim",
            [(x - w / 2, -0.06, 0), (x + w / 2, -0.06, 0), (x + w / 2, -0.06, 3.0), (x, -0.06, 3.45), (x - w / 2, -0.06, 3.0),
             (x - w / 2, 0.06, 0), (x + w / 2, 0.06, 0), (x + w / 2, 0.06, 3.0), (x, 0.06, 3.45), (x - w / 2, 0.06, 3.0)],
            [[0, 1, 2, 3, 4], [5, 6, 7, 8, 9], [0, 1, 6, 5], [1, 2, 7, 6], [2, 3, 8, 7], [3, 4, 9, 8], [4, 0, 5, 9]],
            m,
        )
    for z in (0.9, 2.4):
        box("Picket_Trim", (SECTION_PICKET, 0.16, 0.26), m @ T(0, 0.12, z), bevel=0)
    box("Picket_Snow", (SECTION_PICKET, 0.26, 0.16), m @ T(0, 0.12, 2.6), bevel=0)
    box("Picket_Trim", (0.56, 0.56, 3.9), m @ T(-SECTION_PICKET / 2, 0, 1.95), bevel=0)
    box("Picket_Snow", (0.72, 0.72, 0.28), m @ T(-SECTION_PICKET / 2, 0, 4.0), bevel=0.05)


def plank():
    m = O("Plank")
    n = 12
    for i in range(n):
        x = -SECTION_PLANK / 2 + SECTION_PLANK * (i + 0.5) / n
        box("Plank_Wood", (SECTION_PLANK / n - 0.07, 0.16, 5.6 + (i % 2) * 0.12), m @ T(x, 0, 2.8), bevel=0)
    for z in (1.1, 4.6):
        box("Plank_Wood", (SECTION_PLANK, 0.18, 0.4), m @ T(0, 0.16, z), bevel=0)
    box("Plank_Wood", (0.7, 0.7, 6.4), m @ T(-SECTION_PLANK / 2, 0, 3.2), bevel=0)
    box("Plank_Snow", (SECTION_PLANK, 0.4, 0.24), m @ T(0, 0, 5.8), bevel=0.05)
    box("Plank_Snow", (0.9, 0.9, 0.3), m @ T(-SECTION_PLANK / 2, 0, 6.5), bevel=0.05)


# ============================================================
# Соседские дома: простые объёмы, главное — силуэт и горящие окна
# ============================================================
def roof_slab(prop, quad):
    pts = [Vector(p) for p in quad]
    n = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
    if n.z < 0:
        n = -n
    m = O(prop)
    hexa(f"{prop}_Roof", [tuple(p - n * 0.3) for p in pts], [tuple(p) for p in pts], m)
    c = sum(pts, Vector()) / 4
    near = [p + (c - p).normalized() * 0.3 for p in pts]
    hexa(f"{prop}_Snow", [tuple(p) for p in near], [tuple(p + n * 0.5) for p in near], m)


def lit_window(prop, x, y, z, w=4.0, h=3.6):
    m = O(prop)
    d = -1 if y < 0 else 1
    box(f"{prop}_Trim", (w + 0.6, 0.2, h + 0.6), m @ T(x, y + d * 0.1, z), bevel=0)
    box(f"{prop}_Light", (w, 0.1, h), m @ T(x, y + d * 0.24, z), bevel=0)
    box(f"{prop}_Trim", (0.18, 0.14, h), m @ T(x, y + d * 0.3, z), bevel=0)


def house_a():
    # Фронтон к улице, крыльцо по центру
    prop, m = "HouseA", O("HouseA")
    w, d, wall_h, rise = 15.0, 12.0, 11.0, 8.0
    box("HouseA_Wall", (w * 2, d * 2, wall_h), m @ T(0, 0, wall_h / 2), bevel=0)
    solid(
        "HouseA_Wall",
        [(-w, -d, wall_h), (w, -d, wall_h), (0, -d, wall_h + rise), (-w, d, wall_h), (w, d, wall_h), (0, d, wall_h + rise)],
        [[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]],
        m,
    )
    over = 1.2
    edge = wall_h - over * rise / w
    roof_slab(prop, [(-w - over, -d - 1, edge), (0, -d - 1, wall_h + rise), (0, d + 1, wall_h + rise), (-w - over, d + 1, edge)])
    roof_slab(prop, [(w + over, -d - 1, edge), (0, -d - 1, wall_h + rise), (0, d + 1, wall_h + rise), (w + over, d + 1, edge)])
    for x in (-8.5, 8.5):
        lit_window(prop, x, -d, 5.2)
        lit_window(prop, x, d, 5.2)
    lit_window(prop, 0, -d, wall_h + 2.2, w=3.4, h=3.0)
    box("HouseA_Trim", (5.4, 0.3, 7.4), m @ T(0, -d - 0.1, 3.7), bevel=0)
    box("HouseA_Light", (4.4, 0.2, 1.1), m @ T(0, -d - 0.26, 6.2), bevel=0)


def house_b():
    # Конёк вдоль улицы, два этажа
    prop, m = "HouseB", O("HouseB")
    w, d, wall_h, rise = 18.0, 11.0, 15.0, 8.0
    box("HouseB_Wall", (w * 2, d * 2, wall_h), m @ T(0, 0, wall_h / 2), bevel=0)
    solid(
        "HouseB_Wall",
        [(-w, -d, wall_h), (-w, d, wall_h), (-w, 0, wall_h + rise), (w, -d, wall_h), (w, d, wall_h), (w, 0, wall_h + rise)],
        [[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]],
        m,
    )
    over = 1.3
    edge = wall_h - over * rise / d
    roof_slab(prop, [(-w - 1, -d - over, edge), (w + 1, -d - over, edge), (w + 1, 0, wall_h + rise), (-w - 1, 0, wall_h + rise)])
    roof_slab(prop, [(-w - 1, d + over, edge), (w + 1, d + over, edge), (w + 1, 0, wall_h + rise), (-w - 1, 0, wall_h + rise)])
    for x in (-11, 0, 11):
        lit_window(prop, x, -d, 11.0)
        lit_window(prop, x, d, 11.0)
        if x != 0:
            lit_window(prop, x, -d, 4.4)
            lit_window(prop, x, d, 4.4)
    box("HouseB_Trim", (5.2, 0.3, 7.4), m @ T(0, -d - 0.1, 3.7), bevel=0)


# ============================================================
# Дальний лес на холмах: кольцо вокруг участка, далеко за соседями
# ============================================================
def far():
    cx, cy = 0.0, -50.0
    seg = 96
    r0, r1 = 440.0, 640.0
    verts, faces = [], []
    heights = [36 + 22 * math.sin(k * 0.37) + 12 * math.sin(k * 0.13 + 1.2) for k in range(seg)]
    for k in range(seg):
        a = 2 * math.pi * k / seg
        c, s = math.cos(a), math.sin(a)
        verts.append((cx + r0 * c, cy + r0 * s, 0))
        verts.append((cx + (r0 + r1) / 2 * c, cy + (r0 + r1) / 2 * s, heights[k]))
        verts.append((cx + r1 * c, cy + r1 * s, heights[k] * 0.4))
    for k in range(seg):
        k2 = (k + 1) % seg
        for j in range(2):
            a, b = k * 3 + j, k2 * 3 + j
            faces.append([a, a + 1, b + 1, b])
    # Грани смотрят к центру кольца, потому что игрок всегда внутри
    p, q, r = Vector(verts[0]), Vector(verts[1]), Vector(verts[4])
    if (q - p).cross(r - q).dot(Vector((cx, cy, 0)) - p) < 0:
        faces = [list(reversed(f)) for f in faces]
    buckets["Far_Hill"].add(verts, faces)
    for _ in range(420):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(r0 + 15, r0 + 130)
        t = (r - r0) / ((r1 - r0) / 2)
        k = int(a / (2 * math.pi) * seg) % seg
        z = heights[k] * t - 2
        h = rng.uniform(34, 62)
        lathe(
            "Far_Tree",
            [(0, 0), (h * 0.22, 0), (h * 0.13, h * 0.42), (h * 0.17, h * 0.42), (0, h)],
            seg=5,
            m=T(cx + r * math.cos(a), cy + r * math.sin(a), z),
            start=rng.uniform(0, 1),
        )


# ============================================================
# Предметы для зон
# ============================================================
def car():
    m = O("Car")
    # Перед машины смотрит в -Y
    hexa("Car_Paint", [(-3.3, -7.6, 1.0), (3.3, -7.6, 1.0), (3.3, 7.6, 1.0), (-3.3, 7.6, 1.0)], [(-3.2, -7.4, 3.2), (3.2, -7.4, 3.2), (3.2, 7.4, 3.2), (-3.2, 7.4, 3.2)], m)
    hexa("Car_Glass", [(-3.0, -3.0, 3.2), (3.0, -3.0, 3.2), (3.0, 5.0, 3.2), (-3.0, 5.0, 3.2)], [(-2.6, -1.2, 5.1), (2.6, -1.2, 5.1), (2.6, 4.2, 5.1), (-2.6, 4.2, 5.1)], m)
    hexa("Car_Paint", [(-2.6, -1.3, 5.1), (2.6, -1.3, 5.1), (2.6, 4.3, 5.1), (-2.6, 4.3, 5.1)], [(-2.5, -1.2, 5.3), (2.5, -1.2, 5.3), (2.5, 4.2, 5.3), (-2.5, 4.2, 5.3)], m)
    for sx in (-3.25, 3.25):
        for sy in (-4.6, 4.6):
            lathe("Car_Rubber", [(0, -0.45), (1.1, -0.45), (1.1, 0.45), (0, 0.45)], seg=10, m=m @ T(sx, sy, 1.1) @ R(90, "Y"))
    for sx in (-2.2, 2.2):
        box("Car_Light", (1.2, 0.1, 0.5), m @ T(sx, -7.65, 2.4), bevel=0)
    blob("Car_Snow", (2.5, 2.9, 0.42), m @ T(0, 1.5, 5.4), e=0.7, nu=10, nv=6)
    blob("Car_Snow", (3.0, 2.3, 0.4), m @ T(0, -5.3, 3.3), e=0.7, nu=10, nv=6)
    blob("Car_Snow", (3.0, 1.5, 0.35), m @ T(0, 6.2, 3.3), e=0.7, nu=10, nv=6)


def bush():
    m = O("Bush")
    for x, y, r in ((0, 0, 2.4), (1.6, 0.6, 1.7), (-1.5, -0.4, 1.8)):
        blob("Bush_Leaf", (r, r * 0.9, r * 0.8), m @ T(x, y, r * 0.7), e=0.85, nu=9, nv=6)
        blob("Bush_Snow", (r * 0.85, r * 0.78, r * 0.42), m @ T(x, y, r * 1.22), e=0.8, nu=9, nv=5)


def bench():
    m = O("Bench")
    for x in (-2.4, 2.4):
        box("Bench_Iron", (0.26, 1.5, 1.6), m @ T(x, 0, 0.8), bevel=0)
        box("Bench_Iron", (0.26, 0.26, 1.5), m @ T(x, 0.62, 2.3), bevel=0)
    for i in range(3):
        box("Bench_Wood", (5.6, 0.42, 0.14), m @ T(0, -0.5 + i * 0.5, 1.68), bevel=0)
    for z in (2.2, 2.8):
        box("Bench_Wood", (5.6, 0.12, 0.36), m @ T(0, 0.7, z), bevel=0)
    blob("Bench_Snow", (2.7, 0.7, 0.2), m @ T(0, 0, 1.84), e=0.6, nu=10, nv=5)


def sled():
    m = O("Sled")
    for i in range(4):
        box("Sled_Wood", (1.8, 0.56, 0.12), m @ T(0, -1.2 + i * 0.8, 0.82), bevel=0)
    for x in (-0.8, 0.8):
        box("Sled_Red", (0.14, 3.6, 0.14), m @ T(x, 0, 0.1), bevel=0)
        hexa("Sled_Red", [(x - 0.07, -1.8, 0.03), (x + 0.07, -1.8, 0.03), (x + 0.07, -1.68, 0.03), (x - 0.07, -1.68, 0.03)], [(x - 0.07, -2.5, 0.85), (x + 0.07, -2.5, 0.85), (x + 0.07, -2.38, 0.85), (x - 0.07, -2.38, 0.85)], m)
        for y in (-1.0, 1.0):
            box("Sled_Red", (0.12, 0.12, 0.7), m @ T(x, y, 0.45), bevel=0)


def woodpile():
    m = O("Woodpile")
    for row in range(4):
        n = 7 - row
        for i in range(n):
            place = m @ T(-2.6 * (n - 1) / 2 * 0.36 + i * 0.94, 0, 0.42 + row * 0.76) @ R(90, "X")
            s = 0.4 + rng.random() * 0.05
            lathe("Woodpile_Wood", [(0, -1.9), (s, -1.9), (s, 1.9), (0, 1.9)], seg=6, m=place)
            lathe("Woodpile_WoodDark", [(0, -1.92), (s * 0.8, -1.92), (s * 0.8, -1.9), (0, -1.9)], seg=6, m=place)
    for x in (-3.4, 3.4):
        box("Woodpile_WoodDark", (0.3, 0.3, 3.6), m @ T(x, 0, 1.8), bevel=0)
    blob("Woodpile_Snow", (2.4, 1.9, 0.42), m @ T(0, 0, 3.5), e=0.7, nu=10, nv=5)


def bins():
    m = O("Bins")
    for x in (-1.4, 1.4):
        lathe("Bins_Metal", [(0, 0), (1.0, 0), (1.2, 3.1), (1.28, 3.1), (1.28, 3.35), (0, 3.55)], seg=10, m=m @ T(x, 0, 0))
        blob("Bins_Snow", (1.05, 1.05, 0.34), m @ T(x, 0, 3.6), e=0.8, nu=10, nv=5)


def garden_lamp():
    m = O("GardenLamp")
    lathe("GardenLamp_Iron", [(0, 0), (0.28, 0), (0.1, 0.3), (0.1, 3.3), (0, 3.3)], seg=6, m=m)
    lathe("GardenLamp_Light", [(0, 3.2), (0.32, 3.3), (0.32, 3.95), (0, 4.05)], seg=8, m=m)
    lathe("GardenLamp_Iron", [(0.45, 4.0), (0.45, 4.1), (0, 4.4)], seg=6, m=m)
    lathe("GardenLamp_Snow", [(0.4, 4.2), (0, 4.62)], seg=6, m=m)


def snowbank():
    m = O("Snowbank")
    for i in range(6):
        x = -10 + i * 4
        r = 2.6 + rng.random() * 1.1
        blob("Snowbank_Snow", (r * 1.1, 2.0 + rng.random() * 0.4, r * 0.75), m @ T(x, rng.random() * 0.5, r * 0.25), e=0.85, nu=10, nv=6)


picket()
plank()
house_a()
house_b()
far()
car()
bush()
bench()
sled()
woodpile()
bins()
garden_lamp()
snowbank()

# Центры мешей для сборки в Studio
manifest = {"props": {p: list(v[0]) for p, v in PROPS.items()}, "centers": {}, "sections": {"Picket": SECTION_PICKET, "Plank": SECTION_PLANK}}
for key, b in buckets.items():
    lo = [min(v[i] for v in b.verts) for i in range(3)]
    hi = [max(v[i] for v in b.verts) for i in range(3)]
    manifest["centers"][key] = [round((lo[i] + hi[i]) / 2, 3) for i in range(3)]
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "world_kit.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=1)

VIEWS = {"props": ((-50, -70, 28), (-40, 0, 2)), "houses": ((-20, -40, 28), (-20, 50, 8))}
finish("Kit", MATERIALS, OUT, "world_kit", render=RENDER, views=VIEWS, ground=(0.82, 0.86, 0.95, 1))
