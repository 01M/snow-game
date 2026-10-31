# Магазин рюкзаков для Snow Cleaning Simulator (вместо фиолетового куба UpgradeShop). Запуск:
#   blender --background --python backpack_shop.py -- <папка вывода> [render]
# Лавка с прилавком и полосатым навесом, на крыше — гигантский рюкзак, на полках рюкзаки по размеру.
# Стиль как у снегоплавилки: железо с заклёпками, латунь, медь, снежные шапки, сосульки.
import math
import os
import sys

from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modellib import (
    R, S, T, blob, box, buckets, extrude_x, facing, fillet, finish, icicle, lathe, rivet,
    round_profile, snow_lump, tube, use_materials,
)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.dirname(os.path.abspath(__file__))
RENDER = "render" in argv

# Имя: (цвет RGB 0-255, metallic, roughness, сила свечения)
MATERIALS = {
    "Iron": ((58, 62, 70), 0.85, 0.5, 0),
    "PaintBlue": ((44, 96, 122), 0.2, 0.4, 0),
    "RedPaint": ((186, 44, 34), 0.25, 0.32, 0),
    "Cream": ((244, 236, 214), 0.0, 0.5, 0),
    "Steel": ((150, 160, 172), 0.9, 0.38, 0),
    "Brass": ((222, 168, 62), 1.0, 0.28, 0),
    "Copper": ((196, 106, 62), 1.0, 0.3, 0),
    "Concrete": ((128, 128, 132), 0.0, 0.9, 0),
    "Snow": ((244, 249, 255), 0.0, 0.75, 0),
    "Ice": ((170, 222, 255), 0.0, 0.08, 0),
    "Wood": ((168, 116, 70), 0.0, 0.7, 0),
    "WoodDark": ((92, 60, 38), 0.0, 0.7, 0),
    "BagRed": ((204, 58, 44), 0.0, 0.8, 0),
    "BagOlive": ((112, 124, 66), 0.0, 0.85, 0),
    "BagBlue": ((54, 110, 170), 0.0, 0.8, 0),
    "Leather": ((110, 68, 38), 0.0, 0.55, 0),
    "Canvas": ((206, 180, 132), 0.0, 0.9, 0),
    "Light": ((255, 196, 110), 0.0, 0.5, 5),
}
use_materials(MATERIALS)

W = 5.3         # половина ширины лавки
YF, YB = -2.7, 3.4  # передняя и задняя стены
YC = (YF + YB) / 2
Z0 = 0.62       # пол
EAVE_Z = 7.85   # край крыши (под навесом должна проходить голова игрока)
RIDGE_Z = 9.9   # конёк
WT = EAVE_Z - 0.2  # верх стен
EAVE_Y = 3.75   # вынос ската от конька
SLOPE = (RIDGE_Z - EAVE_Z) / EAVE_Y


def roof_z(y):
    return RIDGE_Z - abs(y - YC) * SLOPE


def rivets_x(mat, x0, x1, y, z, step, normal=(0, -1, 0), r=0.06):
    n = max(1, round((x1 - x0) / step))
    for i in range(n + 1):
        rivet(mat, (x0 + (x1 - x0) * i / n, y, z), normal, r)


# ============================================================
# Рюкзак. Низ по центру в начале координат, высота тела = 1, перед = -Y
# ============================================================
def backpack(main, m, hi=False):
    nu, nv = (20, 12) if hi else (12, 8)
    blob(main, (0.43, 0.27, 0.47), m @ T(0, 0, 0.47), e=0.45, nu=nu, nv=nv)
    # Клапан
    blob(main, (0.45, 0.3, 0.13), m @ T(0, -0.02, 0.93), e=0.5, nu=nu, nv=nv)
    blob(main, (0.39, 0.06, 0.17), m @ T(0, -0.29, 0.8), e=0.5, nu=nu, nv=nv // 2 + 2)
    # Передний карман
    blob(main, (0.31, 0.12, 0.23), m @ T(0, -0.29, 0.31), e=0.45, nu=nu, nv=nv)
    # Ремни с пряжками
    for sx in (-0.19, 0.19):
        box("Leather", (0.075, 0.02, 0.42), m @ T(sx, -0.36, 0.72), bevel=0.006 if hi else 0)
        box("Brass", (0.1, 0.03, 0.06), m @ T(sx, -0.375, 0.6), bevel=0.008 if hi else 0)
    if not hi:
        return
    # Клапан кармана, строчка-молния, боковые карманы, скатка сверху, ручка, лямки сзади
    blob(main, (0.27, 0.05, 0.08), m @ T(0, -0.39, 0.46), e=0.5, nu=16, nv=8)
    box("Brass", (0.05, 0.03, 0.09), m @ T(0, -0.43, 0.39), bevel=0.008)
    for sx in (-0.47, 0.47):
        blob(main, (0.09, 0.17, 0.2), m @ T(sx, 0, 0.27), e=0.5, nu=16, nv=10)
        box("Leather", (0.04, 0.2, 0.05), m @ T(sx * 1.03, 0, 0.42), bevel=0.008)
    roll = m @ T(0, 0.02, 1.15) @ R(90, "Y")
    lathe("Canvas", round_profile([(0, -0.46), (0.135, -0.46), (0.135, 0.46), (0, 0.46)], 0.03), seg=20, m=roll)
    lathe("WoodDark", [(0.135, 0.461), (0.07, 0.461), (0, 0.461)], seg=20, m=roll)
    for sx in (-0.28, 0.28):
        lathe("Leather", round_profile([(0.13, -0.035), (0.15, -0.035), (0.15, 0.035), (0.13, 0.035)], 0.008), seg=20, m=m @ T(sx, 0.02, 1.15) @ R(90, "Y"))
        box("Leather", (0.06, 0.02, 0.2), m @ T(sx, -0.11, 1.0), bevel=0.005)
    p = [m @ Vector(v) for v in [(-0.13, 0.27, 0.9), (-0.13, 0.33, 1.02), (0.13, 0.33, 1.02), (0.13, 0.27, 0.9)]]
    tube("Leather", fillet(p, 0.05, steps=3), 0.022, seg=6)
    for sx in (-0.2, 0.2):
        p = [m @ Vector(v) for v in [(sx, 0.26, 0.88), (sx, 0.36, 0.72), (sx * 1.15, 0.37, 0.3), (sx * 1.35, 0.26, 0.13)]]
        tube("Leather", fillet(p, 0.12, steps=4), 0.045, seg=6)


# ============================================================
# Фундамент, пол, каркас
# ============================================================
box("Concrete", (12.6, 9.2, 0.32), T(0, 0, 0.16), bevel=0.05)
box("Concrete", (11.7, 8.3, 0.32), T(0, 0, 0.46), bevel=0.05)
for i in range(11):
    box("Wood", (2 * W / 11 - 0.03, YB - YF, 0.06), T(-W + (i + 0.5) * 2 * W / 11, YC, Z0 + 0.03), bevel=0.012)
for sx in (-W, W):
    for y in (YF, YB):
        box("Iron", (0.44, 0.44, WT - Z0), T(sx, y, (WT + Z0) / 2), bevel=0.05)
        for z in (1.2, 7.0):
            nx = 1 if sx > 0 else -1
            rivet("Steel", (sx + nx * 0.22, y, z), (nx, 0, 0), 0.07)
            rivet("Steel", (sx, y - 0.22 if y < 0 else y + 0.22, z), (0, -1 if y < 0 else 1, 0), 0.07)

# ============================================================
# Стены: крашеные доски, железные пояса с заклёпками
# ============================================================
for i in range(14):
    box("PaintBlue", (2 * W / 14 - 0.035, 0.22, WT - Z0), T(-W + (i + 0.5) * 2 * W / 14, YB - 0.05, (WT + Z0) / 2), bevel=0.02)
for sx in (-W, W):
    nx = 1 if sx > 0 else -1
    for i in range(10):
        dy = (YB - YF) / 10
        box("PaintBlue", (0.22, dy - 0.035, 6.7), T(sx - nx * 0.05, YF + (i + 0.5) * dy, Z0 + 3.35), bevel=0.02)
    # Щипец
    x0, x1 = sorted((sx - 0.14 * nx, sx + 0.06 * nx))
    extrude_x("PaintBlue", [(YF, 7.3), (YB, 7.3), (YB, roof_z(YB)), (YC, RIDGE_Z - 0.06), (YF, roof_z(YF))], x0, x1)
    # Пояса
    for z in (1.2, 7.0):
        box("Iron", (0.09, YB - YF - 0.4, 0.26), T(sx + nx * 0.08, YC, z), bevel=0.02)
        for i in range(7):
            rivet("Steel", (sx + nx * 0.125, YF + 0.45 + i * 0.87, z), (nx, 0, 0), 0.05)
    # Окно с латунной рамой
    wy, wz = YC, 4.1
    box("Light", (0.06, 2.0, 2.1), T(sx + nx * 0.08, wy, wz), bevel=0)
    box("Iron", (0.08, 0.1, 2.1), T(sx + nx * 0.1, wy, wz), bevel=0.01)
    box("Iron", (0.08, 2.0, 0.1), T(sx + nx * 0.1, wy, wz), bevel=0.01)
    for dy, dz, sy, sz in [(-1.06, 0, 0.14, 2.3), (1.06, 0, 0.14, 2.3), (0, 1.11, 2.1, 0.14), (0, -1.11, 2.1, 0.14)]:
        box("Brass", (0.12, sy, sz), T(sx + nx * 0.11, wy + dy, wz + dz), bevel=0.02)
    box("Iron", (0.32, 2.5, 0.12), T(sx + nx * 0.19, wy, wz - 1.24), bevel=0.03)
    # Снег на подоконнике
    for dy, s in [(-0.75, 0.2), (-0.15, 0.26), (0.65, 0.22)]:
        lathe("Snow", [(0, 0), (s, 0), (s * 0.6, s * 0.3), (0, s * 0.42)], seg=8, m=T(sx + nx * 0.2, wy + dy, wz - 1.18) @ S(0.55, 1.6, 1))
    # Круглое окошко на щипце
    m = facing((nx, 0, 0), (sx + nx * 0.06, YC, 8.65))
    lathe("Light", [(0, 0.02), (0.36, 0.02)][::-1], seg=16, m=m)
    lathe("Brass", round_profile([(0.34, -0.02), (0.52, -0.02), (0.52, 0.09), (0.36, 0.09), (0.34, 0.02)], 0.02), seg=20, m=m)
for z in (1.2, 7.0):
    box("Iron", (2 * W - 0.4, 0.09, 0.26), T(0, YB + 0.1, z), bevel=0.02)
    rivets_x("Steel", -W + 0.5, W - 0.5, YB + 0.145, z, 0.95, (0, 1, 0), 0.05)

# ============================================================
# Внутри: обшивка, потолок, полки с рюкзаками по размеру, лампы
# ============================================================
for i in range(8):
    box("Wood", (2 * W - 0.25, 0.06, (WT - Z0) / 8 - 0.03), T(0, YB - 0.2, Z0 + (i + 0.5) * (WT - Z0) / 8), bevel=0.012)
for i in range(9):
    box("WoodDark", (2 * W + 0.1, (YB - YF) / 9 - 0.03, 0.08), T(0, YF + (i + 0.5) * (YB - YF) / 9, WT + 0.05), bevel=0.012)
SHELF_Y = YB - 0.75
for z in (2.5, 5.0):
    box("WoodDark", (2 * W - 0.5, 1.05, 0.13), T(0, SHELF_Y, z), bevel=0.03)
    box("Brass", (2 * W - 0.5, 0.03, 0.05), T(0, SHELF_Y - 0.53, z), bevel=0.01)
    for x in (-3.8, 0, 3.8):
        tube("Iron", [(x, SHELF_Y + 0.4, z - 0.45), (x, SHELF_Y - 0.25, z - 0.07)], 0.04, seg=6)
for x, size, main in [(-3.8, 1.1, "BagOlive"), (-1.9, 1.45, "BagBlue"), (0.45, 1.8, "BagRed"), (3.2, 2.15, "BagOlive")]:
    backpack(main, T(x, SHELF_Y - 0.02, 5.065) @ R(8 if x < 0 else -8, "Z") @ S(size))
for x, size, main in [(-2.6, 1.6, "BagRed"), (0.2, 1.8, "BagBlue"), (3.1, 1.6, "BagRed")]:
    backpack(main, T(x, SHELF_Y - 0.02, 2.565) @ R(6 if x < 0 else -6, "Z") @ S(size))
for x in (-2.6, 2.6):
    tube("Iron", [(x, YC, 7.72), (x, YC, 7.05)], 0.03, seg=6)
    lathe("Brass", round_profile([(0.04, 5.8), (0.2, 5.7), (0.48, 5.42), (0.46, 5.42), (0.18, 5.66), (0, 5.72)][::-1], 0.01), seg=12, m=T(x, YC, 1.3))
    blob("Light", (0.17, 0.17, 0.2), T(x, YC, 6.72), e=1, nu=10, nv=6)

# ============================================================
# Прилавок и вывеска
# ============================================================
CY = YF - 0.02
for i in range(16):
    box("Wood", (2 * W / 16 - 0.03, 0.14, 2.03), T(-W + (i + 0.5) * 2 * W / 16, CY, Z0 + 1.015), bevel=0.018)
box("WoodDark", (2 * W - 0.2, 1.0, 2.0), T(0, CY + 0.55, Z0 + 1.0), bevel=0.02)
for z in (1.02, 2.3):
    box("Iron", (2 * W - 0.4, 0.05, 0.2), T(0, CY - 0.09, z), bevel=0.015)
    rivets_x("Steel", -W + 0.5, W - 0.5, CY - 0.115, z, 0.95, (0, -1, 0), 0.045)
box("WoodDark", (2 * W + 0.3, 1.75, 0.18), T(0, CY + 0.22, 2.74), bevel=0.05)
box("Iron", (2 * W + 0.34, 0.05, 0.1), T(0, CY - 0.655, 2.74), bevel=0.012)

# Вывеска над прилавком: латунная рамка, рюкзак и плюс
HZ0, HZ1 = 6.72, roof_z(YF)
HC = 7.28  # центр видимой части (верх закрыт краем крыши)
box("WoodDark", (2 * W, 0.24, HZ1 - HZ0), T(0, YF, (HZ0 + HZ1) / 2), bevel=0.03)
fr = [(-W + 0.45, -2.84, HZ0 + 0.14), (W - 0.45, -2.84, HZ0 + 0.14), (W - 0.45, -2.84, 7.72), (-W + 0.45, -2.84, 7.72)]
tube("Brass", fillet(fr + fr[:2], 0.12, steps=3)[1:], 0.045, seg=6, caps=False)
EM = T(-0.5, -2.83, HC - 0.36) @ S(0.68, 0.13, 0.68)
blob("BagRed", (0.43, 0.27, 0.47), EM @ T(0, 0, 0.47), e=0.45, nu=14, nv=8)
blob("BagRed", (0.36, 0.3, 0.2), EM @ T(0, -0.5, 0.25), e=0.5, nu=12, nv=6)
blob("BagRed", (0.45, 0.3, 0.14), EM @ T(0, -0.5, 0.86), e=0.5, nu=14, nv=6)
for sx in (-0.19, 0.19):
    box("Brass", (0.09, 0.2, 0.3), EM @ T(sx, -1.0, 0.68), bevel=0)
box("Brass", (0.62, 0.08, 0.18), T(0.5, -2.84, HC), bevel=0.025)
box("Brass", (0.18, 0.08, 0.62), T(0.5, -2.84, HC), bevel=0.025)
for sx in (-W + 0.22, W - 0.22):
    rivet("Brass", (sx, -2.83, HC + 0.3), (0, -1, 0), 0.08)
    rivet("Brass", (sx, -2.83, HC - 0.3), (0, -1, 0), 0.08)

# На прилавке: манометр вместимости
TOP = 2.83
gm = T(-3.3, CY + 0.05, 0)
tube("Iron", [gm @ Vector((0, 0, TOP)), gm @ Vector((0, 0, TOP + 0.5))], 0.07, seg=8)
lathe("Iron", round_profile([(0, TOP), (0.3, TOP), (0.3, TOP + 0.08), (0.08, TOP + 0.12)], 0.02), seg=14, m=gm)
g = facing((0, -1, 0.0), gm @ Vector((0, 0, TOP + 1.0)))
lathe("Brass", round_profile([(0, -0.08), (0.56, -0.08), (0.56, 0.12), (0.46, 0.12), (0.46, 0.06), (0, 0.06)], 0.03), seg=20, m=g)
lathe("Cream", [(0, 0.08), (0.46, 0.08)][::-1], seg=20, m=g)
for i in range(9):
    a = math.radians(-135 + i * 270 / 8) + math.pi / 2
    box("Iron", (0.03, 0.03, 0.01), g @ T(0.37 * math.cos(a), 0.37 * math.sin(a), 0.09), bevel=0)
tube("RedPaint", [g @ Vector((0, 0, 0.1)), g @ Vector((0.26, 0.17, 0.1))], 0.02, seg=5)
lathe("Iron", [(0, 0.09), (0.05, 0.09), (0.05, 0.13), (0, 0.13)], seg=10, m=g)

# Касса
RG = T(3.3, CY + 0.25, TOP)
box("Brass", (1.15, 0.9, 0.2), RG @ T(0, 0, 0.1), bevel=0.03)
box("Copper", (1.0, 0.75, 0.42), RG @ T(0, 0.04, 0.4), bevel=0.04)
extrude_x("Brass", [(-0.34, 0.6), (0.42, 0.6), (0.42, 1.02), (0.0, 1.02)], -0.48, 0.48, RG)
box("Iron", (0.62, 0.05, 0.2), RG @ T(0, 0.02, 1.0) @ T(0, -0.02, 0.06), bevel=0.012)
box("Cream", (0.5, 0.06, 0.13), RG @ T(0, -0.015, 1.06), bevel=0)
for r in range(3):
    for c in range(5):
        k = RG @ T(-0.32 + c * 0.16, -0.17 - r * 0.15, 0.78 + (2 - r) * 0.08 - 0.04) @ R(-30, "X")
        lathe("Cream", [(0.05, -0.02), (0.05, 0.03), (0, 0.04)], seg=6, m=k)
tube("Iron", [RG @ Vector((0.5, 0.05, 0.5)), RG @ Vector((0.72, 0.05, 0.5)), RG @ Vector((0.72, 0.05, 0.85))], 0.03, seg=6)
blob("RedPaint", (0.07, 0.07, 0.07), RG @ T(0.72, 0.05, 0.9), e=1, nu=8, nv=6)

# Катушки ниток и рюкзак-образец
for i, (mat, dx) in enumerate([("RedPaint", 0.0), ("Cream", 0.42), ("BagBlue", 0.84)]):
    sp = T(0.95 + dx, CY - 0.05, TOP)
    lathe("WoodDark", round_profile([(0, 0), (0.17, 0), (0.17, 0.05), (0.09, 0.05), (0.09, 0.42), (0.17, 0.42), (0.17, 0.47), (0, 0.47)], 0.01), seg=8, m=sp)
    lathe(mat, round_profile([(0.08, 0.06), (0.15, 0.06), (0.15, 0.41), (0.08, 0.41)], 0.015), seg=8, m=sp)
backpack("BagRed", T(-0.8, CY + 0.15, TOP) @ R(-12, "Z") @ S(1.25))

# ============================================================
# Навес в красно-кремовую полоску с фестонами
# ============================================================
AW_Y0, AW_Y1 = YF - 0.1, YF - 1.75
AW_Z0, AW_Z1 = 6.72, 6.3
N = 11
ax0, ax1 = -W - 0.25, W + 0.25
for i in range(N):
    mat = "RedPaint" if i % 2 == 0 else "Cream"
    x0 = ax0 + (ax1 - ax0) * i / N
    x1 = ax0 + (ax1 - ax0) * (i + 1) / N
    extrude_x(mat, [(AW_Y1, AW_Z1 - 0.05), (AW_Y0, AW_Z0 - 0.05), (AW_Y0, AW_Z0 + 0.05), (AW_Y1, AW_Z1 + 0.05)], x0, x1)
    # Фестон: полукруг вниз
    verts, faces = [], []
    for side, yy in ((0, AW_Y1 - 0.03), (1, AW_Y1 + 0.03)):
        verts.append(((x0 + x1) / 2, yy, AW_Z1 + 0.05))
        for k in range(9):
            a = math.pi * k / 8
            r = (x1 - x0) / 2
            verts.append(((x0 + x1) / 2 + r * math.cos(a), yy, AW_Z1 + 0.05 - (0.1 if k in (0, 8) else 0) - 0.3 * math.sin(a)))
    faces = [[0, 1 + k, 2 + k] for k in range(8)]
    faces += [[10, 12 + k, 11 + k] for k in range(8)]
    for k in range(8):
        faces.append([1 + k, 11 + k, 12 + k, 2 + k])
    buckets[mat].add(verts, faces)
tube("Iron", [(ax0, AW_Y1 + 0.03, AW_Z1), (ax1, AW_Y1 + 0.03, AW_Z1)], 0.05, seg=8)
tube("Iron", [(ax0, AW_Y0, AW_Z0), (ax1, AW_Y0, AW_Z0)], 0.07, seg=8)
for x in (-W + 0.35, W - 0.35):
    tube("Iron", [(x, YF - 0.12, 5.1), (x, AW_Y1 * 0.45 + AW_Y0 * 0.55, (AW_Z1 + AW_Z0) / 2 - 0.05)], 0.04, seg=6)
    tube("Iron", [(x, YF - 0.12, 5.1), (x, YF - 0.12, 6.0)], 0.04, seg=6)


# Снег на навесе: неровная лента поверх полос
def grid_snow(x0, x1, nx, y0, y1, ny, surface, thick, droop=0.1, wave=None):
    verts, faces = [], []
    for i in range(nx):
        for j in range(ny):
            x = x0 + (x1 - x0) * i / (nx - 1)
            y = y0 + (y1 - y0) * j / (ny - 1)
            if wave:
                y += wave(x) * (1 - j / (ny - 1))
            u = min(i, nx - 1 - i) / 3.0
            v = min(j, ny - 1 - j) / 3.0
            edge = min(1.0, u, v) ** 0.55
            t = thick(x, y)
            verts.append((x, y, surface(x, y) + t * edge - droop * (1 - edge)))
    for i in range(nx - 1):
        for j in range(ny - 1):
            a, b, c, d = i * ny + j, (i + 1) * ny + j, (i + 1) * ny + j + 1, i * ny + j + 1
            faces.append([a, b, c, d])
    buckets["Snow"].add(verts, faces)


def awning_z(y):
    return AW_Z0 + (AW_Z1 - AW_Z0) * (y - AW_Y0) / (AW_Y1 - AW_Y0)


# Только у стены: полоски навеса должны быть видны
grid_snow(ax0 - 0.05, ax1 + 0.05, 30, AW_Y0 - 0.65, AW_Y0, 7, lambda x, y: awning_z(y) + 0.05,
          lambda x, y: 0.1 + 0.2 * max(0, noise.noise(Vector((x * 0.6, y * 0.8, 2.3))) + 0.35), droop=0.03,
          wave=lambda x: 0.22 * math.sin(x * 1.3 + 0.7) + 0.12 * math.sin(x * 3.1))
for i, (x, ln) in enumerate([(-5.1, 0.25), (-1.9, 0.3), (1.95, 0.22), (5.15, 0.3)]):
    icicle((x, AW_Y1 - 0.02, AW_Z1 - 0.24), ln)

# ============================================================
# Крыша со снегом и сосульками
# ============================================================
RX = W + 0.8
extrude_x("Iron", [(YC - EAVE_Y, EAVE_Z - 0.16), (YC, RIDGE_Z - 0.16), (YC, RIDGE_Z), (YC - EAVE_Y, EAVE_Z)], -RX, RX)
extrude_x("Iron", [(YC, RIDGE_Z - 0.16), (YC + EAVE_Y, EAVE_Z - 0.16), (YC + EAVE_Y, EAVE_Z), (YC, RIDGE_Z)], -RX, RX)
for sx in (-RX, RX):
    tube("WoodDark", [(sx, YC - EAVE_Y, EAVE_Z - 0.1), (sx, YC, RIDGE_Z - 0.1), (sx, YC + EAVE_Y, EAVE_Z - 0.1)], 0.09, seg=6)
for x in (-3.6, -1.8, 0, 1.8, 3.6):
    box("WoodDark", (0.16, 0.14, 0.2), T(x, YC - EAVE_Y + 0.25, EAVE_Z - 0.2) @ R(0, "X"), bevel=0.02)
    box("WoodDark", (0.16, 0.14, 0.2), T(x, YC + EAVE_Y - 0.25, EAVE_Z - 0.2), bevel=0.02)


def roof_thick(x, y):
    n = noise.noise(Vector((x * 0.4, y * 0.5, 7.7))) * 0.4 + noise.noise(Vector((x * 1.1, y * 1.3, 3.1))) * 0.12
    return 0.42 + n


grid_snow(-RX - 0.15, RX + 0.15, 40, YC - EAVE_Y - 0.15, YC + EAVE_Y + 0.15, 26, lambda x, y: roof_z(y), roof_thick, droop=0.05)
# Языки снега и сосульки по краю
for x, ln in [(-5.6, 0.3), (-3.7, 0.18), (-1.4, 0.22), (1.6, 0.18), (3.2, 0.25), (5.2, 0.2)]:
    for yy, ang in ((YC - EAVE_Y - 0.12, 0), (YC + EAVE_Y + 0.12, 180)):
        m = T(x, yy, EAVE_Z + 0.08) @ R(ang, "Z")
        lathe("Snow", [(0, -ln), (0.15, -ln * 0.75), (0.28, -ln * 0.25), (0.33, 0.04), (0.2, 0.22), (0, 0.28)], seg=9, m=m @ S(1.3, 0.55, 1))
for x, ln in [(-6.0, 0.7), (-4.6, 0.42), (-2.7, 0.85), (-0.4, 0.5), (1.9, 0.72), (4.0, 0.46), (5.8, 0.8)]:
    icicle((x, YC + EAVE_Y + 0.05, EAVE_Z - 0.18), ln)

# Гигантский рюкзак на коньке: стальная площадка на стойках
BZ = RIDGE_Z + 0.55
box("Iron", (3.9, 2.5, 0.16), T(0, YC, BZ - 0.08), bevel=0.04)
for sx in (-1.75, 1.75):
    box("Iron", (0.2, 1.8, 0.8), T(sx, YC, BZ - 0.5), bevel=0.03)
    for sy in (-1, 1):
        rivet("Steel", (sx, YC + sy * 1.25, BZ - 0.08), (0, sy, 0), 0.05)
for sx in (-1.8, -0.9, 0, 0.9, 1.8):
    rivet("Steel", (sx, YC - 1.25, BZ - 0.08), (0, -1, 0), 0.05)
    rivet("Steel", (sx, YC + 1.25, BZ - 0.08), (0, 1, 0), 0.05)
backpack("BagRed", T(0, YC, BZ) @ R(-6, "Z") @ S(2.75), hi=True)
# Снежная шапка на скатке
lathe("Snow", [(0, 0), (0.78, 0), (0.6, 0.14), (0.3, 0.22), (0, 0.25)], seg=14, m=T(-0.45, YC + 0.08, BZ + 3.5) @ S(1.1, 0.5, 1))
lathe("Snow", [(0, 0), (0.5, 0), (0.38, 0.1), (0.18, 0.16), (0, 0.18)], seg=12, m=T(0.8, YC, BZ + 3.5) @ S(1.1, 0.5, 1))

# ============================================================
# Дымовая труба, водосток, фонари, мелочи на фундаменте
# ============================================================
CHX, CHY = 3.7, 2.1
CH_TOP = 12.3
lathe("Iron", [(0, EAVE_Z), (0.34, EAVE_Z), (0.34, CH_TOP), (0, CH_TOP)], seg=16, m=T(CHX, CHY, 0))
for z in (10.1, 11.5):
    lathe("Iron", round_profile([(0.34, z - 0.1), (0.44, z - 0.1), (0.44, z + 0.1), (0.34, z + 0.1)], 0.02), seg=16, m=T(CHX, CHY, 0))
    for i in range(6):
        a = 2 * math.pi * i / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        rivet("Steel", Vector((CHX, CHY, z)) + d * 0.44, d, 0.035)
lathe("Iron", round_profile([(0.34, CH_TOP - 0.4), (0.54, CH_TOP - 0.05), (0.54, CH_TOP + 0.15), (0.38, CH_TOP + 0.15), (0.3, CH_TOP), (0, CH_TOP)], 0.02), seg=16, m=T(CHX, CHY, 0))
lathe("Snow", [(0, 0), (0.85, 0), (0.6, 0.28), (0.36, 0.42), (0, 0.44)], seg=14, m=T(CHX, CHY, roof_z(CHY) + 0.28))

# Медный водосток сзади
GY = YC + EAVE_Y + 0.08
tube("Copper", [(RX, GY, EAVE_Z - 0.1), (-RX + 0.3, GY, EAVE_Z - 0.1)], 0.13, seg=10)
down = fillet([(-RX + 0.3, GY, EAVE_Z - 0.1), (-RX + 0.3, GY + 0.0, 7.35), (-W - 0.35, YB + 0.5, 6.7), (-W - 0.35, YB + 0.5, 1.0)], 0.3, steps=5)
tube("Copper", down, 0.12, seg=10)
lathe("Copper", [(0.12, 1.1), (0.24, 0.86), (0.24, 0.72), (0.18, 0.72)][::-1], seg=12, m=T(-W - 0.35, YB + 0.5, 0))
lathe("Ice", [(0.05, 0.75), (0.1, 0.5), (0, 0.33)][::-1], seg=8, m=T(-W - 0.35, YB + 0.5, 0))
for z in (2.2, 4.2):
    tube("Iron", [(-W - 0.35, YB + 0.3, z), (-W - 0.35, YB + 0.5, z)], 0.15, seg=8)

# Фонари по бокам прилавка
for sx in (-1, 1):
    px = sx * (W + 0.22)
    tube("Iron", fillet([(px, YF, 5.9), (px + sx * 0.5, YF, 5.9), (px + sx * 0.5, YF, 5.6)], 0.12, steps=3), 0.035, seg=6)
    L = T(px + sx * 0.5, YF, 4.97)
    lathe("Brass", round_profile([(0, 0), (0.18, 0), (0.18, 0.08), (0, 0.08)], 0.015), seg=10, m=L)
    lathe("Brass", [(0.18, 0.5), (0.2, 0.52), (0.05, 0.66), (0, 0.66)], seg=10, m=L)
    blob("Light", (0.13, 0.13, 0.22), L @ T(0, 0, 0.29), e=1, nu=10, nv=6)
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        tube("Iron", [L @ Vector((0.17 * math.cos(a), 0.17 * math.sin(a), 0.05)), L @ Vector((0.17 * math.cos(a), 0.17 * math.sin(a), 0.52))], 0.018, seg=4)

# Бочка с рулонами ткани слева от прилавка
bx, by = -W - 0.72, -2.1
bar = [(0, 0)]
for i in range(9):
    t = i / 8
    bar.append((0.42 + 0.08 * math.sin(math.pi * t), 1.25 * t))
bar += [(0.36, 1.25), (0.36, 1.1), (0, 1.1)]
lathe("Wood", bar, seg=16, m=T(bx, by, Z0))
for z in (0.25, 1.0):
    r = 0.42 + 0.08 * math.sin(math.pi * z / 1.25) + 0.012
    lathe("Iron", [(r - 0.02, z - 0.05), (r, z - 0.05), (r, z + 0.05), (r - 0.02, z + 0.05)], seg=16, m=T(bx, by, Z0))
for dx, dy, h, tilt, mat in [(-0.13, -0.1, 1.0, 8, "Canvas"), (0.14, -0.08, 0.8, -7, "BagRed"), (0.0, 0.16, 1.2, 4, "BagBlue")]:
    lathe(mat, round_profile([(0, 0), (0.12, 0), (0.12, h), (0, h)], 0.02), seg=10, m=T(bx + dx, by + dy, Z0 + 1.0) @ R(tilt, "Y"))

# Ящики справа от прилавка
for dy, dz, s, yaw in [(-1.95, 0, 0.82, 4), (-1.0, 0, 0.72, -5), (-1.9, 0.82, 0.62, 12)]:
    m = T(W + 0.72, dy, Z0 + dz + s / 2) @ R(yaw, "Z")
    box("Wood", (s, s, s), m, bevel=0.03)
    for sign in (-1, 1):
        box("WoodDark", (s + 0.03, 0.08, s + 0.03), m @ T(0, sign * (s / 2 - 0.05), 0), bevel=0.012)
        box("WoodDark", (0.08, s + 0.03, s + 0.03), m @ T(sign * (s / 2 - 0.05), 0, 0), bevel=0.012)
lathe("Snow", [(0, 0), (0.3, 0), (0.22, 0.1), (0, 0.15)], seg=8, m=T(W + 0.72, -1.9, Z0 + 1.44))

# Снег у подножия
for x, y, s in [(5.35, 3.85, 0.55), (-3.6, 4.05, 0.42), (1.2, 4.05, 0.5), (-5.75, 0.6, 0.42), (5.75, 1.5, 0.48), (-4.8, -3.85, 0.42), (5.2, -3.9, 0.36)]:
    snow_lump(x, y, 0.3 if abs(x) > 5.8 or abs(y) > 4.1 else Z0, s)

finish(
    "Shop", MATERIALS, OUT, "backpack_shop", RENDER,
    views={
        "front": ((9, -22, 10), (0, 0, 6.5)),
        "back": ((-14, 19, 12), (0, 0, 6.5)),
        "close": ((1.5, -10.5, 5.0), (0, -1, 4.1)),
    },
)
