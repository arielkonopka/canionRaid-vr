"""Dłonie manekina na kontrolery (Blender, bez okna):
  blender -b CrashTestDummy_UnityMecanim.blend -P tools/prepare_dummy_hands.py -- KATALOG_WYJŚCIA [podgląd.png]

Użytkownik 2026-11-12: "chciałbym dłonie w powietrzu, jako alternatywne
sterowanie" (gracz też jest manekinem - żółte dłonie). Z tego samego modelu
co tools/prepare_dummy.py: palce zgięte w chwyt (kierownica / rękojeść
kontrolera), dłoń wycięta (kości hand / palm / f_* / thumb), w układzie
kontrolera Godota: -Z = od nadgarstka do kłykci, +Y = strona kciuka,
zero w środku dłoni. Zapis: dummy_hand_L.obj, dummy_hand_R.obj (+ .mtl,
tekstura dummy_texture.png obok).
"""
import bpy, sys, math, os
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
out_dir = args[0]
preview = args[1] if len(args) > 1 else ""
K = 1.75 / 3.268                         # skala jak w prepare_dummy.py

arm = bpy.data.objects["metarig"]
man = bpy.data.objects["man"]
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
pb = arm.pose.bones


def upd():
    bpy.context.view_layer.update()


def hand_frame(s):
    h = pb["hand." + s]
    # Od nadgarstka do kłykcia środkowego palca (sama kość "hand" jest krótka
    # i odchylona - dłoń wychodziła skierowana w dół).
    fwd = (pb["f_middle.01." + s].head - h.head).normalized()
    th = pb["thumb.02." + s].tail - h.head
    thumb = (th - fwd * th.dot(fwd)).normalized()
    return h.head.copy(), h.tail.copy(), fwd, thumb


def curl(bone, deg, palm_dir):
    """Zgina kość wokół jej lokalnej osi X w tę stronę, w którą leży wnętrze
    dłoni (znak sprawdzany ruchem końca kości)."""
    b = pb[bone]
    for sign in (1.0, -1.0):
        b.rotation_mode = "XYZ"
        b.rotation_euler = (math.radians(deg) * sign, 0.0, 0.0)
        upd()
        moved = (b.tail - b.head).dot(palm_dir)
        b0 = b.rotation_euler.copy()
        b.rotation_euler = (0.0, 0.0, 0.0)
        upd()
        rest = (b.tail - b.head).dot(palm_dir)
        if moved > rest:
            b.rotation_euler = b0
            upd()
            return


for s in ("L", "R"):
    _, _, fwd, thumb = hand_frame(s)
    # Wnętrze dłoni: od grzbietu w stronę kciuka i trochę w bok - tu kciuk
    # leży z przodu dłoni, więc palce zginamy w jego stronę.
    palm = thumb
    for f in ("f_index", "f_middle", "f_ring", "f_pinky"):
        for i, a in ((1, 55.0), (2, 65.0), (3, 45.0)):
            n = "%s.0%d.%s" % (f, i, s)
            if n in pb:
                curl(n, a, palm)
    for i, a in ((2, 25.0), (3, 25.0)):
        n = "thumb.0%d.%s" % (i, s)
        if n in pb:
            curl(n, a, -fwd)

frames = {s: hand_frame(s) for s in ("L", "R")}
pb_knuckle = {s: pb["f_middle.01." + s].head.copy() for s in ("L", "R")}
bpy.ops.object.mode_set(mode="OBJECT")

# Wierzchołki dłoni - zanim modyfikator zostanie zastosowany (grupy zostają).
hand_groups = {}
for g in man.vertex_groups:
    n = g.name
    side = n[-1]
    base = n.split(".")[0]
    if side in "LR" and (base in ("hand", "thumb") or base.startswith("palm") or base.startswith("f_")):
        hand_groups[g.index] = side

bpy.context.view_layer.objects.active = man
man.select_set(True)
for m in list(man.modifiers):
    if m.type == "ARMATURE":
        bpy.ops.object.modifier_apply(modifier=m.name)

me = man.data
side_of = {}
for v in me.vertices:
    best, bw = None, 0.0
    for ge in v.groups:
        if ge.weight > bw:
            best, bw = ge.group, ge.weight
    if best in hand_groups:
        side_of[v.index] = hand_groups[best]

mat = bpy.data.materials.new("dummy")
mat.use_nodes = True
tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(os.path.join(os.path.dirname(bpy.data.filepath), "man_neutral_Texture1.png"))
mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])

import bmesh
uv_layer = me.uv_layers.active.data
for s in ("L", "R"):
    head, tail, fwd, thumb = frames[s]
    origin = (head + pb_knuckle[s]) * 0.5     # środek dłoni
    z = -fwd
    y = thumb
    x = y.cross(z).normalized()
    y = z.cross(x).normalized()
    inv = Matrix((x, y, z))              # wiersze = osie: lokalne = inv @ (p - origin)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    vmap = {}
    for p in me.polygons:
        if not all(side_of.get(vi) == s for vi in p.vertices):
            continue
        vs = []
        for vi in p.vertices:
            if vi not in vmap:
                vmap[vi] = bm.verts.new(inv @ (me.vertices[vi].co - origin) * K)
            vs.append(vmap[vi])
        try:
            face = bm.faces.new(vs)
        except ValueError:
            continue
        for loop, li in zip(face.loops, p.loop_indices):
            loop[uv].uv = uv_layer[li].uv
    nm = bpy.data.meshes.new("hand_" + s)
    bm.to_mesh(nm)
    bm.free()
    nm.materials.append(mat)
    ob = bpy.data.objects.new("dummy_hand_" + s, nm)
    bpy.context.scene.collection.objects.link(ob)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(out_dir, "dummy_hand_%s.obj" % s)
    bpy.ops.wm.obj_export(filepath=path, export_selected_objects=True, forward_axis="NEGATIVE_Z",
            up_axis="Y", export_materials=True, path_mode="STRIP", export_triangulated_mesh=True)
    with open(path[:-4] + ".mtl") as fh:
        lines = ["map_Kd dummy_texture.png\n" if l.startswith("map_Kd") else l for l in fh]
    with open(path[:-4] + ".mtl", "w") as fh:
        fh.writelines(lines)
    print("ZAPISANO", path, "ścian", len(nm.polygons), "wymiary", tuple(round(d, 3) for d in ob.dimensions))
