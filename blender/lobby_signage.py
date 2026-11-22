"""Build the departure cassette, enamel shop signs and timber records board."""

import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parent
STEM = "lobby_signage"
OUT = ROOT / "exports" / STEM
BLEND, FBX, META = ROOT / f"{STEM}.blend", OUT / f"{STEM}.fbx", OUT / f"{STEM}.json"
assert not any(path.exists() for path in (BLEND, FBX, META))

scene = bpy.data.scenes.new("Lobby World Signs")
bpy.context.window.scene = scene
source = bpy.data.collections.new("Editable signage")
scene.collection.children.link(source)
export = bpy.data.collections.new("FBX export")
scene.collection.children.link(export)

finishes = {
    "Cast": ((45, 58, 80), "Metal"),
    "Steel": ((157, 173, 186), "Metal"),
    "Slate": ((32, 44, 69), "SmoothPlastic"),
    "Timber": ((124, 83, 59), "Wood"),
    "Brown": ((95, 60, 44), "Wood"),
    "Brass": ((161, 127, 74), "Metal"),
    "Ivory": ((232, 214, 175), "SmoothPlastic"),
    "Paper": ((224, 216, 198), "SmoothPlastic"),
}
materials = {}
for name, (rgb, _) in finishes.items():
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*[value / 255 for value in rgb], 1)
    materials[name] = mat

displays = {"Truck": (-6.6, 0, 4.6), "Kiosk": (6.3, 0, 5.3),
            "Gazebo": (-6.6, 0, -.15), "Record": (5.6, 0, .4)}


def clipped(width, bottom, top, cut):
    return [(-width + cut, bottom), (width - cut, bottom), (width, bottom + cut), (width, top - cut),
            (width - cut, top), (-width + cut, top), (-width, top - cut), (-width, bottom + cut)]


def solid(name, group, finish, profiles, bevel):
    n = len(profiles[0][1])
    verts = [(x, y, z) for y, points in profiles for x, z in points]
    faces = [tuple(reversed(range(n))), tuple(range(len(verts) - n, len(verts)))]
    for i in range(len(profiles) - 1):
        for j in range(n):
            a, b = i * n + j, i * n + (j + 1) % n
            faces.append((a, b, b + n, a + n))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    source.objects.link(ob)
    ob.location = displays[group.split("_")[0]]
    ob.data.materials.append(materials[finish])
    ob["group"], ob["finish"] = group, finish
    if bevel:
        mod = ob.modifiers.new("Rounded tooling", "BEVEL")
        mod.width, mod.segments = bevel, 2
        mod.limit_method, mod.harden_normals = "ANGLE", True
    return ob


def plate(name, group, finish, points, front, back, bevel):
    return solid(name, group, finish, [(front, points), (back, points)], bevel)


def tab(name, group, finish, x, w, bottom, top, front, back, bevel):
    pts = [(i + x, k) for i, k in clipped(w, bottom, top, min(.11, w / 2))]
    return plate(name, group, finish, pts, front, back, bevel)


# Raised corners and tapered return form one bolt-on cassette over the stock roof housing.
solid("Flared steel cassette", "Truck_Case", "Cast", [
    (-.40, clipped(6.11, -2.82, 2.72, .40)),
    (-.13, clipped(6.19, -2.97, 2.84, .31)),
    (.24, clipped(5.94, -2.82, 2.71, .24)),
], .095)
plate("Bright rolled lip", "Truck_Rim", "Steel", clipped(5.93, -2.72, 2.61, .28), -.447, -.383, .026)
plate("Destination enamel", "Truck_Print", "Slate", clipped(5.78, -2.60, 2.49, .205), -.473, -.426, .019)
for x in (-5.35, 5.35):
    tab("Lower retaining shoe", "Truck_Clips", "Cast", x, .22, -2.94, -2.56, -.49, -.20, .045)


def market_profile(w, h):
    return [(-w * .78, -h), (w * .78, -h), (w * .91, -h * .82), (w, -h * .48),
            (w, h * .31), (w * .91, h * .68), (w * .68, h * .86), (w * .49, h),
            (-w * .49, h), (-w * .68, h * .86), (-w * .91, h * .68), (-w, h * .31),
            (-w, -h * .48), (-w * .91, -h * .82)]


for kind, width, height, timber in (("Kiosk", 2.78, .67, "Timber"), ("Gazebo", 3.16, .625, "Brown")):
    plate("Carved fascia", kind + "_Wood", timber, market_profile(width, height), -.265, .17, .067)
    plate("Fitted rim", kind + "_Rim", "Brass", market_profile(width - .13, height - .107), -.305, -.246, .020)
    plate("Fired enamel", kind + "_Print", "Ivory", market_profile(width - .214, height - .174), -.340, -.283, .019)
    for x in (-width * .87, width * .87):
        tab("Mounting ear", kind + "_Mounts", "Cast", x, .18, -.29, .29, -.27, .22, .036)

for x in (-2.02, 2.02):
    tab("Saddle bent up to entrance lintel", "Gazebo_Hangers", "Cast", x, .125, .39, 1.31, .03, .26, .028)
    tab("Lintel return", "Gazebo_Hangers", "Cast", x, .125, 1.12, 1.35, .19, .58, .024)

# Announcements board, on tall square timber posts. A crown rail protects the print from weather.
plate("Mortised board body", "Record_Wood", "Timber", clipped(4.96, -2.93, 2.76, .30), -.35, .22, .105)
plate("Inset lining", "Record_Rim", "Brown", clipped(4.71, -2.705, 2.54, .22), -.399, -.336, .035)
plate("Painted records face", "Record_Print", "Paper", clipped(4.54, -2.56, 2.42, .15), -.426, -.38, .019)
plate("Weather cap", "Record_Cap", "Cast", clipped(5.04, 2.64, 2.94, .085), -.47, .31, .046)
for x in (-3.72, 3.72):
    tab("Timber upright", "Record_Posts", "Brown", x, .22, -5.39, 2.50, .15, .64, .05)
    tab("Shoe at the floor", "Record_Shoes", "Cast", x, .28, -5.39, -4.97, .08, .68, .052)


def bake():
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    grouped = {}
    for ob in source.objects:
        evaluated = ob.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        verts, faces = grouped.setdefault((ob["group"], ob["finish"]), ([], []))
        offset = len(verts)
        verts.extend(tuple(v.co) for v in mesh.vertices)
        faces.extend(tuple(offset + i for i in t.vertices) for t in mesh.loop_triangles)
        evaluated.to_mesh_clear()
    bpy.ops.object.select_all(action="DESELECT")
    records = []
    # Four separate templates sit side-by-side in the file for easy selection in Import 3D.
    for (name, finish), (verts, faces) in grouped.items():
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        assert all(e.is_manifold for e in bm.edges) and bm.calc_volume(signed=True) > 0, name
        bm.free()
        ob = bpy.data.objects.new(name, mesh)
        export.objects.link(ob)
        ob.data.materials.append(materials[finish])
        ob.location.x = {"Truck": -13, "Kiosk": 0, "Gazebo": 8, "Record": 19}[name.split("_")[0]]
        ob.select_set(True)
        rgb, material = finishes[finish]
        records.append({"name": name, "min": [min(v[i] for v in verts) for i in range(3)],
                        "max": [max(v[i] for v in verts) for i in range(3)], "rgb": rgb,
                        "material": material, "triangles": len(faces)})
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=str(FBX), use_selection=True, object_types={"MESH"},
                             apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
                             axis_forward="-Z", axis_up="Y", bake_space_transform=True,
                             bake_anim=False, add_leaf_bones=False, use_triangles=True)
    META.write_text(json.dumps({"meshes": records}, indent=2) + "\n", encoding="utf-8")
    export.hide_viewport = export.hide_render = True
    return records


stats = bake()
camera_data = bpy.data.cameras.new("Sign construction")
camera = bpy.data.objects.new("Sign construction", camera_data)
scene.collection.objects.link(camera)
camera.location = (1.5, -25, 11.5)
camera.rotation_euler = (Vector((-.25, 0, 1.5)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type, camera_data.ortho_scale = "ORTHO", 27
scene.camera = camera
scene.render.engine = "BLENDER_WORKBENCH"
scene.world = bpy.data.worlds.new("Workshop slate")
scene.world.color = (.13, .145, .17)
shading = scene.display.shading
shading.color_type, shading.light = "MATERIAL", "STUDIO"
shading.show_shadows, shading.show_cavity, shading.cavity_type = True, True, "BOTH"
scene.render.resolution_x, scene.render.resolution_y = 1450, 930
scene.render.resolution_percentage = 100
bpy.data.libraries.write(str(BLEND), {scene}, compress=True)
result = {"asset": str(FBX), "parts": len(stats), "triangles": sum(row["triangles"] for row in stats)}
