# Набор моделей для карты «Дом»: заборы, ворота, машина, предметы для зон, фонари, соседние дома. Запуск:
#   blender --background --python world_kit.py -- <папка вывода> [render]
# Предметы стоят рядами, каждый со своим смещением (PROPS); перед смотрит в -Y (в игре +Z).
# Меш называется Kit_<предмет>_<материал>. world_kit.json — центры мешей и смещения: по ним предметы собираются в Studio.
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modellib import R, T, blob, box, buckets, finish, hexa, lathe, loft, patch, solid, tube, use_materials

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.dirname(os.path.abspath(__file__))
RENDER = "render" in argv

PALETTE = {
    "Trim": ((246, 240, 228), 0.0, 0.6, 0),
    "Snow": ((244, 249, 255), 0.0, 0.75, 0),
    "Wood": ((150, 108, 72), 0.0, 0.75, 0),
    "WoodDark": ((96, 66, 44), 0.0, 0.8, 0),
    "Iron": ((46, 50, 58), 0.7, 0.5, 0),
    "Brass": ((222, 168, 62), 1.0, 0.28, 0),
    "Wall": ((196, 170, 140), 0.0, 0.7, 0),
    "Shade": ((132, 112, 92), 0.0, 0.8, 0),
    "Accent": ((58, 84, 96), 0.0, 0.6, 0),
    "Roof": ((66, 72, 88), 0.0, 0.85, 0),
    "Dark": ((34, 38, 46), 0.0, 0.7, 0),
    "Light": ((255, 196, 110), 0.0, 0.5, 5),
    "Paint": ((44, 78, 110), 0.3, 0.3, 0),
    "Glass": ((32, 44, 60), 0.2, 0.1, 0),
    "Lens": ((205, 215, 225), 0.2, 0.15, 0),
    "Metal": ((150, 158, 168), 0.8, 0.35, 0),
    "Leaf": ((62, 98, 70), 0.0, 0.9, 0),
    "Red": ((186, 44, 34), 0.0, 0.5, 0),
    "Bins": ((120, 128, 138), 0.7, 0.45, 0),
}

# Предмет: ((смещение X, Y), материалы)
PROPS = {
    "Picket": ((-110, 0), ("Trim", "Snow")),
    "Plank": ((-90, 0), ("Wood", "Snow")),
    "GateA": ((-140, 0), ("Trim", "Snow", "Iron", "Brass")),
    "GateB": ((-175, 0), ("Trim", "Snow", "Iron", "Brass")),
    "Car": ((-70, 0), ("Paint", "Glass", "Dark", "Metal", "Lens", "Red", "Snow")),
    "Bush": ((-55, 0), ("Leaf", "Snow")),
    "Bench": ((-45, 0), ("Wood", "Iron", "Snow")),
    "Sled": ((-35, 0), ("Wood", "Red")),
    "Woodpile": ((-22, 0), ("Wood", "WoodDark", "Snow")),
    "Bins": ((-8, 0), ("Bins", "Snow")),
    "GardenLamp": ((2, 0), ("Iron", "Light", "Snow")),
    "StreetLamp": ((10, 0), ("Iron", "Light", "Snow")),
    "Snowbank": ((30, 0), ("Snow",)),
    "HouseA": ((-85, 60), ("Wall", "Shade", "Trim", "Accent", "Roof", "Snow", "Light")),
    "HouseB": ((-20, 60), ("Wall", "Shade", "Trim", "Accent", "Roof", "Snow", "Light")),
    "HouseC": ((45, 60), ("Wall", "Shade", "Trim", "Accent", "Roof", "Snow", "Light")),
}
MATERIALS = {}
for prop, (_, mats) in PROPS.items():
    for mat in mats:
        MATERIALS[f"{prop}_{mat}"] = PALETTE[mat]
use_materials(MATERIALS)

rng = random.Random(21)
noise.seed_set(4)


def O(prop):
    ox, oy = PROPS[prop][0]
    return T(ox, oy, 0)


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def picket_board(mat, x, w, top, m, y=0.0, shoulder=0.42):
    solid(
        mat,
        [(x - w / 2, y - 0.06, 0), (x + w / 2, y - 0.06, 0), (x + w / 2, y - 0.06, top - shoulder), (x, y - 0.06, top), (x - w / 2, y - 0.06, top - shoulder),
         (x - w / 2, y + 0.06, 0), (x + w / 2, y + 0.06, 0), (x + w / 2, y + 0.06, top - shoulder), (x, y + 0.06, top), (x - w / 2, y + 0.06, top - shoulder)],
        [[0, 1, 2, 3, 4], [5, 6, 7, 8, 9], [0, 1, 6, 5], [1, 2, 7, 6], [2, 3, 8, 7], [3, 4, 9, 8], [4, 0, 5, 9]],
        m,
    )


# ============================================================
# Заборы: секции вдоль X, начало координат в центре секции
# ============================================================
SECTION_PICKET = 8.0
SECTION_PLANK = 12.0


def picket():
    m = O("Picket")
    n = 9
    for i in range(n):
        picket_board("Picket_Trim", -SECTION_PICKET / 2 + SECTION_PICKET * (i + 0.5) / n, 0.55, 3.45, m)
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


def gate(prop, length):
    """Двустворчатые ворота в стиле штакетника: тот же цвет и шаг, верх створок поднимается к центру. Замок показывает, что закрыто."""
    m = O(prop)
    half = length / 2
    top = lambda x: 3.3 + 1.5 * math.sin(math.pi / 2 * (1 - abs(x) / half))
    n = int(length / 0.86)
    for i in range(n):
        x = -half + length * (i + 0.5) / n
        if abs(x) < 0.3:
            continue
        picket_board(f"{prop}_Trim", x, 0.55, top(x), m)
    box(f"{prop}_Trim", (length, 0.16, 0.26), m @ T(0, 0.12, 0.9), bevel=0)
    steps = 12
    for i in range(steps):
        x0, x1 = -half + length * i / steps, -half + length * (i + 1) / steps
        z0, z1 = top(x0) - 0.95, top(x1) - 0.95
        hexa(f"{prop}_Trim", [(x0, 0.04, z0 - 0.14), (x1, 0.04, z1 - 0.14), (x1, 0.2, z1 - 0.14), (x0, 0.04 + 0.16, z0 - 0.14)], [(x0, 0.04, z0 + 0.14), (x1, 0.04, z1 + 0.14), (x1, 0.2, z1 + 0.14), (x0, 0.2, z0 + 0.14)], m)
        hexa(f"{prop}_Snow", [(x0, 0.0, z0 + 0.14), (x1, 0.0, z1 + 0.14), (x1, 0.26, z1 + 0.14), (x0, 0.26, z0 + 0.14)], [(x0, 0.0, z0 + 0.32), (x1, 0.0, z1 + 0.32), (x1, 0.26, z1 + 0.32), (x0, 0.26, z0 + 0.32)], m)
    # Столбы и стойки в центре
    for sx in (-half, half):
        box(f"{prop}_Trim", (0.9, 0.9, 5.3), m @ T(sx, 0, 2.65), bevel=0.05)
        box(f"{prop}_Trim", (1.2, 1.2, 0.24), m @ T(sx, 0, 5.4), bevel=0.04)
        snow_top = m @ T(sx, 0, 5.5)
        lathe(f"{prop}_Snow", [(0.62, 0), (0.5, 0.2), (0.25, 0.36), (0, 0.42)], seg=8, m=snow_top)
    for sx in (-0.2, 0.2):
        box(f"{prop}_Trim", (0.34, 0.2, top(0) + 0.1), m @ T(sx, 0, (top(0) + 0.1) / 2), bevel=0)
    # Цепь и замок по центру, петли у столбов
    box(f"{prop}_Iron", (1.0, 0.08, 0.1), m @ T(0, -0.14, 2.6), bevel=0)
    box(f"{prop}_Brass", (0.42, 0.14, 0.46), m @ T(0, -0.2, 2.34), bevel=0.04)
    lathe(f"{prop}_Iron", [(0.13, 0), (0.17, 0.1), (0.13, 0.24), (0, 0.26)], seg=8, m=m @ T(0, -0.2, 2.52))
    for sx in (-half + 0.45, half - 0.45):
        for z in (0.9, 2.5):
            box(f"{prop}_Iron", (1.1, 0.1, 0.18), m @ T(sx + (0.5 if sx < 0 else -0.5), -0.1, z), bevel=0)


# ============================================================
# Машина: кузов и кабина по кольцам, стёкла и детали лоскутами на их поверхности
# ============================================================
BODY = [
    (-7.85, 1.3, 2.4, 2.8), (-7.7, 1.02, 2.68, 3.02), (-7.2, 0.95, 2.86, 3.18), (-6.4, 0.95, 3.0, 3.28), (-4.8, 0.95, 3.15, 3.36),
    (-3.0, 0.95, 3.32, 3.4), (-1.0, 0.95, 3.42, 3.42), (2.0, 0.95, 3.5, 3.42), (5.0, 0.95, 3.55, 3.4), (6.4, 0.97, 3.52, 3.34),
    (7.3, 1.0, 3.4, 3.2), (7.7, 1.05, 3.25, 3.05), (7.85, 1.3, 3.0, 2.85),
]
CABIN = [
    (-3.5, 3.36, 2.95), (-2.6, 3.85, 2.92), (-1.5, 4.45, 2.85), (-0.4, 4.95, 2.75), (1.0, 5.2, 2.7), (3.4, 5.28, 2.68),
    (5.2, 5.2, 2.66), (6.2, 4.85, 2.7), (6.9, 4.05, 2.78), (7.35, 3.35, 2.85),
]
CABIN_CHAIN = [(1.0, 0.0), (0.97, 0.25), (0.92, 0.55), (0.87, 0.78), (0.76, 0.93), (0.5, 0.99), (0.0, 1.0)]


def table_value(table, y, col):
    """Сплайн Катмулла — Рома по таблице станций."""
    n = len(table)
    y = max(table[0][0], min(table[-1][0], y))
    i = 0
    while i < n - 2 and table[i + 1][0] < y:
        i += 1
    y0, y1 = table[i][0], table[i + 1][0]
    t = (y - y0) / (y1 - y0)
    p1, p2 = table[i][col], table[i + 1][col]
    p0 = table[i - 1][col] if i > 0 else p1
    p3 = table[i + 2][col] if i + 2 < n else p2
    return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t)


def spow(v, e):
    return math.copysign(abs(v) ** e, v)


def body_pt(y, a, side=1):
    """Точка кузова: a — угол сечения (0 — борт, 90° — верх)."""
    zlo, zhi, w = table_value(BODY, y, 1), table_value(BODY, y, 2), table_value(BODY, y, 3)
    mid, half = (zlo + zhi) / 2, (zhi - zlo) / 2
    return Vector((side * w * spow(math.cos(a), 0.42), y, mid + half * spow(math.sin(a), 0.42)))


def cabin_pt(y, u, side=1):
    """Точка кабины: u = 0 — у пояса, u = 1 — центр крыши."""
    belt = table_value(BODY, y, 2) - 0.05
    top = max(table_value(CABIN, y, 1), belt + 0.03)
    w = table_value(CABIN, y, 2)
    t = max(0.0, min(0.9999, u)) * (len(CABIN_CHAIN) - 1)
    i = int(t)
    f = t - i
    xf = CABIN_CHAIN[i][0] * (1 - f) + CABIN_CHAIN[i + 1][0] * f
    zf = CABIN_CHAIN[i][1] * (1 - f) + CABIN_CHAIN[i + 1][1] * f
    return Vector((side * w * xf, y, belt + (top - belt) * zf))


def split_shell(grid, classify, away, m):
    """Поверхность по сетке (ряды, кольцо точек): материал задаётся на ячейку, поэтому стёкла и фары не спорят с кузовом."""
    rows, cols = len(grid), len(grid[0])
    per = {}
    for i in range(rows - 1):
        for j in range(cols):
            j2 = (j + 1) % cols
            mat = classify(i, j)
            if mat is None:
                continue
            d = per.setdefault(mat, {"verts": [], "index": {}, "faces": []})
            ids = []
            for key in ((i, j), (i, j2), (i + 1, j2), (i + 1, j)):
                if key not in d["index"]:
                    d["index"][key] = len(d["verts"])
                    d["verts"].append(grid[key[0]][key[1]])
                ids.append(d["index"][key])
            pts = [d["verts"][k] for k in ids]
            n = (pts[1] - pts[0]).cross(pts[3] - pts[0])
            fc = sum(pts, Vector()) / 4
            d["faces"].append(list(reversed(ids)) if n.dot(fc - away(fc)) < 0 else ids)
    for mat, d in per.items():
        buckets[mat].add([tuple(v) for v in d["verts"]], d["faces"], m)


def end_cap(mat, ring, outward, m):
    c = sum(ring, Vector()) / len(ring)
    verts = [tuple(p) for p in ring] + [tuple(c)]
    last = len(ring)
    faces = []
    for k in range(len(ring)):
        f = [k, (k + 1) % len(ring), last]
        n = (ring[f[1]] - ring[f[0]]).cross(c - ring[f[0]])
        faces.append(list(reversed(f)) if n.dot(outward) < 0 else f)
    buckets[mat].add(verts, faces, m)


def car():
    m = O("Car")
    d2r = math.pi / 180
    seam_ys = (-1.25, 1.325, 3.875)

    def in_seam(y0, y1):
        return any(s - 0.04 <= y0 and y1 <= s + 0.04 for s in seam_ys)

    # Кузов: кольцо через 10°, станции совпадают с границами фар, огней и швов
    body_y = [-7.85, -7.75, -7.62, -7.3, -6.9, -6.45, -5.6, -4.8, -4.0, -3.2, -2.4, -1.29, -1.21, -0.6, 0.3, 1.285, 1.365, 2.4, 3.4, 3.835, 3.915, 4.8, 5.6, 6.2, 6.65, 7.2, 7.5, 7.68, 7.78, 7.85]
    body_grid = [[body_pt(y, a * 10 * d2r) for a in range(36)] for y in body_y]

    def body_class(i, j):
        y0, y1, a = body_y[i], body_y[i + 1], j * 10
        if 190 <= a < 350:
            return "Car_Dark"
        upper = 20 <= a < 60 or 120 <= a < 160
        if upper and y0 >= -7.62 and y1 <= -6.45:
            return "Car_Lens"
        if upper and y0 >= 6.65 and y1 <= 7.68:
            return "Car_Red"
        if in_seam(y0, y1) and (a < 80 or a >= 100):
            return "Car_Dark"
        return "Car_Paint"

    split_shell(body_grid, body_class, lambda p: Vector((0, p.y, 2.0)), m)
    end_cap("Car_Paint", body_grid[0], Vector((0, -1, 0)), m)
    end_cap("Car_Paint", body_grid[-1], Vector((0, 1, 0)), m)

    # Кабина: ячейки стёкол и стоек на одной поверхности с крышей
    cab_y = [-3.5, -2.85, -2.3, -1.75, -1.29, -1.21, -0.9, -0.55, -0.1, 0.5, 1.2, 1.285, 1.365, 1.45, 2.1, 2.75, 3.4, 3.75, 3.835, 3.915, 4.0, 4.6, 5.2, 5.75, 5.95, 6.4, 6.95, 7.2, 7.35]
    n_chain = len(CABIN_CHAIN) - 1
    cols = [(k / n_chain, 1) for k in range(n_chain + 1)] + [(k / n_chain, -1) for k in range(n_chain - 1, -1, -1)]
    cab_grid = [[cabin_pt(y, u, side) for u, side in cols] for y in cab_y]

    def cab_class(i, j):
        y0, y1 = cab_y[i], cab_y[i + 1]
        if j >= len(cols) - 1:
            return None
        # Ячейка между точками j и j + 1: для правой половины низ — j, для левой — зеркально
        ulo = min(cols[j][0], cols[j + 1][0])
        if -2.85 <= y0 and y1 <= -1.25 and ulo >= 0.33:
            return "Car_Glass"
        if -1.25 <= y0 and y1 <= -0.55 and ulo >= 0.66:
            return "Car_Glass"
        if 5.95 <= y0 and y1 <= 6.95 and ulo >= 0.33:
            return "Car_Glass"
        side_band = 0.16 <= ulo < 0.5
        for a, b in ((-1.21, 1.2), (1.45, 3.75), (4.0, 5.75)):
            if side_band and a <= y0 and y1 <= b:
                return "Car_Glass"
        for a, b in ((1.2, 1.45), (3.75, 4.0)):
            if side_band and a <= y0 and y1 <= b:
                return "Car_Dark"
        if in_seam(y0, y1) and ulo < 0.16:
            return "Car_Dark"
        return "Car_Paint"

    split_shell(cab_grid, cab_class, lambda p: Vector((0, p.y, 3.0)), m)

    for side in (1, -1):
        for yh in (0.75, 3.4):
            box("Car_Metal", (0.08, 0.7, 0.16), m @ T(side * (table_value(BODY, yh, 3) + 0.03), yh, 2.95), bevel=0)
        # Зеркало
        blob("Car_Paint", (0.34, 0.2, 0.22), m @ T(side * 3.4, -1.7, 3.66), e=0.7, nu=8, nv=5)
        box("Car_Dark", (0.5, 0.1, 0.1), m @ T(side * 3.12, -1.7, 3.55), bevel=0)
        # Колёса: тёмная арка на борту, шина почти вровень с кузовом
        for yw in (-4.75, 4.6):
            w_here = table_value(BODY, yw, 3)
            lathe("Car_Dark", [(0, -0.02), (1.32, -0.02), (1.32, 0.02), (0, 0.02)], seg=20, m=m @ T(side * (w_here + 0.015), yw, 1.1) @ R(90, "Y"))
            lathe("Car_Dark", [(0, -0.4), (0.92, -0.4), (1.08, -0.28), (1.08, 0.28), (0.92, 0.4), (0, 0.4)], seg=20, m=m @ T(side * (w_here - 0.34), yw, 1.08) @ R(90, "Y"))
            outward = R(90 * side, "Y")
            lathe("Car_Metal", [(0, 0.0), (0.66, 0.0), (0.66, 0.05), (0.56, 0.09), (0.24, 0.06), (0.2, 0.14), (0, 0.16)], seg=12, m=m @ T(side * (w_here + 0.06), yw, 1.08) @ outward)
            for k in range(5):
                a = 2 * math.pi * k / 5
                box("Car_Dark", (0.06, 0.1, 0.5), m @ T(side * (w_here + 0.15), yw + 0.34 * math.sin(a), 1.08 + 0.34 * math.cos(a)) @ R(-k * 72, "X"), bevel=0)
        # Рейлинг на крыше
        rail = [m @ cabin_pt(y, 0.72, side) + Vector((0, 0, 0.14)) for y in (0.1, 1.1, 2.1, 3.1, 4.1, 5.0)]
        tube("Car_Dark", rail, 0.06, seg=5)
    # Решётка, противотуманные фары, номера
    box("Car_Dark", (3.4, 0.14, 0.72), m @ T(0, -7.88, 2.02), bevel=0.03)
    for z in (1.84, 2.02, 2.2):
        box("Car_Metal", (3.2, 0.06, 0.05), m @ T(0, -7.97, z), bevel=0)
    box("Car_Lens", (1.3, 0.05, 0.42), m @ T(0, -7.9, 1.38), bevel=0)
    box("Car_Lens", (1.3, 0.05, 0.42), m @ T(0, 7.88, 1.95), bevel=0)
    box("Car_Dark", (3.8, 0.08, 0.12), m @ T(0, 7.9, 2.42), bevel=0)

    # Снег лежит по форме кузова: толщина спадает к краям лоскута
    def span(a, b, n):
        return [a + (b - a) * i / n for i in range(n + 1)]

    def across(y, s, u0):
        side = 1 if s >= 0 else -1
        return cabin_pt(y, 1 - abs(s) * (1 - u0), side)

    def snow(fn, us, vs, thick):
        rows = []
        n_u, n_v = len(us) - 1, len(vs) - 1
        for iu, u in enumerate(us):
            row = []
            for iv, v in enumerate(vs):
                p = fn(u, v)
                edge = min(smooth(min(iu, n_u - iu) / (n_u * 0.22)), smooth(min(iv, n_v - iv) / (n_v * 0.22)))
                bump = 0.75 + 0.5 * noise.noise(p * 0.9 + Vector((3, 1, 0)))
                row.append(m @ (p + Vector((0, 0, 0.07 + thick * edge * bump))))
            rows.append(row)
        patch("Car_Snow", rows, lambda c: c - Vector((0, 0, 1)))

    snow(lambda y, s: across(y, s, 0.6), span(-0.4, 5.7, 16), span(-1, 1, 12), 0.5)
    snow(lambda y, a: body_pt(y, a * d2r, 1), span(-6.3, -3.25, 10), span(36, 144, 12), 0.34)


# ============================================================
# Предметы для зон
# ============================================================
def lumpy_grid(c, r, seed, nu, nv, grow=1.0):
    rows = []
    for j in range(nv + 1):
        phi = -math.pi / 2 + math.pi * j / nv
        row = []
        for k in range(nu):
            a = 2 * math.pi * k / nu
            d = Vector((math.cos(phi) * math.cos(a), math.cos(phi) * math.sin(a), math.sin(phi)))
            n = 1 + 0.13 * noise.noise(d * 1.9 + Vector((seed, seed * 2, 0))) + 0.05 * noise.noise(d * 5 + Vector((seed, 0, 1)))
            row.append(Vector(c) + Vector((d.x * r[0], d.y * r[1], d.z * r[2])) * n * grow)
        rows.append(row)
    return rows


def lumpy_add(mat, rows, c, keep, m):
    nu = len(rows[0])
    verts, faces = [], []
    index = {}

    def vid(j, k):
        key = (j, k % nu)
        if key not in index:
            index[key] = len(verts)
            verts.append(rows[j][k % nu])
        return index[key]

    for j in range(len(rows) - 1):
        for k in range(nu):
            quad = [rows[j][k], rows[j][(k + 1) % nu], rows[j + 1][(k + 1) % nu], rows[j + 1][k]]
            fc = sum(quad, Vector()) / 4
            if not keep(fc):
                continue
            f = [vid(j, k), vid(j, k + 1), vid(j + 1, k + 1), vid(j + 1, k)]
            faces.append(f)
    if not faces:
        return
    vs = verts
    fixed = []
    for f in faces:
        n = (vs[f[1]] - vs[f[0]]).cross(vs[f[3]] - vs[f[0]])
        fc = sum((vs[i] for i in f), Vector()) / 4
        fixed.append(list(reversed(f)) if n.dot(fc - Vector(c)) < 0 else f)
    buckets[mat].add([tuple(v) for v in verts], fixed, m)


def bush():
    m = O("Bush")
    for i, (x, y, r) in enumerate(((0, 0, 2.2), (1.9, 0.5, 1.5), (-1.8, -0.4, 1.6), (0.3, -1.3, 1.3))):
        c = (x, y, r * 0.72)
        radii = (r, r * 0.92, r * 0.86)
        rows = lumpy_grid(c, radii, i * 3 + 1, 18, 11)
        lumpy_add("Bush_Leaf", rows, c, lambda p: True, m)
        snow_rows = lumpy_grid(c, radii, i * 3 + 1, 18, 11, grow=1.05)
        cut = c[2] + r * 0.34

        def on_top(p, cut=cut):
            return p.z + 0.35 * noise.noise(p * 1.4) > cut

        lumpy_add("Bush_Snow", snow_rows, c, on_top, m)


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
            lathe("Woodpile_WoodDark", [(0, 1.9), (s * 0.8, 1.9), (s * 0.8, 1.92), (0, 1.92)], seg=6, m=place)
    for x in (-3.4, 3.4):
        box("Woodpile_WoodDark", (0.3, 0.3, 3.6), m @ T(x, 0, 1.8), bevel=0)
    c = (0, 0, 3.32)
    rows = lumpy_grid(c, (2.5, 2.05, 0.62), 7, 14, 8)
    lumpy_add("Woodpile_Snow", rows, c, lambda p: p.z > 3.2, m)


def bins():
    m = O("Bins")
    for x in (-1.4, 1.4):
        lathe("Bins_Bins", [(0, 0), (1.0, 0), (1.2, 3.1), (1.28, 3.1), (1.28, 3.35), (0, 3.55)], seg=10, m=m @ T(x, 0, 0))
        blob("Bins_Snow", (1.05, 1.05, 0.34), m @ T(x, 0, 3.6), e=0.8, nu=10, nv=5)


def garden_lamp():
    m = O("GardenLamp")
    lathe("GardenLamp_Iron", [(0, 0), (0.28, 0), (0.1, 0.3), (0.1, 3.3), (0, 3.3)], seg=6, m=m)
    lathe("GardenLamp_Light", [(0, 3.2), (0.32, 3.3), (0.32, 3.95), (0, 4.05)], seg=8, m=m)
    lathe("GardenLamp_Iron", [(0, 4.0), (0.45, 4.0), (0.45, 4.1), (0, 4.4)], seg=6, m=m)
    lathe("GardenLamp_Snow", [(0, 4.2), (0.4, 4.2), (0, 4.62)], seg=6, m=m)


def street_lamp():
    m = O("StreetLamp")
    lathe("StreetLamp_Iron", [(0, 0), (0.75, 0), (0.68, 0.3), (0.42, 0.6), (0.3, 1.1), (0.24, 1.3), (0.17, 10.4), (0.3, 10.6), (0.3, 10.85), (0.4, 11.0), (0, 11.0)], seg=8, m=m)
    lathe("StreetLamp_Light", [(0, 11.0), (0.4, 11.0), (0.66, 12.7), (0, 12.7)], seg=6, m=m)
    lathe("StreetLamp_Iron", [(0, 12.65), (0.88, 12.65), (0.88, 12.8), (0.28, 13.35), (0, 13.5)], seg=6, m=m)
    for k in range(6):
        a = 2 * math.pi * k / 6
        x0, y0 = 0.42 * math.cos(a), 0.42 * math.sin(a)
        x1, y1 = 0.7 * math.cos(a), 0.7 * math.sin(a)
        tube("StreetLamp_Iron", [m @ Vector((x0, y0, 11.0)), m @ Vector((x1, y1, 12.7))], 0.035, seg=3)
    lathe("StreetLamp_Snow", [(0, 13.0), (0.74, 13.0), (0.4, 13.45), (0.12, 13.72), (0, 13.75)], seg=6, m=m)


def snowbank():
    m = O("Snowbank")
    for i in range(6):
        x = -10 + i * 4
        r = 2.6 + rng.random() * 1.1
        c = (x, rng.random() * 0.5, r * 0.25)
        rows = lumpy_grid(c, (r * 1.15, 2.1, r * 0.78), i + 11, 14, 8)
        lumpy_add("Snowbank_Snow", rows, c, lambda p: p.z > -0.2, m)


# ============================================================
# Соседские дома: те же приёмы, что у главного дома, но деталей меньше
# ============================================================
class Neighbor:
    def __init__(self, prop):
        self.p = prop
        self.m = O(prop)

    def k(self, mat):
        return f"{self.p}_{mat}"

    def box(self, mat, size, pos, frame=None):
        base = self.m @ frame if frame is not None else self.m
        box(self.k(mat), size, base @ T(*pos), bevel=0)

    def frame(self, side, p, offset=0.0):
        if side == "front":
            return T(offset, p, 0)
        if side == "back":
            return T(offset, p, 0) @ R(180, "Z")
        if side == "right":
            return T(p, offset, 0) @ R(90, "Z")
        return T(p, offset, 0) @ R(-90, "Z")

    def boards(self, frame, half, z0, z1, gable_from=None, slope=1.0, step=1.4):
        z = z0 + step / 2
        while z < z1:
            h = half
            if gable_from is not None and z > gable_from:
                h = half - (z - gable_from) / slope
            if h > 0.5:
                self.box("Wall", (h * 2, 0.14, step - 0.16), (0, -0.07, z), frame)
            z += step

    def block(self, x0, x1, y0, y1, height):
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        self.box("Shade", (x1 - x0, y1 - y0, height), (cx, cy, height / 2))
        self.box("Shade", (x1 - x0 + 0.5, y1 - y0 + 0.5, 1.5), (cx, cy, 0.75))
        hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
        for side, p, half, off in (("front", y0, hx, cx), ("back", y1, hx, cx), ("left", x0, hy, cy), ("right", x1, hy, cy)):
            self.boards(self.frame(side, p, off), half, 1.5, height)
        for sx in (x0, x1):
            for sy in (y0, y1):
                self.box("Trim", (0.6, 0.6, height - 1.5), (sx, sy, (height + 1.5) / 2))

    def slab_pair(self, quad):
        pts = [Vector(p) for p in quad]
        n = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
        if n.z < 0:
            n = -n
        hexa(self.k("Roof"), [tuple(p - n * 0.35) for p in pts], [tuple(p) for p in pts], self.m)
        c = sum(pts, Vector()) / 4
        near = [p + (c - p).normalized() * 0.3 for p in pts]
        hexa(self.k("Snow"), [tuple(p) for p in near], [tuple(p + n * 0.5) for p in near], self.m)

    def tri(self, verts):
        solid(self.k("Shade"), verts, [[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]], self.m)

    def gable_y(self, xc, half, y0, y1, z0, rise, over=1.0, end=1.0):
        """Конёк вдоль Y: торцы y0 и y1 с вагонкой."""
        self.tri([(xc - half, y0, z0), (xc + half, y0, z0), (xc, y0, z0 + rise), (xc - half, y1, z0), (xc + half, y1, z0), (xc, y1, z0 + rise)])
        slope = rise / half
        self.boards(T(xc, y0, 0), half, z0, z0 + rise, gable_from=z0, slope=slope)
        self.boards(T(xc, y1, 0) @ R(180, "Z"), half, z0, z0 + rise, gable_from=z0, slope=slope)
        edge = z0 - over * slope
        ridge = z0 + rise
        for d in (-1, 1):
            self.slab_pair([(xc + d * (half + over), y0 - end, edge), (xc, y0 - end, ridge), (xc, y1 + end, ridge), (xc + d * (half + over), y1 + end, edge)])
            self.box("Trim", (0.3, y1 - y0 + 2 * end, 0.3), (xc + d * (half + over), (y0 + y1) / 2, edge - 0.15))

    def gable_x(self, x0, x1, yc, half, z0, rise, over=1.0, end=1.0):
        """Конёк вдоль X: торцы x0 и x1 с вагонкой."""
        self.tri([(x0, yc - half, z0), (x0, yc + half, z0), (x0, yc, z0 + rise), (x1, yc - half, z0), (x1, yc + half, z0), (x1, yc, z0 + rise)])
        slope = rise / half
        self.boards(self.frame("left", x0, yc), half, z0, z0 + rise, gable_from=z0, slope=slope)
        self.boards(self.frame("right", x1, yc), half, z0, z0 + rise, gable_from=z0, slope=slope)
        edge = z0 - over * slope
        ridge = z0 + rise
        for d in (-1, 1):
            self.slab_pair([(x0 - end, yc + d * (half + over), edge), (x0 - end, yc, ridge), (x1 + end, yc, ridge), (x1 + end, yc + d * (half + over), edge)])
            self.box("Trim", (x1 - x0 + 2 * end, 0.3, 0.3), ((x0 + x1) / 2, yc + d * (half + over), edge - 0.15))

    def window(self, frame, u, z, w=4.4, h=4.2, lit=True, shutters=True):
        zc = z + h / 2
        self.box("Light" if lit else "Roof", (w, 0.12, h), (u, -0.1, zc), frame)
        for d in (-1, 1):
            self.box("Trim", (0.3, 0.3, h + 0.6), (u + d * (w / 2 + 0.15), -0.15, zc), frame)
            self.box("Trim", (w, 0.3, 0.3), (u, -0.15, zc + d * (h / 2 + 0.15)), frame)
            if shutters:
                self.box("Accent", (1.0, 0.18, h + 0.3), (u + d * (w / 2 + 0.85), -0.09, zc), frame)
        self.box("Trim", (0.16, 0.22, h), (u, -0.18, zc), frame)
        self.box("Trim", (w, 0.22, 0.16), (u, -0.18, zc), frame)
        self.box("Snow", (w + 0.6, 0.5, 0.26), (u, -0.3, z - 0.18), frame)

    def door(self, frame, u, z=0.0, w=4.4, h=7.6):
        self.box("Accent", (w, 0.18, h), (u, -0.3, z + h / 2), frame)
        for d in (-1, 1):
            self.box("Trim", (0.4, 0.36, h + 0.4), (u + d * (w / 2 + 0.2), -0.28, z + h / 2 + 0.2), frame)
        self.box("Trim", (w, 0.36, 0.4), (u, -0.28, z + h + 0.2), frame)
        self.box("Light", (w - 1.0, 0.1, 0.9), (u, -0.42, z + h - 0.9), frame)

    def porch(self, xc, y_wall, width, depth, roof_z):
        """Крыльцо с навесом: пол, столбы, скат."""
        y1 = y_wall - depth
        self.box("Shade", (width, depth, 1.2), (xc, y_wall - depth / 2, 0.6))
        self.box("Wall", (width + 0.3, depth + 0.3, 0.2), (xc, y_wall - depth / 2, 1.25))
        for d in (-1, 1):
            self.box("Trim", (0.5, 0.5, roof_z - 1.3), (xc + d * (width / 2 - 0.4), y1 + 0.4, (roof_z + 1.3) / 2))
        self.box("Trim", (width, 0.4, 0.4), (xc, y1 + 0.4, roof_z - 0.1))
        self.slab_pair([(xc - width / 2 - 0.5, y_wall, roof_z + 1.3), (xc + width / 2 + 0.5, y_wall, roof_z + 1.3), (xc + width / 2 + 0.5, y1 - 0.5, roof_z), (xc - width / 2 - 0.5, y1 - 0.5, roof_z)])

    def chimney(self, x, y, z0, z1):
        self.box("Shade", (2.6, 2.6, z1 - z0), (x, y, (z0 + z1) / 2))
        self.box("Accent", (3.0, 3.0, 0.3), (x, y, z1 + 0.15))
        self.box("Snow", (2.8, 2.8, 0.25), (x, y, z1 + 0.42))

    def icicles(self, x0, x1, y, z, step=3.0):
        x = x0
        while x < x1:
            base = self.m @ Vector((x + rng.random(), y, z))
            lathe(self.k("Snow"), [(0, 0), (0.7, 0), (0.5, 0.25), (0, 0.42)], seg=6, m=T(base.x, base.y, base.z - 0.1))
            x += step + rng.random()


def house_a():
    """Полтора этажа, фронтон к улице, крыльцо, пристроенный гараж справа."""
    h = Neighbor("HouseA")
    h.block(-13, 13, -11, 11, 11)
    h.gable_y(0, 13, -11, 11, 11, 9)
    front = h.frame("front", -11)
    back = h.frame("back", 11)
    h.window(front, -7.6, 3.2)
    h.window(front, 7.6, 3.2, lit=False)
    h.window(front, 0, 12.6, w=3.4, h=3.2, shutters=False)
    h.window(back, -6.5, 3.2)
    h.window(back, 6.5, 3.2)
    h.window(back, 0, 12.6, w=3.4, h=3.2, shutters=False, lit=False)
    left = h.frame("left", -13)
    h.window(left, -4.5, 3.2)
    h.window(left, 4.5, 3.2, lit=False)
    h.door(front, 0, 1.2)
    h.porch(0, -11, 9.4, 4.4, 9.4)
    # Гараж
    h.block(13, 27, -9, 11, 9)
    h.gable_x(13, 27, 1, 10, 9, 5.4)
    gf = h.frame("front", -9, 20)
    h.box("Trim", (10.5, 0.18, 7.4), (0, -0.25, 3.9), gf)
    for row in (1.9, 3.7, 5.5):
        h.box("Shade", (10.5, 0.2, 0.1), (0, -0.28, row), gf)
    h.box("Light", (9.5, 0.1, 0.8), (0, -0.33, 6.7), gf)
    h.chimney(-7, 3.5, 13, 21.5)


def house_b():
    """Два этажа, конёк вдоль улицы, слуховые окна, крыльцо по центру."""
    h = Neighbor("HouseB")
    h.block(-19, 19, -11, 11, 17)
    h.gable_x(-19, 19, 0, 11, 17, 8.5)
    front = h.frame("front", -11)
    back = h.frame("back", 11)
    for x, lit in ((-13, True), (0, True), (13, False)):
        h.window(front, x, 10.8, lit=lit)
    for x, lit in ((-13, True), (13, True)):
        h.window(front, x, 3.4, lit=lit)
    for x, lit in ((-13, False), (0, True), (13, True)):
        h.window(back, x, 10.8, lit=lit)
    for x, lit in ((-13, True), (13, False)):
        h.window(back, x, 3.4, lit=lit)
    for side, p in (("left", -19), ("right", 19)):
        f = h.frame(side, p)
        h.window(f, -4.5, 10.8, shutters=False, lit=side == "left")
        h.window(f, 4.5, 3.4, shutters=False, lit=side == "right")
    h.door(front, 0, 1.2)
    h.porch(0, -11, 11, 4.6, 9.2)
    # Слуховые окна на переднем скате
    slope = 8.5 / 11
    for x in (-8, 8):
        y0 = -9.0
        z0 = 17 + (11 + y0) * slope
        h.box("Shade", (5.4, 4.6, 3.2), (x, y0 + 2.3, z0 + 1.6))
        h.boards(T(x, y0, 0), 2.7, z0, z0 + 3.2)
        h.window(T(x, y0, 0), 0, z0 + 0.5, w=2.8, h=2.2, shutters=False)
        h.tri([(x - 2.7, y0, z0 + 3.2), (x + 2.7, y0, z0 + 3.2), (x, y0, z0 + 5.0), (x - 2.7, y0 + 4.6, z0 + 3.2), (x + 2.7, y0 + 4.6, z0 + 3.2), (x, y0 + 4.6, z0 + 5.0)])
        h.slab_pair([(x - 3.3, y0 - 0.4, z0 + 2.9), (x, y0 - 0.4, z0 + 5.2), (x, y0 + 5, z0 + 5.2), (x - 3.3, y0 + 5, z0 + 2.9)])
        h.slab_pair([(x + 3.3, y0 - 0.4, z0 + 2.9), (x, y0 - 0.4, z0 + 5.2), (x, y0 + 5, z0 + 5.2), (x + 3.3, y0 + 5, z0 + 2.9)])
    h.chimney(-14, 2.5, 20, 29)
    h.chimney(14, -2.5, 20, 29)


def house_c():
    """Г-образный дом: длинный объём и выступающее крыло с фронтоном, веранда вдоль фасада."""
    h = Neighbor("HouseC")
    h.block(-18, 8, -5, 11, 13)
    h.gable_x(-18, 8, 3, 8, 13, 7)
    h.block(8, 22, -13, 11, 13)
    h.gable_y(15, 7, -13, 11, 13, 7)
    front = h.frame("front", -5)
    wing = h.frame("front", -13, 15)
    back = h.frame("back", 11)
    h.window(front, -13, 3.4)
    h.window(front, -2.5, 3.4, lit=False)
    h.window(front, -7.8, 8.5, w=3.6, h=3.0, shutters=False)
    h.door(front, 4.2, 1.2, w=4.0)
    h.window(wing, 0, 3.4, w=6.2, h=4.4)
    h.window(wing, 0, 9.3, w=4.2, h=3.2, shutters=False, lit=False)
    h.window(wing, 0, 15.4, w=2.6, h=2.2, shutters=False)
    h.window(back, -12, 3.4)
    h.window(back, -2, 3.4)
    h.window(back, 10, 3.4, lit=False)
    h.window(back, 10, 9, shutters=False)
    h.window(h.frame("right", 22, -1), 5, 3.4, lit=False)
    h.window(h.frame("right", 22, -1), -5, 3.4)
    h.window(h.frame("left", -18, 3), 0, 3.4)
    # Веранда вдоль фасада
    h.box("Shade", (26, 5.4, 1.2), (-5, -7.7, 0.6))
    h.box("Wall", (26.3, 5.7, 0.2), (-5, -7.7, 1.25))
    for x in (-17.6, -10, -2, 7.4):
        h.box("Trim", (0.46, 0.46, 7.4), (x, -10.0, 5.0))
    h.box("Trim", (26, 0.36, 0.36), (-5, -10.0, 8.7))
    h.slab_pair([(-18.6, -5, 10.4), (8, -5, 10.4), (8, -10.8, 8.9), (-18.6, -10.8, 8.9)])
    h.chimney(-12, 7, 15, 25)


picket()
plank()
gate("GateA", 20.0)
gate("GateB", 27.0)
car()
bush()
bench()
sled()
woodpile()
bins()
garden_lamp()
street_lamp()
snowbank()
house_a()
house_b()
house_c()

# Центры мешей для сборки в Studio
manifest = {"props": {p: list(v[0]) for p, v in PROPS.items()}, "centers": {}, "sections": {"Picket": SECTION_PICKET, "Plank": SECTION_PLANK}}
for key, b in buckets.items():
    if not b.verts:
        print("EMPTY", key)
        continue
    lo = [min(v[i] for v in b.verts) for i in range(3)]
    hi = [max(v[i] for v in b.verts) for i in range(3)]
    manifest["centers"][key] = [round((lo[i] + hi[i]) / 2, 3) for i in range(3)]
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "world_kit.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=1)

VIEWS = {
    "car": ((-58, -14, 6.5), (-70, 0, 2.6)),
    "carback": ((-82, 14, 7), (-70, 0, 2.6)),
    "props": ((-22, -24, 8), (-22, 0, 2)),
    "gate": ((-140, -20, 6.5), (-140, 0, 2.4)),
    "fence": ((-100, -18, 6.5), (-100, 0, 2.4)),
    "housea": ((-58, 18, 12), (-80, 60, 9)),
    "houseb": ((10, 18, 12), (-20, 60, 11)),
    "housec": ((70, 12, 12), (48, 60, 9)),
    "housesback": ((-20, 130, 18), (-20, 60, 10)),
    "bush": ((-49, -8, 5), (-55, 0, 1.8)),
    "lamp": ((16, -8, 8), (10, 0, 8)),
}
finish("Kit", MATERIALS, OUT, "world_kit", render=RENDER, views=VIEWS, ground=(0.82, 0.86, 0.95, 1))
