"""Winter Industrial coin stand. Generate in Blender via MCP in Object Mode.

Units are studs, the front is -Y, and the origin is the existing coin deck.
Print faces export flat; the studio-placement metadata restores their shared rake.
"""
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(r"C:\Users\bnjlj\Downloads\snow-game") / "blender"
STEM = "x2_cash_stand_v2"
OUT = ROOT / "exports" / STEM
BLEND = ROOT / (STEM + ".blend")
FBX, META = OUT / (STEM + ".fbx"), OUT / (STEM + ".json")
assert bpy.context.mode == "OBJECT"
assert not any(path.exists() for path in (BLEND, FBX, META))
assert "CashStandV2" not in bpy.data.scenes

previous_scene = bpy.context.scene
scene = bpy.data.scenes.new("CashStandV2")
bpy.context.window.scene = scene
scene.unit_settings.system = "NONE"


def collection(name):
    result = bpy.data.collections.new(name)
    scene.collection.children.link(result)
    return result


source, export, reference = (collection(name) for name in ("Stand source", "Mesh export", "Coin scale reference"))
finishes = {
    "Paint": ((35, 49, 67), "SmoothPlastic", .23, .44),
    "Iron": ((42, 47, 53), "Metal", .56, .50),
    "Steel": ((117, 137, 152), "Metal", .72, .48),
    "Brass": ((172, 135, 67), "Metal", .72, .43),
    "Enamel": ((24, 37, 59), "SmoothPlastic", .10, .43),
    "Lens": ((97, 112, 120), "SmoothPlastic", .14, .32),
    "Coin": ((240, 190, 60), "Metal", .65, .43),
}
materials = {}
for name, (rgb, _, metallic, roughness) in finishes.items():
    mat = bpy.data.materials.new("CashStand_" + name)
    color = (*[((v / 255 + .055) / 1.055) ** 2.4 for v in rgb], 1)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    materials[name] = mat

rake_center = (0, -1.255, -.345)
rake = 23
rake_matrix = Matrix.Translation(Vector(rake_center)) @ Matrix.Rotation(-math.radians(rake), 4, "X")
pose = {"deck": Matrix.Identity(4), "rake": rake_matrix}


def mesh(name, finish, rings, bevel, mount="deck", group=None, target=source):
    n = len(rings[0])
    verts = [coord for ring in rings for coord in ring]
    faces = [tuple(reversed(range(n)))]
    for row in range(len(rings) - 1):
        for j in range(n):
            a, b = row*n+j, row*n+(j+1)%n
            faces.append((a, b, b+n, a+n))
    faces.append(tuple(range(len(verts)-n, len(verts))))
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    ob = bpy.data.objects.new(name, data)
    target.objects.link(ob)
    ob.data.materials.append(materials[finish])
    ob.matrix_world = pose[mount]
    ob["finish"], ob["mount"], ob["export"] = finish, mount, group or "Stand" + finish
    if bevel:
        mod = ob.modifiers.new("Cast edge", "BEVEL")
        mod.width, mod.segments = bevel, 2
        mod.limit_method = "ANGLE"
        mod.harden_normals = True
    return ob


def lathe(name, finish, profile, x=0, y=0, segments=32):
    rings = [[(x+r*math.cos((i+.5)*math.tau/segments),
               y+r*math.sin((i+.5)*math.tau/segments), z) for i in range(segments)]
             for z, r in profile]
    return mesh(name, finish, rings, .014)


def extrusion(name, finish, outline, front, back, bevel=.018, mount="deck", group=None):
    return mesh(name, finish, [[(x, y, z) for x, z in outline] for y in (front, back)],
                bevel, mount, group)


def pin(name, finish, x, z, back, front, radius, mount="deck", group=None, target=source):
    rings = [[(x+r*math.cos(i*math.tau/16), y, z+r*math.sin(i*math.tau/16))
              for i in range(16)] for y,r in ((back,radius), (front+.012,radius), (front,radius*.80))]
    return mesh(name, finish, rings, 0, mount, group, target)


# Low circular casting with a flared shoulder and a narrow metal seam.
lathe("Cast footing", "Iron", [(-1.84, .99),(-.84, 1.10),(-.75, 1.25),(-.65, 1.25),(-.58, 1.18)])
lathe("Painted waist and shoulder", "Paint",
      [(-.68, 1.18),(-.57, 1.12),(-.36, 1.07),(-.22, 1.09),(-.105, 1.22),(-.04, 1.22),(.005, 1.16)])
lathe("Steel rim", "Steel", [(-.145,1.175),(-.117,1.22),(-.091,1.225),(-.071,1.22)])
lathe("Recessed brass seam", "Brass", [(-.535,1.112),(-.518,1.115),(-.501,1.107)], segments=40)
lathe("Stack cup", "Iron", [(-.012, .53),(.014,.54),(.034,.515)], x=-.51, y=-.30)

# Two folded saddles lift the coin by its lower rim. Front lips turn back into
# the slot and the rear cheeks carry the weight against the lean of the coin.
for x in (-.352, .752):
    side = [(-.19,-.018),(-.155,.062),(-.033,.265),(.028,.302),(.071,.277),
            (.075,.206),(.184,.227),(.219,.344),(.288,.362),(.351,.27),(.37,-.018)]
    ob = mesh("Folded coin saddle", "Iron",
              [[(x+w,y,z) for y,z in side] for w in (-.119,.119)], .025)
    shoe = [(x-.107,.049),(x+.107,.049),(x+.086,.135),(x-.086,.135)]
    extrusion("Saddle keeper", "Steel", shoe, -.172, -.125, .012)
    pin("Keeper pin", "Brass", x,.095,-.174,-.201,.032)
    pin("Rear saddle pin", "Steel", x,.266,.182,.157,.026)

# One sculpted tilted apron: chamfered frame, dark enamel, narrow service wing.
back = [(-1.01,-.285),(-.90,-.372),(.93,-.372),(1.09,-.26),(1.09,.23),
        (.975,.342),(-.94,.342),(-1.09,.185),(-1.09,-.18)]
extrusion("Angled cast apron", "Iron", back, -.042,.195,.033,"rake", "BadgeIron")
rim = [(-1.00,-.24),(-.88,-.34),(.91,-.34),(1.055,-.24),(1.055,.211),
       (.945,.310),(-.90,.310),(-1.051,.166),(-1.051,-.153)]
extrusion("Stamped steel face", "Steel", rim, -.104,-.014,.022,"rake","BadgeSteel")
front = [(-.94,-.207),(-.84,-.283),(.355,-.283),(.453,-.190),(.453,.175),
         (.35,.25),(-.85,.25),(-.973,.133),(-.973,-.15)]
extrusion("Navy product enamel", "Enamel", front, -.125,-.084,.010,"rake","Cash_ProductFace")

# Lens in a turned bezel, with a single narrow etched steel legend below.
pin("Lens retaining collar", "Iron",.737,.094,-.095,-.173,.108,"rake","BadgeIron")
pin("Turned brass bezel", "Brass",.737,.094,-.165,-.183,.085,"rake","BadgeBrass")
pin("Status lens", "Lens",.737,.094,-.183,-.211,.060,"rake","Cash_StatusLens")
legend = [(.485,-.243),(.514,-.265),(.969,-.265),(.995,-.241),(.995,-.120),
          (.97,-.098),(.514,-.098),(.485,-.120)]
extrusion("Etched steel legend", "Steel", legend,-.122,-.096,.006,"rake","Cash_IndicatorFace")
for x,z in ((-.943,.232),(-.944,-.256),(.987,.239),(.98,-.289)):
    pin("Apron mounting stud", "Brass",x,z,-.101,-.145,.027,"rake","BadgeBrass")

# The original coin is a Studio Part. These simplified scale dummies stay in Blender.
coin = pin("Original coin envelope", "Coin", 0,0,.10,-.10,.85,target=reference)
coin.matrix_world = Matrix.Translation(Vector((.2,.05,.86))) @ Matrix.Rotation(math.radians(8),4,"X")
for x,z in ((-.55,.08),(-.49,.23),(-.55,.38)):
    ring = [[(x+.5*math.cos(i*math.tau/32),-.3+.5*math.sin(i*math.tau/32),z+dz)
             for i in range(32)] for dz in (-.07,.07)]
    mesh("Small coin envelope","Coin",ring,0,target=reference)

bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()
groups = {}
for ob in source.objects:
    key = ob["export"], ob["finish"], ob["mount"]
    evaluated = ob.evaluated_get(deps)
    data = evaluated.to_mesh()
    data.calc_loop_triangles()
    verts, tris = groups.setdefault(key, ([], []))
    start = len(verts)
    flatten = pose[ob["mount"]].inverted() @ ob.matrix_world
    verts.extend(tuple(flatten @ v.co) for v in data.vertices)
    tris.extend(tuple(start+i for i in t.vertices) for t in data.loop_triangles)
    evaluated.to_mesh_clear()

bpy.ops.object.select_all(action="DESELECT")
records = []
for (name, finish, mount), (verts, tris) in groups.items():
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], tris)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    assert all(edge.is_manifold for edge in bm.edges) and bm.calc_volume(signed=True) > 0, name
    bm.free()
    ob = bpy.data.objects.new(name, data)
    export.objects.link(ob)
    ob.data.materials.append(materials[finish])
    ob.select_set(True)
    records.append({"name":name, "min":[min(v[k] for v in verts) for k in range(3)],
                    "max":[max(v[k] for v in verts) for k in range(3)],
                    "mount":mount, "triangles":len(tris), "rgb":finishes[finish][0],
                    "material":finishes[finish][1]})

OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.fbx(filepath=str(FBX),use_selection=True,object_types={"MESH"},
    apply_unit_scale=True,apply_scale_options="FBX_SCALE_ALL",axis_forward="-Z",axis_up="Y",
    bake_space_transform=True,bake_anim=False,add_leaf_bones=False,use_triangles=True)
META.write_text(json.dumps({"meshes":records, "rakeCenter":rake_center, "rakeDegrees":rake},
                           indent=2)+"\n", encoding="utf-8")
for ob in export.objects:
    ob.hide_set(True)
    ob.hide_render = True
for area in bpy.context.screen.areas:
    if area.type == "VIEW_3D":
        view = area.spaces.active
        view.shading.color_type = "MATERIAL"
        view.shading.show_cavity = True
        view.overlay.show_overlays = False
        view.region_3d.view_location = Vector((0,0,.05))
        view.region_3d.view_rotation = Vector((3,-7,4)).to_track_quat("Z","Y")
        view.region_3d.view_distance = 5.5
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),check_existing=True,compress=True,copy=True)
assert previous_scene.name in bpy.data.scenes
result = {"fbx":str(FBX), "parts":len(records), "triangles":sum(r["triangles"] for r in records)}
