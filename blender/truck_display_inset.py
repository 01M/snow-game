"""Build a recessed display window for the original Lobby truck roof housing."""

import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent
NAME = "truck_display_inset"
OUT = ROOT / "exports" / NAME
BLEND, FBX, META = ROOT / f"{NAME}.blend", OUT / f"{NAME}.fbx", OUT / f"{NAME}.json"
assert not any(path.exists() for path in (BLEND, FBX, META))

scene = bpy.data.scenes.new("Truck roof display inset")
bpy.context.window.scene = scene
source = bpy.data.collections.new("Editable fascia and window")
scene.collection.children.link(source)


def outline(width, bottom, top, corner):
    return [(-width + corner, bottom), (width - corner, bottom), (width, bottom + corner),
            (width, top - corner), (width - corner, top), (-width + corner, top),
            (-width, top - corner), (-width, bottom + corner)]


def build(name, sections, rgb, bevel, hollow=False):
    count = len(sections[0][1])
    points = [(x, depth, z) for depth, ring in sections for x, z in ring]
    if hollow:
        faces = []
        edges = len(sections)
    else:
        faces = [tuple(reversed(range(count))), tuple(range(len(points) - count, len(points)))]
        edges = len(sections) - 1
    for i in range(edges):
        current, following = i * count, ((i + 1) % len(sections)) * count
        for j in range(count):
            nxt = (j + 1) % count
            faces.append((current + j, current + nxt, following + nxt, following + j))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    source.objects.link(ob)
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*[x / 255 for x in rgb], 1)
    ob.data.materials.append(material)
    ob["rgb"], ob["installedName"] = rgb, name
    edge = ob.modifiers.new("Rounded painted edge", "BEVEL")
    edge.width, edge.segments = bevel, 3
    edge.limit_method, edge.harden_normals = "ANGLE", True
    return ob


# Paint matches the factory roof housing and the truck's stamped cab panels.
# The thicker top brow turns in toward the glass instead of sitting over it.
build("Truck_OrangeFascia", [
    (.39, outline(6.12, -2.92, 2.91, .33)),
    (.17, outline(6.22, -2.96, 2.98, .34)),
    (-.092, outline(6.17, -2.88, 2.88, .37)),
    (-.098, outline(5.73, -2.63, 2.34, .26)),
    (.046, outline(5.56, -2.49, 2.20, .23)),
    (.39, outline(5.52, -2.44, 2.16, .22)),
], (232, 116, 32), .044, hollow=True)

# A small rubber shoulder sits behind the painted edge and grounds the pane.
build("Truck_WindowSeat", [
    (.238, outline(5.61, -2.53, 2.24, .25)),
    (.052, outline(5.61, -2.53, 2.23, .25)),
    (.047, outline(5.47, -2.40, 2.10, .20)),
    (.238, outline(5.45, -2.38, 2.08, .20)),
], (51, 45, 42), .014, hollow=True)
build("Truck_Print", [
    (.041, outline(5.50, -2.43, 2.13, .218)),
    (.151, outline(5.50, -2.43, 2.13, .218)),
], (30, 31, 37), .015)

# Keep the editable sections and bevels. Export a separate triangulated set with
# dimensions in the same coordinate system as the other Lobby sign assets.
bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()
exports = bpy.data.collections.new("FBX meshes")
scene.collection.children.link(exports)
bpy.ops.object.select_all(action="DESELECT")
records = []
for ob in source.objects:
    evaluated = ob.evaluated_get(deps)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    vertices = [tuple(v.co) for v in mesh.vertices]
    tris = [tuple(t.vertices) for t in mesh.loop_triangles]
    data = bpy.data.meshes.new(ob.name)
    data.from_pydata(vertices, [], tris)
    bm = bmesh.new()
    bm.from_mesh(data)
    assert all(edge.is_manifold for edge in bm.edges) and bm.calc_volume(signed=True) > 0, ob.name
    bm.free()
    exported = bpy.data.objects.new(ob.name + "_baked", data)
    exports.objects.link(exported)
    exported.data.materials.append(ob.data.materials[0])
    exported.select_set(True)
    records.append({"name": exported.name, "installedName": ob["installedName"], "rgb": list(ob["rgb"]),
                    "triangles": len(tris), "min": [min(v[i] for v in vertices) for i in range(3)],
                    "max": [max(v[i] for v in vertices) for i in range(3)]})
    evaluated.to_mesh_clear()

OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.fbx(filepath=str(FBX), use_selection=True, object_types={"MESH"},
                         apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
                         axis_forward="-Z", axis_up="Y", bake_space_transform=True,
                         bake_anim=False, add_leaf_bones=False, use_triangles=True)
META.write_text(json.dumps({"meshes": records}, indent=2) + "\n", encoding="utf-8")
exports.hide_viewport = exports.hide_render = True

camera_data = bpy.data.cameras.new("Inset section")
camera = bpy.data.objects.new("Inset section", camera_data)
scene.collection.objects.link(camera)
camera.location = (6.8, -14.8, 4.1)
camera.rotation_euler = (Vector((0, .02, -.11)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type, camera_data.ortho_scale = "ORTHO", 14.3
scene.camera = camera
scene.render.engine = "BLENDER_WORKBENCH"
scene.world = bpy.data.worlds.new("Slate backdrop")
scene.world.color = (.13, .145, .17)
shading = scene.display.shading
shading.color_type, shading.light = "MATERIAL", "STUDIO"
shading.show_cavity, shading.cavity_type, shading.show_shadows = True, "BOTH", True
scene.render.resolution_x, scene.render.resolution_y = 1280, 790
scene.render.resolution_percentage = 100
bpy.data.libraries.write(str(BLEND), {scene}, compress=True)
result = {"asset": str(FBX), "parts": len(records), "triangles": sum(row["triangles"] for row in records)}
