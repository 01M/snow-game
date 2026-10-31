# Снегоплавилка для Snow Cleaning Simulator. Запуск:
#   blender --background --python snowmelter.py -- <папка вывода> [render]
# 1 единица Blender = 1 stud. Начало координат = центр на уровне земли, перед машины смотрит в -Y
# (в игре это +Z, в сторону двора). Каждый материал — отдельный меш: в Studio это отдельный MeshPart,
# цвет и материал которому задаются уже там.
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.dirname(os.path.abspath(__file__))
RENDER = "render" in argv

# Имя: (цвет RGB 0-255, metallic, roughness, сила свечения)
MATERIALS = {
    "Iron": ((58, 62, 70), 0.85, 0.5, 0),
    "RedPaint": ((186, 44, 34), 0.25, 0.32, 0),
    "Steel": ((150, 160, 172), 0.9, 0.38, 0),
    "Brass": ((222, 168, 62), 1.0, 0.28, 0),
    "Copper": ((196, 106, 62), 1.0, 0.3, 0),
    "Concrete": ((128, 128, 132), 0.0, 0.9, 0),
    "Snow": ((244, 249, 255), 0.0, 0.75, 0),
    "Ice": ((170, 222, 255), 0.0, 0.08, 0),
    "Fire": ((255, 130, 30), 0.0, 0.5, 6),
    "Dial": ((244, 240, 225), 0.0, 0.4, 0),
    "Needle": ((200, 30, 30), 0.0, 0.4, 0),
}


class Bucket:
    def __init__(self):
        self.verts, self.faces = [], []

    def add(self, verts, faces, m=None):
        base = len(self.verts)
        for v in verts:
            v = Vector(v)
            self.verts.append(m @ v if m else v)
        for f in faces:
            self.faces.append([i + base for i in f])


buckets = {name: Bucket() for name in MATERIALS}


def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def lathe(mat, profile, seg=32, m=None, start=0.0):
    """Тело вращения вокруг Z. profile — [(радиус, z)] снизу вверх: нормали наружу; сверху вниз — внутрь."""
    verts, faces, rings = [], [], []
    for r, z in profile:
        if r < 1e-5:
            rings.append([len(verts)])
            verts.append((0, 0, z))
        else:
            ring = []
            for k in range(seg):
                a = start + 2 * math.pi * k / seg
                ring.append(len(verts))
                verts.append((r * math.cos(a), r * math.sin(a), z))
            rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(seg):
            k2 = (k + 1) % seg
            if len(a) == 1:
                faces.append([a[0], b[k], b[k2]])
            elif len(b) == 1:
                faces.append([a[k], a[k2], b[0]])
            else:
                faces.append([a[k], a[k2], b[k2], b[k]])
    buckets[mat].add(verts, faces, m)


def round_profile(points, radius=0.06):
    """Скругляет углы профиля двумя фасками — на ребре появляется блик, как у настоящей детали."""
    out = [points[0]]
    for i in range(1, len(points) - 1):
        p, a, b = Vector(points[i]), Vector(points[i - 1]), Vector(points[i + 1])
        d1, d2 = a - p, b - p
        r = min(radius, d1.length * 0.45, d2.length * 0.45)
        if r < 1e-4 or d1.length < 1e-4 or d2.length < 1e-4:
            out.append(points[i])
            continue
        p1, p2 = p + d1.normalized() * r, p + d2.normalized() * r
        out += [tuple(p1), tuple((p1 + p2) / 2 * 0.6 + p * 0.4), tuple(p2)]
    out.append(points[-1])
    return out


def box(mat, size, m=None, bevel=0.05, segments=1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=bevel, segments=segments, profile=0.5, affect="EDGES")
    verts = [tuple(v.co) for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    buckets[mat].add(verts, faces, m)


def fillet(points, radius, steps=6):
    """Полилиния со скруглёнными углами (для труб)."""
    pts = [Vector(p) for p in points]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        p, d1, d2 = pts[i], pts[i - 1] - pts[i], pts[i + 1] - pts[i]
        r = min(radius, d1.length * 0.49, d2.length * 0.49)
        a, b = p + d1.normalized() * r, p + d2.normalized() * r
        for s in range(steps + 1):
            t = s / steps
            out.append(a * (1 - t) ** 2 + p * 2 * t * (1 - t) + b * t * t)
    out.append(pts[-1])
    return out


def tube(mat, path, radius, seg=10, caps=True):
    path = [Vector(p) for p in path]
    verts, faces = [], []
    up = Vector((0, 0, 1))
    t0 = (path[1] - path[0]).normalized()
    n = t0.cross(up)
    if n.length < 1e-3:
        n = t0.cross(Vector((1, 0, 0)))
    n.normalize()
    prev_t = t0
    for i, p in enumerate(path):
        if i == 0:
            t = t0
        elif i == len(path) - 1:
            t = (path[i] - path[i - 1]).normalized()
        else:
            t = (path[i + 1] - path[i - 1]).normalized()
        n = (n - t * n.dot(t)).normalized()
        b = t.cross(n)
        for k in range(seg):
            a = 2 * math.pi * k / seg
            verts.append(p + n * (radius * math.cos(a)) + b * (radius * math.sin(a)))
        prev_t = t
    for i in range(len(path) - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            faces.append([i * seg + k, i * seg + k2, (i + 1) * seg + k2, (i + 1) * seg + k])
    if caps:
        faces.append(list(range(seg - 1, -1, -1)))
        last = (len(path) - 1) * seg
        faces.append([last + k for k in range(seg)])
    buckets[mat].add(verts, faces)


def rivet(mat, pos, normal, radius=0.075):
    m = Matrix.Translation(pos) @ Vector((0, 0, 1)).rotation_difference(Vector(normal).normalized()).to_matrix().to_4x4()
    lathe(mat, [(radius, 0.0), (radius * 0.72, radius * 0.7), (0, radius)], seg=5, m=m)


def rivet_ring(mat, radius, z, count, rivet_r=0.075, phase=0.0):
    for i in range(count):
        a = phase + 2 * math.pi * i / count
        d = Vector((math.cos(a), math.sin(a), 0))
        rivet(mat, d * radius + Vector((0, 0, z)), d, rivet_r)


def facing(direction, pos):
    """Матрица: локальная +Z смотрит в direction, стоит в pos."""
    r = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4()
    return Matrix.Translation(pos) @ r


def polar(angle_deg, radius, z):
    a = math.radians(angle_deg)
    return Vector((radius * math.cos(a), radius * math.sin(a), z))


# ============================================================
# Фундамент
# ============================================================
lathe("Concrete", round_profile([(0, 0), (5.75, 0), (5.75, 0.32), (4.85, 0.32), (4.85, 0.62), (0, 0.62)], 0.05), seg=8, start=math.radians(22.5))

# ============================================================
# Топка: чугунная, с фланцами и заклёпками
# ============================================================
TOP_FIRE = 3.05
lathe("Iron", round_profile([
    (0, 0.62), (3.95, 0.62), (3.95, 0.86), (3.62, 0.86), (3.5, 1.1), (3.5, 2.72), (3.8, 2.72), (3.8, TOP_FIRE), (0, TOP_FIRE),
], 0.05), seg=32)
rivet_ring("Steel", 3.8, 0.74, 22, 0.08, 0.05)
rivet_ring("Steel", 3.8, 2.885, 22, 0.08)

# Проём топки спереди: рама, огонь, колосники
FRONT = -3.5
box("Iron", (3.5, 0.5, 0.3), T(0, FRONT - 0.02, 2.59), bevel=0.05)
box("Iron", (3.5, 0.5, 0.3), T(0, FRONT - 0.02, 1.13), bevel=0.05)
for x in (-1.6, 1.6):
    box("Iron", (0.3, 0.5, 1.2), T(x, FRONT - 0.02, 1.86), bevel=0.05)
box("Fire", (3.0, 0.1, 1.3), T(0, FRONT + 0.06, 1.86), bevel=0)
for i in range(7):
    x = -1.2 + i * 0.4
    tube("Iron", [(x, FRONT - 0.3, 1.26), (x, FRONT - 0.3, 2.46)], 0.05, seg=6)
for z in (1.86,):
    tube("Iron", [(-1.45, FRONT - 0.3, z), (1.45, FRONT - 0.3, z)], 0.045, seg=6)
for x in (-1.6, 1.6):
    for z in (1.15, 2.57):
        rivet("Steel", (x, FRONT - 0.27, z), (0, -1, 0), 0.07)
# Открытая дверца на петлях
HX = 1.78
for z in (1.35, 2.35):
    tube("Steel", [(HX, FRONT - 0.3, z - 0.15), (HX, FRONT - 0.3, z + 0.15)], 0.08, seg=8)
door = T(HX + 0.72, FRONT - 0.72, 1.85) @ Matrix.Rotation(math.radians(-45), 4, "Z")
box("Iron", (0.14, 2.0, 1.45), door @ T(0, 0, 0) @ Matrix.Rotation(math.radians(90), 4, "Z"), bevel=0.04)
tube("Brass", fillet([door @ Vector((-0.6, -0.07, -0.3)), door @ Vector((-0.6, -0.28, -0.3)), door @ Vector((-0.6, -0.28, 0.3)), door @ Vector((-0.6, -0.07, 0.3))], 0.07, steps=3), 0.045, seg=6)
# Зольный ящик
box("Steel", (2.4, 0.5, 0.4), T(0, FRONT - 0.32, 0.95), bevel=0.05)
tube("Brass", [(-0.35, FRONT - 0.57, 0.95), (-0.35, FRONT - 0.72, 0.95), (0.35, FRONT - 0.72, 0.95), (0.35, FRONT - 0.57, 0.95)], 0.04, seg=6)

# ============================================================
# Бак: выпуклый, красный, с бандажами и вертикальными швами
# ============================================================
B0, B1 = TOP_FIRE, 7.15
profile = [(3.3, B0)]
for i in range(1, 12):
    t = i / 11
    profile.append((3.3 + 0.28 * math.sin(math.pi * t), B0 + (B1 - B0) * t))
profile = [(0, B0)] + profile + [(2.75, B1 + 0.2), (0, B1 + 0.2)]
lathe("RedPaint", profile, seg=40)


def tank_r(z):
    return 3.3 + 0.28 * math.sin(math.pi * (z - B0) / (B1 - B0))


for z in (3.75, 6.45):
    r = tank_r(z) + 0.07
    lathe("Iron", round_profile([(r - 0.1, z - 0.17), (r, z - 0.17), (r, z + 0.17), (r - 0.1, z + 0.17)], 0.03), seg=36)
    rivet_ring("Steel", r, z, 24, 0.06)
# Вертикальные швы
for ang in (135, 225, 315, 45):
    path = [polar(ang, tank_r(3.75 + i * 0.27) + 0.015, 3.75 + i * 0.27) for i in range(11)]
    tube("Iron", path, 0.05, seg=6)
    for i in range(1, 10, 2):
        z = 3.75 + i * 0.27
        rivet("Steel", polar(ang, tank_r(z) + 0.05, z), polar(ang, 1, 0), 0.05)

# Манометр спереди
gz = 5.3
gp = polar(-68, tank_r(gz), gz)
gd = polar(-68, 1, 0)
tube("Brass", [gp - gd * 0.05, gp + gd * 0.42], 0.09, seg=8)
g = facing(gd, gp + gd * 0.42)
lathe("Brass", round_profile([(0, -0.06), (0.62, -0.06), (0.62, 0.16), (0.5, 0.16), (0.5, 0.08), (0, 0.08)], 0.03), seg=28, m=g)
lathe("Dial", [(0, 0.1), (0.5, 0.1)][::-1], seg=28, m=g)
for i in range(9):
    a = math.radians(-135 + i * 270 / 8) + math.pi / 2
    tick = g @ T(0.4 * math.cos(a), 0.4 * math.sin(a), 0.112)
    box("Iron", (0.03, 0.03, 0.01), tick, bevel=0)
tube("Needle", [g @ Vector((0, 0, 0.125)), g @ Vector((0.27, 0.2, 0.125))], 0.022, seg=5)
lathe("Iron", [(0, 0.11), (0.06, 0.11), (0.06, 0.15), (0, 0.15)], seg=10, m=g)

# Вентиль сбоку
vz = 4.9
vp = polar(-20, tank_r(vz), vz)
vd = polar(-20, 1, 0)
tube("Copper", [vp - vd * 0.05, vp + vd * 0.55], 0.13, seg=10)
lathe("Brass", [(0, 0.25), (0.2, 0.25), (0.2, 0.55), (0, 0.55)], seg=10, m=facing(vd, vp))
v = facing(vd, vp + vd * 0.72)
tube("Iron", [v @ Vector((0, 0, -0.25)), v @ Vector((0, 0, 0.05))], 0.04, seg=6)
ring = [v @ Vector((0.44 * math.cos(2 * math.pi * i / 20), 0.44 * math.sin(2 * math.pi * i / 20), 0)) for i in range(21)]
tube("RedPaint", ring, 0.065, seg=8, caps=False)
for i in range(4):
    a = math.pi / 4 + i * math.pi / 2
    tube("RedPaint", [v @ Vector((0, 0, 0)), v @ Vector((0.42 * math.cos(a), 0.42 * math.sin(a), 0))], 0.04, seg=6)

# Медный змеевик вокруг бака (на задней и боковых сторонах, спереди не закрывает манометр)
coil = []
for i in range(70):
    t = i / 69
    ang = 110 + t * 320
    z = 4.15 + t * 1.75
    coil.append(polar(ang, tank_r(z) + 0.1, z))
coil = [polar(110, tank_r(4.15) - 0.1, 4.15)] + coil + [polar(430, tank_r(5.9) - 0.1, 5.9)]
tube("Copper", coil, 0.085, seg=6)
for ang in (150, 230, 310, 390):
    t = (ang - 110) / 320
    z = 4.15 + t * 1.75
    tube("Iron", [polar(ang, tank_r(z) + 0.1, z - 0.13), polar(ang, tank_r(z) + 0.1, z + 0.13)], 0.11, seg=6)

# ============================================================
# Воронка со снегом
# ============================================================
H0, H1 = 7.2, 9.1
lathe("Steel", round_profile([
    (2.6, H0), (2.75, H0 + 0.25), (4.3, H1), (4.42, H1 + 0.14), (4.42, H1 + 0.3), (4.2, H1 + 0.3), (4.1, H1 + 0.12), (2.65, H0 + 0.45), (0, H0 + 0.45),
], 0.04), seg=40)
lathe("Iron", round_profile([(2.62, H0 + 0.02), (2.92, H0 + 0.02), (2.92, H0 + 0.3), (2.7, H0 + 0.3)], 0.03), seg=32)
lathe("Iron", round_profile([(4.2, H1 - 0.06), (4.5, H1 - 0.06), (4.5, H1 + 0.16), (4.3, H1 + 0.16)], 0.03), seg=40)
rivet_ring("Steel", 4.5, H1 + 0.05, 28, 0.065)
# Рёбра воронки
for i in range(8):
    ang = 22.5 + i * 45
    tube("Iron", [polar(ang, 2.92, H0 + 0.4), polar(ang, 4.2, H1 - 0.1)], 0.055, seg=6)


# Шапка снега: неровная, переваливается через край
def snow_height(x, y):
    r = math.hypot(x, y)
    dome = 1.25 * max(0.0, 1 - (r / 4.25) ** 2) ** 0.6
    n = noise.noise(Vector((x * 0.55, y * 0.55, 1.7))) * 0.42 + noise.noise(Vector((x * 1.4, y * 1.4, 5.1))) * 0.12
    return H1 + 0.18 + dome + n * min(1.0, (4.4 - r) * 1.2 if r < 4.4 else 0)


seg, rings_n = 56, 13
verts, faces = [], []
verts.append((0, 0, snow_height(0, 0)))
for j in range(1, rings_n + 1):
    t = j / rings_n
    for k in range(seg):
        a = 2 * math.pi * k / seg
        wob = 1 + 0.035 * math.sin(a * 5 + 1.3) + 0.025 * math.sin(a * 11)
        r = 4.42 * t * (wob if j > rings_n - 2 else 1)
        x, y = r * math.cos(a), r * math.sin(a)
        verts.append((x, y, snow_height(x, y)))
for k in range(seg):
    faces.append([0, 1 + k, 1 + (k + 1) % seg])
for j in range(rings_n - 1):
    for k in range(seg):
        k2 = (k + 1) % seg
        a = 1 + j * seg
        b = 1 + (j + 1) * seg
        faces.append([a + k, b + k, b + k2, a + k2])
# закрываем снизу, чтобы шапка не была пустой изнутри
last = 1 + (rings_n - 1) * seg
faces.append([last + k for k in range(seg - 1, -1, -1)])
buckets["Snow"].add(verts, faces)
# Языки снега, свисающие с края
for ang, length in [(-100, 0.55), (-62, 0.32), (-28, 0.48), (35, 0.4), (95, 0.55), (160, 0.35), (205, 0.5), (245, 0.3)]:
    p = polar(ang, 4.42, H1 + 0.24)
    m = T(*p) @ Matrix.Rotation(math.radians(ang), 4, "Z")
    lathe("Snow", [(0, -length), (0.14, -length * 0.8), (0.26, -length * 0.3), (0.31, 0.02), (0.2, 0.2), (0, 0.27)], seg=9, m=m @ Matrix.Diagonal((0.55, 1.3, 1, 1)))

# Сосульки
for i, (ang, length) in enumerate([(-115, 0.75), (-88, 0.45), (-74, 0.9), (-46, 0.55), (-12, 0.7), (18, 0.4), (58, 0.8), (118, 0.6), (142, 0.42), (182, 0.72), (222, 0.5), (262, 0.62)]):
    p = polar(ang, 4.44, H1 - 0.04)
    lathe("Ice", [(0, -length), (0.05, -length * 0.55), (0.1, -length * 0.15), (0.11, 0), (0, 0.04)], seg=6, m=T(*p))

# ============================================================
# Дымовая труба за баком
# ============================================================
CH = polar(45, 4.75, 0)
stub = polar(45, 3.45, 2.1)
chim = fillet([stub, Vector((CH.x, CH.y, 2.1)), Vector((CH.x, CH.y, 13.0))], 0.8, steps=8)
tube("Iron", chim, 0.5, seg=14, caps=False)
for z in (4.2, 6.9, 9.6, 12.2):
    lathe("Iron", round_profile([(0.5, z - 0.12), (0.62, z - 0.12), (0.62, z + 0.12), (0.5, z + 0.12)], 0.03), seg=18, m=T(CH.x, CH.y, 0))
    for i in range(6):
        a = 2 * math.pi * i / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        rivet("Steel", Vector((CH.x, CH.y, z)) + d * 0.62, d, 0.04)
lathe("Iron", round_profile([(0.5, 12.75), (0.72, 13.15), (0.72, 13.4), (0.54, 13.4), (0.44, 13.2), (0.0, 13.2)], 0.03), seg=20, m=T(CH.x, CH.y, 0))
# Хомут и лапа, держащие трубу у воронки
tube("Iron", [polar(45, 4.2, 9.0), polar(45, 4.3, 9.0)], 0.08, seg=6)
tube("Iron", [Vector((CH.x, CH.y, 6.9)), polar(45, tank_r(6.45), 6.6)], 0.07, seg=6)
lathe("Iron", round_profile([(0, 0.62), (0.85, 0.62), (0.85, 0.82), (0.55, 1.0), (0.42, 1.0)], 0.03), seg=14, m=T(CH.x, CH.y, 0))
tube("Iron", [Vector((CH.x, CH.y, 0.9)), Vector((CH.x, CH.y, 2.0))], 0.28, seg=12)

# ============================================================
# Лестница сзади слева
# ============================================================
LA = 135
ldir = polar(LA, 1, 0)
lside = Vector((-ldir.y, ldir.x, 0))
for s in (-0.55, 0.55):
    base = ldir * 4.55 + lside * s
    tube("Steel", fillet([base + Vector((0, 0, 0.62)), base + Vector((0, 0, 9.7)), base - ldir * 0.4 + Vector((0, 0, 10.05))], 0.25, steps=5), 0.07, seg=8)
    tube("Steel", [ldir * 4.55 + lside * s + Vector((0, 0, 2)), ldir * 3.6 + lside * s + Vector((0, 0, 2))], 0.05, seg=6)
    tube("Steel", [ldir * 4.55 + lside * s + Vector((0, 0, 6.9)), ldir * 3.6 + lside * s + Vector((0, 0, 6.9))], 0.05, seg=6)
for i in range(11):
    z = 1.2 + i * 0.8
    tube("Steel", [ldir * 4.55 + lside * -0.55 + Vector((0, 0, z)), ldir * 4.55 + lside * 0.55 + Vector((0, 0, z))], 0.05, seg=6)

# ============================================================
# Слив талой воды слева
# ============================================================
dz = 3.45
drain = fillet([polar(180, 3.4, dz), polar(180, 5.0, dz), polar(180, 5.0, dz - 1.25)], 0.45, steps=8)
tube("Copper", drain, 0.2, seg=12)
lathe("Iron", round_profile([(0.2, -0.1), (0.34, -0.1), (0.34, 0.1), (0.2, 0.1)], 0.03), seg=12, m=facing((-1, 0, 0), polar(180, tank_r(dz) + 0.1, dz)))
spout = polar(180, 5.0, dz - 1.25)
lathe("Copper", [(0.2, spout.z + 0.1), (0.3, spout.z - 0.1), (0.3, spout.z - 0.22), (0.24, spout.z - 0.22)][::-1], seg=12, m=T(spout.x, spout.y, 0))
lathe("Ice", [(0.05, spout.z - 0.2), (0.1, 0.5), (0.0, 0.34)][::-1], seg=8, m=T(spout.x, spout.y, 0))
# Лужа: плоская, неровная
verts = [(-5.0, 0, 0.345)]
for k in range(28):
    a = 2 * math.pi * k / 28
    r = 0.75 + 0.1 * math.sin(a * 3 + 0.6) + 0.06 * math.sin(a * 7)
    verts.append((-5.0 + r * math.cos(a), r * 0.85 * math.sin(a), 0.345))
buckets["Ice"].add(verts, [[0, 1 + k, 1 + (k + 1) % 28] for k in range(28)])
# Снежок на фундаменте у подножия
for (x, y, s) in [(3.7, -3.1, 0.55), (-3.3, -3.55, 0.42), (4.2, -1.3, 0.35), (-1.2, 4.55, 0.5)]:
    lathe("Snow", [(0, 0.3), (s, 0.3), (s * 0.85, 0.3 + s * 0.28), (s * 0.45, 0.3 + s * 0.5), (0, 0.3 + s * 0.56)], seg=12, m=T(x, y, 0.32))


# ============================================================
# Сборка сцены
# ============================================================
bpy.ops.wm.read_factory_settings(use_empty=True)
objects = []
for name, (rgb, metal, rough, emit) in MATERIALS.items():
    b = buckets[name]
    if not b.faces:
        continue
    mesh = bpy.data.meshes.new("Melter_" + name)
    mesh.from_pydata([tuple(v) for v in b.verts], [], b.faces)
    mesh.update()
    mesh.shade_smooth()
    mesh.set_sharp_from_angle(angle=math.radians(40))
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    col = tuple((c / 255) ** 2.2 for c in rgb) + (1,)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = emit
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("Melter_" + name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    objects.append(obj)
    print(f"{name}: {len(mesh.vertices)} verts, {sum(len(p.vertices) - 2 for p in mesh.polygons)} tris")

total = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
print("TOTAL tris:", total)

os.makedirs(OUT, exist_ok=True)
for o in objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "snowmelter.fbx"),
    use_selection=True,
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z",
    axis_up="Y",
    mesh_smooth_type="FACE",
    bake_space_transform=True,
)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "snowmelter.blend"))

if RENDER:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    # Рендер на видеокарте: первый доступный тип устройств, иначе процессор
    prefs = bpy.context.preferences.addons["cycles"].preferences
    scene.cycles.device = "CPU"
    for device_type in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
        try:
            prefs.compute_device_type = device_type
        except TypeError:
            continue
        prefs.get_devices()
        gpus = [d for d in prefs.devices if d.type == device_type]
        if gpus:
            for d in prefs.devices:
                d.use = d.type == device_type
            scene.cycles.device = "GPU"
            print("Render device:", device_type, [d.name for d in gpus])
            break
    if scene.cycles.device == "CPU":
        print("Render device: CPU")
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1100, 1100
    scene.view_settings.view_transform = "Standard"

    ground = bpy.data.meshes.new("Ground")
    ground.from_pydata([(-60, -60, 0), (60, -60, 0), (60, 60, 0), (-60, 60, 0)], [], [[0, 1, 2, 3]])
    gmat = bpy.data.materials.new("GroundMat")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.25, 0.14, 1)
    ground.materials.append(gmat)
    scene.collection.objects.link(bpy.data.objects.new("Ground", ground))

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.74, 0.92, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    scene.world = world

    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.2
    sun.angle = math.radians(8)
    sun_obj = bpy.data.objects.new("Sun", sun)
    sun_obj.rotation_euler = (math.radians(52), 0, math.radians(-40))
    scene.collection.objects.link(sun_obj)

    cam = bpy.data.cameras.new("Cam")
    cam.lens = 42
    cam_obj = bpy.data.objects.new("Cam", cam)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    target = Vector((0, 0, 6.3))
    views = {"front": (9, -21, 11), "back": (-15, 18, 12), "close": (5.5, -10.5, 6)}
    for label, pos in views.items():
        cam_obj.location = pos
        cam_obj.rotation_euler = (target - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        if label == "close":
            cam_obj.rotation_euler = (Vector((0, -2, 4.6)) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(OUT, f"preview_{label}.png")
        bpy.ops.render.render(write_still=True)
print("DONE")
