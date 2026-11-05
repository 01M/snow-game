# Лопата для инструмента «Лопата» (Tool Shovel), два варианта для сравнения:
#   A — Classic: широкий слегка изогнутый пластиковый ковш, низкие бортики;
#   B — Bucket: глубокий ковш с высокими бортиками и задней стенкой.
# Общее: оранжевый пластик, алюминиевый черенок, чёрная D-ручка, стальная накладка на кромке.
#
# Оси: 1 единица = 1 stud. Ковш смотрит в +Y Blender (в игре −Z = «вперёд» Tool), вогнутая сторона вверх (+Z).
# Начало координат — центр перекладины D-ручки (там держит правая рука), поэтому Handle ставится туда же.
# Каждый материал — отдельный меш (MeshPart в Studio): <Prefix>_Plastic, _Metal, _Steel, _Grip.
#
# Запуск: blender --background --python blender/shovel.py -- <папка> [A|B|AB] [render]
# В открытом Blender (через MCP): задать VARIANTS и OUT в глобалах и выполнить файл.
import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd())
import modellib as ml  # noqa: E402

MATERIALS = {
    # имя: (rgb 0..255, metallic, roughness, emission)
    "Plastic": ((236, 108, 30), 0.0, 0.45, 0),
    "Metal": ((196, 202, 210), 1.0, 0.32, 0),
    "Steel": ((118, 124, 134), 1.0, 0.4, 0),
    "Grip": ((30, 32, 36), 0.0, 0.75, 0),
}

VARIANTS_DEF = {
    "A": dict(
        width=1.75,  # ширина ковша у кромки
        taper=0.08,  # насколько уже ковш у черенка
        length=1.35,  # длина ковша от кромки до черенка
        scoop=0.16,  # подъём задней части (вогнутость вдоль)
        across=0.05,  # прогиб поперёк
        lip=0.11,  # высота бортиков
        lip_start=0.86,  # где по ширине начинается бортик (доля полуширины)
        back=0.08,  # задняя стенка
        thick=0.055,
        tilt=24,  # угол ковша к черенку, градусы
        shaft=2.35,  # длина черенка от ковша до D-ручки
        ribs=(-0.42, 0.0, 0.42),
    ),
    "B": dict(
        width=1.6,
        taper=0.12,
        length=1.3,
        scoop=0.15,
        across=0.06,
        lip=0.38,
        lip_start=0.62,
        back=0.3,
        thick=0.06,
        tilt=20,
        shaft=2.35,
        ribs=(-0.3, 0.3),
    ),
}


# ---------- геометрия ----------


def add_closed(mat, verts, faces, m=None):
    """Замкнутое тело: нормали пересчитываются наружу, поэтому порядок граней в генераторах не важен."""
    bm = bmesh.new()
    vs = [bm.verts.new(m @ Vector(v) if m else Vector(v)) for v in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.verts.index_update()
    out_v = [tuple(v.co) for v in bm.verts]
    out_f = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    ml.buckets[mat].add(out_v, out_f)


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


class Blade:
    """Поверхность ковша P(u, v): u ∈ [−1, 1] поперёк, v ∈ [0, 1] от кромки к черенку. Вогнутость вверх."""

    def __init__(self, p):
        self.p = p
        tilt = math.radians(p["tilt"])
        # ковш отогнут от черенка в сторону вогнутости: когда ковш лежит на снегу, черенок поднимается к рукам
        self.rot = Matrix.Rotation(tilt, 4, "X")
        self.shift = -self.raw(0.0, 1.0) + Vector((0, 0, -0.07))

    def raw(self, u, v):
        p = self.p
        half = p["width"] / 2 * (1 - p["taper"] * v)
        x = u * half
        y = p["length"] * (1 - v)  # кромка впереди (+Y), черенок на v = 1
        z = p["scoop"] * max(0.0, v) ** 2.2 + p["across"] * u * u
        # бортики и задняя стенка: в углу берётся большее из двух, иначе угол торчит «плавником»
        side = p["lip"] * smoothstep(p["lip_start"], 1.0, abs(u)) ** 1.6
        back = p["back"] * smoothstep(0.78, 1.0, v) ** 1.5
        z += max(side, back)
        return self.rot @ Vector((x, y, z))

    def point(self, u, v):
        return self.raw(u, v) + self.shift

    def normal(self, u, v):
        e = 1e-3
        du = self.point(min(1, u + e), v) - self.point(max(-1, u - e), v)
        dv = self.point(u, min(1, v + e)) - self.point(u, max(0, v - e))
        n = du.cross(dv)
        if n.z < 0:
            n = -n
        return n.normalized()


def shell(mat, surf, u0, u1, v0, v1, nu, nv, thick, offset=0.0, rim=4):
    """Толстая пластина по поверхности с полукруглым скруглённым краем (блик по кромке)."""
    us = [u0 + (u1 - u0) * i / nu for i in range(nu + 1)]
    vs = [v0 + (v1 - v0) * j / nv for j in range(nv + 1)]
    # контур по периметру сетки (против часовой при взгляде сверху)
    loop = [(i, 0) for i in range(nu)] + [(nu, j) for j in range(nv)] + [(i, nv) for i in range(nu, 0, -1)] + [(0, j) for j in range(nv, 0, -1)]
    verts, faces = [], []

    def P(i, j):
        return surf.point(us[i], vs[j])

    def N(i, j):
        return surf.normal(us[i], vs[j])

    top, bot = {}, {}
    for i in range(nu + 1):
        for j in range(nv + 1):
            c = P(i, j) + N(i, j) * offset
            top[i, j] = len(verts)
            verts.append(c + N(i, j) * thick / 2)
            bot[i, j] = len(verts)
            verts.append(c - N(i, j) * thick / 2)
    for i in range(nu):
        for j in range(nv):
            faces.append([top[i, j], top[i + 1, j], top[i + 1, j + 1], top[i, j + 1]])
            faces.append([bot[i, j], bot[i, j + 1], bot[i + 1, j + 1], bot[i + 1, j]])
    # скруглённый край: кольца между верхом и низом, выпуклые наружу по касательной
    cx, cy = nu / 2, nv / 2
    rings = []
    for i, j in loop:
        n = N(i, j)
        c = P(i, j) + n * offset
        # наружу по поверхности: от центра сетки
        di, dj = i - cx, j - cy
        ii = min(nu, max(0, i + (1 if di > 0.01 else -1 if di < -0.01 else 0)))
        jj = min(nv, max(0, j + (1 if dj > 0.01 else -1 if dj < -0.01 else 0)))
        o = P(ii, jj) - P(i, j)
        if i not in (0, nu):
            o = P(i, jj) - P(i, j)
        if j not in (0, nv):
            o = P(ii, j) - P(i, j)
        o = (o - n * o.dot(n))
        o = o.normalized() if o.length > 1e-6 else Vector((0, 0, 0))
        ring = [top[i, j]]
        for k in range(1, rim):
            a = math.pi * k / rim
            ring.append(len(verts))
            verts.append(c + n * (thick / 2) * math.cos(a) + o * (thick / 2) * math.sin(a))
        ring.append(bot[i, j])
        rings.append(ring)
    for r in range(len(rings)):
        a, b = rings[r], rings[(r + 1) % len(rings)]
        for k in range(rim):
            faces.append([a[k], b[k], b[k + 1], a[k + 1]])
    add_closed(mat, verts, faces)


def lathe_vf(profile, seg):
    """Тело вращения вокруг Z, profile [(r, z)] — концы с r = 0 замыкаются."""
    verts, faces, rings = [], [], []
    for r, z in profile:
        if r < 1e-6:
            rings.append([len(verts)])
            verts.append((0, 0, z))
        else:
            ring = []
            for k in range(seg):
                a = 2 * math.pi * k / seg
                ring.append(len(verts))
                verts.append((r * math.cos(a), r * math.sin(a), z))
            rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            k2 = (k + 1) % seg
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                faces.append([a[0], b[k2], b[k]])
            elif len(b) == 1:
                faces.append([a[k], a[k2], b[0]])
            else:
                faces.append([a[k], a[k2], b[k2], b[k]])
    return verts, faces


def lathe_along(mat, profile, start, end, seg=16):
    """Тело вращения по оси start→end; profile [(r, t)], t ∈ [0, 1] вдоль оси."""
    start, end = Vector(start), Vector(end)
    L = (end - start).length
    v, f = lathe_vf([(r, t * L) for r, t in profile], seg)
    m = Matrix.Translation(start) @ Vector((0, 0, 1)).rotation_difference((end - start).normalized()).to_matrix().to_4x4()
    add_closed(mat, v, f, m)


def tube_vf(path, radius, seg=12, closed=False, caps=True):
    path = [Vector(p) for p in path]
    n_pts = len(path)
    verts, faces = [], []
    t0 = (path[1] - path[0]).normalized()
    nrm = t0.cross(Vector((0, 0, 1)))
    if nrm.length < 1e-3:
        nrm = t0.cross(Vector((1, 0, 0)))
    nrm.normalize()
    for i, p in enumerate(path):
        if closed:
            t = (path[(i + 1) % n_pts] - path[i - 1]).normalized()
        elif i == 0:
            t = t0
        elif i == n_pts - 1:
            t = (path[i] - path[i - 1]).normalized()
        else:
            t = (path[i + 1] - path[i - 1]).normalized()
        nrm = (nrm - t * nrm.dot(t)).normalized()
        b = t.cross(nrm)
        for k in range(seg):
            a = 2 * math.pi * k / seg
            verts.append(tuple(p + nrm * (radius * math.cos(a)) + b * (radius * math.sin(a))))
    segs = n_pts if closed else n_pts - 1
    for i in range(segs):
        i2 = (i + 1) % n_pts
        for k in range(seg):
            k2 = (k + 1) % seg
            faces.append([i * seg + k, i * seg + k2, i2 * seg + k2, i2 * seg + k])
    if caps and not closed:
        faces.append(list(range(seg)))
        last = (n_pts - 1) * seg
        faces.append([last + k for k in range(seg)])
    return verts, faces


def rounded_loop(points, radius, steps=5):
    """Замкнутая ломаная со скруглёнными углами."""
    pts = [Vector(p) for p in points]
    out = []
    for i in range(len(pts)):
        p, a, b = pts[i], pts[i - 1], pts[(i + 1) % len(pts)]
        d1, d2 = a - p, b - p
        r = min(radius, d1.length * 0.45, d2.length * 0.45)
        s, e = p + d1.normalized() * r, p + d2.normalized() * r
        for k in range(steps + 1):
            t = k / steps
            out.append(s * (1 - t) ** 2 + p * 2 * t * (1 - t) + e * t * t)
    return out


# ---------- сборка ----------


def build(key):
    p = VARIANTS_DEF[key]
    ml.use_materials(MATERIALS)
    blade = Blade(p)
    th = p["thick"]

    # 1. ковш
    shell("Plastic", blade, -1, 1, 0.0, 1.0, 26, 16, th)

    # 2. рёбра жёсткости на рабочей стороне: от черенка к середине ковша
    for u in p["ribs"]:
        path = [blade.point(u * (1 - 0.1 * v), v) + blade.normal(u, v) * (th * 0.35) for v in [0.32 + 0.68 * k / 10 for k in range(11)]]
        r = 0.032 if key == "A" else 0.036
        v_, f_ = tube_vf(path, r, seg=8)
        add_closed("Plastic", v_, f_)

    # 3. стальная накладка по кромке (охватывает край ковша)
    shell("Steel", blade, -0.985, 0.985, -0.012, 0.075 if key == "A" else 0.09, 26, 2, th * 1.9)
    for u in (-0.75, -0.25, 0.25, 0.75):
        c = blade.point(u, 0.04) + blade.normal(u, 0.04) * th * 0.95
        n = blade.normal(u, 0.04)
        lathe_along("Steel", [(0.035, 0.0), (0.03, 0.4), (0.018, 0.85), (0.0, 1.0)], c - n * 0.01, c + n * 0.025, seg=8)

    # 4. гнездо черенка: пластиковая втулка, продолжающая центральное ребро
    root = blade.point(0, 1.0)
    shaft_dir = Vector((0, -1, 0))
    sock_a = root + Vector((0, 0.06, 0.0))
    sock_b = root + shaft_dir * 0.5
    lathe_along("Plastic", [(0.0, 0.0), (0.1, 0.0), (0.135, 0.12), (0.13, 0.55), (0.1, 0.92), (0.088, 1.0), (0.0, 1.0)], sock_a, sock_b, seg=16)
    # клин под ковшом, держит гнездо
    wedge = [blade.point(0, 0.55 + 0.45 * k / 8) - blade.normal(0, 0.55 + 0.45 * k / 8) * th * 0.4 for k in range(9)]
    v_, f_ = tube_vf(wedge, 0.05, seg=8)
    add_closed("Plastic", v_, f_)
    lathe_along("Steel", [(0.03, 0.0), (0.028, 0.5), (0.0, 1.0)], sock_a + shaft_dir * 0.32 + Vector((0.12, 0, 0)), sock_a + shaft_dir * 0.32 + Vector((0.15, 0, 0)), seg=8)

    # 5. алюминиевый черенок
    shaft_end = sock_b + shaft_dir * p["shaft"]
    lathe_along("Metal", [(0.0, 0.0), (0.072, 0.0), (0.072, 1.0), (0.0, 1.0)], sock_b - shaft_dir * 0.1, shaft_end + shaft_dir * 0.05, seg=14)

    # 6. D-ручка: муфта, треугольная рамка, обрезиненная перекладина
    lathe_along("Grip", [(0.0, 0.0), (0.082, 0.0), (0.09, 0.15), (0.09, 0.8), (0.11, 1.0), (0.0, 1.0)], shaft_end - shaft_dir * 0.05, shaft_end + shaft_dir * 0.3, seg=14)
    apex = shaft_end + shaft_dir * 0.25
    bar_y = apex + shaft_dir * 0.62
    half = 0.27
    frame = rounded_loop([apex, bar_y + Vector((half, 0, 0)), bar_y + Vector((-half, 0, 0))], 0.12)
    v_, f_ = tube_vf(frame, 0.05, seg=10, closed=True)
    add_closed("Grip", v_, f_)
    lathe_along("Grip", [(0.0, 0.0), (0.07, 0.0), (0.085, 0.12), (0.088, 0.5), (0.085, 0.88), (0.07, 1.0), (0.0, 1.0)], bar_y + Vector((-0.21, 0, 0)), bar_y + Vector((0.21, 0, 0)), seg=14)

    # начало координат — центр перекладины
    grip = bar_y.copy()
    for b in ml.buckets.values():
        b.verts = [v - grip for v in b.verts]
    return grip


LIFT = 2.0


def preview(out, name, views):
    """Превью на видеокарте: модель поднята над снежной землёй (FBX и .blend уже записаны с началом в ручке)."""
    import bpy

    scene = bpy.context.scene
    for o in scene.objects:
        o.location.z += LIFT
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    scene.cycles.device = "GPU"
    print("Render device:", [d.name for d in prefs.devices if d.use])
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1100, 1100
    scene.view_settings.view_transform = "Standard"
    gmesh = bpy.data.meshes.new("Ground")
    gmesh.from_pydata([(-60, -60, 0), (60, -60, 0), (60, 60, 0), (-60, 60, 0)], [], [[0, 1, 2, 3]])
    gmat = bpy.data.materials.new("GroundMat")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.82, 0.87, 0.95, 1)
    gmesh.materials.append(gmat)
    scene.collection.objects.link(bpy.data.objects.new("Ground", gmesh))
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.55, 0.8, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    scene.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.0
    sun.angle = math.radians(8)
    sun_obj = bpy.data.objects.new("Sun", sun)
    sun_obj.rotation_euler = (math.radians(50), 0, math.radians(-40))
    scene.collection.objects.link(sun_obj)
    cam = bpy.data.cameras.new("Cam")
    cam.lens = 35
    cam_obj = bpy.data.objects.new("Cam", cam)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    for label, (pos, look) in views.items():
        pos, look = Vector(pos) + Vector((0, 0, LIFT)), Vector(look) + Vector((0, 0, LIFT))
        cam_obj.location = pos
        cam_obj.rotation_euler = (look - pos).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out, f"{name}_preview_{label}.png")
        bpy.ops.render.render(write_still=True)


def run(out, keys, render=False):
    import bpy

    results = {}
    for i, key in enumerate(keys):
        build(key)
        name = "shovel_" + key.lower()
        views = None
        if render:
            views = {
                "front": ((2.6, 7.6, 2.4), (0, 4.3, -0.1)),
                "scoop": ((0.4, 6.0, 3.2), (0, 4.4, -0.1)),
                "side": ((-6.5, 2.2, 1.0), (0, 2.2, 0.0)),
                "fp": ((0.6, -1.2, 1.4), (0, 4.0, -0.6)),
            }
        ml.finish("Shovel" + key, MATERIALS, out, name)
        results[key] = os.path.join(out, name + ".fbx")
        if render and bpy.app.background:
            preview(out, name, views)
        if not bpy.app.background:
            # в открытом Blender варианты стоят рядом для просмотра; FBX уже записан с началом в ручке
            objs = [o for o in bpy.data.objects if o.name.startswith("Shovel" + key + "_")]
            for o in objs:
                o.location.x = i * 2.6
            blend = os.path.join(out, name + ".blend")
            bpy.data.libraries.write(blend, set(objs), fake_user=True)
    return results


if __name__ == "__main__" or "VARIANTS" in globals():
    import bpy

    if bpy.app.background:
        argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
        out = argv[0] if argv else os.path.join(os.path.dirname(os.path.abspath(__file__)), "exports", "shovel")
        keys = list(argv[1]) if len(argv) > 1 else ["A", "B"]
        run(out, keys, render="render" in argv)
    else:
        result = run(globals().get("OUT"), list(globals().get("VARIANTS", "AB")))
