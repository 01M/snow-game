"""Refine the a37c7db coin stand in Blender without editing its source assets."""
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(r"C:\Users\bnjlj\Downloads\snow-game") / "blender"
STEM = "x2_cash_stand_integrated"
OUT = ROOT / "exports" / STEM
RENDER = ROOT / "renders" / STEM / "01-blender-construction.png"
BLEND, FBX, META = ROOT / (STEM + ".blend"), OUT / (STEM + ".fbx"), OUT / (STEM + ".json")
assert not any(p.exists() for p in (BLEND, FBX, META, RENDER))
assert bpy.context.mode == "OBJECT"

# Append the committed source from disk. Match its collections through the scene,
# so the operation works even if the original source is already open.
with bpy.data.libraries.load(str(ROOT / "x2_cash_stand_v2.blend")) as (available, loaded):
    assert "CashStandV2" in available.scenes
    loaded.scenes = ["CashStandV2"]
original, = loaded.scenes
scene = bpy.data.scenes.new("CashStandIntegrated")
bpy.context.window.scene = scene


def collection(name):
    new = bpy.data.collections.new(name)
    scene.collection.children.link(new)
    return new


source = collection("Refined cast stand")
export = collection("Flat FBX export")
reference = collection("Original coin envelopes (reference)")
rake_center = (0, -1.255, -.345)
rake_degrees = 23
rake = Matrix.Translation(Vector(rake_center)) @ Matrix.Rotation(-math.radians(rake_degrees), 4, "X")
coin_shift = .27
coin_lean = 4
coin_lift = .105
coin = Matrix.Translation(Vector((.2,.05+coin_shift,.86+coin_lift))) @ Matrix.Rotation(math.radians(coin_lean),4,"X")
old_parts = next(c for c in original.collection.children if c.name.startswith("Stand source"))
old_refs = next(c for c in original.collection.children if c.name.startswith("Coin scale reference"))
materials = {ob["finish"]: ob.data.materials[0] for ob in old_parts.objects}
rgb = {
    "Paint": ((35,49,67),"SmoothPlastic"), "Iron": ((42,47,53),"Metal"),
    "Steel": ((117,137,152),"Metal"), "Brass": ((172,135,67),"Metal"),
    "Enamel": ((24,37,59),"SmoothPlastic"), "Lens": ((97,112,120),"SmoothPlastic"),
}
preserved = {"Cast footing", "Painted waist and shoulder", "Steel rim", "Recessed brass seam",
             "Stack cup", "Navy product enamel", "Etched steel legend"}
for ob in old_parts.objects:
    if ob.name.split(".")[0] in preserved:
        source.objects.link(ob.copy())
for ob in old_refs.objects:
    duplicate = ob.copy()
    reference.objects.link(duplicate)
    if ob.name.startswith("Original coin envelope"):
        duplicate.matrix_world = coin
assert len(source.objects) == len(preserved) and len(reference.objects) == 4


def mesh(name, finish, rings, bevel, mount, group):
    n = len(rings[0])
    vertices = [v for ring in rings for v in ring]
    faces = [tuple(reversed(range(n))), tuple(range(len(vertices)-n, len(vertices)))]
    for row in range(len(rings)-1):
        for j in range(n):
            a, b = row*n+j, row*n+(j+1)%n
            faces.append((a,b,b+n,a+n))
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    ob = bpy.data.objects.new(name, data)
    source.objects.link(ob)
    ob.data.materials.append(materials[finish])
    ob.matrix_world = rake if mount == "rake" else Matrix.Identity(4)
    ob["finish"], ob["mount"], ob["export"] = finish, mount, group
    if bevel:
        mod = ob.modifiers.new("Machined edge", "BEVEL")
        mod.width, mod.segments = bevel, 2
        mod.limit_method, mod.harden_normals = "ANGLE", True
    return ob


def extrude(name, finish, shape, front, rear, bevel, group):
    rings = [[(x,y,z) for x,z in shape] for y in (front,rear)]
    return mesh(name, finish, rings, bevel, "rake", group)


# One cast throat joins the rim and angled plate. Sections are deeper at the
# shoulders so the corners land back on the curved drum.
profile = [(-.028,.235),(-.021,-.225),(.070,-.284),(.153,-.295),
           (.230,-.210),(.285,-.075),(.39,.057),(.55,.134),(.67,.198),
           (.68,.282),(.56,.329),(.285,.333),(.083,.30)]
rings = []
for x,taper in [(-1.016,.63),(-.84,.93),(-.57,1),(.20,1),(.58,.96),(.92,.68)]:
    sweep = .085 * (abs(x)/1.02)**2
    rings.append([(x, y+max(y,0)*sweep+sweep*.15, z*taper+(1-taper)*.065) for y,z in profile])
mesh("Swept mounting throat","Paint",rings,.028,"rake","BadgeHousing")

outline = [(-1.007,-.239),(-.887,-.326),(.354,-.326),(.505,-.254),(.906,-.258),
           (1.009,-.167),(1.009,.153),(.904,.234),(.482,.234),(.381,.304),
           (-.93,.304),(-1.049,.174),(-1.049,-.144)]
extrude("Folded housing shoulder","Paint",outline,-.104,.095,.025,"BadgeHousing")
frame = [(-.999,-.202),(-.87,-.306),(.374,-.306),(.473,-.204),(.473,.189),
         (.369,.275),(-.88,.275),(-.995,.145)]
extrude("Fine trim around enamel","Steel",frame,-.118,-.092,.009,"BadgeSteel")

# The center of the shaped saddle terminates in a mounting shoe on the deck.
# The separate steel edge is above the deck along its entire length.
def crescent(name, finish, group, angle, inner, outer, front, rear, with_foot=False):
    rings = []
    for i in range(25):
        u = -1+2*i/24
        a = math.radians(angle*u)
        lip = (1-abs(u)**5)
        ri = inner+(.023*(1-lip))
        ro = outer-(outer-inner)*.55*(1-lip)
        section = [(ri,front+.014*(1-lip)),(ro,front),(ro,rear),(ri,rear)]
        ring = [coin @ Vector((r*math.sin(a), y, -r*math.cos(a))) for r,y in section]
        if with_foot:
            front_edge, rear_edge = ring[1], ring[2]
            weight = max(0, min(1, (.66-abs(u))/.38))
            weight = weight**2*(3-2*weight)
            foot_front, foot_rear = front_edge.copy(), rear_edge.copy()
            foot_front.y += .020
            foot_rear.y -= .020
            for point in (foot_front, foot_rear):
                point.z = point.z*(1-weight)+.005*weight-.009*(1-weight)
            ring[2:2] = [foot_front, foot_rear]
        rings.append([tuple(v) for v in ring])
    return mesh(name,finish,rings,.012 if finish=="Paint" else .005,"deck",group)


crescent("Curved seat with machined foot","Paint","CoinCradle",56,.838,.973,-.137,.152,with_foot=True)
crescent("Coin cradle rim","Steel","CradleLip",54,.858,.920,-.152,-.121)

# Thin annular seat with a gently crowned lens, contained inside its bezel.
def circle(x,z,y,r):
    return [(x+r*math.cos(i*math.tau/24),y,z+r*math.sin(i*math.tau/24)) for i in range(24)]


x,z = .735,.098
# Closed annulus built by four loops and one repeated bridge in azimuth.
n = 24
lens_assembly = []
for i in range(n):
    a = i*math.tau/n
    lens_assembly.append([(x+r*math.cos(a),y,z+r*math.sin(a))
        for r,y in ((.107,-.103),(.100,-.121),(.074,-.121),(.073,-.103))])
# Separate complete solids with a darker socket around the coloured lens.
mesh("Seat around lens","Iron",[circle(x,z,-.098,.109),circle(x,z,-.116,.106)],.004,"rake","LensSocket")
data = bpy.data.meshes.new("Annular lens rim")
vertices = [v for ring in lens_assembly for v in ring]
faces = [(4*i+j,4*i+(j+1)%4,4*((i+1)%n)+(j+1)%4,4*((i+1)%n)+j) for i in range(n) for j in range(4)]
data.from_pydata(vertices,[],faces)
data.update()
bm=bmesh.new()
bm.from_mesh(data)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(data)
bm.free()
rim=bpy.data.objects.new("Inset brass ring",data)
source.objects.link(rim)
rim.matrix_world=rake
rim.data.materials.append(materials["Brass"])
rim["finish"],rim["mount"],rim["export"]="Brass","rake","LensRim"
mesh("Status glass","Lens",[circle(x,z,-.113,.073),circle(x,z,-.122,.072),
     circle(x,z,-.127,.054)],.002,"rake","Cash_StatusLens")

bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()
groups = {}
for ob in source.objects:
    key = ob["export"],ob["finish"],ob["mount"]
    ev = ob.evaluated_get(deps)
    data = ev.to_mesh()
    data.calc_loop_triangles()
    verts,tris = groups.setdefault(key,([],[]))
    flatten = rake.inverted() @ ob.matrix_world if ob["mount"]=="rake" else ob.matrix_world
    start=len(verts)
    verts.extend(tuple(flatten @ v.co) for v in data.vertices)
    tris.extend(tuple(start+i for i in t.vertices) for t in data.loop_triangles)
    ev.to_mesh_clear()

bpy.ops.object.select_all(action="DESELECT")
records=[]
for (name,finish,mount),(verts,tris) in groups.items():
    data=bpy.data.meshes.new(name)
    data.from_pydata(verts,[],tris)
    data.update()
    bm=bmesh.new()
    bm.from_mesh(data)
    assert all(e.is_manifold for e in bm.edges) and bm.calc_volume(signed=True)>0,name
    bm.free()
    ob=bpy.data.objects.new(name,data)
    export.objects.link(ob)
    ob.data.materials.append(materials[finish])
    ob.select_set(True)
    color,material=rgb[finish]
    records.append(dict(name=name,finish=finish,mount=mount,rgb=color,material=material,
                        triangles=len(tris),min=[min(v[k] for v in verts) for k in range(3)],
                        max=[max(v[k] for v in verts) for k in range(3)]))

OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.fbx(filepath=str(FBX),use_selection=True,object_types={"MESH"},
    apply_unit_scale=True,apply_scale_options="FBX_SCALE_ALL",axis_forward="-Z",axis_up="Y",
    bake_space_transform=True,bake_anim=False,add_leaf_bones=False,use_triangles=True)
META.write_text(json.dumps(dict(meshes=records,rakeCenter=rake_center,rakeDegrees=rake_degrees,
                                bigCoinShiftBack=coin_shift,bigCoinLift=coin_lift,bigCoinLeanDegrees=coin_lean),
                           indent=2)+"\n",encoding="utf-8")
for ob in export.objects:
    ob.hide_set(True)
    ob.hide_render=True

camera_data=bpy.data.cameras.new("Construction close-up")
camera=bpy.data.objects.new("Construction close-up",camera_data)
scene.collection.objects.link(camera)
camera.location=(3.9,-6.2,2.65)
target=Vector((0,-.14,-.36))
camera.rotation_euler=(target-camera.location).to_track_quat("-Z","Y").to_euler()
camera_data.type="ORTHO"
camera_data.ortho_scale=5.60
scene.camera=camera
scene.render.engine="BLENDER_WORKBENCH"
scene.world=bpy.data.worlds.new("Cash stand studio backdrop")
scene.world.color=(.13,.15,.18)
shading=scene.display.shading
shading.color_type="MATERIAL"
shading.light="STUDIO"
shading.show_cavity=True
shading.cavity_type="BOTH"
shading.show_shadows=True
shading.show_specular_highlight=True
scene.render.resolution_x,scene.render.resolution_y=1400,1080
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
RENDER.parent.mkdir(parents=True,exist_ok=True)
scene.render.filepath=str(RENDER)
for area in bpy.context.screen.areas:
    if area.type=="VIEW_3D":
        view=area.spaces.active
        view.shading.color_type="MATERIAL"
        view.shading.show_cavity=True
        view.overlay.show_overlays=False
        view.region_3d.view_location=target
        view.region_3d.view_rotation=camera.rotation_euler.to_quaternion()
        view.region_3d.view_distance=5.25
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),check_existing=True,compress=True,copy=True)
bpy.ops.render.render(write_still=True)
result={"parts":len(records),"triangles":sum(r["triangles"] for r in records),
        "render":str(RENDER),"export":str(FBX)}
