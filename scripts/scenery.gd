extends RefCounted
class_name Scenery

## Otoczenie toru: drzewa i głazy jako MultiMesh (tysiące obiektów
## w kilku wywołaniach rysowania - na Queście to ma znaczenie) oraz góry
## na horyzoncie. Siatki low-poly z płaskim cieniowaniem i kolorami
## wierzchołków - kanciaste z wyboru, nie z ograniczenia.
##
## W VR otoczenie to nie tylko wygląd: bez punktów odniesienia przy ziemi
## nie czuć ani prędkości, ani wysokości, na której wisi tor.

static var _meshes := {}


## Wspólny materiał: kolor z wierzchołków (i z instancji MultiMesh).
static func _vc_material() -> StandardMaterial3D:
	if not _meshes.has("mat"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		_meshes["mat"] = m
	return _meshes["mat"]


## Stożek / walec (n boków) od y0 do y1, promienie r0 -> r1, kolor c.
static func _cone(st: SurfaceTool, n: int, y0: float, y1: float, r0: float, r1: float, c: Color, rot := 0.0) -> void:
	st.set_color(c)
	for i in range(n):
		var a0 := TAU * i / n + rot
		var a1 := TAU * (i + 1) / n + rot
		var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		# Ściana boczna (zgodnie z ruchem wskazówek zegara patrząc z zewnątrz).
		st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
		# Spód.
		st.add_vertex(Vector3(0, y0, 0)); st.add_vertex(p00); st.add_vertex(p01)
		if r1 > 0.001:
			st.add_vertex(Vector3(0, y1, 0)); st.add_vertex(p11); st.add_vertex(p10)


## Drzewo iglaste: pień i trzy stożki igliwia, każdy lekko obrócony.
static func conifer() -> Mesh:
	if not _meshes.has("conifer"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_cone(st, 6, 0.0, 2.2, 0.28, 0.2, Color(0.33, 0.22, 0.13))
		var g := Color(0.16, 0.32, 0.17)
		_cone(st, 7, 1.6, 5.2, 2.2, 0.0, g, 0.0)
		_cone(st, 7, 3.4, 6.8, 1.7, 0.0, g.lightened(0.08), 0.4)
		_cone(st, 7, 5.0, 8.4, 1.15, 0.0, g.lightened(0.15), 0.9)
		st.generate_normals()
		st.set_material(_vc_material())
		_meshes["conifer"] = st.commit()
	return _meshes["conifer"]


## Drzewo liściaste: pień i bryła korony z dwóch ściętych ostrosłupów.
static func broadleaf() -> Mesh:
	if not _meshes.has("broadleaf"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_cone(st, 6, 0.0, 3.0, 0.3, 0.22, Color(0.36, 0.25, 0.15))
		var g := Color(0.28, 0.42, 0.16)
		_cone(st, 8, 2.4, 4.6, 1.2, 2.8, g, 0.2)
		_cone(st, 8, 4.6, 7.0, 2.8, 0.6, g.lightened(0.1), 0.2)
		st.generate_normals()
		st.set_material(_vc_material())
		_meshes["broadleaf"] = st.commit()
	return _meshes["broadleaf"]


## Głaz: nieregularny wielościan (zniekształcony ośmiościan podzielony raz).
static func rock() -> Mesh:
	if not _meshes.has("rock"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_color(Color(0.5, 0.49, 0.46))
		var v := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0.8, 0), Vector3(0, -0.3, 0),
				Vector3(0, 0, 1), Vector3(0, 0, -1)]
		var jitter := [Vector3(0.1, 0.05, 0.0), Vector3(-0.15, 0.1, 0.1), Vector3(0.1, 0.0, -0.1),
				Vector3(0, 0, 0), Vector3(0.1, 0.12, 0.05), Vector3(-0.05, 0.08, -0.15)]
		for i in range(6):
			v[i] += jitter[i]
		var faces := [[2, 0, 4], [2, 4, 1], [2, 1, 5], [2, 5, 0], [3, 4, 0], [3, 1, 4], [3, 5, 1], [3, 0, 5]]
		for f in faces:
			# Kolejność zgodna z ruchem wskazówek zegara patrząc z zewnątrz.
			st.add_vertex(v[f[0]]); st.add_vertex(v[f[2]]); st.add_vertex(v[f[1]])
		st.generate_normals()
		st.set_material(_vc_material())
		_meshes["rock"] = st.commit()
	return _meshes["rock"]


## Rozrzuca drzewa i głazy wzdłuż toru (próbki w układzie toru). Zwraca
## węzły do dodania jako dzieci toru. Nic nie stoi bliżej niż `clear` od
## osi toru - ani pod jezdnią, ani przy filarach.
static func scatter(samples: Array, rng: RandomNumberGenerator, clear := 16.0) -> Array:
	var kinds := {"conifer": [], "broadleaf": [], "rock": []}
	var step := 3
	for i in range(0, samples.size(), step):
		var s: Dictionary = samples[i]
		var pos: Vector3 = s["pos"]
		var right: Vector3 = s["right"] * Vector3(1, 0, 1)
		if right.length() < 0.1:
			continue
		right = right.normalized()
		for side in [-1.0, 1.0]:
			if rng.randf() > 0.55:
				continue
			# Gęściej blisko toru, rzadziej dalej (rozkład kwadratowy).
			var lat := clear + pow(rng.randf(), 2.0) * 220.0
			var p: Vector3 = Vector3(pos.x, 0.0, pos.z) + right * side * lat \
					+ Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
			if _too_close(samples, p, clear):
				continue
			var r := rng.randf()
			var kind := "conifer" if r < 0.5 else ("broadleaf" if r < 0.85 else "rock")
			var sc := rng.randf_range(0.7, 1.5) if kind != "rock" else rng.randf_range(0.6, 2.4)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.2), sc)), p)
			var tint := Color.from_hsv(rng.randf_range(-0.03, 0.04), 0.0, rng.randf_range(0.8, 1.15))
			kinds[kind].append([xf, tint])
	var out := []
	for kind in kinds:
		var items: Array = kinds[kind]
		if items.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = conifer() if kind == "conifer" else (broadleaf() if kind == "broadleaf" else rock())
		mm.instance_count = items.size()
		for j in range(items.size()):
			mm.set_instance_transform(j, items[j][0])
			# Kolor instancji mnoży kolor wierzchołka - drobna różnorodność.
			var t: Color = items[j][1]
			mm.set_instance_color(j, Color(t.v, t.v, t.v * 0.95))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scenery_" + kind
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(mmi)
	return out


static func _too_close(samples: Array, p: Vector3, clear: float) -> bool:
	var c2 := clear * clear
	for i in range(0, samples.size(), 4):
		var q: Vector3 = samples[i]["pos"]
		var d := Vector2(q.x - p.x, q.z - p.z)
		if d.length_squared() < c2:
			return true
	return false


## Pierścień gór na horyzoncie (promień ~1,5-2,5 km). Jeden węzeł; scena
## jazdy przesuwa go za autem w poziomie, jak tło.
static func horizon(rng: RandomNumberGenerator) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 36
	for i in range(n):
		var a := TAU * i / n + rng.randf_range(-0.05, 0.05)
		var dist := rng.randf_range(1500.0, 2500.0)
		var h := rng.randf_range(120.0, 420.0)
		var r := rng.randf_range(250.0, 520.0)
		var c := Vector3(cos(a) * dist, -10.0, sin(a) * dist)
		var rock_c := Color(0.38, 0.42, 0.38).lerp(Color(0.45, 0.43, 0.4), rng.randf())
		var sides := 6
		var rot := rng.randf() * TAU
		var tip := c + Vector3(rng.randf_range(-40, 40), h, rng.randf_range(-40, 40))
		for k in range(sides):
			var a0 := TAU * k / sides + rot
			var a1 := TAU * (k + 1) / sides + rot
			var p0 := c + Vector3(cos(a0) * r, 0, sin(a0) * r)
			var p1 := c + Vector3(cos(a1) * r, 0, sin(a1) * r)
			# Śnieg na wysokich szczytach: górna część ściany jasna.
			var mid0 := p0.lerp(tip, 0.72)
			var mid1 := p1.lerp(tip, 0.72)
			st.set_color(rock_c)
			st.add_vertex(p0); st.add_vertex(mid0); st.add_vertex(mid1)
			st.add_vertex(p0); st.add_vertex(mid1); st.add_vertex(p1)
			st.set_color(Color(0.92, 0.93, 0.95) if h > 300.0 else rock_c.lightened(0.1))
			st.add_vertex(mid0); st.add_vertex(tip); st.add_vertex(mid1)
	st.generate_normals()
	st.set_material(_vc_material())
	var mi := MeshInstance3D.new()
	mi.name = "Horizon"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
