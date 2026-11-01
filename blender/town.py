# Дальний план карты «Дом»: долина с городком на склонах, улицы с огнями, лес на холмах. Запуск:
#   blender --background --python town.py -- <папка вывода> [render]
# Координаты: (X, Y Blender) = (X игры, -Z игры), начало — в игре (0, 0, 0), уровень верха Baseplate.
# Всё разбито на 8 секторов вокруг участка: меш не больше 2048 studs, движок отбрасывает сектора вне камеры.
# Меш называется Town_S<сектор>_<материал>.
import math
import os
import random
import sys

import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modellib import buckets, finish, solid, use_materials

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.dirname(os.path.abspath(__file__))
RENDER = "render" in argv

SECTORS = 8
PALETTE = {
    "Ground": ((228, 234, 246), 0.0, 0.9, 0),
    "Road": ((122, 126, 140), 0.0, 0.9, 0),
    "Wall": ((176, 158, 138), 0.0, 0.8, 0),
    "Roof": ((236, 242, 250), 0.0, 0.8, 0),
    "Lit": ((255, 196, 110), 0.0, 0.5, 5),
    "TreeDark": ((52, 76, 86), 0.0, 0.9, 0),
    "TreeSnow": ((196, 210, 228), 0.0, 0.9, 0),
}
MATERIALS = {f"S{s}_{mat}": v for s in range(SECTORS) for mat, v in PALETTE.items()}
use_materials(MATERIALS)

rng = random.Random(77)
noise.seed_set(12)

CY = 20.0  # центр долины в координатах Blender (участок)
STRETCH = 1.5  # долина вытянута вдоль главной улицы
FLAT = 300.0  # до этого расстояния земля ровная
RIDGE = 1340.0  # внешний край холмов
EXCLUDE = (300.0, -240.0, 150.0)  # |x|, zmin, zmax: здесь стоят настоящие дома и участок


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def valley(x, y):
    return math.sqrt((x / STRETCH) ** 2 + (y - CY) ** 2)


def height(x, y):
    d = valley(x, y)
    t = smooth((d - FLAT) / (RIDGE - FLAT))
    if t <= 0:
        return 0.15
    wave = noise.noise(Vector((x / 460, y / 460, 3.0))) * 0.5 + noise.noise(Vector((x / 190, y / 190, 7.0))) * 0.14
    return 0.15 + t ** 1.35 * (210 + 120 * wave)


def sector(x, y):
    a = math.atan2(y - CY, x / STRETCH)
    return min(SECTORS - 1, int((a + math.pi) / (2 * math.pi) * SECTORS))


def key(x, y, mat):
    return f"S{sector(x, y)}_{mat}"


def excluded(gx, gz, pad=0.0):
    return abs(gx) < EXCLUDE[0] + pad and EXCLUDE[1] - pad < gz < EXCLUDE[2] + pad


# ============================================================
# Земля: кольцо от ровной части до гребня холмов
# ============================================================
def ground():
    n_az = 96
    ds = [FLAT - 6 + (RIDGE - FLAT + 6) * (i / 26) ** 1.15 for i in range(27)]
    for i in range(len(ds) - 1):
        for k in range(n_az):
            a0, a1 = -math.pi + 2 * math.pi * k / n_az, -math.pi + 2 * math.pi * (k + 1) / n_az
            pts = []
            for d, a in ((ds[i], a0), (ds[i], a1), (ds[i + 1], a1), (ds[i + 1], a0)):
                x, y = STRETCH * d * math.cos(a), CY + d * math.sin(a)
                pts.append((x, y, height(x, y)))
            # Сторона вверх: при обходе по углу от внутреннего кольца к внешнему нормаль смотрит вверх через разворот
            face = [0, 3, 2, 1]
            mx = sum(p[0] for p in pts) / 4
            my = sum(p[1] for p in pts) / 4
            buckets[key(mx, my, "Ground")].add(pts, [face])


# ============================================================
# Улицы и огни
# ============================================================
def strip(points, width, mat="Road", lift=0.45, floor=None):
    """Лента по точкам (x, y): повторяет холмы, floor — нижняя граница высоты."""
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy)
        nx, ny = -dy / ln * width / 2, dx / ln * width / 2
        z0 = height(x0, y0) + lift
        z1 = height(x1, y1) + lift
        if floor is not None:
            z0, z1 = max(z0, floor), max(z1, floor)
        pts = [(x0 - nx, y0 - ny, z0), (x0 + nx, y0 + ny, z0), (x1 + nx, y1 + ny, z1), (x1 - nx, y1 - ny, z1)]
        n = Vector(pts[1]) - Vector(pts[0])
        n = n.cross(Vector(pts[3]) - Vector(pts[0]))
        face = [0, 1, 2, 3] if n.z > 0 else [3, 2, 1, 0]
        buckets[key((x0 + x1) / 2, (y0 + y1) / 2, mat)].add(pts, [face])


def lamp(x, y, size=1.5, up=12.0):
    """Огонёк фонаря: октаэдр, издалека читается как светлая точка."""
    z = height(x, y) + up
    verts = [(x, y, z + size), (x, y, z - size), (x + size, y, z), (x - size, y, z), (x, y + size, z), (x, y - size, z)]
    faces = [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]
    buckets[key(x, y, "Lit")].add(verts, faces)


road_cells = []


def street_x(gz, x0, x1, width=14.0, floor=None):
    """Улица вдоль X на Z игры = gz: режется на куски вне зоны настоящих домов."""
    step = 42.0
    x = x0
    run = []
    y = -gz
    while x <= x1:
        inside = excluded(x, gz, 6.0)
        if inside or valley(x, y) > RIDGE - 30:
            if len(run) > 1:
                strip(run, width, floor=floor)
            run = []
        else:
            run.append((x, y))
            if int(x) % 84 == 0:
                lamp(x, y + width / 2 + 2)
        x += step
    if len(run) > 1:
        strip(run, width, floor=floor)


def street_z(gx, z0, z1, width=12.0):
    step = 42.0
    z = z0
    run = []
    while z <= z1:
        y = -z
        if excluded(gx, z, 6.0) or valley(gx, y) > RIDGE - 30:
            if len(run) > 1:
                strip(run, width)
            run = []
        else:
            run.append((gx, y))
            if int(z) % 84 == 0:
                lamp(gx + width / 2 + 2, y)
        z += step
    if len(run) > 1:
        strip(run, width)


# ============================================================
# Дома и деревья низкой детализации
# ============================================================
def low_house(x, y, w, d, wall, along_x, lit_chance=0.62):
    h = height(x, y)
    base = h - 6.0
    top = h + wall
    rise = (d if along_x else w) * 0.55
    if along_x:
        verts = [(x - w, y - d, base), (x + w, y - d, base), (x + w, y + d, base), (x - w, y + d, base),
                 (x - w, y - d, top), (x + w, y - d, top), (x + w, y + d, top), (x - w, y + d, top),
                 (x - w, y, top + rise), (x + w, y, top + rise)]
        faces = [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 8, 7], [5, 6, 9]]
        roofs = [[4, 5, 9, 8], [6, 7, 8, 9]]
    else:
        verts = [(x - w, y - d, base), (x + w, y - d, base), (x + w, y + d, base), (x - w, y + d, base),
                 (x - w, y - d, top), (x + w, y - d, top), (x + w, y + d, top), (x - w, y + d, top),
                 (x, y - d, top + rise), (x, y + d, top + rise)]
        faces = [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 8], [6, 7, 9]]
        roofs = [[4, 8, 9, 7], [5, 6, 9, 8]]
    center = Vector((x, y, h + wall / 2))
    vs = [Vector(v) for v in verts]

    def outward(f):
        n = Vector((0, 0, 0))
        for i, a in enumerate(f):
            n += vs[a].cross(vs[f[(i + 1) % len(f)]])
        fc = sum((vs[i] for i in f), Vector()) / len(f)
        return f if n.dot(fc - center) > 0 else list(reversed(f))

    buckets[key(x, y, "Wall")].add(verts, [outward(f) for f in faces])
    buckets[key(x, y, "Roof")].add(verts, [outward(f) for f in roofs])
    # Окна — квадраты на всех четырёх сторонах
    for side in range(4):
        n_win = 2 if side in (0, 2) else 1
        for i in range(n_win):
            if rng.random() > lit_chance:
                continue
            t = (i + 1) / (n_win + 1) * 2 - 1
            size = 1.5
            z0, z1 = h + wall * 0.4, h + wall * 0.4 + size * 1.5
            if side == 0:
                a, b = (x + t * w - size, y - d - 0.25), (x + t * w + size, y - d - 0.25)
            elif side == 1:
                a, b = (x + w + 0.25, y + t * d - size), (x + w + 0.25, y + t * d + size)
            elif side == 2:
                a, b = (x + t * w + size, y + d + 0.25), (x + t * w - size, y + d + 0.25)
            else:
                a, b = (x - w - 0.25, y + t * d + size), (x - w - 0.25, y + t * d - size)
            buckets[key(x, y, "Lit")].add([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], [[0, 1, 2, 3]])


def cone(mat, x, y, z0, z1, r, sides=4, turn=0.0):
    verts = [(x + r * math.cos(turn + 2 * math.pi * k / sides), y + r * math.sin(turn + 2 * math.pi * k / sides), z0) for k in range(sides)]
    verts.append((x, y, z1))
    faces = [[k, (k + 1) % sides, sides] for k in range(sides)]
    buckets[key(x, y, mat)].add(verts, faces)


def far_tree(x, y, h_tree):
    base = height(x, y) - 2
    r = h_tree * 0.26
    turn = rng.random() * 1.5
    cone("TreeDark", x, y, base, base + h_tree * 0.62, r, 4, turn)
    cone("TreeSnow", x, y, base + h_tree * 0.42, base + h_tree, r * 0.68, 4, turn + 0.4)


def tall_block(x, y, w, d, floors):
    """Многоэтажка в центре городка: сетка окон, часть не горит."""
    h = height(x, y)
    top = h + floors * 4.6
    verts = [(x - w, y - d, h - 6), (x + w, y - d, h - 6), (x + w, y + d, h - 6), (x - w, y + d, h - 6),
             (x - w, y - d, top), (x + w, y - d, top), (x + w, y + d, top), (x - w, y + d, top)]
    faces = [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    solid_faces = [[4, 5, 6, 7]]
    vs = [Vector(v) for v in verts]
    center = Vector((x, y, (h + top) / 2))

    def outward(f):
        n = Vector((0, 0, 0))
        for i, a in enumerate(f):
            n += vs[a].cross(vs[f[(i + 1) % len(f)]])
        fc = sum((vs[i] for i in f), Vector()) / len(f)
        return f if n.dot(fc - center) > 0 else list(reversed(f))

    buckets[key(x, y, "Wall")].add(verts, [outward(f) for f in faces])
    buckets[key(x, y, "Roof")].add(verts, [outward(f) for f in solid_faces])
    for floor in range(floors):
        z0, z1 = h + 1.4 + floor * 4.6, h + 3.6 + floor * 4.6
        for side in range(4):
            span, n_win = (w, max(2, int(w / 3.2))) if side in (0, 2) else (d, max(2, int(d / 3.2)))
            for i in range(n_win):
                if rng.random() > 0.48:
                    continue
                t = (i + 0.5) / n_win * 2 - 1
                s = span * 0.9 / n_win
                if side == 0:
                    a, b = (x + t * w - s / 2, y - d - 0.2), (x + t * w + s / 2, y - d - 0.2)
                elif side == 1:
                    a, b = (x + w + 0.2, y + t * d - s / 2), (x + w + 0.2, y + t * d + s / 2)
                elif side == 2:
                    a, b = (x + t * w + s / 2, y + d + 0.2), (x + t * w - s / 2, y + d + 0.2)
                else:
                    a, b = (x - w - 0.2, y + t * d + s / 2), (x - w - 0.2, y + t * d - s / 2)
                buckets[key(x, y, "Lit")].add([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], [[0, 1, 2, 3]])


def steeple(x, y, height_total):
    """Церковь с высоким шпилем: узнаваемый силуэт на склоне."""
    low_house(x, y, 12, 22, 18, False, lit_chance=0.9)
    h = height(x, y)
    tower = height_total * 0.55
    base = [(x - 5, y - 26, h - 4), (x + 5, y - 26, h - 4), (x + 5, y - 16, h - 4), (x - 5, y - 16, h - 4)]
    top = [(p[0], p[1], h + tower) for p in base]
    solid(key(x, y, "Roof"), base + top, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]])
    cone("TreeDark", x, y - 21, h + tower, h + height_total, 6.5, 4, math.pi / 4)
    buckets[key(x, y, "Lit")].add(
        [(x - 1.6, y - 26.3, h + tower - 8), (x + 1.6, y - 26.3, h + tower - 8), (x + 1.6, y - 26.3, h + tower - 3), (x - 1.6, y - 26.3, h + tower - 3)], [[0, 1, 2, 3]]
    )


def radio_mast(x, y, tall):
    h = height(x, y)
    cone("TreeDark", x, y, h - 2, h + tall, 4.5, 3)
    for k in range(3):
        z = h + tall * (0.5 + k * 0.25)
        v = [(x, y, z + 2.2), (x, y, z - 2.2), (x + 2.2, y, z), (x - 2.2, y, z), (x, y + 2.2, z), (x, y - 2.2, z)]
        buckets[key(x, y, "Lit")].add(v, [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]])


# ============================================================
# Сборка
# ============================================================
ground()

ROW_STEP = 150
GRID_X = 210
rows = [52 + ROW_STEP * k for k in range(-9, 10)]
# Главная улица уходит вдаль в обе стороны и поднимается по склону
for x0, x1 in ((-2000, -440), (440, 2000)):
    run = []
    x = x0
    while x <= x1:
        if valley(x, -52) < RIDGE - 30:
            run.append((x, -52))
            if int(x) % 84 == 0:
                lamp(x, -52 + 12, up=12.0)
                lamp(x + 42, -52 - 12, up=12.0)
        x += 42
    strip(run, 20.0, floor=1.03)
for gz in rows:
    if gz != 52:
        street_x(gz, -2000, 2000)
for gx in range(-GRID_X * 8, GRID_X * 8 + 1, GRID_X):
    street_z(gx, -1500, 1500)

houses = 0
for gz in rows:
    for side in (-1, 1):
        house_z = gz + side * 38
        x = -2000 + rng.uniform(0, 40)
        while x < 2000:
            x += rng.uniform(38, 52)
            y = -house_z
            d = valley(x, y)
            if d > RIDGE - 40 or excluded(x, house_z, 14.0):
                continue
            # Рядом с участком плотнее, к гребню реже
            keep = 1.0 if d < 620 else max(0.14, 1.0 - (d - 620) / 780)
            if rng.random() > keep:
                continue
            # Не ставим дом на поперечную улицу
            nearest = round(x / GRID_X) * GRID_X
            if abs(x - nearest) < 22:
                continue
            w, dep = rng.uniform(10, 14), rng.uniform(8, 11)
            low_house(x, y, w, dep, rng.uniform(9, 16), rng.random() < 0.7)
            houses += 1

trees = 0
attempts = 0
while trees < 2300 and attempts < 40000:
    attempts += 1
    d = FLAT + 10 + (RIDGE - FLAT - 25) * rng.random() ** 0.8
    a = rng.uniform(-math.pi, math.pi)
    x, y = STRETCH * d * math.cos(a), CY + d * math.sin(a)
    gz = -y
    if excluded(x, gz, 8.0):
        continue
    # Лес пятнами, на гребне гуще
    patchy = noise.noise(Vector((x / 170, y / 170, 11.0)))
    if patchy < -0.05 and d < 950:
        continue
    near_street = min(abs(gz - r) for r in rows) < 58 and d < 1000
    if near_street and rng.random() < 0.82:
        continue
    far_tree(x, y, rng.uniform(32, 58))
    trees += 1

# Центр городка на дальнем склоне по главной улице и второй район напротив
for cx, cy, count in ((1180, -180, 16), (-1260, 240, 12)):
    for i in range(count):
        bx = cx + rng.uniform(-150, 150)
        by = cy + rng.uniform(-110, 110)
        tall_block(bx, by, rng.uniform(10, 18), rng.uniform(10, 16), rng.randint(5, 14))

steeple(-430, 620, 96)
steeple(620, -610, 80)
radio_mast(980, 880, 150)
radio_mast(-720, -860, 130)

print("houses", houses, "trees", trees)
empty = [k for k, b in buckets.items() if not b.faces]
print("empty", empty)
bad_size = {}
for k, b in buckets.items():
    if b.verts:
        ext = [max(v[i] for v in b.verts) - min(v[i] for v in b.verts) for i in range(3)]
        if max(ext) > 2040:
            bad_size[k] = [round(e) for e in ext]
print("too big", bad_size)

VIEWS = {
    "street": ((0, -48, 7), (500, -52, 18)),
    "across": ((0, -22, 7), (0, -600, 30)),
    "back": ((0, 110, 7), (0, 900, 30)),
    "air": ((600, -900, 380), (0, 0, 0)),
}
finish("Town", MATERIALS, OUT, "town", render=RENDER, views=VIEWS, ground=(0.82, 0.86, 0.95, 1))

if RENDER:
    scene = bpy.context.scene
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.1, 0.16, 0.36, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    bpy.data.lights["Sun"].energy = 0.25
    bpy.data.lights["Sun"].color = (0.6, 0.72, 1.0)
    scene.cycles.samples = 48
    scene.camera.data.clip_end = 6000
    cam = bpy.data.objects["Cam"]
    for label, (pos, look) in VIEWS.items():
        cam.location = pos
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(OUT, f"town_dusk_{label}.png")
        bpy.ops.render.render(write_still=True)
    print("DONE dusk")
