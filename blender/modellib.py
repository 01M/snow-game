# Общие детали для моделей Snow Cleaning Simulator (тот же стиль, что у snowmelter.py).
# 1 единица Blender = 1 stud. Начало координат = центр на уровне земли, перед смотрит в -Y (в игре +Z).
# Каждый материал — отдельный меш: в Studio это отдельный MeshPart, цвет и материал задаются там.
import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector


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


buckets = {}


def use_materials(materials):
    buckets.clear()
    for name in materials:
        buckets[name] = Bucket()


def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def S(x, y=None, z=None):
    return Matrix.Diagonal((x, x if y is None else y, x if z is None else z, 1))


def R(deg, axis):
    return Matrix.Rotation(math.radians(deg), 4, axis)


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
    bm.verts.index_update()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    buckets[mat].add(verts, faces, m)


def solid(mat, verts, faces, m=None):
    """Замкнутое выпуклое тело: если грани вывернуты, разворачивает, иначе в игре они не видны."""
    vs = [Vector(v) for v in verts]
    volume = 0.0
    for f in faces:
        for i in range(1, len(f) - 1):
            volume += vs[f[0]].dot(vs[f[i]].cross(vs[f[i + 1]]))
    if volume < 0:
        faces = [list(reversed(f)) for f in faces]
    buckets[mat].add(verts, faces, m)


def hexa(mat, low, high, m=None):
    """Шестигранник: low и high — по 4 вершины в одном порядке."""
    solid(mat, list(low) + list(high), [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]], m)


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
    t0 = (path[1] - path[0]).normalized()
    n = t0.cross(Vector((0, 0, 1)))
    if n.length < 1e-3:
        n = t0.cross(Vector((1, 0, 0)))
    n.normalize()
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


def facing(direction, pos):
    """Матрица: локальная +Z смотрит в direction, стоит в pos."""
    r = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4()
    return Matrix.Translation(pos) @ r


def extrude_x(mat, pts_yz, x0, x1, m=None):
    """Выпуклый многоугольник (y, z), против часовой стрелки при взгляде с +X, вытянутый от x0 до x1."""
    n = len(pts_yz)
    verts = [(x0, y, z) for y, z in pts_yz] + [(x1, y, z) for y, z in pts_yz]
    faces = [list(range(n - 1, -1, -1)), list(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    buckets[mat].add(verts, faces, m)


def blob(mat, half, m=None, e=0.5, nu=20, nv=12):
    """Суперэллипсоид: мягкий «кирпич» со скруглёнными углами (e=1 — эллипсоид, меньше — ближе к коробке)."""
    def p(c, s):
        return math.copysign(abs(c) ** e, c), math.copysign(abs(s) ** e, s)

    verts = [(0, 0, -half[2])]
    for j in range(1, nv):
        cv, sv = p(math.cos(-math.pi / 2 + math.pi * j / nv), math.sin(-math.pi / 2 + math.pi * j / nv))
        for k in range(nu):
            a = 2 * math.pi * k / nu
            cu, su = p(math.cos(a), math.sin(a))
            verts.append((half[0] * cv * cu, half[1] * cv * su, half[2] * sv))
    verts.append((0, 0, half[2]))
    faces = []
    top = len(verts) - 1
    for k in range(nu):
        k2 = (k + 1) % nu
        faces.append([0, 1 + k, 1 + k2])
        faces.append([top - nu + k, top - nu + k2, top])
    for j in range(nv - 2):
        for k in range(nu):
            k2 = (k + 1) % nu
            a, b = 1 + j * nu, 1 + (j + 1) * nu
            faces.append([a + k, a + k2, b + k2, b + k])
    buckets[mat].add(verts, faces, m)


def snow_lump(x, y, z, s, seg=12):
    lathe("Snow", [(0, 0), (s, 0), (s * 0.85, s * 0.28), (s * 0.45, s * 0.5), (0, s * 0.56)], seg=seg, m=T(x, y, z))


def icicle(pos, length, seg=6):
    lathe("Ice", [(0, -length), (0.05, -length * 0.55), (0.1, -length * 0.15), (0.11, 0), (0, 0.04)], seg=seg, m=T(*pos))


def finish(prefix, materials, out, name, render=False, views=None, target=(0, 0, 6), ground=(0.42, 0.25, 0.14, 1)):
    """Собирает меши <prefix>_<материал>, пишет <name>.fbx и .blend, при render — рендерит превью на видеокарте."""
    if bpy.app.background:
        bpy.ops.wm.read_factory_settings(use_empty=True)
    else:
        # В открытом Blender (через MCP) сцену не сбрасываем: меняем только свои объекты
        for o in list(bpy.data.objects):
            if o.name.startswith(prefix + "_"):
                bpy.data.objects.remove(o)
        for o in bpy.context.selected_objects:
            o.select_set(False)
    objects = []
    for mat_name, (rgb, metal, rough, emit) in materials.items():
        b = buckets[mat_name]
        if not b.faces:
            continue
        mesh = bpy.data.meshes.new(prefix + "_" + mat_name)
        mesh.from_pydata([tuple(v) for v in b.verts], [], b.faces)
        mesh.update()
        mesh.shade_smooth()
        mesh.set_sharp_from_angle(angle=math.radians(40))
        mat = bpy.data.materials.new(mat_name)
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
        obj = bpy.data.objects.new(prefix + "_" + mat_name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        objects.append(obj)
        print(f"{mat_name}: {len(mesh.vertices)} verts, {sum(len(p.vertices) - 2 for p in mesh.polygons)} tris")

    print("TOTAL tris:", sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects))

    os.makedirs(out, exist_ok=True)
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(out, name + ".fbx"),
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        bake_space_transform=True,
    )
    if bpy.app.background:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, name + ".blend"))

    if not render:
        print("DONE")
        return

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
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

    gmesh = bpy.data.meshes.new("Ground")
    gmesh.from_pydata([(-60, -60, 0), (60, -60, 0), (60, 60, 0), (-60, 60, 0)], [], [[0, 1, 2, 3]])
    gmat = bpy.data.materials.new("GroundMat")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = ground
    gmesh.materials.append(gmat)
    scene.collection.objects.link(bpy.data.objects.new("Ground", gmesh))

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

    for label, (pos, look) in (views or {}).items():
        cam_obj.location = pos
        cam_obj.rotation_euler = (Vector(look or target) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out, f"{name}_preview_{label}.png")
        bpy.ops.render.render(write_still=True)
    print("DONE")
