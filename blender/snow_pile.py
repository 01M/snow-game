# Куча снега Движка (PileClient): один низкополигональный сугроб + бесшовные карты для SurfaceAppearance.
# Меш: приплюснутый купол на эллипсе 2×2 (Blender X×Y) высотой 1, плоское дно, мягко неровный силуэт,
# ~400 треугольников, одна UV-развёртка сверху (0..1, без швов). В игре PileClient растягивает его по Size.
# Карты 512×512 (SurfaceAppearance до 1024), бесшовные (периодический шум через FFT):
#   ColorMap — почти белый, серый (без синевы, оттенок задаёт SurfaceAppearance.Color), мелкое зерно;
#   NormalMap — OpenGL, tangent space (Roblox поддерживает только его): зелёный канал = +V вверх;
#   RoughnessMap — 8-bit grayscale, около 0.9, редкие искорки глаже.
#
# Запуск: blender --background --python blender/snow_pile.py -- <папка>
# В открытом Blender (через MCP): задать OUT в глобалах и выполнить файл.
import math
import os
import struct
import sys
import zlib

import bmesh
import bpy
import numpy as np

NAME = "SnowPile"
SEGMENTS = 24  # по окружности
RINGS = 8  # от центра к краю (центр — веер)
TEX = 512
SEED = 7


def out_dir():
    if "OUT" in globals():
        return globals()["OUT"]
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1]
    return os.path.join(os.getcwd(), "blender", "exports", "snow_pile")


# ---------------------------------------------------------------- меш
def edge_scale(a):
    # мягкая неровность силуэта: несколько низких гармоник по углу
    return 1 + 0.045 * math.sin(2 * a + 0.6) + 0.035 * math.sin(3 * a + 2.1) + 0.02 * math.sin(5 * a + 4.0)


def height_at(t, a):
    # t — доля радиуса (0 центр, 1 край). Купол, у края мягко скруглён, вершина чуть смещена назад
    base = (1 - t * t) ** 0.62
    bumps = 1 + 0.06 * math.sin(2 * a + 1.3) * t + 0.04 * math.sin(3 * a + 0.4) * t * (1 - t) * 4
    return max(base * bumps, 0.0)


def build_mesh():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    top = bm.verts.new((0, 0, 1.0))
    rings = []
    for i in range(1, RINGS + 1):
        t = i / RINGS
        ring = []
        for k in range(SEGMENTS):
            a = 2 * math.pi * k / SEGMENTS
            s = edge_scale(a) * t
            ring.append(bm.verts.new((s * math.cos(a), s * math.sin(a), height_at(t, a))))
        rings.append(ring)
    faces = []
    r0 = rings[0]
    for k in range(SEGMENTS):
        faces.append(bm.faces.new((top, r0[k], r0[(k + 1) % SEGMENTS])))
    for a_ring, b_ring in zip(rings, rings[1:]):
        for k in range(SEGMENTS):
            k2 = (k + 1) % SEGMENTS
            faces.append(bm.faces.new((a_ring[k], b_ring[k], b_ring[k2], a_ring[k2])))
    # плоское дно: веер к центру на z = 0
    bottom = bm.verts.new((0, 0, 0))
    edge = rings[-1]
    for k in range(SEGMENTS):
        faces.append(bm.faces.new((bottom, edge[(k + 1) % SEGMENTS], edge[k])))
    bm.normal_update()
    # UV: проекция сверху, экстент силуэта → 0..1
    ext = max(abs(c) for v in bm.verts for c in (v.co.x, v.co.y))
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (0.5 + 0.5 * co.x / ext, 0.5 + 0.5 * co.y / ext)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    tris = len(bm.faces)
    mesh = bpy.data.meshes.new(NAME)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = True
    return mesh, tris


# ---------------------------------------------------------------- текстуры
def periodic_noise(rng, n, beta, lo_cut=0):
    """Бесшовный шум 1/f^beta: случайная фаза в частотной области, обратное FFT периодично по построению."""
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1
    amp = 1 / f**beta
    amp[0, 0] = 0
    if lo_cut:
        amp[f < lo_cut / n] = 0
    phase = rng.uniform(0, 2 * np.pi, (n, n))
    field = np.real(np.fft.ifft2(amp * np.exp(1j * phase)))
    field -= field.mean()
    return field / (np.abs(field).max() + 1e-9)


def make_textures():
    rng = np.random.default_rng(SEED)
    n = TEX
    soft = periodic_noise(rng, n, 1.6)  # мягкие пятна
    grain = periodic_noise(rng, n, 0.6, lo_cut=40)  # мелкое зерно, как у снега на земле
    sparkle = rng.random((n, n)) > 0.9965  # редкие искорки
    height = 0.55 * soft + 0.45 * grain

    color = 0.94 + 0.035 * soft + 0.025 * grain
    color = np.where(sparkle, 1.0, color)
    color = np.clip(color, 0, 1)

    # нормали из высоты (центральные разности по кругу — бесшовно); OpenGL: +Y (зелёный) = вверх по V
    strength = 5.0
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    # строки PNG идут сверху вниз, а V растёт вверх: производная по V = −dy
    nx, ny, nz = -dx, dy, np.ones_like(dx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / length, ny / length, nz / length], axis=-1) * 0.5 + 0.5

    rough = 0.9 + 0.04 * grain
    rough = np.where(sparkle, 0.55, rough)
    rough = np.clip(rough, 0, 1)
    return color, normal, rough


def write_png(path, data):
    """data: (h, w) 0..1 → 8-bit grayscale; (h, w, 3) → RGB 24-bit."""
    arr = np.clip(np.round(data * 255), 0, 255).astype(np.uint8)
    h, w = arr.shape[:2]
    gray = arr.ndim == 2
    rows = arr.reshape(h, -1)
    raw = b"".join(b"\x00" + rows[y].tobytes() for y in range(h))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 0 if gray else 2, 0, 0, 0)
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# ---------------------------------------------------------------- сборка
def main():
    out = out_dir()
    os.makedirs(out, exist_ok=True)

    color, normal, rough = make_textures()
    paths = {
        "color": os.path.join(out, "snow_pile_color.png"),
        "normal": os.path.join(out, "snow_pile_normal.png"),
        "roughness": os.path.join(out, "snow_pile_roughness.png"),
    }
    write_png(paths["color"], np.repeat(color[:, :, None], 3, axis=2))
    write_png(paths["normal"], normal)
    write_png(paths["roughness"], rough)

    # в открытом Blender меняем только свой объект
    old = bpy.data.objects.get(NAME)
    if old:
        bpy.data.objects.remove(old)
    mesh, tris = build_mesh()
    obj = bpy.data.objects.new(NAME, mesh)
    bpy.context.scene.collection.objects.link(obj)

    # материал для просмотра в Blender (в Roblox карты задаёт SurfaceAppearance)
    mat = bpy.data.materials.get(NAME) or bpy.data.materials.new(NAME)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        img = bpy.data.images.load(paths["color"], check_existing=False)
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = img
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.9
    mesh.materials.append(mat)

    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(out, "snow_pile.fbx"),
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        bake_space_transform=True,
        path_mode="STRIP",
    )
    dims = tuple(round(d, 3) for d in obj.dimensions)
    return {"tris": tris, "dims": dims, "out": out}


result = main()
print(result)
