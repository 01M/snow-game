# Модели лобби Snow Cleaning Simulator: снегоуборочные грузовики очереди, большая ёлка, киоски, беседка, горка, площадь. Запуск:
#   blender --background --python lobby.py -- <папка вывода> [render]
# Предметы стоят рядом, каждый со своим смещением (PROPS); перед смотрит в -Y (в игре +Z).
# Меш называется Lobby_<предмет>_<материал>. lobby.json — центры мешей и смещения: по ним предметы собираются в Studio.
import json
import math
import os
import random
import sys

from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modellib import R, T, blob, box, buckets, finish, hexa, lathe, patch, solid, tube, use_materials

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.dirname(os.path.abspath(__file__))
RENDER = "render" in argv

PALETTE = {
    "Body": ((232, 116, 32), 0.1, 0.45, 0),
    "Yellow": ((240, 186, 40), 0.1, 0.5, 0),
    "Dark": ((34, 38, 46), 0.0, 0.7, 0),
    "Metal": ((150, 158, 168), 0.8, 0.35, 0),
    "Glass": ((32, 44, 60), 0.2, 0.1, 0),
    "Wood": ((150, 108, 72), 0.0, 0.75, 0),
    "WoodDark": ((96, 66, 44), 0.0, 0.8, 0),
    "Snow": ((244, 249, 255), 0.0, 0.75, 0),
    "Ice": ((150, 205, 240), 0.1, 0.2, 0),
    "Trim": ((246, 240, 228), 0.0, 0.6, 0),
    "Stone": ((132, 138, 152), 0.0, 0.9, 0),
    "Roof": ((66, 72, 88), 0.0, 0.85, 0),
    "Fir": ((36, 84, 66), 0.0, 0.9, 0),
    "Light": ((255, 196, 110), 0.0, 0.5, 5),
    "Beacon": ((255, 150, 30), 0.0, 0.5, 5),
    "BulbRed": ((255, 70, 60), 0.0, 0.5, 5),
    "BulbGold": ((255, 200, 90), 0.0, 0.5, 5),
    "BulbGreen": ((80, 230, 110), 0.0, 0.5, 5),
    "BulbBlue": ((90, 160, 255), 0.0, 0.5, 5),
    "Red": ((186, 44, 34), 0.0, 0.5, 0),
    "Cream": ((238, 226, 200), 0.0, 0.6, 0),
    "Blue": ((46, 92, 160), 0.0, 0.5, 0),
    "Green": ((52, 130, 82), 0.0, 0.5, 0),
    "Purple": ((112, 66, 170), 0.0, 0.5, 0),
    "Gold": ((222, 168, 62), 1.0, 0.28, 0),
    "Silver": ((190, 196, 206), 1.0, 0.3, 0),
    "Bronze": ((170, 104, 58), 1.0, 0.35, 0),
    "TailLight": ((255, 60, 40), 0.0, 0.5, 4),
    "RampEdge": ((240, 186, 40), 0.1, 0.5, 0),
    "RampMetal": ((120, 128, 140), 0.8, 0.4, 0),
}
BULBS = ("BulbRed", "BulbGold", "BulbGreen", "BulbBlue")

# Предмет: ((смещение X, Y), материалы)
PROPS = {
    "Truck": ((-170, 0), ("Body", "Cream", "Yellow", "Dark", "Metal", "Glass", "Snow", "Light", "Beacon", "TailLight", "RampEdge", "RampMetal") + BULBS),
    "BigTree": ((-115, 0), ("Fir", "Snow", "WoodDark", "Stone", "Red", "Blue", "Gold", "Green") + BULBS),
    "ShopKiosk": ((-75, 0), ("Wood", "WoodDark", "Trim", "Roof", "Snow", "Light", "Red", "Cream", "Blue", "Gold", "Green") + BULBS),
    "UpgradeKiosk": ((-45, 0), ("Wood", "WoodDark", "Trim", "Roof", "Snow", "Light", "Blue", "Cream", "Green", "Purple", "Gold", "Dark", "Metal", "Red") + BULBS),
    "Gazebo": ((-10, 0), ("Wood", "WoodDark", "Trim", "Roof", "Snow", "Light", "Gold", "Silver", "Bronze", "Stone") + BULBS),
    "Hill": ((45, 0), ("Snow", "Ice", "Wood", "WoodDark", "Trim", "Light", "Red") + BULBS),
    "Plaza": ((0, 110), ("Stone", "Light", "Snow")),
}
MATERIALS = {}
for prop, (_, mats) in PROPS.items():
    for mat in mats:
        MATERIALS[f"{prop}_{mat}"] = PALETTE[mat]
use_materials(MATERIALS)

rng = random.Random(31)
noise.seed_set(9)


def O(prop):
    ox, oy = PROPS[prop][0]
    return T(ox, oy, 0)


def bulb(prop, m, pos, size=0.16, color=None):
    color = color or BULBS[rng.randrange(4)]
    lathe(f"{prop}_{color}", [(0, -size), (size, 0), (0, size)], seg=5, m=m @ T(*pos))


def garland(prop, m, p0, p1, n, sag=0.35, size=0.14):
    p0, p1 = Vector(p0), Vector(p1)
    for i in range(n):
        t = (i + 0.5) / n
        p = p0.lerp(p1, t)
        p.z -= sag * 4 * t * (1 - t)
        bulb(prop, m, tuple(p), size, BULBS[i % 4])


def wheel(prop, m, x, y, r=1.45, w=0.8):
    place = m @ T(x, y, r) @ R(90, "Y")
    lathe(f"{prop}_Dark", [(0, -w), (r * 0.8, -w), (r, -w * 0.7), (r, w * 0.7), (r * 0.8, w), (0, w)], seg=12, m=place)
    side = 1 if x > 0 else -1
    lathe(f"{prop}_Metal", [(0, 0), (r * 0.5, 0), (r * 0.42, 0.12), (0, 0.16)], seg=8, m=m @ T(x + side * w, y, r) @ R(90 * side, "Y"))


# ============================================================
# Грузовик: начало координат — центр площадки на земле, кузов к игроку (-Y), кабина и отвал за ним (+Y).
# Настил — сама деталь Pad (12×12, верх Z = DECK), в меше его нет. Sign (12×6) стоит на крыше кабины, центр (0, SIGN_Y, SIGN_Z).
# Трап, рама и колёса (Ramp*, Dark, Metal) неподвижны, остальное трясёт LobbyTruckClient.
# ============================================================
DECK = 2.6
SIGN_Y, SIGN_Z = 8.6, 14.9


def fender(p, m, side, y0, y1):
    """Крыло над колесом: дуга из пяти сегментов, сверху кремовая кромка."""
    r, cz = 2.35, 1.9
    x0, x1 = (6.1, 8.2) if side > 0 else (-8.2, -6.1)
    yc = (y0 + y1) / 2
    half = (y1 - y0) / 2
    steps = 6
    for i in range(steps):
        a0 = math.pi * i / steps
        a1 = math.pi * (i + 1) / steps
        def pt(a, rr):
            return yc - math.cos(a) * half * rr / r, cz + math.sin(a) * rr
        ya, za = pt(a0, r)
        yb, zb = pt(a1, r)
        yai, zai = pt(a0, r - 0.28)
        ybi, zbi = pt(a1, r - 0.28)
        hexa(f"{p}_Body", [(x0, yai, zai), (x1, yai, zai), (x1, ybi, zbi), (x0, ybi, zbi)], [(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)], m)


def truck():
    p = "Truck"
    m = O(p)
    # рама и колёса
    box(f"{p}_Dark", (10.6, 27, 1.1), m @ T(0, 7, 1.75), bevel=0.05)
    for x in (-7.15, 7.15):
        for y in (-3, 2.2, 14.5):
            wheel(p, m, x, y, r=1.9, w=0.95)
    for side in (-1, 1):
        fender(p, m, side, -5.6, -0.4)
        fender(p, m, side, -0.2, 4.6)
        fender(p, m, side, 12.2, 16.8)
    # трап: кромки жёлтые, середина рифлёная
    for x0, x1, mat in ((-5.9, -4.2, "RampEdge"), (-4.2, 4.2, "RampMetal"), (4.2, 5.9, "RampEdge")):
        verts = [(x0, -6, DECK), (x1, -6, DECK), (x1, -6, DECK - 0.4), (x0, -6, DECK - 0.4), (x0, -12.6, 0.04), (x1, -12.6, 0.04)]
        solid(f"{p}_{mat}", verts, [[0, 1, 2, 3], [0, 4, 5, 1], [3, 2, 5, 4], [0, 3, 4], [1, 5, 2]], m)
    for x in (-4.2, -2.1, 0, 2.1, 4.2):
        if abs(x) < 4:
            hexa(f"{p}_Dark", [(x - 0.08, -7, DECK - 0.33), (x + 0.08, -7, DECK - 0.33), (x + 0.08, -12, 0.42), (x - 0.08, -12, 0.42)], [(x - 0.08, -7, DECK - 0.27), (x + 0.08, -7, DECK - 0.27), (x + 0.08, -12, 0.48), (x - 0.08, -12, 0.48)], m)
    # борта кузова: низкие, с кремовой кромкой
    for side in (-1, 1):
        x = side * 6.3
        box(f"{p}_Body", (0.5, 12.6, 1.6), m @ T(x, 0.2, DECK + 0.8), bevel=0.08)
        box(f"{p}_Cream", (0.62, 12.7, 0.26), m @ T(x, 0.2, DECK + 1.68), bevel=0.05)
        box(f"{p}_Yellow", (0.62, 0.7, 2.0), m @ T(x, -6.0, DECK + 0.95), bevel=0.05)
        box(f"{p}_TailLight", (1.3, 0.14, 0.62), m @ T(side * 4.9, -6.02, DECK - 0.75), bevel=0.02)
        # снег в углах кузова
        blob(f"{p}_Snow", (1.7, 1.5, 0.75), m @ T(side * 4.5, 5.1, DECK + 0.32), e=0.85, nu=10, nv=5)
    # передний борт
    box(f"{p}_Body", (13.1, 0.6, 3.2), m @ T(0, 6.5, DECK + 1.6), bevel=0.08)
    box(f"{p}_Cream", (13.2, 0.7, 0.26), m @ T(0, 6.5, DECK + 3.25), bevel=0.05)
    for i in range(7):
        x = -5.4 + i * 1.8
        hexa(f"{p}_Yellow", [(x - 0.45, 6.17, DECK + 0.3), (x + 0.15, 6.17, DECK + 0.3), (x + 0.15, 6.2, DECK + 0.3), (x - 0.45, 6.2, DECK + 0.3)], [(x + 0.15, 6.17, DECK + 1.3), (x + 0.75, 6.17, DECK + 1.3), (x + 0.75, 6.2, DECK + 1.3), (x + 0.15, 6.2, DECK + 1.3)], m)
    # кабина: округлая, с крупными окнами и широкой кремовой полосой
    box(f"{p}_Body", (11, 8.6, 8.6), m @ T(0, 11.3, 6.9), bevel=0.75, segments=3)
    box(f"{p}_Cream", (11.1, 8.7, 0.7), m @ T(0, 11.3, 5.9), bevel=0.2)
    box(f"{p}_Glass", (7.4, 0.12, 2.9), m @ T(0, 6.98, 8.9), bevel=0)
    for side in (-1, 1):
        box(f"{p}_Glass", (0.12, 5.6, 3.0), m @ T(side * 5.52, 11.6, 8.9), bevel=0)
        box(f"{p}_Dark", (0.5, 0.25, 1.3), m @ T(side * 6.1, 15.4, 8.4), bevel=0.04)
        box(f"{p}_Dark", (1.1, 0.14, 0.14), m @ T(side * 5.75, 15.4, 9.2), bevel=0)
    # капот, решётка, фары
    box(f"{p}_Body", (9.8, 6.4, 5.2), m @ T(0, 18.2, 4.7), bevel=0.7, segments=3)
    box(f"{p}_Glass", (9.4, 0.12, 3.0), m @ T(0, 15.62, 9.0), bevel=0)
    box(f"{p}_Dark", (5.6, 0.2, 2.6), m @ T(0, 21.42, 4.3), bevel=0.04)
    for i in range(5):
        box(f"{p}_Metal", (5.2, 0.1, 0.16), m @ T(0, 21.5, 3.4 + i * 0.46), bevel=0)
    for x in (-3.8, 3.8):
        lathe(f"{p}_Light", [(0, 0), (0.85, 0), (0.85, 0.2), (0, 0.28)], seg=12, m=m @ T(x, 21.4, 4.4) @ R(-90, "X"))
    blob(f"{p}_Snow", (4.6, 2.9, 0.42), m @ T(0, 18.2, 7.3), e=0.6, nu=12, nv=5)
    # выхлопная труба
    lathe(f"{p}_Metal", [(0, 0), (0.34, 0), (0.3, 8.4), (0.4, 8.5), (0.4, 9.7), (0, 9.7)], seg=8, m=m @ T(5.95, 14.9, 3.6))
    # табло на крыше: две стойки, тёмная рамка, маячки по углам, снизу гирлянда
    for x in (-3.6, 3.6):
        box(f"{p}_Dark", (1.5, 1.5, 1.0), m @ T(x, SIGN_Y + 1.0, 11.5), bevel=0.08)
    box(f"{p}_Body", (12.9, 0.9, 6.9), m @ T(0, SIGN_Y + 0.65, SIGN_Z), bevel=0.14)
    blob(f"{p}_Snow", (6.6, 0.75, 0.32), m @ T(0, SIGN_Y + 0.65, SIGN_Z + 3.5), e=0.6, nu=12, nv=5)
    for x in (-5.3, 5.3):
        lathe(f"{p}_Dark", [(0, 0), (0.7, 0), (0.7, 0.22), (0, 0.22)], seg=10, m=m @ T(x, SIGN_Y + 0.65, SIGN_Z + 3.45))
        lathe(f"{p}_Beacon", [(0, 0), (0.58, 0), (0.52, 0.65), (0.28, 0.98), (0, 1.06)], seg=10, m=m @ T(x, SIGN_Y + 0.65, SIGN_Z + 3.67))
    garland(p, m, (-6.3, SIGN_Y + 0.1, SIGN_Z + 3.3), (6.3, SIGN_Y + 0.1, SIGN_Z + 3.3), 16, sag=0.18, size=0.17)
    # снег на крыше кабины
    blob(f"{p}_Snow", (5.0, 3.2, 0.45), m @ T(0, 12.6, 11.25), e=0.6, nu=12, nv=5)
    # отвал: широкая дуга с чёрно-жёлтыми полосами, рёбра и нож
    segs = 10
    def arc(a):
        r = 2.6
        return 23.6 - r * math.cos(math.radians(a)) * 0.8, 2.6 + r * math.sin(math.radians(a))
    for i in range(segs):
        y0, z0 = arc(-60 + i * 12)
        y1, z1 = arc(-60 + (i + 1) * 12)
        hexa(f"{p}_Yellow", [(-9.4, y0, z0), (9.4, y0, z0), (9.4, y0 + 0.4, z0), (-9.4, y0 + 0.4, z0)], [(-9.4, y1, z1), (9.4, y1, z1), (9.4, y1 + 0.4, z1), (-9.4, y1 + 0.4, z1)], m)
    box(f"{p}_Dark", (19, 0.55, 0.5), m @ T(0, 24.1, 0.4), bevel=0.03)
    for x in (-5, 5):
        box(f"{p}_Dark", (0.9, 2.7, 0.9), m @ T(x, 22.2, 2.3), bevel=0.04)
    for i in range(8):
        blob(f"{p}_Snow", (1.5, 1.0, 0.6), m @ T(-7.8 + i * 2.2, 25.2, 0.45 + rng.random() * 0.3), e=0.8, nu=8, nv=4)


# ============================================================
# Большая ёлка: начало координат — центр ствола на земле
# ============================================================
def fir_tier(mat, zb, zt, r, m, n=14, jag=0.2, turn=0.0):
    verts = [(0, 0, zt), (0, 0, zb + (zt - zb) * 0.1)]
    for k in range(n * 2):
        a = turn + math.pi * k / n
        rr = r * (1.0 if k % 2 == 0 else 1.0 - jag)
        verts.append((rr * math.cos(a), rr * math.sin(a), zb + (0.0 if k % 2 == 0 else (zt - zb) * 0.07)))
    faces = []
    count = n * 2
    for k in range(count):
        a, b = 2 + k, 2 + (k + 1) % count
        faces.append([0, a, b])
        faces.append([1, b, a])
    buckets[mat].add(verts, faces, m)


def big_tree():
    p = "BigTree"
    m = O(p)
    lathe(f"{p}_Stone", [(0, 0), (13, 0), (13, 0.25), (12.3, 0.8), (11.6, 0.8), (11.4, 0.5), (0, 0.5)], seg=24, m=m)
    lathe(f"{p}_WoodDark", [(0, 0), (2.0, 0), (1.5, 2.5), (1.1, 8), (0, 8)], seg=10, m=m)
    tiers = 8
    height = 40.0
    for i in range(tiers):
        t = i / tiers
        zb = 4.0 + (height - 11) * t
        zt = zb + 13 - 4.5 * t
        r = 11.0 - 8.4 * t
        turn = i * 0.37
        fir_tier(f"{p}_Fir", zb, zt, r, m, n=max(9, 15 - i), turn=turn)
        # снег на видимой полосе яруса: снизу остаётся зелёная кромка
        k = 0.12
        fir_tier(f"{p}_Snow", zb + (zt - zb) * k + 0.25, zt + 0.3, r * (1 - k) + 0.3, m, n=max(9, 15 - i), jag=0.24, turn=turn)
    top = height + 0.9
    # звезда
    star = [(0, -0.45, top), (0, 0.45, top)]
    faces = []
    for k in range(10):
        a = math.pi / 2 + math.pi * k / 5
        rr = 2.6 if k % 2 == 0 else 1.1
        star.append((rr * math.cos(a), 0, top + rr * math.sin(a)))
    for k in range(10):
        a, b = 2 + k, 2 + (k + 1) % 10
        faces += [[0, a, b], [1, b, a]]
    solid(f"{p}_BulbGold", star, faces, m)
    # спираль лампочек по конусу и шары
    n = 150
    for i in range(n):
        t = i / n
        z = 6 + (height - 8) * t
        r = (10.0 * (1 - t) ** 0.95 + 0.9) * 0.97
        a = t * 2 * math.pi * 7.5
        bulb(p, m, (r * math.cos(a), r * math.sin(a), z), 0.3 - 0.1 * t, BULBS[i % 4])
    for i in range(26):
        z = 7 + rng.random() * (height - 14)
        t = (z - 6) / (height - 8)
        r = 10.0 * (1 - t) + 0.8
        a = rng.random() * math.tau
        mat = ("Red", "Blue", "Gold", "Green")[i % 4]
        lathe(f"{p}_{mat}", [(0, -0.5), (0.4, -0.3), (0.5, 0), (0.4, 0.3), (0, 0.5)], seg=8, m=m @ T(r * math.cos(a), r * math.sin(a), z))
    # подарки
    gifts = [(-6, -7, 2.4, "Red", "Gold"), (-2.5, -9, 1.7, "Blue", "Gold"), (3.8, -8, 2.8, "Green", "Red"), (7.5, -5, 1.8, "Gold", "Red"), (8, 3, 2.2, "Red", "Green"), (-8, 3, 2.0, "Blue", "Red"), (-3, 8, 2.4, "Gold", "Blue"), (4, 8, 1.8, "Green", "Gold")]
    for x, y, s, col, rib in gifts:
        place = m @ T(x, y, 0.5 + s / 2) @ R(rng.random() * 40 - 20, "Z")
        box(f"{p}_{col}", (s, s, s), place, bevel=0.05)
        box(f"{p}_{rib}", (s + 0.06, s * 0.2, s + 0.06), place, bevel=0)
        box(f"{p}_{rib}", (s * 0.2, s + 0.06, s + 0.06), place, bevel=0)
    for i in range(10):
        a = i / 10 * math.tau + 0.3
        blob(f"{p}_Snow", (2.2, 2.0, 0.55), m @ T(11.9 * math.cos(a), 11.9 * math.sin(a), 0.8), e=0.8, nu=8, nv=4)


# ============================================================
# Киоски: начало координат — центр на земле, прилавок спереди (-Y). Ширина 12, глубина 9.
# ============================================================
def kiosk_shell(p, m, stripe_a, stripe_b):
    box(f"{p}_WoodDark", (12.6, 9.6, 0.5), m @ T(0, 0, 0.25), bevel=0.05)
    for x in (-5.9, 5.9):
        box(f"{p}_Wood", (0.5, 9, 7.5), m @ T(x, 0, 4.25), bevel=0.04)
    box(f"{p}_Wood", (12.3, 0.5, 7.5), m @ T(0, 4.25, 4.25), bevel=0.04)
    box(f"{p}_Light", (10.8, 0.1, 3.4), m @ T(0, 3.95, 5.4), bevel=0)
    box(f"{p}_Trim", (12.6, 1.5, 0.35), m @ T(0, -3.8, 3.5), bevel=0.05)
    box(f"{p}_Wood", (12.2, 1.2, 3.0), m @ T(0, -3.8, 1.85), bevel=0.04)
    for y in (0.5, 2.5):
        box(f"{p}_Trim", (10.8, 1.4, 0.2), m @ T(0, y + 0.8, 3.3 + (y - 0.5) * 0.9), bevel=0.02)
    # крыша и снег
    for sign in (-1, 1):
        hexa(
            f"{p}_Roof",
            [(sign * 0, -5.4, 11.6), (sign * 7.3, -5.4, 7.9), (sign * 7.3, 5.4, 7.9), (sign * 0, 5.4, 11.6)],
            [(sign * 0, -5.4, 11.25), (sign * 7.3, -5.4, 7.55), (sign * 7.3, 5.4, 7.55), (sign * 0, 5.4, 11.25)],
            m,
        )
        hexa(
            f"{p}_Snow",
            [(sign * 0, -5.55, 11.85), (sign * 7.5, -5.55, 8.05), (sign * 7.5, 5.55, 8.05), (sign * 0, 5.55, 11.85)],
            [(sign * 0, -5.55, 11.58), (sign * 7.5, -5.55, 7.85), (sign * 7.5, 5.55, 7.85), (sign * 0, 5.55, 11.58)],
            m,
        )
    solid(f"{p}_Wood", [(-6.15, -4.3, 8), (6.15, -4.3, 8), (0, -4.3, 11.1), (-6.15, -4.7, 8), (6.15, -4.7, 8), (0, -4.7, 11.1)], [[0, 1, 2], [3, 5, 4], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]], m)
    # полосатый навес
    n = 8
    for i in range(n):
        x0 = -6.4 + 12.8 * i / n
        x1 = x0 + 12.8 / n
        mat = stripe_a if i % 2 == 0 else stripe_b
        hexa(
            f"{p}_{mat}",
            [(x0, -7.0, 6.15), (x1, -7.0, 6.15), (x1, -4.4, 7.9), (x0, -4.4, 7.9)],
            [(x0, -7.0, 6.35), (x1, -7.0, 6.35), (x1, -4.4, 8.1), (x0, -4.4, 8.1)],
            m,
        )
        box(f"{p}_{mat}", (x1 - x0, 0.1, 0.8), m @ T((x0 + x1) / 2, -7.0, 5.8), bevel=0)
    garland(p, m, (-6.4, -7.1, 5.3), (6.4, -7.1, 5.3), 16, sag=0.22)
    for x in (-5.9, 5.9):
        box(f"{p}_WoodDark", (0.3, 0.3, 5.5), m @ T(x, -6.8, 2.8), bevel=0.02)
    blob(f"{p}_Snow", (6.2, 1.25, 0.26), m @ T(0, -5.8, 7.25) @ R(34, "X"), e=0.6, nu=12, nv=5)


def gift(p, m, x, y, z, s, col, rib):
    place = m @ T(x, y, z + s / 2)
    box(f"{p}_{col}", (s, s, s), place, bevel=0.04)
    box(f"{p}_{rib}", (s + 0.05, s * 0.2, s + 0.05), place, bevel=0)
    box(f"{p}_{rib}", (s * 0.2, s + 0.05, s + 0.05), place, bevel=0)


def shop_kiosk():
    p = "ShopKiosk"
    m = O(p)
    kiosk_shell(p, m, "Red", "Cream")
    for x, y, z, s, col, rib in [(-4, -3.8, 3.68, 1.4, "Blue", "Gold"), (-1.7, -3.8, 3.68, 1.0, "Green", "Red"), (1.4, -3.8, 3.68, 1.6, "Red", "Gold"), (4, -3.8, 3.68, 1.1, "Gold", "Blue"), (-3.5, 1.3, 3.4, 1.3, "Red", "Cream"), (0, 1.3, 3.4, 1.6, "Green", "Gold"), (3.5, 1.3, 3.4, 1.3, "Blue", "Cream")]:
        gift(p, m, x, y, z, s, col, rib)
    # большой подарок на крыше
    gift(p, m, 0, 0, 11.5, 3.0, "Red", "Gold")
    for sign in (-1, 1):
        lathe(f"{p}_Gold", [(0, -0.25), (0.75, -0.15), (0.9, 0), (0.75, 0.15), (0, 0.25)], seg=8, m=m @ T(sign * 0.75, 0, 14.9) @ R(90, "X"))


def backpack(p, m, x, y, z, s, mat):
    place = m @ T(x, y, z + s * 0.75)
    blob(f"{p}_{mat}", (s * 0.55, s * 0.36, s * 0.75), place, e=0.45, nu=12, nv=6)
    blob(f"{p}_{mat}", (s * 0.42, s * 0.14, s * 0.3), place @ T(0, -s * 0.38, -s * 0.22), e=0.5, nu=10, nv=5)
    box(f"{p}_Dark", (s * 0.08, s * 0.05, s * 1.2), place @ T(-s * 0.22, s * 0.36, 0), bevel=0)
    box(f"{p}_Dark", (s * 0.08, s * 0.05, s * 1.2), place @ T(s * 0.22, s * 0.36, 0), bevel=0)
    box(f"{p}_Metal", (s * 0.34, s * 0.04, s * 0.04), place @ T(0, -s * 0.52, -s * 0.3), bevel=0)


def upgrade_kiosk():
    p = "UpgradeKiosk"
    m = O(p)
    kiosk_shell(p, m, "Blue", "Cream")
    # лестница прокачки: рюкзаки растут от маленького к золотому гиганту
    for x, s, mat in ((-4.6, 0.75, "Green"), (-2.4, 1.1, "Blue"), (0.5, 1.5, "Purple"), (4.0, 2.0, "Gold")):
        backpack(p, m, x, -3.75, 3.68, s, mat)
    # инструменты на задней стене
    def shovel(x, mat):
        box(f"{p}_WoodDark", (0.14, 0.14, 2.9), m @ T(x, 3.85, 5.5), bevel=0)
        box(f"{p}_{mat}", (1.0, 0.08, 0.8), m @ T(x, 3.85, 3.9), bevel=0.02)
    shovel(-4.2, "Metal")
    shovel(-2.6, "Red")
    box(f"{p}_Red", (1.5, 1.0, 1.0), m @ T(0.2, 3.65, 4.6), bevel=0.08)
    lathe(f"{p}_Dark", [(0, 0), (0.42, 0), (0.42, 0.25), (0, 0.25)], seg=8, m=m @ T(0.2, 3.1, 4.6) @ R(90, "X"))
    box(f"{p}_Gold", (2.0, 1.3, 1.5), m @ T(3.4, 3.55, 4.95), bevel=0.1)
    tube(f"{p}_Metal", [m @ Vector((3.4, 3.4, 5.8)), m @ Vector((3.4, 3.4, 7.1)), m @ Vector((4.4, 3.4, 7.1))], 0.14, seg=6)
    # огромный рюкзак на крыше — виден издалека
    backpack(p, m, 0, 0, 11.3, 3.2, "Gold")


# ============================================================
# Беседка рекордов: начало — центр на земле, ступени спереди (-Y)
# ============================================================
def gazebo():
    p = "Gazebo"
    m = O(p)
    R0, SEG = 9.0, 8
    start = math.pi / 8
    lathe(f"{p}_Stone", [(0, 0), (R0 + 0.6, 0), (R0 + 0.6, 0.4), (0, 0.4)], seg=SEG, m=m, start=start)
    lathe(f"{p}_Wood", [(0, 0.4), (R0 + 0.25, 0.4), (R0 + 0.25, 0.9), (0, 0.9)], seg=SEG, m=m, start=start)
    for i in range(3):
        box(f"{p}_Wood", (6, 1.0, 0.3), m @ T(0, -(R0 * math.cos(start) + 0.7 + i * 0.9), 0.75 - i * 0.28), bevel=0.02)
    pts = []
    for k in range(SEG):
        a = start + k * math.tau / SEG
        pts.append((R0 * math.cos(a), R0 * math.sin(a)))
        box(f"{p}_Trim", (0.6, 0.6, 9.0), m @ T(pts[-1][0], pts[-1][1], 5.4), bevel=0.06)
    for k in range(SEG):
        a, b = Vector((*pts[k], 0)), Vector((*pts[(k + 1) % SEG], 0))
        mid = (a + b) / 2
        ang = math.degrees(math.atan2(b.y - a.y, b.x - a.x))
        length = (b - a).length
        box(f"{p}_Trim", (length, 0.34, 0.34), m @ T(mid.x, mid.y, 9.9) @ R(ang, "Z"), bevel=0.03)
        if abs(mid.x) > 0.5 or mid.y > 0:  # спереди проём
            box(f"{p}_Trim", (length, 0.2, 0.2), m @ T(mid.x, mid.y, 3.5) @ R(ang, "Z"), bevel=0.02)
            for i in range(1, 6):
                q = a.lerp(b, i / 6)
                box(f"{p}_Trim", (0.12, 0.12, 2.6), m @ T(q.x, q.y, 2.2), bevel=0)
        garland(p, m, (a.x, a.y, 9.6), (b.x, b.y, 9.6), 8, sag=0.32)
    # крыша: чешуйчатый конус, снег, шпиль с фонарём
    lathe(f"{p}_Roof", [(0, 9.9), (R0 + 1.6, 9.9), (R0 + 1.6, 10.1), (3.0, 14.5), (0.5, 16.3), (0, 16.4)], seg=SEG, m=m, start=start)
    lathe(f"{p}_Snow", [(R0 + 1.5, 10.2), (R0 + 1.7, 10.15), (R0 + 1.2, 10.75), (3.0, 15.0), (0.4, 16.7), (0, 16.8)], seg=SEG, m=m, start=start)
    lathe(f"{p}_Gold", [(0, 16.6), (0.3, 16.6), (0.12, 18.5), (0, 19.0)], seg=8, m=m)
    lathe(f"{p}_Light", [(0, 7.2), (0.55, 7.5), (0.55, 8.4), (0, 8.7)], seg=8, m=m)
    lathe(f"{p}_WoodDark", [(0, 8.7), (0.1, 8.7), (0.1, 9.9), (0, 9.9)], seg=6, m=m)
    # пьедестал 1-2-3 и кубок
    for x, h, mat in ((0, 2.7, "Gold"), (-3.6, 1.8, "Silver"), (3.6, 1.2, "Bronze")):
        box(f"{p}_{mat}", (3.4, 3.4, h), m @ T(x, 1.4, 0.9 + h / 2), bevel=0.06)
    lathe(f"{p}_Gold", [(0, 3.6), (0.75, 3.6), (0.75, 3.8), (0.2, 4.05), (0.2, 4.7), (0.55, 4.9), (1.15, 5.6), (1.2, 6.5), (1.1, 6.5), (0.5, 5.2), (0, 5.1)], seg=12, m=m @ T(0, 1.4, 0))


# ============================================================
# Горка: начало — на уровне земли. +X — вниз по скату. Верхняя площадка x -24..-17 на высоте 14.
# Жёлоб |y| < 4, лестница в полосе y -11..-7. Полоса разгона заканчивается на x = 20.
# ============================================================
SLOPE_TOP, SLOPE_END, HILL_H = -17.0, 20.0, 13.6


def slope(x):
    s = max(0.0, min(1.0, (x - SLOPE_TOP) / (SLOPE_END - SLOPE_TOP)))
    return HILL_H * (1 - s) ** 1.7


def hill():
    p = "Hill"
    m = O(p)

    def h_snow(x, y):
        # по бокам жёлоба снежные бортики, дальше склон уходит в землю
        ay = abs(y)
        base = slope(x) if x >= -24 else 0
        if x < -24:
            base = max(0, HILL_H * (1 - (-24 - x) / 2.5))
        side_limit = 13.0 if y > 0 else 6.8
        fall = 1 - max(0.0, min(1.0, (ay - 4.6) / (side_limit - 4.6)))
        fall = fall * fall * (3 - 2 * fall)
        wall = 1.2 * max(0.0, 1 - abs(ay - 4.8) / 1.0) * min(1.0, base / 1.5 + 0.3)
        n = noise.noise(Vector((x / 5, y / 5, 2.0))) * 0.55 * fall
        z = base * fall + wall * (1 if x < SLOPE_END + 1 else 0) + n
        return max(0.0, z)

    grid = []
    for i in range(46):
        x = -27 + i * 1.1
        row = []
        for j in range(25):
            y = -7.5 + j * (21.0 / 24)
            if abs(y) < 3.9:
                z = max(slope(x) - 0.12, 0.0) if x >= -24 else h_snow(x, y)
            else:
                z = h_snow(x, y)
            row.append((x, y, z))
        grid.append(row)
    patch(f"{p}_Snow", grid, lambda fc: fc - Vector((0, 0, 1)), m)

    ice = []
    for i in range(40):
        x = SLOPE_TOP - 0.2 + i * (SLOPE_END + 2.5 - SLOPE_TOP) / 39
        row = []
        for y in (-4.0, -3.2, -1.1, 1.1, 3.2, 4.0):
            dip = 0.28 if abs(y) < 2 else (0.12 if abs(y) < 3.5 else 0.0)
            row.append((x, y, slope(x) + 0.14 - dip * 0.4))
        ice.append(row)
    patch(f"{p}_Ice", ice, lambda fc: fc - Vector((0, 0, 1)), m)

    # верхняя площадка и перила
    box(f"{p}_Wood", (7.6, 16.6, 0.4), m @ T(-20.8, -3.0, HILL_H), bevel=0.03)
    for x, y in ((-24.3, -11), (-24.3, 5), (-17.3, -11), (-17.3, 5), (-24.3, -3)):
        box(f"{p}_WoodDark", (0.4, 0.4, HILL_H + 3.5), m @ T(x, y, (HILL_H + 3.5) / 2), bevel=0.02)
    box(f"{p}_WoodDark", (0.2, 16.2, 0.2), m @ T(-24.3, -3.0, HILL_H + 3.0), bevel=0)
    box(f"{p}_WoodDark", (0.2, 16.2, 0.2), m @ T(-24.3, -3.0, HILL_H + 1.8), bevel=0)
    box(f"{p}_WoodDark", (7.0, 0.2, 0.2), m @ T(-20.8, 5, HILL_H + 3.0), bevel=0)
    box(f"{p}_WoodDark", (7.0, 0.2, 0.2), m @ T(-20.8, 5, HILL_H + 1.8), bevel=0)
    # лестница
    steps = 24
    for i in range(steps):
        t = i / (steps - 1)
        x = 4.0 - 21.0 * t
        z = (HILL_H - 0.3) * t
        box(f"{p}_Wood", (0.95, 4.0, 0.2), m @ T(x, -9.0, z + 0.2), bevel=0)
    for y in (-11.1, -6.9):
        tube(f"{p}_WoodDark", [m @ Vector((4.5, y, 0)), m @ Vector((-17.3, y, HILL_H))], 0.2, seg=4)
        tube(f"{p}_Trim", [m @ Vector((4.5, y, 3.2)), m @ Vector((-17.3, y, HILL_H + 3.2))], 0.1, seg=4)
        for i in range(5):
            t = i / 4
            x = 4.5 - 21.8 * t
            z = HILL_H * t
            box(f"{p}_WoodDark", (0.25, 0.25, z + 3.2), m @ T(x, y, (z + 3.2) / 2), bevel=0)
    # арка над стартом с гирляндой
    for y in (-5.1, 5.1):
        box(f"{p}_Red", (0.5, 0.5, 6.5), m @ T(-16.6, y, HILL_H + 2.9), bevel=0.04)
    box(f"{p}_Red", (0.6, 11.0, 0.7), m @ T(-16.6, 0, HILL_H + 6.2), bevel=0.05)
    blob(f"{p}_Snow", (0.5, 5.7, 0.28), m @ T(-16.6, 0, HILL_H + 6.7), e=0.6, nu=12, nv=5)
    garland(p, m, (-16.9, -5.2, HILL_H + 5.75), (-16.9, 5.2, HILL_H + 5.75), 14, sag=0.3)
    for y in (-5.1, 5.1):
        lathe(f"{p}_Light", [(0, 0), (0.45, 0.1), (0.45, 0.7), (0, 0.85)], seg=8, m=m @ T(-16.6, y, HILL_H + 6.85))
    # снежные валы по бокам конца разгона: сама полоса свободна, на площадь не заходят
    for y in (-7.5, -5.6, 5.6, 7.5):
        blob(f"{p}_Snow", (2.4, 1.6, 1.1), m @ T(16.5 + rng.random() * 2, y, 0.75), e=0.85, nu=10, nv=5)


# ============================================================
# Площадь и дорожки: начало совпадает с началом координат игры, верх камня Z = 0.3
# ============================================================
def plaza():
    p = "Plaza"
    m = O(p)
    lift = 0.3
    # круглая площадка появления: (0, +Z 30 в игре) → Blender y = -30
    lathe(f"{p}_Stone", [(0, 0), (11, 0), (11, lift), (0, lift)], seg=28, m=m @ T(0, -30, 0))
    lathe(f"{p}_Light", [(5.6, lift), (6.0, lift), (6.0, lift + 0.04), (5.6, lift + 0.04)], seg=28, m=m @ T(0, -30, 0))
    # главная дорожка и поперечная вдоль трапов
    box(f"{p}_Stone", (9, 44, lift), m @ T(0, -2, lift / 2), bevel=0)
    box(f"{p}_Stone", (112, 8, lift), m @ T(0, 14, lift / 2), bevel=0)
    # снег по краям дорожек
    for x, y in ((-5.2, -22), (5.2, -22), (-5.2, -8), (5.2, -8), (-5.2, 4), (5.2, 4)):
        blob(f"{p}_Snow", (1.1, 7.0, 0.3), m @ T(x, y, lift * 0.6), e=0.8, nu=8, nv=4)
    for x in (-46, -32, -18, 18, 32, 46):
        blob(f"{p}_Snow", (5.5, 1.0, 0.28), m @ T(x, 9.4, lift * 0.6), e=0.8, nu=8, nv=4)


truck()
big_tree()
shop_kiosk()
upgrade_kiosk()
gazebo()
hill()
plaza()

# Центры мешей: по ним предметы собираются в Studio
centers = {}
for name, b in buckets.items():
    if b.verts:
        lo = [min(v[i] for v in b.verts) for i in range(3)]
        hi = [max(v[i] for v in b.verts) for i in range(3)]
        centers[name] = [round((lo[i] + hi[i]) / 2, 3) for i in range(3)]
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "lobby.json"), "w") as f:
    json.dump({"props": {k: v[0] for k, v in PROPS.items()}, "centers": centers}, f, indent=1)

finish(
    "Lobby",
    MATERIALS,
    OUT,
    "lobby",
    render=RENDER,
    views={
        "truck_back": ((-170, -36, 12), (-170, 6, 9)),
        "truck_quarter": ((-146, -26, 16), (-170, 6, 8)),
        "truck_side": ((-126, 9, 10), (-170, 9, 8)),
        "truck_front": ((-156, 52, 12), (-170, 12, 6)),
        "tree": ((-85, -52, 22), (-115, 0, 20)),
        "kiosks": ((-55, -36, 12), (-60, 0, 7)),
        "gazebo": ((12, -30, 14), (-10, 0, 7)),
        "hill": ((90, -42, 26), (42, 0, 6)),
    },
    ground=(0.8, 0.85, 0.95, 1),
)
