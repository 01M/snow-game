"""Winter Industrial signs. Run in Blender, in Object Mode, using Blender MCP.

One unit per stud, Z up, front -Y. Exports only the new geometry in a new scene.
"""
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(r"C:\Users\bnjlj\Downloads\snow-game") / "blender"
OUT = ROOT / "exports/winter_industrial_signs"
STEM = "winter_industrial_signs_v1"
FILES = (ROOT / (STEM + ".blend"), OUT / (STEM + ".fbx"), OUT / (STEM + ".json"))
assert bpy.context.mode == 'OBJECT' and not any(p.exists() for p in FILES)
assert "WinterIndustrialSigns" not in bpy.data.scenes

scene = bpy.data.scenes.new("WinterIndustrialSigns")
bpy.context.window.scene = scene
scene.unit_settings.system = 'NONE'
spec = {
    "Enamel": ((24, 38, 64), "SmoothPlastic", .15, .42),
    "Steel": ((116, 130, 149), "Metal", .78, .4),
    "Iron": ((48, 57, 71), "Metal", .62, .5),
    "Brass": ((174, 140, 77), "Metal", .65, .46),
    "Lens": ((76, 91, 99), "SmoothPlastic", .06, .48),
}
materials = {}
for name, (rgb, _, metallic, roughness) in spec.items():
    material = bpy.data.materials.new("WinterSigns_" + name)
    color = [((v / 255 + .055) / 1.055) ** 2.4 if v > 10 else v / 3294.6 for v in rgb]
    material.diffuse_color = (*color, 1)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = material.diffuse_color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    materials[name] = material

source = bpy.data.collections.new("WinterSigns_Source")
scene.collection.children.link(source)
export = bpy.data.collections.new("WinterSigns_Export")
scene.collection.children.link(export)
offset = {"Melter": 0, "Cash": 5.5}


def solid(group, material, rings, bevel):
    section = len(rings[0])
    assert len(rings) >= 2 and all(len(r) == section for r in rings)
    vertices = [(x + offset[group], y, z) for r in rings for x, y, z in r]
    faces = [tuple(reversed(range(section)))]
    for start in range(0, len(vertices) - section, section):
        for j in range(section):
            a, b = start + j, start + (j + 1) % section
            faces.append((a, b, b + section, a + section))
    faces.append(tuple(range(len(vertices) - section, len(vertices))))
    mesh = bpy.data.meshes.new(group + material + "_Source")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(group + material, mesh)
    source.objects.link(ob)
    mesh.materials.append(materials[material])
    ob["group"], ob["finish"] = group, material
    if bevel:
        mod = ob.modifiers.new("Edge break", 'BEVEL')
        mod.width, mod.segments = bevel, 2
        mod.limit_method = 'ANGLE'
        mod.harden_normals = True
    return ob


def corners(w, h, cut):
    a, b = w/2, h/2
    return [(-a+cut,-b),(a-cut,-b),(a,-b+cut),(a,b-cut),
            (a-cut,b),(-a+cut,b),(-a,b-cut),(-a,-b+cut)]


def plaque(group, material, w, h, cut, front, back, x=0, z=0, bevel=.014):
    return solid(group,material,[[(u+x,y,v+z) for u,v in corners(w,h,cut)]
                                 for y in (front,back)],bevel)


def rivet(group, x, z, y, r, material="Brass"):
    rings = [[(x+r*s*math.cos(i*math.tau/12), q, z+r*s*math.sin(i*math.tau/12))
              for i in range(12)] for q,s in ((y,.93),(y-.025,1),(y-.046,.68))]
    return solid(group, material, rings, 0)


# Nameplate in the clear red belt above the existing copper coil.
# Bent brackets follow the tank chord and meet two folded end tabs.
plaque("Melter","Iron",3.42,1.08,.19,-.17,-.015,bevel=.026)
plaque("Melter","Steel",3.43,1.04,.19,-.227,-.105,bevel=.029)
plaque("Melter","Enamel",3.27,.88,.15,-.246,-.185,bevel=.012)
for side in (-1, 1):
    end = [(-.24,.16),(-.18,.16),(-.18,-.16),(-.24,-.16)]
    # The outer end curves back toward the cylinder skin.
    sections = [(1.57,0),(1.72,.02),(1.87,.12),(1.99,.38),(2.04,.65),(2.08,.80)]
    rings = [[(side*x,y+depth,z+.10) for y,z in end] for x,depth in sections]
    solid("Melter","Iron",rings,.022)
    plaque("Melter","Steel",.35,.31,.062,-.289,-.190,x=side*1.62,z=.10,bevel=.025)
    rivet("Melter",side*1.68,.10,-.289,.065)
    rivet("Melter",side*2.04,.10,.39,.042,"Steel")


# Cast plinth with a low chamfered deck and a separate instrument window.
# Its origin represents the existing coin deck at world Y=3.13.
for name,w,d,cut,z0,z1 in (
    ("Iron",2.95,2.37,.20,-1.98,-.82),
    ("Iron",2.80,2.26,.18,-.88,-.12),
    ("Steel",2.88,2.31,.19,-.145,0),
):
    solid("Cash",name,[[(x,y,z) for x,y in corners(w,d,cut)]
                      for z in (z0,z1)],.035)
plaque("Cash","Steel",2.61,.72,.105,-1.177,-1.065,z=-.48,bevel=.021)
plaque("Cash","Enamel",1.55,.603,.071,-1.200,-1.134,x=-.435,z=-.48,bevel=.009).name="Cash_ProductFace"
plaque("Cash","Enamel",.80,.603,.067,-1.200,-1.134,x=.817,z=-.48,bevel=.009).name="Cash_IndicatorFace"
for x in (-1.23,1.246):
    for z in (-.25,-.70):
        rivet("Cash",x,z,-1.174,.034)
# Short jaws retain the edge of the original large coin.
for y in (-.18,.15):
    solid("Cash","Iron", [[(x,y+dy,z) for x,dy in corners(.58,.14,.035)]
                          for z in (-.02,.125)], .025)
    rivet("Cash",.19,.061,y-.07,.036)

# Export one static mesh per finish, except the two independent print faces.
deps = bpy.context.evaluated_depsgraph_get()
groups = {}
for ob in source.objects:
    special = ob.name if ob.name in {"Cash_ProductFace", "Cash_IndicatorFace"} else None
    key = (special or ob["group"]+"_"+ob["finish"], ob["finish"])
    ev = ob.evaluated_get(deps)
    mesh = ev.to_mesh()
    mesh.calc_loop_triangles()
    verts, tris = groups.setdefault(key, ([], []))
    start = len(verts)
    verts.extend(tuple(ob.matrix_world @ v.co) for v in mesh.vertices)
    tris.extend(tuple(start+i for i in t.vertices) for t in mesh.loop_triangles)
    ev.to_mesh_clear()

record = []
bpy.ops.object.select_all(action='DESELECT')
for (name, finish), (verts, tris) in groups.items():
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], tris)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    assert all(e.is_manifold for e in bm.edges) and bm.calc_volume(signed=True) > 0, name
    bm.free()
    ob = bpy.data.objects.new(name, data)
    export.objects.link(ob)
    ob.data.materials.append(materials[finish])
    ob.select_set(True)
    record.append({"name":name, "min":[min(v[k] for v in verts) for k in range(3)],
                   "max":[max(v[k] for v in verts) for k in range(3)], "triangles":len(tris),
                   "rgb":spec[finish][0], "material":spec[finish][1]})

OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.fbx(filepath=str(FILES[1]),use_selection=True,object_types={'MESH'},
    apply_unit_scale=True,apply_scale_options='FBX_SCALE_ALL',axis_forward='-Z',axis_up='Y',
    bake_space_transform=True,bake_anim=False,add_leaf_bones=False,use_triangles=True)
FILES[2].write_text(json.dumps({"meshes":record,"xOffset":offset,"units":"stud; front -Y; up Z"},
                                indent=2)+"\n",encoding="utf-8")
for ob in export.objects:
    ob.hide_set(True)
    ob.hide_render = True
for area in bpy.context.screen.areas:
    if area.type == 'VIEW_3D':
        space = area.spaces.active
        space.shading.color_type = 'MATERIAL'
        space.shading.show_cavity = True
        space.overlay.show_overlays = False
        space.region_3d.view_location = Vector((3,-.1,-.25))
        space.region_3d.view_rotation = Vector((.85,-8,3)).to_track_quat('Z','Y')
        space.region_3d.view_distance = 11
bpy.ops.wm.save_as_mainfile(filepath=str(FILES[0]),check_existing=True,compress=True,copy=True)
result = {"files":[str(p) for p in FILES], "meshes":len(record),
          "triangles":sum(r["triangles"] for r in record), "normals":"OK"}
