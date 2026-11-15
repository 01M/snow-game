"""Cozy Workshop plaque, v1. Run through Blender MCP, never clear the current file.

Project convention: one Blender unit = one stud; Z up, front = -Y.
ASSET is exportable geometry. REFERENCE and PRINT_PREVIEW are presentation only.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(r"C:\Users\bnjlj\Downloads\snow-game")
PREFIX = "SCS_PlaqueA"
assert PREFIX not in bpy.data.scenes, "Prototype scene exists; refine it instead of rebuilding."
assert bpy.context.mode == "OBJECT", "Inspect/leave the current editing mode before creating a new scene."

preserved = {key: sorted(getattr(bpy.data, key).keys()) for key in
             ("scenes", "objects", "meshes", "materials", "cameras", "lights")}
scene = bpy.data.scenes.new(PREFIX)
bpy.context.window.scene = scene
scene.unit_settings.system = "NONE"
scene.unit_settings.scale_length = 1.0
scene["project_units"] = "1 Blender unit = 1 Roblox stud; front -Y, up Z"
scene["preserved_before_build"] = json.dumps(preserved)
scene["approval"] = "BLENDER ART PROTOTYPE ONLY; NOT IMPORTED INTO ROBLOX"


def collection(name):
    c = bpy.data.collections.new(PREFIX + "_" + name)
    scene.collection.children.link(c)
    return c


asset = collection("ASSET")
stage = collection("REFERENCE_NOT_EXPORT")
printing = collection("PRINT_PREVIEW_NOT_EXPORT")
rig = collection("CAMERAS_LIGHTS")


def linear(rgb):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in (x / 255 for x in rgb))


def material(name, rgb, metallic=0.0, roughness=0.5, coat=0.0):
    m = bpy.data.materials.new(PREFIX + "_" + name)
    m.diffuse_color = (*linear(rgb), 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = m.diffuse_color
    bs.inputs["Metallic"].default_value = metallic
    bs.inputs["Roughness"].default_value = roughness
    bs.inputs["Coat Weight"].default_value = coat
    bs.inputs["Coat Roughness"].default_value = 0.25
    return m


wood = material("WarmWood", (151, 96, 53), roughness=0.64)
enamel = material("CreamEnamel", (244, 235, 211), metallic=0.035, roughness=0.3, coat=0.2)
frame = material("PaintedSteel", (63, 73, 82), metallic=0.6, roughness=0.46)
steel = material("ClipSteel", (123, 130, 133), metallic=0.8, roughness=0.49)
brass = material("DullBrass", (177, 140, 79), metallic=0.7, roughness=0.5)
ink = material("PreviewNavyInk", (27, 42, 92), roughness=0.85)
shelfwood = material("ReferenceShelfWood", (185, 139, 82), roughness=0.72)
wallwood = material("ReferenceWallWood", (142, 83, 44), roughness=0.8)
pale = material("ReferencePalePaint", (213, 216, 209), roughness=0.75)
snow = material("ReferenceSnow", (226, 235, 244), roughness=0.9)


def grain(m, low, high, scale=(1.7, 5.0, 30.0)):
    nt = m.node_tree
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = 1.0
    tex.inputs["Detail"].default_value = 1.0
    mapping = nt.nodes.new("ShaderNodeVectorMath")
    mapping.operation = "MULTIPLY"
    mapping.inputs[1].default_value = scale
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Object"], mapping.inputs[0])
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[0].color = (*linear(low), 1)
    ramp.color_ramp.elements[1].color = (*linear(high), 1)
    nt.links.new(tex.outputs["Fac"], ramp.inputs[0])
    nt.links.new(ramp.outputs["Color"], nt.nodes.get("Principled BSDF").inputs["Base Color"])


grain(wood, (134, 81, 43), (163, 108, 61))
grain(shelfwood, (169, 121, 70), (191, 146, 88))
grain(wallwood, (132, 75, 40), (148, 89, 49), (1.0, 2.0, 11.0))


def mesh_object(name, verts, faces, mat, coll, bevel=0.0):
    mesh = bpy.data.meshes.new(PREFIX + "_" + name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(PREFIX + "_" + name, mesh)
    coll.objects.link(ob)
    mesh.materials.append(mat)
    if bevel:
        mod = ob.modifiers.new("Soft manufactured edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.harden_normals = True
    return ob


def extrude_xz(name, poly, front_y, back_y, mat, coll=asset, bevel=0.015):
    n = len(poly)
    verts = [(x, front_y, z) for x, z in poly] + [(x, back_y, z) for x, z in poly]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, i + n, (i + 1) % n + n, (i + 1) % n) for i in range(n)]
    return mesh_object(name, verts, faces, mat, coll, bevel)


def octagon(w, h, cut):
    x, z = w / 2, h / 2
    return [(-x + cut, -z), (x - cut, -z), (x, -z + cut), (x, z - cut),
            (x - cut, z), (-x + cut, z), (-x, z - cut), (-x, -z + cut)]


wood_profile = [(-1.40, -.49), (1.40, -.49), (1.52, -.37), (1.52, .29), (1.40, .42),
                (1.38, .42), (1.38, .57), (1.28, .65), (1.08, .65), (.98, .55), (.98, .43),
                (-.98, .43), (-.98, .55), (-1.08, .65), (-1.28, .65), (-1.38, .57),
                (-1.38, .42), (-1.40, .42), (-1.52, .29), (-1.52, -.37)]
back = extrude_xz("WoodBacking", wood_profile, -.03, .15, wood, bevel=.025)
face = extrude_xz("FlatEnamel", octagon(2.65, .75, .12), -.125, -.05, enamel, bevel=.012)
face["flat_print_region"] = "x ±1.15, z ±0.265; front plane y=-0.125; normal (0,-1,0)"
face["surface_gui"] = "Keep dynamic text on a separate flat SurfaceGui anchor; no text baked in export."


def ring(name, outer, inner, front_y, back_y, mat):
    n = len(outer)
    verts = [(x, y, z) for y in (front_y, back_y) for loop in (outer, inner) for x, z in loop]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(i, j, n + j, n + i), (2*n+i, 3*n+i, 3*n+j, 2*n+j),
                  (i, 2*n+i, 2*n+j, j), (n+i, n+j, 3*n+j, 3*n+i)]
    return mesh_object(name, verts, faces, mat, asset, .012)


ring("BeveledMetalRim", octagon(2.80, .90, .145), octagon(2.64, .74, .12), -.14, -.025, frame)


def clip(x, suffix):
    # A true C-jaw grips the 0.3-stud shelf lip; the short lower tongue mounts behind the wooden ear.
    yz = [(.05, .50), (.09, .50), (.09, .71), (.46, .71), (.46, .75),
          (.09, .75), (.09, 1.05), (.46, 1.05), (.46, 1.09), (.05, 1.09)]
    n = len(yz)
    verts = [(xx, y, z) for xx in (x - .08, x + .08) for y, z in yz]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2*n))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    return mesh_object("SpringClip_" + suffix, verts, faces, steel, asset, .009)


for x, suffix in ((-1.18, "L"), (1.18, "R")):
    clip(x, suffix)
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=.055, depth=.025,
        end_fill_type="NGON", location=(x, -.048, .54), rotation=(math.pi/2, 0, 0))
    head = bpy.context.object
    head.name = PREFIX + "_Fastener_" + suffix
    for c in list(head.users_collection): c.objects.unlink(head)
    asset.objects.link(head)
    head.data.materials.append(brass)
    bevel = head.modifiers.new("Head edge", "BEVEL")
    bevel.width, bevel.segments = .006, 1


def box(name, location, size, mat, coll=stage, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    ob = bpy.context.object
    ob.name = PREFIX + "_" + name
    ob.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for c in list(ob.users_collection): c.objects.unlink(ob)
    coll.objects.link(ob)
    ob.data.materials.append(mat)
    if bevel:
        m = ob.modifiers.new("Simple edge", "BEVEL")
        m.width, m.segments = bevel, 1
    return ob


for x, suffix in ((-1.18, "L"), (1.18, "R")):
    box("FastenerSlot_" + suffix, (x, -.062, .54), (.061, .004, .009), frame, asset, 0)

# Measured shelf dimensions from House Map; presentation context, not a map replacement or export.
box("ReferenceUpperShelf", (0, .8, .9), (4.2, 1.4, .3), shelfwood)
box("ReferenceLowerShelf", (0, .8, -1.1), (4.2, 1.4, .3), shelfwood)
for x in (-2.0, 2.0): box("ReferenceLeg", (x, .2, -.3), (.25, .25, 4.0), pale)
box("ReferenceBackWall", (0, 1.65, .3), (5.6, .12, 5.0), wallwood)
box("ReferenceSnowFloor", (0, 0, -2.36), (14, 12, .15), snow, bevel=0)
stage["note"] = "Approximate one-bay shelf context from House Map dimensions; not part of asset."

# Optional ink-only sample for judging the empty printable field. Never part of the exported asset.
font = bpy.data.fonts.load(r"C:\Windows\Fonts\arialbd.ttf")
font.name = PREFIX + "_PreviewFont_NOT_Nunito"
for label, z, size in (("Лопата", .15, .29), ("8 Cash", -.14, .31)):
    data = bpy.data.curves.new(PREFIX + "_SamplePrint", "FONT")
    data.body, data.size = label, size
    data.align_x, data.align_y = "CENTER", "CENTER"
    data.font, data.extrude, data.offset = font, 0, 0
    data.materials.append(ink)
    ob = bpy.data.objects.new(PREFIX + "_PreviewText_" + label, data)
    printing.objects.link(ob)
    ob.location = (0, -.1265, z)
    ob.rotation_euler = (math.pi/2, 0, 0)
printing["note"] = "Flat preview ink only; actual integration must use Ui Nunito and dynamic SurfaceGui."


def camera(name, position, target, vfov):
    data = bpy.data.cameras.new(PREFIX + "_" + name)
    ob = bpy.data.objects.new(data.name, data)
    rig.objects.link(ob)
    ob.location = position
    ob.rotation_euler = (Vector(target) - ob.location).to_track_quat("-Z", "Y").to_euler()
    data.sensor_fit, data.sensor_height = "VERTICAL", 24
    data.lens = 24 / (2 * math.tan(math.radians(vfov) / 2))
    data.clip_start, data.clip_end = .03, 150
    return ob


game_camera = camera("GameplayCamera", (2.9, -6.38, 3.06), (0, 0, 0), 70)
game_camera["note"] = "Approximate actual prototype Play camera: 7.65 studs, 24° sideways/down; 70° vertical FOV."
detail_camera = camera("DetailCamera", (2.9, -6.38, 3.06), (0, 0, .18), 31)
scene.camera = game_camera


def light(name, location, energy, color, size, target=(0, 0, 0)):
    data = bpy.data.lights.new(PREFIX + "_" + name, "AREA")
    ob = bpy.data.objects.new(data.name, data)
    rig.objects.link(ob)
    ob.location = location
    ob.rotation_euler = (Vector(target)-ob.location).to_track_quat("-Z", "Y").to_euler()
    data.energy, data.color, data.shape, data.size = energy, color, "DISK", size
    return ob


light("WarmKey", (-3, -4, 5), 650, (1.0, .78, .53), 4)
light("WinterFill", (4, -2, 3), 430, (.58, .73, 1.0), 4)
light("TopSoft", (0, 2, 5), 450, (1.0, .92, .78), 3)
world = bpy.data.worlds.new(PREFIX + "_World")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (.25, .32, .46, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = .35
scene.world = world
scene.render.engine = "CYCLES"
scene.cycles.samples, scene.cycles.use_denoising = 48, True
scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = 1600, 900, 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
scene.render.film_transparent = False

# Select only our asset, and make an actual material viewport useful immediately.
bpy.ops.object.select_all(action="DESELECT")
for ob in asset.objects: ob.select_set(True)
bpy.context.view_layer.objects.active = back
bpy.context.view_layer.update()
for area in bpy.context.screen.areas:
    if area.type == "VIEW_3D":
        space = area.spaces.active
        space.shading.type = "MATERIAL"
        space.shading.use_scene_lights = True
        space.shading.use_scene_world = True
        space.overlay.show_overlays = False
        space.region_3d.view_rotation = detail_camera.matrix_world.to_quaternion()
        space.region_3d.view_location = Vector((0, .1, .2))
        space.region_3d.view_distance = 4.8
        space.region_3d.view_perspective = "PERSP"
        space.lens = 45

result = {"scene": scene.name, "asset_objects": [o.name for o in asset.objects],
          "preserved": all(name in getattr(bpy.data, key) for key, names in preserved.items() for name in names),
          "units": scene["project_units"], "print_region": face["flat_print_region"]}
