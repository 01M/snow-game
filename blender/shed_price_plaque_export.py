"""Save the inspected plaque source and export ONLY its static material groups.

Run via Blender MCP after shed_price_plaque.py. Never deletes original scene data.
"""
import bpy
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(r"C:\Users\bnjlj\Downloads\snow-game")
PREFIX = "SCS_PlaqueA"
scene = bpy.data.scenes[PREFIX]
assert bpy.context.scene == scene
asset = bpy.data.collections[PREFIX + "_ASSET"]
blend_path = ROOT / "blender/shed_price_plaque_v1.blend"
export_dir = ROOT / "blender/exports/shed_price_plaque"
fbx_path = export_dir / "shed_price_plaque_v1.fbx"
meta_path = export_dir / "shed_price_plaque_v1.json"
assert not any(p.exists() for p in (blend_path, fbx_path, meta_path)), "Do not overwrite existing deliverables."
assert PREFIX + "_EXPORT_MESHES" not in bpy.data.collections
export_dir.mkdir(parents=True, exist_ok=True)

export_coll = bpy.data.collections.new(PREFIX + "_EXPORT_MESHES")
scene.collection.children.link(export_coll)
groups = {}
deps = bpy.context.evaluated_depsgraph_get()
for ob in asset.objects:
    evaluated = ob.evaluated_get(deps)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    mat = ob.data.materials[0]
    vertices, triangles = groups.setdefault(mat.name, ([], []))
    base = len(vertices)
    vertices.extend(tuple(ob.matrix_world @ v.co) for v in mesh.vertices)
    triangles.extend(tuple(base + i for i in t.vertices) for t in mesh.loop_triangles)
    evaluated.to_mesh_clear()

export_objects = []
for mat_name, (vertices, triangles) in groups.items():
    mesh = bpy.data.meshes.new(mat_name + "_ExportMesh")
    mesh.from_pydata(vertices, [], triangles)
    mesh.update()
    mesh.materials.append(bpy.data.materials[mat_name])
    if mat_name.endswith("CreamEnamel"):
        uv = mesh.uv_layers.new(name="Front_XZ")
        for loop in mesh.loops:
            co = mesh.vertices[loop.vertex_index].co
            uv.data[loop.index].uv = ((co.x + 1.325) / 2.65, (co.z + .375) / .75)
    ob = bpy.data.objects.new(mat_name.replace(PREFIX + "_", "Plaque_"), mesh)
    export_coll.objects.link(ob)
    export_objects.append(ob)

bpy.ops.object.select_all(action="DESELECT")
for ob in export_objects: ob.select_set(True)
bpy.context.view_layer.objects.active = export_objects[0]
bpy.ops.export_scene.fbx(filepath=str(fbx_path), use_selection=True, object_types={"MESH"},
    apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y",
    mesh_smooth_type="FACE", bake_space_transform=True, bake_anim=False, add_leaf_bones=False,
    use_custom_props=False, use_triangles=True)
for ob in export_objects:
    ob.hide_render = True
    ob.hide_set(True)

metadata = {
    "status": "art prototype, awaiting approval; not imported into Roblox",
    "units": "1 Blender unit = 1 stud; Z up, front -Y",
    "fbx_axes": {"forward": "-Z", "up": "Y", "scale": "FBX_SCALE_ALL"},
    "wood_backing_bounds": {"width": 3.04, "height": 1.14, "depth": .18},
    "shelf_context": {"width": 4.2, "depth": 1.4, "thickness": .3},
    "print_surface": {"plane_y": -.125, "normal": [0, -1, 0], "safe_width": 2.3, "safe_height": .53},
    "meshes": [{"name": ob.name, "material": ob.data.materials[0].name,
                "triangles": len(ob.data.polygons)} for ob in export_objects],
    "triangles_total": sum(len(ob.data.polygons) for ob in export_objects),
    "excluded": ["reference shelf and wall", "cameras and lights", "preview text", "original scene objects"],
    "materials_note": "Editable procedural wood/coat shaders are in .blend. FBX has base material colors; no grain baked yet.",
    "text_note": "Preview ink is flat Arial Bold, not final Nunito. All dynamic text/price/state belongs in SurfaceGui.",
    "gameplay_camera": {"position": [2.9, -6.38, 3.06], "target": [0, 0, 0], "vertical_fov_deg": 70},
}
meta_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")

# Leave an inspectable front viewport and retain the measured gameplay camera in the source.
for ob in bpy.data.collections[PREFIX + "_REFERENCE_NOT_EXPORT"].objects: ob.hide_set(False)
for ob in bpy.data.collections[PREFIX + "_PRINT_PREVIEW_NOT_EXPORT"].objects: ob.hide_set(True)
scene.camera = bpy.data.objects[PREFIX + "_GameplayCamera"]
scene.view_settings.exposure = 0
bpy.ops.object.select_all(action="DESELECT")
back = bpy.data.objects[PREFIX + "_WoodBacking"]
back.select_set(True)
bpy.context.view_layer.objects.active = back
bpy.context.view_layer.update()
for area in bpy.context.screen.areas:
    if area.type == "VIEW_3D":
        space = area.spaces.active
        space.region_3d.view_rotation = bpy.data.objects[PREFIX + "_DetailCamera"].matrix_world.to_quaternion()
        space.region_3d.view_location = Vector((0, .1, .2))
        space.region_3d.view_distance = 4.8
        space.lens = 45

preserved = json.loads(scene["preserved_before_build"])
assert all(n in getattr(bpy.data, key) for key, names in preserved.items() for n in names)
bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=True, compress=True)
result = {"blend": str(blend_path), "fbx": str(fbx_path), "metadata": str(meta_path),
          "triangles": metadata["triangles_total"], "export_meshes": len(export_objects), "original_data_preserved": True}
