"""Manekin crash-test do gry (Blender, bez okna):
  blender -b CrashTestDummy_UnityMecanim.blend -P tools/prepare_dummy.py -- WYJŚCIE.obj TEKSTURA.png [podgląd.png]
  ... -- WYJŚCIE.glb TEKSTURA.png  - manekin gracza ze szkieletem (poza siedząca = spoczynkowa)

Źródło: "Crash Test Dummy mark1", Panckuha, blendswap.com/blend/19677, CC0
(archiwum w build/media_in/dummy, poza gitem). Model w pozie T, rig
"metarig" (nazwy kości Rigify: hips, thigh.L, shin.L, upper_arm.L, ...).
Skrypt ustawia pozę siedzącą z rękami na kierownicy (kierunki kości liczone
w układzie postaci: przód z kierunku stóp), wypieka ją w siatkę (bez
szkieletu w grze), skaluje do ~1,75 m wzrostu, punkt zero w biodrach
(do posadzenia na fotelu) i eksportuje OBJ z teksturą manekina.
"""
import bpy, sys, math
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
out_glb, tex_path = args[0], args[1]
preview = args[2] if len(args) > 2 else ""

arm = bpy.data.objects["metarig"]
man = bpy.data.objects["man"]
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
pb = arm.pose.bones

def upd():
    bpy.context.view_layer.update()

def dirv(b):
    return (pb[b].tail - pb[b].head).normalized()

# Osie postaci (układ armatury): góra z kręgosłupa, przód ze stopy.
up = Vector((0, 0, 1))
fwd = (pb["foot.L"].tail - pb["foot.L"].head)
fwd.z = 0.0
fwd.normalize()
side_l = (pb["thigh.L"].head - pb["thigh.R"].head)
side_l.z = 0.0
side_l.normalize()
print("PRZÓD", fwd, "LEWO", side_l)

def aim(b, target):
    target = target.normalized()
    cur = dirv(b)
    q = cur.rotation_difference(target)
    h = pb[b].head.copy()
    pb[b].matrix = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ pb[b].matrix
    upd()

def deg(a):
    return math.radians(a)

def mix(f, u, s=0.0, sd=None):
    v = fwd * f + up * u
    if sd is not None:
        v += sd * s
    return v

# Tułów lekko odchylony (oparcie fotela ~15°).
for b in ["spine", "chest"]:
    aim(b, up * math.cos(deg(15)) - fwd * math.sin(deg(15)))
aim("neck", up * math.cos(deg(5)) - fwd * math.sin(deg(5)))
aim("head", up)
for s, sd in (("L", side_l), ("R", -side_l)):
    # Pozycja w aucie (nisko, nogi wyciągnięte do pedałów): uda do przodu
    # z kolanami lekko w górę, łydki pochyło w przód - stopy ~0,3 m pod
    # biodrami, a nie 0,5 jak na krześle (wystawały spod podłogi auta).
    aim("thigh." + s, mix(1.0, 0.12, 0.12, sd))
    aim("shin." + s, mix(0.9, -0.55, 0.05, sd))
    aim("foot." + s, mix(0.6, -0.8))
    # Ręce do kierownicy: ramię w przód i w dół, przedramię w przód i do środka.
    aim("upper_arm." + s, mix(0.75, -0.55, 0.15, sd))
    # Dłonie na kierownicy ~0,38 m: na "za dziesięć druga", ~0,18 m od osi.
    aim("forearm." + s, mix(1.0, 0.3, -0.12, sd))
    aim("hand." + s, mix(1.0, 0.15, -0.02, sd))

# Punkt zero: biodra (głowa kości hips) w pozie - do posadzenia na fotelu.
hips_pos = arm.matrix_world @ pb["hips"].head
bpy.ops.object.mode_set(mode="OBJECT")

if out_glb.endswith(".glb"):
    # Manekin gracza ze szkieletem (użytkownik 2026-11-12: "fajnie by było,
    # gdyby gracz był tym manekinem ... a nie tylko dłonie"): poza siedząca
    # staje się pozą spoczynkową (gra rusza tylko ramionami - IK - i prawą
    # stopą), skala 1,75 m, zero w biodrach, tekstura manekina.
    import os
    k = 1.75 / 3.268
    bpy.context.view_layer.objects.active = man
    for o in bpy.context.scene.objects:
        o.select_set(False)
    man.select_set(True)
    mod = [m for m in man.modifiers if m.type == "ARMATURE"][0]
    bpy.ops.object.modifier_copy(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)          # siatka w pozie
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)               # poza = spoczynek
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in list(bpy.data.objects):
        if o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o)
    # Zero w biodrach i skala - na obu obiektach naraz, potem zastosowane.
    for o in (arm, man):
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    arm.location = -hips_pos * k
    arm.scale = (k, k, k)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    man.matrix_parent_inverse.identity()
    mat = bpy.data.materials.new("dummy")
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(tex_path)
    mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    man.data.materials.clear()
    man.data.materials.append(mat)
    for p in man.data.polygons:
        p.material_index = 0
    bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB", export_skins=True,
            export_animations=False, use_selection=False, export_yup=True)
    print("ZAPISANO", out_glb)
    sys.exit(0)

# Wypiekanie pozy: zastosuj modyfikator armatury.
bpy.context.view_layer.objects.active = man
man.select_set(True)
for m in list(man.modifiers):
    if m.type == "ARMATURE":
        bpy.ops.object.modifier_apply(modifier=m.name)
man.parent = None
bpy.data.objects.remove(arm)
for o in list(bpy.data.objects):
    if o.type in ("CAMERA", "LIGHT"):
        bpy.data.objects.remove(o)
man.vertex_groups.clear()

# Skala: wysokość w pozie T 3,268 j. -> 1,75 m. Zero w biodrach.
me = man.data
k = 1.75 / 3.268
for v in me.vertices:
    v.co *= k
man.data.update()
for v in me.vertices:
    v.co -= hips_pos * k
man.data.update()
bpy.context.view_layer.update()
xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
print("ROZMIAR [m] x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))

# Materiał: tekstura manekina (Blender Internal z 2.78 nie ma węzłów).
mat = bpy.data.materials.new("dummy")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes.get("Principled BSDF")
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(tex_path)
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.6
me.materials.clear()
me.materials.append(mat)
for p in me.polygons:
    p.material_index = 0

print("SKALA OBIEKTU", tuple(man.scale), "OBRÓT", tuple(man.rotation_euler))
# OBJ (eksporter glTF w Blenderze z Debiana wymaga numpy, którego nie ma;
# modele aut też są w OBJ). Godot: -Z przód (stopy manekina w -Z), Y góra.
bpy.ops.wm.obj_export(filepath=out_glb, export_selected_objects=False, apply_modifiers=True,
        forward_axis="Z", up_axis="Y", export_materials=True, path_mode="STRIP",
        export_triangulated_mesh=True)
print("ZAPISANO", out_glb, "trójkątów", sum(len(p.vertices) - 2 for p in me.polygons))
# Tekstura w repo nazywa się dummy_texture.png (obok OBJ).
mtl = out_glb[:-4] + ".mtl"
with open(mtl) as fh:
    lines = ["map_Kd dummy_texture.png\n" if l.startswith("map_Kd") else l for l in fh]
with open(mtl, "w") as fh:
    fh.writelines(lines)

if preview:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = 900
    sc.render.resolution_y = 500
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.2
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x = 600
    sc.render.resolution_y = 600
    # Dwa rzuty: z boku (lewa strona postaci) i z przodu.
    for name, pos in (("bok", side_l * 5.0), ("przod", fwd * 5.0)):
        cam.location = pos + up * 0.3
        d = (Vector((0, 0, 0.3)) - cam.location)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = preview.replace(".png", "_" + name + ".png")
        bpy.ops.render.render(write_still=True)
