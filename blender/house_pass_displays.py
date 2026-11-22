"""Build the Auto Sell mounting skid and VIP presentation plinth."""

import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parent
STEM = "house_pass_displays"
OUT = ROOT / "exports" / STEM
BLEND = ROOT / f"{STEM}.blend"
FBX = OUT / f"{STEM}.fbx"
META = OUT / f"{STEM}.json"
assert not any(path.exists() for path in (BLEND, FBX, META))

scene = bpy.data.scenes.new("House Pass Displays")
bpy.context.window.scene = scene


def collection(name):
    group = bpy.data.collections.new(name)
    scene.collection.children.link(group)
    return group


source = collection("Editable mounts")
references = collection("Original product scale references")
export = collection("Roblox FBX mesh set")
spread = {"Auto": 2.18, "Vip": -2.18}
mounts = {
    "Auto": ((0, -1.285, .51), 47),
    "Vip": ((0, -1.135, .452), 34),
}
supports = {"Auto": (.76, "Auto_Rails"), "Vip": (.84, "Vip_Foot")}
finishes = {
    "Skid": ((36, 44, 51), "Metal"),
    "Cast": ((64, 84, 101), "Metal"),
    "Silver": ((135, 153, 164), "Metal"),
    "Night": ((27, 41, 62), "SmoothPlastic"),
    "Navy": ((42, 53, 71), "SmoothPlastic"),
    "Wine": ((102, 36, 48), "Fabric"),
    "Blackened": ((36, 37, 48), "Metal"),
    "Brass": ((161, 127, 70), "Metal"),
    "Champagne": ((206, 178, 119), "SmoothPlastic"),
}
palette = {}
for name, (rgb, surface) in finishes.items():
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*[c / 255 for c in rgb], 1)
    palette[name] = mat


def translation(coords):
    return Matrix.Translation(Vector(coords))


def mount_transform(product):
    offset, degrees = mounts[product]
    return translation(offset) @ Matrix.Rotation(-math.radians(degrees), 4, "X")


def cast(name, part, finish, rings, bevel=0, angled=False):
    count = len(rings[0])
    vertices = [v for ring in rings for v in ring]
    faces = [tuple(reversed(range(count))), tuple(range(len(vertices) - count, len(vertices)))]
    for row in range(len(rings) - 1):
        for i in range(count):
            a, b = row * count + i, row * count + (i + 1) % count
            faces.append((a, b, b + count, a + count))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    source.objects.link(ob)
    ob.data.materials.append(palette[finish])
    product = part.split("_")[0]
    ob.matrix_world = translation((spread[product], 0, 0))
    if angled:
        ob.matrix_world @= mount_transform(product)
    ob["part"], ob["finish"], ob["angled"] = part, finish, angled
    if bevel:
        mod = ob.modifiers.new("Cut edge", "BEVEL")
        mod.width, mod.segments = bevel, 2
        mod.limit_method, mod.harden_normals = "ANGLE", True
    return ob


def clipped(x, front, back, corner, height, dx=0):
    return [
        (px + dx, py, height)
        for px, py in (
            (-x + corner, front), (x - corner, front), (x, front + corner),
            (x, back - corner), (x - corner, back), (-x + corner, back),
            (-x, back - corner), (-x, front + corner),
        )
    ]


def levels(rows, dx=0):
    return [clipped(x, front, back, corner, z, dx) for z, x, front, back, corner in rows]


def bezel(name, part, finish, width, height, corner, front, back, bevel):
    rings = [clipped(width, -height, height, corner, y) for y in (front, back)]
    return cast(name, part, finish, [[(x, y, z) for x, z, y in ring] for ring in rings], bevel, True)


# Parallel steel feet keep the skid low, with the paintwork chamfered back
# where the steel feet emerge. The front crossmember carries the enamel.
for x in (-.86, .86):
    cast("Drawn skid rail", "Auto_Rails", "Skid", levels([
        (.008, .23, -1.47, 1.02, .16),
        (.095, .23, -1.47, 1.02, .16),
        (.226, .175, -1.32, .91, .13),
    ], x), .032)

cast("Tapered machine tray", "Auto_Tray", "Cast", levels([
    (.135, .875, -1.24, .93, .27),
    (.27, 1.12, -1.49, 1.03, .32),
    (.37, 1.14, -1.49, 1.075, .32),
    (.615, 1.10, -1.17, 1.075, .28),
    (.687, 1.10, -1.10, 1.095, .29),
    (.735, 1.073, -1.075, 1.075, .27),
]), .022)
cast("Machine bedding plate", "Auto_Bed", "Skid", levels([
    (.727, 1.027, -1.034, 1.034, .271),
    (.753, 1.027, -1.034, 1.034, .271),
]), .008)

bezel("Formed shoulders meeting the tray", "Auto_Housing", "Cast", 1.044, .294, .102, -.024, .157, .024)
bezel("Pressed steel reveal", "Auto_Frame", "Silver", 1.009, .265, .079, -.045, -.018, .007)
bezel("Blue enamel data plate", "Auto_PrintFace", "Night", .962, .233, .069, -.059, -.036, .008)

# The VIP plinth is squat, wide and octagonal. The tilted plaque is let into
# the sloping front facet and framed by that facet's edge, below a fabric deck.
cast("Dark footing", "Vip_Foot", "Blackened", levels([
    (.010, 1.014, -.974, .969, .275),
    (.083, 1.051, -1.007, 1.004, .286),
    (.127, 1.071, -1.038, 1.035, .296),
]), .022)
cast("Faceted lacquered casket", "Vip_Body", "Navy", levels([
    (.098, 1.048, -1.015, .995, .291),
    (.221, 1.305, -1.254, 1.033, .334),
    (.265, 1.307, -1.240, 1.052, .341),
    (.635, 1.157, -.990, .993, .311),
    (.676, 1.135, -.996, .997, .32),
    (.692, 1.149, -1.014, 1.014, .326),
]), .025)
cast("Recessed warm perimeter seam", "Vip_Seam", "Brass", levels([
    (.677, 1.145, -1.009, 1.009, .322),
    (.708, 1.151, -1.022, 1.022, .332),
]), .005)
cast("Inset upholstery seat", "Vip_Seat", "Wine", levels([
    (.701, 1.136, -1.017, 1.017, .323),
    (.733, 1.113, -1.002, 1.002, .319),
    (.754, 1.051, -.975, .975, .315),
]), .014)
bezel("Inset nameplate return", "Vip_Mount", "Blackened", .737, .218, .124, -.012, .065, .010)
bezel("Champagne maker's cartouche", "Vip_PrintFace", "Champagne", .708, .191, .117, -.025, -.008, .007)


def export_meshes():
    """Bake triangulated meshes while keeping the UI-facing faces axis-aligned."""
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    groups = {}
    for ob in source.objects:
        part = ob["part"]
        product = part.split("_")[0]
        mount = mount_transform(product) if ob["angled"] else Matrix.Identity(4)
        to_mount = mount.inverted() @ translation((-spread[product], 0, 0)) @ ob.matrix_world
        evaluated = ob.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        vertices, faces = groups.setdefault((part, ob["finish"], ob["angled"]), ([], []))
        start = len(vertices)
        vertices.extend(tuple(to_mount @ v.co) for v in mesh.vertices)
        faces.extend(tuple(start + i for i in t.vertices) for t in mesh.loop_triangles)
        evaluated.to_mesh_clear()

    bpy.ops.object.select_all(action="DESELECT")
    records = []
    for (part, finish, angled), (vertices, faces) in groups.items():
        mesh = bpy.data.meshes.new(part)
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        assert all(edge.is_manifold for edge in bm.edges) and bm.calc_volume(signed=True) > 0, part
        bm.free()
        ob = bpy.data.objects.new(part, mesh)
        export.objects.link(ob)
        ob.data.materials.append(palette[finish])
        ob.location.x = spread[part.split("_")[0]]
        ob.select_set(True)
        color, surface = finishes[finish]
        records.append({
            "name": part, "angled": angled, "rgb": color, "material": surface,
            "triangles": len(faces),
            "min": [min(v[i] for v in vertices) for i in range(3)],
            "max": [max(v[i] for v in vertices) for i in range(3)],
        })
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=str(FBX), use_selection=True, object_types={"MESH"}, use_triangles=True,
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL", bake_space_transform=True,
        axis_forward="-Z", axis_up="Y", bake_anim=False, add_leaf_bones=False,
    )
    META.write_text(json.dumps({"mounts": mounts, "supports": supports, "meshes": records}, indent=2) + "\n",
                    encoding="utf-8")
    export.hide_render = True
    export.hide_viewport = True
    return records


records = export_meshes()

# The miniature uses these exact source meshes in Studio at 20% scale.
mini_parts = {"Melter_Concrete", "Melter_Snow", "Melter_RedPaint", "Melter_Iron", "Melter_Steel"}
with bpy.data.libraries.load(str(ROOT / "snowmelter.blend")) as (original, loaded):
    assert mini_parts <= set(original.objects)
    loaded.objects = sorted(mini_parts)
origin = translation((spread["Auto"], 0, .75))
for ob in loaded.objects:
    refs_matrix = ob.matrix_world.copy()
    references.objects.link(ob)
    ob.matrix_world = origin @ Matrix.Scale(.2, 4) @ refs_matrix
    ob["product"] = "Auto"

# Crown proxies are positional studies; Studio keeps the original crown parts.
def proxy(name, rgb, x, y, z, radius, height, sides, *, tilt=0, yaw=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=height, location=(x, y, z))
    ob = bpy.context.object
    ob.name = name
    ob.rotation_euler = (tilt, 0, yaw)
    for group in list(ob.users_collection):
        group.objects.unlink(ob)
    references.objects.link(ob)
    ob["product"] = "Vip"
    mat = bpy.data.materials.new(name + " reference")
    mat.diffuse_color = (*[c / 255 for c in rgb], 1)
    ob.data.materials.append(mat)


vx = spread["Vip"]
proxy("VIP cushion", (179, 44, 44), vx, 0, .86, .95, .22, 32)
proxy("VIP lower band", (225, 169, 37), vx, 0, 1.13, .72, .32, 24)
proxy("VIP cap", (174, 33, 45), vx, 0, 1.35, .60, .50, 24)
for i in range(5):
    theta = i * math.tau / 5
    proxy("VIP crown point", (225, 169, 37), vx + .66 * math.sin(theta), -.66 * math.cos(theta), 1.53,
          .34, .08, 4, tilt=math.pi / 2, yaw=theta)

# The FBX keeps axis-aligned sign meshes for installation. The editable source
# shows the installed height above the paving, with its feet extended to grade.
by_name = {row["name"]: row for row in records}
for ob in source.objects:
    part = ob["part"]
    rise, support_part = supports[part.split("_")[0]]
    if part == support_part:
        low = by_name[part]["min"][2]
        original_height = by_name[part]["max"][2] - low
        scale = Matrix.Diagonal((1, 1, 1 + rise / original_height, 1))
        ob.matrix_world = translation((0, 0, low)) @ scale @ translation((0, 0, -low)) @ ob.matrix_world
    else:
        ob.matrix_world = translation((0, 0, rise)) @ ob.matrix_world
for ob in references.objects:
    ob.matrix_world = translation((0, 0, supports[ob["product"]][0])) @ ob.matrix_world

camera_data = bpy.data.cameras.new("Product construction")
camera = bpy.data.objects.new("Product construction", camera_data)
scene.collection.objects.link(camera)
target = Vector((0, -.23, 1.65))
camera.location = (2.8, -9.0, 5.0)
camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type = "ORTHO"
camera_data.ortho_scale = 8.65
scene.camera = camera
scene.render.engine = "BLENDER_WORKBENCH"
scene.world = bpy.data.worlds.new("Steel grey studio")
scene.world.color = (.13, .145, .17)
shading = scene.display.shading
shading.color_type = "MATERIAL"
shading.light = "STUDIO"
shading.show_shadows = True
shading.show_cavity = True
shading.cavity_type = "BOTH"
scene.render.resolution_x, scene.render.resolution_y = 1420, 870
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
bpy.data.libraries.write(str(BLEND), {scene}, compress=True)
result = {"scene": scene.name, "export": str(FBX), "parts": len(records),
          "triangles": sum(row["triangles"] for row in records)}
