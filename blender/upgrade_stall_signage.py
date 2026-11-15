"""Cozy Workshop counter plaque and buckle-mounted product tag.

Run through Blender MCP. New scene only; never clears existing user data.
One Blender unit = one Roblox stud. Z up, front -Y, as in the Shed export.
"""
import bpy
import bmesh
import json
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(r"C:\Users\bnjlj\Downloads\snow-game")
PREFIX = "SCS_UpgradeSigns"
OUT = ROOT / "blender/exports/upgrade_stall_signage"
BLEND = ROOT / "blender/upgrade_stall_signage_v1.blend"
FBX = OUT / "upgrade_stall_signage_v1.fbx"
META = OUT / "upgrade_stall_signage_v1.json"
assert bpy.context.mode == 'OBJECT'
assert PREFIX not in bpy.data.scenes
assert not any(p.exists() for p in (BLEND, FBX, META))
preserved = {key: sorted(getattr(bpy.data, key).keys()) for key in
             ('scenes', 'objects', 'meshes', 'materials', 'cameras', 'lights')}
scene = bpy.data.scenes.new(PREFIX)
bpy.context.window.scene = scene
scene.unit_settings.system = 'NONE'
scene.unit_settings.scale_length = 1
scene['project_units'] = '1 unit = 1 stud; front -Y, up Z'
scene['preserved_before_build'] = json.dumps(preserved)
asset = bpy.data.collections.new(PREFIX + '_ASSET')
scene.collection.children.link(asset)
exports = bpy.data.collections.new(PREFIX + '_EXPORT')
scene.collection.children.link(exports)


def linear(rgb):
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
                 for v in (x / 255 for x in rgb))


specs = {
    'WarmWood': ((190, 151, 105), 'Wood', 0, .67),
    'PaintedSteel': ((63, 73, 82), 'Metal', .55, .45),
    'CreamEnamel': ((239, 224, 193), 'SmoothPlastic', .025, .32),
    'DullBrass': ((177, 140, 79), 'Metal', .7, .48),
    'Leather': ((110, 68, 38), 'Leather', 0, .7),
}
mats = {}
for name, (rgb, _, metallic, roughness) in specs.items():
    m = bpy.data.materials.new(PREFIX + '_' + name)
    m.diffuse_color = (*linear(rgb), 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = m.diffuse_color
    bs.inputs['Metallic'].default_value = metallic
    bs.inputs['Roughness'].default_value = roughness
    if name == 'CreamEnamel':
        bs.inputs['Coat Weight'].default_value = .15
    mats[name] = m


def mesh(name, vertices, faces, material, bevel=0):
    data = bpy.data.meshes.new(PREFIX + '_' + name)
    data.from_pydata(vertices, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(PREFIX + '_' + name, data)
    asset.objects.link(obj)
    data.materials.append(mats[material])
    obj['group'] = name.split('_')[0]
    obj['material_key'] = material
    if bevel:
        mod = obj.modifiers.new('Manufactured edge', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = 'ANGLE'
        mod.harden_normals = True
    return obj


def plate(name, width, height, cut, front, back, material, x=0, bevel=.012):
    w, h = width / 2, height / 2
    poly = [(-w+cut, -h), (w-cut, -h), (w, -h+cut), (w, h-cut),
            (w-cut, h), (-w+cut, h), (-w, h-cut), (-w, -h+cut)]
    vertices = [(px+x, y, z) for y in (front, back) for px, z in poly]
    n = len(poly)
    faces = [tuple(range(n)), tuple(range(n, n*2))]
    faces += [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)]
    return mesh(name, vertices, faces, material, bevel)


def cylinder(name, x, y, z, radius, depth, material, seg=16):
    vertices = [(x+radius*math.cos(i*math.tau/seg), yy,
                 z+radius*math.sin(i*math.tau/seg))
                for yy in (y-depth/2, y+depth/2) for i in range(seg)]
    faces = [tuple(range(seg)), tuple(range(seg, seg*2))]
    faces += [(i, (i+1) % seg, (i+1) % seg+seg, i+seg) for i in range(seg)]
    return mesh(name, vertices, faces, material, .004)


def slot(name, x, y, z, length, width):
    return plate(name, length, width, width*.2, y-.003, y+.003,
                 'PaintedSteel', x=x, bevel=.001)


# Flush fascia plate: no hanging ears, shelf clips, extra ornaments or pedestal.
plate('Counter_Backing', 4.28, 1.02, .11, -.06, .06, 'WarmWood', bevel=.025)
plate('Counter_Frame', 4.12, .94, .10, -.125, -.035, 'PaintedSteel', bevel=.025)
plate('Counter_Face', 3.92, .78, .075, -.156, -.104, 'CreamEnamel', bevel=.014)
for i, (x, z) in enumerate(((-2.02, -.365), (2.02, -.365), (2.02, .365), (-2.02, .365))):
    cylinder('Counter_Screw'+str(i), x, -.146, z, .039, .034, 'DullBrass')
    ob = slot('Counter_Slot'+str(i), x, -.166, 0, .048, .007)
    ob.location.z = z

# Tag is presented to the right in the export, then placed at the existing buckle.
TX = 6.0
plate('Tag_Backing', 1.10, .96, .13, -.035, .035, 'Leather', x=TX, bevel=.018)
plate('Tag_Frame', 1.04, .90, .115, -.080, -.022, 'PaintedSteel', x=TX, bevel=.018)
plate('Tag_Face', .92, .76, .08, -.106, -.064, 'CreamEnamel', x=TX, bevel=.009)

# Flat folded leather loop. Back fold reaches the existing buckle 0.28 studs behind
# the plaque. The front tail is riveted to its top edge, rather than floating.
control = [(-.098, .35), (-.098, .52), (-.055, .63), (.04, .69),
           (.22, .69), (.30, .63), (.30, .51), (.275, .43)]
path = []
for i in range(len(control)-1):
    a = Vector(control[max(i-1, 0)])
    b = Vector(control[i])
    c = Vector(control[i+1])
    d = Vector(control[min(i+2, len(control)-1)])
    for j in range(5):
        t = j / 5
        path.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
path.append(Vector(control[-1]))
verts = []
for i, point in enumerate(path):
    tangent = path[min(i+1, len(path)-1)] - path[max(i-1, 0)]
    normal = Vector((-tangent.y, tangent.x)).normalized() * .012
    for sx, side in ((-.068, -1), (.068, -1), (.068, 1), (-.068, 1)):
        p = point + normal * side
        verts.append((TX+sx, p.x, p.y))
faces = [(0, 1, 2, 3), tuple(range(len(verts)-4, len(verts)))]
for i in range(len(path)-1):
    for j in range(4):
        faces.append((i*4+j, i*4+(j+1)%4, (i+1)*4+(j+1)%4, (i+1)*4+j))
mesh('Tag_FoldedLoop', verts, faces, 'Leather', .003)
cylinder('Tag_Rivet', TX, -.125, .35, .032, .026, 'DullBrass')

# Evaluated material groups are separate for each sign, so SurfaceGui targets have
# a tight face bounding box. No texture bake or geometry from the stall is exported.
bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()
groups = {}
for ob in asset.objects:
    ev = ob.evaluated_get(deps)
    data = ev.to_mesh()
    data.calc_loop_triangles()
    key = (ob['group'], ob['material_key'])
    vs, ts = groups.setdefault(key, ([], []))
    base = len(vs)
    vs.extend(tuple(ob.matrix_world @ v.co) for v in data.vertices)
    ts.extend(tuple(base+i for i in t.vertices) for t in data.loop_triangles)
    ev.to_mesh_clear()

objects, records = [], []
for (group, material), (vs, ts) in groups.items():
    data = bpy.data.meshes.new(group+'_'+material)
    data.from_pydata(vs, [], ts)
    data.update()
    data.materials.append(mats[material])
    bm = bmesh.new()
    bm.from_mesh(data)
    assert all(e.is_manifold for e in bm.edges), 'Non-manifold export: '+data.name
    assert bm.calc_volume(signed=True) > 0, 'Reversed normals: '+data.name
    bm.free()
    ob = bpy.data.objects.new(group+'_'+material, data)
    exports.objects.link(ob)
    objects.append(ob)
    mins = [min(v[k] for v in vs) for k in range(3)]
    maxs = [max(v[k] for v in vs) for k in range(3)]
    records.append({'name':ob.name, 'triangles':len(ts), 'bounds_min':mins,
                    'bounds_max':maxs, 'rgb':specs[material][0],
                    'roblox_material':specs[material][1]})

OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
for ob in objects: ob.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.export_scene.fbx(filepath=str(FBX), use_selection=True, object_types={'MESH'},
    apply_unit_scale=True, apply_scale_options='FBX_SCALE_ALL', axis_forward='-Z', axis_up='Y',
    mesh_smooth_type='FACE', bake_space_transform=True, bake_anim=False,
    add_leaf_bones=False, use_custom_props=False, use_triangles=True)
metadata = {'units':'1 Blender unit = 1 Roblox stud; Z up, front -Y',
    'counter':{'origin':[0,0,0], 'width':4.28, 'height':1.02, 'face':[3.92,.78]},
    'tag':{'origin':[6,0,0], 'face':[.92,.76], 'loop_reaches_back':.30},
    'meshes':records, 'normals':'NORMALS OK; closed manifold, positive signed volume',
    'text':'Dynamic SurfaceGui only, no baked labels', 'source_data_preserved':True}
META.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
for ob in objects:
    ob.hide_set(True)
    ob.hide_render = True
for ob in asset.objects: ob.select_set(False)
for area in bpy.context.screen.areas:
    if area.type == 'VIEW_3D':
        space = area.spaces.active
        space.shading.type = 'SOLID'
        space.shading.color_type = 'MATERIAL'
        space.shading.show_cavity = True
        space.overlay.show_overlays = False
        space.region_3d.view_location = Vector((2.6, 0, .15))
        space.region_3d.view_rotation = Vector((0, -8, 3)).to_track_quat('Z', 'Y')
        space.region_3d.view_distance = 9
assert all(n in getattr(bpy.data, key) for key, names in preserved.items() for n in names)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), check_existing=True, compress=True)
result = {'blend':str(BLEND), 'fbx':str(FBX), 'meshes':len(objects),
          'triangles':sum(r['triangles'] for r in records), 'normals':'NORMALS OK',
          'source_data_preserved':True}
