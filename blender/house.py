# Дом с гаражом для карты «Дом» Snow Cleaning Simulator. Запуск:
#   blender --background --python house.py -- <папка вывода> [render]
# Начало координат — центр дома на уровне земли: в игре (0, 1, -67). Перед смотрит в -Y (в игре +Z, к двору).
# Занимает то же место, что Blockout.House: дом x -25..25, гараж x 28..52, y -15..15.
# Вперёд выступают только веранда со ступенями (до y = -25) и верхние фронтоны (до y = -18.2).
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modellib import R, T, box, finish, hexa, icicle, lathe, snow_lump, solid, tube, use_materials

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.dirname(os.path.abspath(__file__))
RENDER = "render" in argv

# Имя: (цвет RGB 0-255, metallic, roughness, сила свечения)
MATERIALS = {
    "Siding": ((226, 200, 152), 0.0, 0.7, 0),
    "SidingShade": ((176, 150, 110), 0.0, 0.8, 0),
    "Trim": ((246, 240, 228), 0.0, 0.6, 0),
    "Shutter": ((50, 88, 98), 0.0, 0.6, 0),
    "Shingle": ((60, 68, 82), 0.0, 0.85, 0),
    "Stone": ((122, 120, 124), 0.0, 0.95, 0),
    "Brick": ((150, 80, 65), 0.0, 0.9, 0),
    "Door": ((150, 44, 38), 0.0, 0.4, 0),
    "Wood": ((150, 108, 72), 0.0, 0.75, 0),
    "Iron": ((40, 44, 50), 0.7, 0.5, 0),
    "Brass": ((222, 168, 62), 1.0, 0.28, 0),
    "Pine": ((46, 92, 62), 0.0, 0.85, 0),
    "Snow": ((244, 249, 255), 0.0, 0.75, 0),
    "Ice": ((170, 222, 255), 0.0, 0.08, 0),
    "Light": ((255, 196, 110), 0.0, 0.5, 5),
    "BulbRed": ((255, 70, 60), 0.0, 0.5, 5),
    "BulbGold": ((255, 200, 90), 0.0, 0.5, 5),
    "BulbGreen": ((80, 230, 110), 0.0, 0.5, 5),
    "BulbBlue": ((90, 160, 255), 0.0, 0.5, 5),
}
use_materials(MATERIALS)

rng = random.Random(7)

FLOOR1, FLOOR2 = 3.2, 11.6  # низ окон первого и второго этажа
EAVE = 19.0  # верх стен дома
RIDGE = 31.0  # конёк дома
SLOPE = 0.8  # уклон крыш дома
BOARD_STEP = 1.25


# Стороны стены: локально стена в плоскости y = 0, наружу -Y, u — вдоль стены
def wall(side, p):
    """side: front/back — p по Y, left/right — p по X."""
    if side == "front":
        return T(0, p, 0)
    if side == "back":
        return T(0, p, 0) @ R(180, "Z")
    if side == "right":
        return T(p, 0, 0) @ R(90, "Z")
    return T(p, 0, 0) @ R(-90, "Z")


def slab(mat, quad, lift, thick):
    """Плита по четырёхугольнику: lift — подъём верха над ним, thick — толщина."""
    pts = [Vector(p) for p in quad]
    n = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
    if n.z < 0:
        n = -n
    hexa(mat, [tuple(p + n * (lift - thick)) for p in pts], [tuple(p + n * lift) for p in pts])


def inset(quad, d):
    pts = [Vector(p) for p in quad]
    c = sum(pts, Vector()) / 4
    return [tuple(p + (c - p).normalized() * d) for p in pts]


def roof_quad(quad, snow_inset=0.3):
    slab("Trim", quad, -0.22, 0.2)
    slab("Shingle", quad, 0.0, 0.22)
    slab("Snow", inset(quad, snow_inset), 0.42, 0.44)


def tri_x(mat, x0, x1, half, z0, rise, y=0.0):
    """Треугольный чердак с коньком вдоль X."""
    solid(
        mat,
        [(x0, y - half, z0), (x0, y + half, z0), (x0, y, z0 + rise), (x1, y - half, z0), (x1, y + half, z0), (x1, y, z0 + rise)],
        [[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]],
    )


def tri_y(mat, y0, y1, xc, half, z0, rise):
    """Треугольный чердак с коньком вдоль Y."""
    solid(
        mat,
        [(xc - half, y0, z0), (xc + half, y0, z0), (xc, y0, z0 + rise), (xc - half, y1, z0), (xc + half, y1, z0), (xc, y1, z0 + rise)],
        [[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]],
    )


def gable_y(xc, half, y0, y1, z0, slope, over):
    """Двускатная крыша с коньком вдоль Y: z0 — высота ската над краем стены."""
    ridge = z0 + half * slope
    edge = z0 - over * slope
    x0, x1 = xc - half - over, xc + half + over
    roof_quad([(x0, y0, edge), (xc, y0, ridge), (xc, y1, ridge), (x0, y1, edge)])
    roof_quad([(x1, y0, edge), (xc, y0, ridge), (xc, y1, ridge), (x1, y1, edge)])


def boards(m, half, z0, z1, gable_from=None, slope=SLOPE):
    """Горизонтальная вагонка на стене: выше gable_from ряд сужается по скату."""
    z = z0 + BOARD_STEP / 2
    while z < z1:
        h = half
        if gable_from is not None and z > gable_from:
            h = half - (z - gable_from) / slope
        if h > 0.4:
            box("Siding", (h * 2, 0.14, BOARD_STEP - 0.14), m @ T(0, -0.07, z), bevel=0)
        z += BOARD_STEP


def window(m, u, z, w=5.0, h=4.6, shutters=True):
    """Окно на стене m: u — центр вдоль стены, z — низ."""
    zc = z + h / 2
    box("Light", (w, 0.12, h), m @ T(u, -0.1, zc), bevel=0)
    for d in (-1, 1):
        box("Trim", (0.36, 0.34, h + 0.72), m @ T(u + d * (w / 2 + 0.18), -0.17, zc), bevel=0)
        box("Trim", (w, 0.34, 0.36), m @ T(u, -0.17, zc + d * (h / 2 + 0.18)), bevel=0)
    box("Trim", (0.2, 0.26, h), m @ T(u, -0.2, zc), bevel=0)
    box("Trim", (w, 0.26, 0.2), m @ T(u, -0.2, zc), bevel=0)
    box("Trim", (w + 1.1, 0.7, 0.26), m @ T(u, -0.4, z - 0.42), bevel=0)
    box("Snow", (w + 0.8, 0.62, 0.3), m @ T(u, -0.42, z - 0.17), bevel=0)
    if shutters:
        for d in (-1, 1):
            box("Shutter", (1.2, 0.2, h + 0.5), m @ T(u + d * (w / 2 + 1.0), -0.1, zc), bevel=0)


def round_window(m, u, z, r=1.5):
    place = m @ T(u, -0.08, z) @ R(90, "X")
    lathe("Trim", [(0, -0.08), (r + 0.34, -0.08), (r + 0.34, 0.2), (r, 0.2), (0, 0.1)], seg=16, m=place)
    lathe("Light", [(0, 0.1), (r, 0.1), (r, 0.14), (0, 0.14)], seg=16, m=place)
    box("Trim", (r * 2, 0.34, 0.16), m @ T(u, -0.33, z), bevel=0)
    box("Trim", (0.16, 0.34, r * 2), m @ T(u, -0.33, z), bevel=0)


def wreath(m, u, z, r=1.05, t=0.34):
    place = m @ T(u, -0.4, z) @ R(90, "X")
    lathe("Pine", [(r, -t), (r + t, 0), (r, t), (r - t, 0), (r, -t)], seg=10, m=place)
    box("Door", (0.8, 0.2, 0.34), m @ T(u, -0.62, z - r - 0.1), bevel=0)


def door(m, u, z, w=5.2, h=8.2, wreathed=True):
    zc = z + h / 2
    box("Door", (w, 0.2, h), m @ T(u, -0.1, zc), bevel=0)
    for d in (-1, 1):
        box("Trim", (0.46, 0.4, h + 0.46), m @ T(u + d * (w / 2 + 0.23), -0.2, zc + 0.23), bevel=0)
        for row in (z + 1.7, z + 4.4):
            box("SidingShade", (w / 2 - 0.9, 0.08, 2.0), m @ T(u + d * w / 4, -0.22, row), bevel=0)
    box("Trim", (w, 0.4, 0.46), m @ T(u, -0.2, z + h + 0.23), bevel=0)
    box("Light", (w - 1.0, 0.1, 1.2), m @ T(u, -0.22, z + h - 1.1), bevel=0)
    lathe("Brass", [(0, 0), (0.17, 0.02), (0.17, 0.16), (0, 0.2)], seg=6, m=m @ T(u + w / 2 - 0.5, -0.2, z + 3.7) @ R(90, "X"))
    if wreathed:
        wreath(m, u, z + 4.9)


def lantern(pos):
    x, y, z = pos
    box("Iron", (0.8, 0.8, 0.14), T(x, y, z + 0.82), bevel=0)
    box("Iron", (0.8, 0.8, 0.14), T(x, y, z - 0.82), bevel=0)
    box("Light", (0.56, 0.56, 1.5), T(x, y, z), bevel=0)


def garland(p0, p1, n, sag=0.35):
    """Гирлянда от p0 к p1 с провисанием: провод и n лампочек по кругу цветов."""
    p0, p1 = Vector(p0), Vector(p1)
    path = []
    for i in range(n + 1):
        t = i / n
        path.append(p0.lerp(p1, t) - Vector((0, 0, sag * 4 * t * (1 - t))))
    tube("Iron", path, 0.035, seg=3, caps=False)
    colors = ("BulbRed", "BulbGold", "BulbGreen", "BulbBlue")
    for i, p in enumerate(path):
        lathe(colors[(i + rng.randrange(2)) % 4], [(0, -0.42), (0.17, -0.3), (0.17, -0.14), (0, -0.04)], seg=5, m=T(*p))


def eave_snow(x0, x1, y, z, step=2.6, ice=0.55):
    """Комья снега и сосульки вдоль горизонтального края крыши."""
    x = x0
    while x <= x1:
        snow_lump(x, y, z - 0.1, 0.7 + rng.random() * 0.5, seg=7)
        if rng.random() < ice:
            icicle((x + rng.random(), y - 0.12, z - 0.15), 0.8 + rng.random() * 1.1, seg=4)
        x += step + rng.random() * 0.8


# ============================================================
# Основной объём дома
# ============================================================
box("SidingShade", (50, 30, EAVE), T(0, 0, EAVE / 2), bevel=0)
tri_x("SidingShade", -25, 25, 15, EAVE, (RIDGE - EAVE) * 15 / 15)
box("Stone", (50.5, 30.5, 1.7), T(0, 0, 0.85), bevel=0)

boards(wall("front", -15), 25, 1.7, EAVE)
boards(wall("back", 15), 25, 1.7, EAVE)
for side, x in (("left", -25), ("right", 25)):
    boards(wall(side, x), 15, 1.7, RIDGE, gable_from=EAVE)

for sx in (-25, 25):
    for sy in (-15, 15):
        box("Trim", (0.7, 0.7, EAVE - 1.7), T(sx, sy, (EAVE + 1.7) / 2), bevel=0)
for side, p, half in (("front", -15, 25), ("back", 15, 25), ("left", -25, 15), ("right", 25, 15)):
    box("Trim", (half * 2, 0.3, 0.4), wall(side, p) @ T(0, -0.15, 9.4), bevel=0)

# Основная крыша, конёк вдоль X
ROOF_X, ROOF_Y = 27.0, 17.0
z_edge = RIDGE - ROOF_Y * SLOPE
roof_quad([(-ROOF_X, -ROOF_Y, z_edge), (ROOF_X, -ROOF_Y, z_edge), (ROOF_X, 0, RIDGE), (-ROOF_X, 0, RIDGE)])
roof_quad([(-ROOF_X, ROOF_Y, z_edge), (ROOF_X, ROOF_Y, z_edge), (ROOF_X, 0, RIDGE), (-ROOF_X, 0, RIDGE)])
box("Snow", (ROOF_X * 2 - 0.4, 0.9, 0.5), T(0, 0, RIDGE + 0.42), bevel=0.1)

# ============================================================
# Передние фронтоны второго этажа: большой слева, малый справа
# ============================================================
GABLE_Y = -17.4
for xc, half, y_end in ((-13.0, 10.0, -4.0), (13.0, 7.0, -7.0)):
    rise = half * SLOPE
    box("SidingShade", (half * 2, -GABLE_Y - 15, EAVE - 10.2), T(xc, (GABLE_Y - 15) / 2, (EAVE + 10.2) / 2), bevel=0)
    tri_y("SidingShade", GABLE_Y, y_end, xc, half, EAVE, rise)
    boards(T(xc, GABLE_Y, 0), half, 10.2, EAVE + rise, gable_from=EAVE)
    gable_y(xc, half, GABLE_Y - 0.8, y_end, EAVE, SLOPE, 0.9)
    box("Trim", (half * 2 + 0.3, 2.7, 0.34), T(xc, (GABLE_Y - 15) / 2, 10.1), bevel=0)
    for d in (-1, 1):
        box("Trim", (0.4, 0.4, EAVE - 10.2), T(xc + d * half, GABLE_Y, (EAVE + 10.2) / 2), bevel=0)
        # Кронштейны под выступом
        hexa(
            "Wood",
            [(xc + d * (half - 1.2) - 0.25, -15.0, 8.6), (xc + d * (half - 1.2) + 0.25, -15.0, 8.6), (xc + d * (half - 1.2) + 0.25, -15.0, 10.0), (xc + d * (half - 1.2) - 0.25, -15.0, 10.0)],
            [(xc + d * (half - 1.2) - 0.25, GABLE_Y + 0.1, 9.9), (xc + d * (half - 1.2) + 0.25, GABLE_Y + 0.1, 9.9), (xc + d * (half - 1.2) + 0.25, GABLE_Y + 0.1, 10.0), (xc + d * (half - 1.2) - 0.25, GABLE_Y + 0.1, 10.0)],
        )

front_gable = T(0, GABLE_Y, 0)
window(front_gable, -18.0, FLOOR2)
window(front_gable, -8.0, FLOOR2)
round_window(front_gable, -13.0, 22.6, 1.7)
window(front_gable, 13.0, FLOOR2, w=6.4)
round_window(front_gable, 13.0, 21.2, 1.15)

# ============================================================
# Окна
# ============================================================
front = wall("front", -15)
window(front, 0.0, 13.0, w=4.2, h=3.8, shutters=False)
window(front, -18.0, FLOOR1)
window(front, 18.0, FLOOR1)

back = wall("back", 15)
for u in (-18.0, -6.5, 6.5, 18.0):
    window(back, u, FLOOR2)
for u in (-18.0, -8.0, 8.0, 18.0):
    window(back, u, FLOOR1)
door(wall("back", 15.25), 0.0, 1.1, wreathed=False)
for d in (-1, 1):
    box("Stone", (6.4, 3.0, 1.1), T(0, 16.5, 0.55), bevel=0)
hexa("Shingle", [(-3.9, 15.0, 10.6), (3.9, 15.0, 10.6), (3.9, 18.4, 9.6), (-3.9, 18.4, 9.6)], [(-3.9, 15.0, 10.9), (3.9, 15.0, 10.9), (3.9, 18.4, 9.9), (-3.9, 18.4, 9.9)])
slab("Snow", inset([(-3.9, 15.0, 10.9), (3.9, 15.0, 10.9), (3.9, 18.4, 9.9), (-3.9, 18.4, 9.9)], 0.15), 0.3, 0.3)
for sx in (-3.5, 3.5):
    box("Trim", (0.34, 0.34, 8.7), T(sx, 18.0, 5.3), bevel=0)
lantern((-4.6, 15.5, 7.5))

left = wall("left", -25)
for u in (-7.0, 7.0):
    window(left, u, FLOOR1)
    window(left, u, FLOOR2)
round_window(left, 0.0, 24.4, 1.7)
right = wall("right", 25)
for u in (-7.0, 7.0):
    window(right, u, FLOOR2)
round_window(right, 0.0, 24.4, 1.7)

# ============================================================
# Веранда со ступенями перед дверью
# ============================================================
VX, VY, VZ = 11.0, -22.0, 1.4  # полуширина, передний край, высота пола
box("Stone", (VX * 2, -VY - 15, VZ - 0.3), T(0, (VY - 15) / 2, (VZ - 0.3) / 2), bevel=0)
box("Wood", (VX * 2 + 0.4, -VY - 15 + 0.4, 0.3), T(0, (VY - 15) / 2, VZ - 0.15), bevel=0)
for i, (y, z) in enumerate(((VY - 0.5, 0.93), (VY - 1.5, 0.47))):
    box("Wood", (8.4 + i * 0.8, 1.0, 0.16), T(0, y, z - 0.08), bevel=0)
    box("Stone", (8.4 + i * 0.8, 1.0, z - 0.16), T(0, y, (z - 0.16) / 2), bevel=0)
    box("Snow", (2.2, 0.8, 0.12), T(-3.2 + i, y, z + 0.04), bevel=0.03)

door(wall("front", -15.25), 0.0, VZ)

POST_Y = VY + 0.4
for u in (-VX + 0.4, -4.3, 4.3, VX - 0.4):
    box("Trim", (0.7, 0.7, 8.0), T(u, POST_Y, VZ + 4.0), bevel=0)
    box("Trim", (1.0, 1.0, 0.8), T(u, POST_Y, VZ + 0.4), bevel=0)
for u in (-VX + 0.4, VX - 0.4):
    box("Trim", (0.6, 0.6, 8.0), T(u, -15.4, VZ + 4.0), bevel=0)


def railing(p0, p1):
    p0, p1 = Vector(p0), Vector(p1)
    mid = (p0 + p1) / 2
    along_x = abs(p1.x - p0.x) > abs(p1.y - p0.y)
    length = (p1 - p0).length
    for z in (VZ + 0.6, VZ + 3.1):
        size = (length, 0.28, 0.2) if along_x else (0.28, length, 0.2)
        box("Trim", size, T(mid.x, mid.y, z), bevel=0)
    box("Snow", ((length, 0.36, 0.2) if along_x else (0.36, length, 0.2)), T(mid.x, mid.y, VZ + 3.28), bevel=0)
    n = int(length / 0.85)
    for i in range(1, n):
        p = p0.lerp(p1, i / n)
        box("Trim", (0.14, 0.14, 2.4), T(p.x, p.y, VZ + 1.85), bevel=0)


railing((-VX + 0.4, POST_Y, 0), (-4.3, POST_Y, 0))
railing((4.3, POST_Y, 0), (VX - 0.4, POST_Y, 0))
railing((-VX + 0.4, POST_Y, 0), (-VX + 0.4, -15.4, 0))
railing((VX - 0.4, POST_Y, 0), (VX - 0.4, -15.4, 0))

# Навес и фронтон над ступенями
VEAVE = VZ + 8.0
roof_quad([(-VX - 0.6, -14.9, VEAVE + 1.5), (VX + 0.6, -14.9, VEAVE + 1.5), (VX + 0.6, VY - 0.8, VEAVE - 0.1), (-VX - 0.6, VY - 0.8, VEAVE - 0.1)])
box("Trim", (VX * 2, 0.5, 0.6), T(0, POST_Y, VEAVE - 0.2), bevel=0)
tri_y("Trim", VY - 0.2, -16.0, 0.0, 5.0, VEAVE, 3.5)
gable_y(0.0, 5.0, VY - 1.0, -16.0, VEAVE, 0.7, 0.7)
round_window(T(0, VY - 0.2, 0), 0.0, VEAVE + 1.25, 0.8)

# Скамья и фонарь на веранде
for d in (-1, 1):
    box("Wood", (0.3, 1.2, 1.3), T(-7.6 + d * 2.3, -16.4, VZ + 0.65), bevel=0)
box("Wood", (5.0, 1.3, 0.24), T(-7.6, -16.4, VZ + 1.35), bevel=0)
box("Wood", (5.0, 0.2, 1.3), T(-7.6, -15.8, VZ + 2.2), bevel=0)
lantern((-3.9, -15.7, VZ + 5.6))
lantern((3.9, -15.7, VZ + 5.6))

# ============================================================
# Гараж: конёк вдоль Y, ворота к подъездной дорожке. Вставка соединяет его с домом
# ============================================================
GX, GH, GWALL = 12.0, 40.0, 12.0  # полуширина, центр, высота стен
GSLOPE = 0.65
GRISE = GX * GSLOPE
box("SidingShade", (GX * 2, 30, GWALL), T(GH, 0, GWALL / 2), bevel=0)
tri_y("SidingShade", -15, 15, GH, GX, GWALL, GRISE)
box("Stone", (GX * 2 + 0.5, 30.5, 1.5), T(GH, 0, 0.75), bevel=0)
gable_y(GH, GX, -16.2, 16.2, GWALL, GSLOPE, 1.1)
box("Snow", (0.9, 32, 0.5), T(GH, 0, GWALL + GRISE + 0.42), bevel=0.1)
boards(T(GH, -15, 0), GX, 1.5, GWALL + GRISE, gable_from=GWALL, slope=GSLOPE)
boards(T(GH, 15, 0) @ R(180, "Z"), GX, 1.5, GWALL + GRISE, gable_from=GWALL, slope=GSLOPE)
boards(wall("right", GH + GX), 15, 1.5, GWALL)
for sx in (-GX, GX):
    for sy in (-15, 15):
        box("Trim", (0.7, 0.7, GWALL - 1.5), T(GH + sx, sy, (GWALL + 1.5) / 2), bevel=0)

gfront = T(GH, -15.3, 0)  # ворота стоят перед цоколем
GD_W, GD_H = 16.0, 9.0
box("Trim", (GD_W, 0.2, GD_H), gfront @ T(0, -0.1, GD_H / 2 + 0.15), bevel=0)
for d in (-1, 1):
    box("Shutter", (0.5, 0.42, GD_H + 0.5), gfront @ T(d * (GD_W / 2 + 0.25), -0.21, GD_H / 2 + 0.4), bevel=0)
box("Shutter", (GD_W + 1.0, 0.42, 0.5), gfront @ T(0, -0.21, GD_H + 0.4), bevel=0)
for row in range(1, 4):
    box("SidingShade", (GD_W, 0.24, 0.12), gfront @ T(0, -0.12, 0.15 + GD_H * row / 4), bevel=0)
for col in range(4):
    u = -GD_W / 2 + GD_W * (col + 0.5) / 4
    box("Light", (GD_W / 4 - 0.9, 0.1, 1.2), gfront @ T(u, -0.24, 0.15 + GD_H * 7 / 8), bevel=0)
    for row in range(3):
        box("SidingShade", (GD_W / 4 - 0.9, 0.05, GD_H / 4 - 0.9), gfront @ T(u, -0.22, 0.15 + GD_H * (row + 0.5) / 4), bevel=0)
wreath(T(GH, -15, 0), 0, GWALL + 2.2, r=0.95)
lantern((GH - 9.6, -15.5, 7.0))
lantern((GH + 9.6, -15.5, 7.0))

gright = wall("right", GH + GX)
window(gright, -6.0, FLOOR1 + 0.4)
window(gright, 6.0, FLOOR1 + 0.4)
gback = T(GH, 15, 0) @ R(180, "Z")
window(gback, -4.0, FLOOR1 + 0.4, w=4.4, h=4.0, shutters=False)
window(gback, 4.0, FLOOR1 + 0.4, w=4.4, h=4.0, shutters=False)

box("SidingShade", (3.4, 18, 9.0), T(26.5, 0, 4.5), bevel=0)
box("Stone", (3.6, 18.4, 1.5), T(26.5, 0, 0.75), bevel=0)
boards(T(26.5, -9, 0), 1.7, 1.5, 9.0)
boards(T(26.5, 9, 0) @ R(180, "Z"), 1.7, 1.5, 9.0)
roof_quad([(24.8, -10, 9.6), (28.2, -10, 9.6), (28.2, 10, 9.6), (24.8, 10, 9.6)], snow_inset=0.15)

# ============================================================
# Труба, снег на краях, гирлянды
# ============================================================
box("Brick", (4.0, 4.0, 12.0), T(-14.0, 5.0, 30.0), bevel=0)
box("Stone", (4.6, 4.6, 0.5), T(-14.0, 5.0, 36.1), bevel=0)
box("Iron", (2.2, 2.2, 0.8), T(-14.0, 5.0, 36.6), bevel=0)
box("Snow", (4.4, 4.4, 0.3), T(-14.0, 5.0, 36.4), bevel=0.05)

z_main = RIDGE - ROOF_Y * SLOPE
eave_snow(-2.5, 5.5, -ROOF_Y, z_main)
eave_snow(-26.5, 26.5, ROOF_Y, z_main)
eave_snow(-VX, VX, VY - 0.8, VEAVE - 0.1)
eave_snow(GH - GX, GH + GX, 16.0, GWALL + 0.3, step=3.4, ice=0.3)
for xc, half in ((-13.0, 10.0), (13.0, 7.0)):
    for d in (-1, 1):
        eave_snow(xc + d * half - 0.4, xc + d * half + 0.4, GABLE_Y - 0.6, EAVE - 0.7, step=1.0)
# Только внешний скат гаража: со стороны дома комья ловят свет окон
x = GH + GX + 1.1
y = -14.0
while y < 15.0:
    snow_lump(x, y, GWALL - 1.1 * GSLOPE - 0.1, 0.6 + rng.random() * 0.4, seg=6)
    if rng.random() < 0.4:
        icicle((x, y + 0.5, GWALL - 1.1 * GSLOPE - 0.15), 0.7 + rng.random(), seg=4)
    y += 3.0 + rng.random()

# По скатам фронтонов, вдоль веранды и по воротам гаража
for xc, half, n in ((-13.0, 10.0, 9), (13.0, 7.0, 7)):
    ridge = EAVE + half * SLOPE
    y = GABLE_Y - 0.9
    garland((xc - half - 0.9, y, EAVE - 0.9), (xc, y, ridge + 0.1), n, sag=0.25)
    garland((xc, y, ridge + 0.1), (xc + half + 0.9, y, EAVE - 0.9), n, sag=0.25)
garland((-VX - 0.4, VY - 0.95, VEAVE - 0.5), (-5.6, VY - 0.95, VEAVE - 0.5), 7)
garland((5.6, VY - 0.95, VEAVE - 0.5), (VX + 0.4, VY - 0.95, VEAVE - 0.5), 7)
garland((-5.6, VY - 1.05, VEAVE - 0.5), (0, VY - 1.05, VEAVE + 3.6), 6, sag=0.15)
garland((0, VY - 1.05, VEAVE + 3.6), (5.6, VY - 1.05, VEAVE - 0.5), 6, sag=0.15)
for u0, u1, z0, z1 in ((-13.1, 0.0, GWALL - 0.6, GWALL + GRISE + 0.2), (0.0, 13.1, GWALL + GRISE + 0.2, GWALL - 0.6)):
    garland((GH + u0, -16.3, z0), (GH + u1, -16.3, z1), 9, sag=0.25)
garland((GH - 8.4, -15.7, GD_H + 1.0), (GH + 8.4, -15.7, GD_H + 1.0), 9)
garland((-26.8, ROOF_Y + 0.1, z_main - 0.2), (26.8, ROOF_Y + 0.1, z_main - 0.2), 26, sag=0.4)

VIEWS = {
    "front": ((10, -98, 14), (10, 0, 15)),
    "corner": ((-52, -62, 24), (6, 0, 14)),
    "garage": ((58, -44, 10), (30, 0, 12)),
    "back": ((26, 64, 22), (10, 0, 14)),
}
finish("House", MATERIALS, OUT, "house", render=RENDER, views=VIEWS, ground=(0.82, 0.86, 0.95, 1))

if RENDER:
    # Синий час: тот же кадр, вечернее небо и слабое солнце
    scene = bpy.context.scene
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.24, 0.5, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    bpy.data.lights["Sun"].energy = 0.25
    bpy.data.lights["Sun"].color = (0.6, 0.72, 1.0)
    cam = bpy.data.objects["Cam"]
    for label in ("front", "corner"):
        pos, look = VIEWS[label]
        cam.location = pos
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(OUT, f"house_preview_dusk_{label}.png")
        bpy.ops.render.render(write_still=True)
    print("DONE dusk")
