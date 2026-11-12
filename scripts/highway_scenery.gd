extends RefCounted
class_name HighwayScenery

## Zabudowa miast i obiekty przy drodze trybu "Autostrada" jako MultiMesh
## (jak Scenery): jedno wywołanie rysowania na rodzaj obiektu w kawałku
## trasy, setki-tysiące instancji. Siatki low-poly z kolorami wierzchołków;
## budynki z proceduralnymi oknami (shaders/facade.gdshader).
##
## Wejście: próbki kawałka (StuntTrack._samples, układ węzła kawałka) i plan
## (HighwayPlan). Wyjście: lista węzłów do `_adopt` w kawałku - kawałek
## buduje je w kolejnych klatkach (slice_build), a znika razem z nimi.
##
##   HighwayScenery.build(samples, plan, rng, edges) -> Array[Node3D]
##
## `edges` = Vector2(lewa, prawa) krawędź asfaltu [m od osi naszej jezdni]:
## prawa = +szerokość/2, lewa = zewnętrzna krawędź jezdni z naprzeciwka
## (StuntTrack._build_highway: przesunięcie o szerokość + HIGHWAY_MEDIAN).
## Moduł odizolowany: nic go jeszcze nie używa (wpina agent lokalny).

## Palety ziemi biomów (ground.gdshader): trawa A, trawa B, ziemia/odmiana,
## pasy pól. Używa xr_main (teren za autem) i StuntTrack (pobocza, pas
## rozdziału - na pustyni nie zielona trawa, przegląd renderów).
const BIOME_GROUND := {
	"meadow": [Color(0.27, 0.40, 0.18), Color(0.42, 0.47, 0.22), Color(0.42, 0.36, 0.25), 0.0],
	"fields": [Color(0.62, 0.54, 0.25), Color(0.40, 0.46, 0.20), Color(0.36, 0.28, 0.18), 1.0],
	"desert": [Color(0.80, 0.68, 0.47), Color(0.72, 0.58, 0.38), Color(0.62, 0.48, 0.32), 0.0],
	"mountains": [Color(0.30, 0.36, 0.24), Color(0.42, 0.42, 0.36), Color(0.48, 0.46, 0.42), 0.0],
	"seaside": [Color(0.40, 0.48, 0.25), Color(0.62, 0.60, 0.42), Color(0.80, 0.74, 0.56), 0.0],
	"canyon": [Color(0.55, 0.36, 0.22), Color(0.62, 0.44, 0.28), Color(0.46, 0.30, 0.20), 0.0],
}

const SIDEWALK := 3.5            # chodnik od krawędzi asfaltu [m]
## Utwardzony pas od krawędzi asfaltu do budynków (chodnik + cofnięcie +
## zapas) - jezdnia stoi 1 m nad terenem, bez tego między chodnikiem
## a budynkiem byłby rów.
const CURB_H := 0.15
## Budynki: front od chodnika (cofnięcie) i wymiary [m].
const SETBACK := Vector2(1.0, 6.0)
const FRONT_SMALL := Vector2(9.0, 18.0)
const FRONT_BIG := Vector2(14.0, 34.0)
const DEPTH := Vector2(9.0, 18.0)
const HEIGHT_SMALL := Vector2(5.5, 12.0)     # 2-4 kondygnacje
const HEIGHT_BIG := Vector2(9.0, 45.0)       # wyżej w środku dużego miasta
const GAP := Vector2(0.0, 5.0)
const PLAZA := SIDEWALK + 6.0 + 1.0     # SIDEWALK + SETBACK.y + zapas
const STREET_EVERY := Vector2(90.0, 160.0)   # przerwa "przecznica" (bez jezdni)
const STREET_W := 12.0
## Drugi rząd zabudowy (tylko duże miasto) - za pierwszym, bez kolizji.
const BACK_ROW_GAP := 8.0
## Kolizja: tylko pierwszy rząd (w zasięgu auta), pudła.
const LAMP_EVERY := 35.0
const POST_OFFSET := 1.2         # słupek od krawędzi asfaltu [m]
const NOISE_WALL_NEAR_CITY := 1500.0   # ekrany akustyczne do tylu m od zabudowy
const NOISE_WALL_OFFSET := 6.0
const NOISE_WALL_PANEL := 4.0
## Dalej niż tyle od kamery nie rysujemy (Quest) [m].
const VIS_BUILDINGS := 1800.0
const VIS_PROPS := 450.0
const VIS_FAR := 3000.0

const PLASTER := [Color(0.86, 0.82, 0.74), Color(0.78, 0.74, 0.66), Color(0.9, 0.88, 0.84),
		Color(0.72, 0.62, 0.52), Color(0.82, 0.76, 0.62), Color(0.66, 0.68, 0.7),
		Color(0.62, 0.42, 0.34)]

static var _cache := {}


## Krawędzie asfaltu dla jezdni szerokości `width` i pasa rozdziału `median`
## (jak StuntTrack._build_highway: druga jezdnia przesunięta w lewo
## o width + median).
static func edges_for(width: float, median := TrackGenerator.HIGHWAY_MEDIAN) -> Vector2:
	return Vector2(-(1.5 * width + median), 0.5 * width)


# --------------------------------------------------------------------------
# Budowa
# --------------------------------------------------------------------------

static func build(samples: Array, plan: HighwayPlan, rng: RandomNumberGenerator, edges: Vector2) -> Array:
	var out := []
	if samples.size() < 2:
		return out
	var d0 := float(samples[0]["dist"])
	var d1 := float(samples[-1]["dist"])
	var kinds := {}          # rodzaj -> [[Transform3D, Color], ...]
	var boxes := []          # kolizja pierwszego rzędu: [Transform3D, Vector3 rozmiar]
	for c in plan.cities_between(d0, d1):
		for side in [-1, 1]:
			_city_side(samples, c, side, edges, d0, d1, rng, kinds, boxes)
		out.append(_sidewalks(samples, maxf(float(c["start"]), d0), minf(float(c["end"]), d1), edges))
	_posts(samples, plan, edges, d0, d1, kinds)
	_noise_walls(samples, plan, edges, d0, d1, kinds)
	_biome_props(samples, plan, edges, d0, d1, rng, kinds)
	for kind in kinds:
		out.append(_multimesh(kind, kinds[kind]))
	if not boxes.is_empty():
		out.append(_collision(boxes))
	for p in plan.posts_between(d0, d1):
		if p["major"]:
			out.append(_km_label(samples, float(p["dist"]), edges.y + POST_OFFSET, int(p["km"])))
	return out


## Jedna strona ulicy w mieście: pierwszy rząd (z kolizją), w dużym mieście
## drugi rząd wyższych budynków.
static func _city_side(samples: Array, c: Dictionary, side: int, edges: Vector2, d0: float, d1: float,
		rng: RandomNumberGenerator, kinds: Dictionary, boxes: Array) -> void:
	var big: bool = c["big"]
	var front := FRONT_BIG if big else FRONT_SMALL
	var hrange := HEIGHT_BIG if big else HEIGHT_SMALL
	var edge := edges.y if side > 0 else -edges.x
	var a := maxf(float(c["start"]), d0)
	var b := minf(float(c["end"]), d1)
	var mid := (float(c["start"]) + float(c["end"])) * 0.5
	var half := (float(c["end"]) - float(c["start"])) * 0.5
	var d := a + rng.randf_range(0.0, 6.0)
	var next_street := d + rng.randf_range(STREET_EVERY.x, STREET_EVERY.y)
	while d < b:
		var w := rng.randf_range(front.x, front.y)
		if d + w > b:
			break
		if d > next_street:
			d += STREET_W
			next_street = d + rng.randf_range(STREET_EVERY.x, STREET_EVERY.y)
			continue
		# Wyżej w środku miasta (duże miasto: "centrum").
		var center := 1.0 - clampf(absf(d + w * 0.5 - mid) / maxf(half, 1.0), 0.0, 1.0)
		var h := lerpf(hrange.x, hrange.y, clampf(rng.randf() * 0.6 + center * 0.5, 0.0, 1.0)) if big \
				else rng.randf_range(hrange.x, hrange.y)
		var depth := rng.randf_range(DEPTH.x, DEPTH.y)
		var setback := rng.randf_range(SETBACK.x, SETBACK.y)
		var lat := (edge + SIDEWALK + setback + depth * 0.5) * side
		var xf := _box_xf(samples, d + w * 0.5, lat, Vector3(w, h, depth))
		var col: Color = PLASTER[rng.randi() % PLASTER.size()]
		_add(kinds, "building", xf, col.lerp(Color.WHITE, rng.randf_range(-0.05, 0.1)))
		boxes.append([xf, Vector3(w, h, depth)])
		if big:
			var h2 := h * rng.randf_range(1.0, 1.6)
			var dep2 := rng.randf_range(DEPTH.x, DEPTH.y * 1.4)
			var lat2 := (edge + SIDEWALK + setback + depth + BACK_ROW_GAP + dep2 * 0.5) * side
			_add(kinds, "building", _box_xf(samples, d + w * 0.5, lat2, Vector3(w, h2, dep2)),
					PLASTER[rng.randi() % PLASTER.size()])
		# Latarnie co LAMP_EVERY po obu stronach (osobna pętla niżej byłaby
		# prostsza, ale tu i tak idziemy po froncie).
		d += w + rng.randf_range(GAP.x, GAP.y)
	var ld := ceilf(a / LAMP_EVERY) * LAMP_EVERY
	while ld < b:
		_add(kinds, "lamp", _upright_xf(samples, ld, (edge + 0.6) * side, side), Color.WHITE)
		ld += LAMP_EVERY


## Transformacja pudła (jednostkowe, podstawa w y = 0) stojącego na
## ziemi (y = 0) w punkcie dystans `d`, przesunięcie w bok `lat`.
static func _box_xf(samples: Array, d: float, lat: float, size: Vector3) -> Transform3D:
	var fr := frame_at(samples, d)
	var right: Vector3 = (fr["right"] as Vector3) * Vector3(1, 0, 1)
	right = right.normalized()
	var fwd := Vector3.UP.cross(right).normalized()
	var p: Vector3 = (fr["pos"] as Vector3) + right * lat
	p.y = 0.0
	var basis := Basis(right * size.x, Vector3.UP * size.y, -fwd * size.z)
	return Transform3D(basis, p)


## Obiekt pionowy (słupek, latarnia) bez skalowania, obrócony przodem do
## jezdni (`side` = strona: lewa -1, prawa +1).
static func _upright_xf(samples: Array, d: float, lat: float, side: int, y := -1.0) -> Transform3D:
	var fr := frame_at(samples, d)
	var right: Vector3 = ((fr["right"] as Vector3) * Vector3(1, 0, 1)).normalized()
	var p: Vector3 = (fr["pos"] as Vector3) + right * lat
	if y >= 0.0:
		p.y = y
	# Lokalne +X siatki patrzy w stronę jezdni.
	var x_axis := -right * float(side)
	return Transform3D(Basis(x_axis, Vector3.UP, x_axis.cross(Vector3.UP)), p)


static func _add(kinds: Dictionary, kind: String, xf: Transform3D, col: Color) -> void:
	if not kinds.has(kind):
		kinds[kind] = []
	kinds[kind].append([xf, col])


## Słupki hektometrowe (co 100 m) i kilometrowe (co 1 km, z tablicą) - po
## prawej, za krawędzią asfaltu; na jezdni z naprzeciwka lustrzanie.
static func _posts(samples: Array, plan: HighwayPlan, edges: Vector2, d0: float, d1: float, kinds: Dictionary) -> void:
	for p in plan.posts_between(d0, d1):
		var d: float = p["dist"]
		if not plan.city_at(d).is_empty():
			continue
		var kind := "km_post" if p["major"] else "hm_post"
		_add(kinds, kind, _upright_xf(samples, d, edges.y + POST_OFFSET, 1), Color.WHITE)
		_add(kinds, kind, _upright_xf(samples, d, edges.x - POST_OFFSET, -1), Color.WHITE)


## Ekrany akustyczne przy podjeździe do miast (obie strony, panele 4 m).
static func _noise_walls(samples: Array, plan: HighwayPlan, edges: Vector2, d0: float, d1: float, kinds: Dictionary) -> void:
	var d := ceilf(d0 / NOISE_WALL_PANEL) * NOISE_WALL_PANEL
	while d < d1:
		var nc := plan.nearest_city(d)
		if not nc["city"].is_empty() and float(nc["gap"]) > 0.0 and float(nc["gap"]) < NOISE_WALL_NEAR_CITY:
			_add(kinds, "noise_wall", _upright_xf(samples, d, edges.y + NOISE_WALL_OFFSET, 1, 0.0), Color.WHITE)
			_add(kinds, "noise_wall", _upright_xf(samples, d, edges.x - NOISE_WALL_OFFSET, -1, 0.0), Color.WHITE)
		d += NOISE_WALL_PANEL


## Obiekty biomu poza miastami (rozrzut jak Scenery.scatter, ale rodzaj
## z biomu; na przejściu losowo z obu).
const BIOME_PROPS := {
	"fields": [["turbine", 0.01, 180.0, 700.0], ["broadleaf", 0.25, 25.0, 250.0], ["bush", 0.3, 15.0, 120.0]],
	"meadow": [["broadleaf", 0.45, 20.0, 220.0], ["conifer", 0.2, 30.0, 250.0], ["bush", 0.4, 14.0, 120.0]],
	"desert": [["cactus", 0.35, 14.0, 200.0], ["rock", 0.35, 18.0, 260.0], ["bush", 0.1, 14.0, 100.0]],
	"mountains": [["conifer", 0.7, 16.0, 260.0], ["rock", 0.3, 16.0, 220.0]],
	"seaside": [["palm", 0.35, 14.0, 120.0], ["bush", 0.3, 14.0, 90.0], ["rock", 0.1, 14.0, 80.0]],
	"canyon": [["rock", 0.5, 16.0, 200.0], ["bush", 0.2, 14.0, 80.0]],
}
const PROP_STEP := 6.0           # co tyle metrów losujemy obiekty po obu stronach


static func _biome_props(samples: Array, plan: HighwayPlan, edges: Vector2, d0: float, d1: float,
		rng: RandomNumberGenerator, kinds: Dictionary) -> void:
	var d := d0
	while d < d1:
		d += PROP_STEP
		if not plan.city_at(d).is_empty():
			continue
		var bl := plan.biome_blend(d)
		var biome: String = bl["b"] if rng.randf() < float(bl["t"]) else bl["a"]
		# Nad morzem obiekty tylko po prawej - z lewej (za jezdnią
		# z naprzeciwka) jest woda (xr_main._update_biome).
		for side in ([1] if biome == "seaside" else [-1, 1]):
			var edge := edges.y if side > 0 else -edges.x
			for entry in BIOME_PROPS.get(biome, []):
				if rng.randf() > float(entry[1]) * PROP_STEP / 6.0 * 0.5:
					continue
				var lat: float = edge + float(entry[2]) + pow(rng.randf(), 1.6) * (float(entry[3]) - float(entry[2]))
				var fr := frame_at(samples, d + rng.randf_range(-3.0, 3.0))
				var right: Vector3 = ((fr["right"] as Vector3) * Vector3(1, 0, 1)).normalized()
				var p: Vector3 = (fr["pos"] as Vector3) + right * lat * float(side)
				p.y = 0.0
				var kind: String = entry[0]
				var sc := rng.randf_range(0.7, 1.4)
				if kind == "rock":
					sc = rng.randf_range(0.6, 2.6)
				elif kind == "turbine":
					sc = rng.randf_range(0.9, 1.1)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.2), sc)), p)
				var v := rng.randf_range(0.82, 1.12)
				_add(kinds, kind, xf, Color(v, v, v * 0.96))


# --------------------------------------------------------------------------
# Węzły
# --------------------------------------------------------------------------

static func _multimesh(kind: String, items: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh(kind)
	mm.instance_count = items.size()
	for j in range(items.size()):
		mm.set_instance_transform(j, items[j][0])
		mm.set_instance_color(j, items[j][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Hwy_" + kind
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		"building", "turbine":
			mmi.visibility_range_end = VIS_FAR if kind == "turbine" else VIS_BUILDINGS
		"conifer", "broadleaf", "rock", "palm", "cactus":
			mmi.visibility_range_end = VIS_BUILDINGS
		_:
			mmi.visibility_range_end = VIS_PROPS
	if kind == "building":
		mmi.material_override = _facade_material()
		# Kopia transformacji dla testów: w trybie headless (atrapa
		# renderera) MultiMesh.get_instance_transform zwraca zawsze
		# Transform3D() - highway_gen_test widział "budynki na jezdni".
		if DisplayServer.get_name() == "headless":
			var xs: Array[Transform3D] = []
			for it in items:
				xs.append(it[0])
			mmi.set_meta("xforms", xs)
	return mmi


## Kolizja pierwszego rzędu zabudowy: jedno ciało, pudła.
static func _collision(boxes: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "HwyBuildingsCollision"
	for b in boxes:
		var xf: Transform3D = b[0]
		var size: Vector3 = b[1]
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		# Pudło siatki ma podstawę w y = 0 i skalę w bazie - kształt bez skali.
		cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * size.y * 0.5)
		body.add_child(cs)
	return body


## Chodniki z krawężnikiem po obu stronach w mieście [a, b): bryła od ziemi
## (y = 0) do jezdni + CURB_H, z kolizją (krawężnik ma czuć się w kołach).
static func _sidewalks(samples: Array, a: float, b: float, edges: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "HwySidewalks"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)
	# Szary beton jak bariera środkowa (był prawie biały, przegląd renderów).
	st.set_color(Color(0.42, 0.42, 0.41))
	var faces := PackedVector3Array()
	var prev := {}
	var d := a
	while true:
		var fr := frame_at(samples, d)
		var right: Vector3 = ((fr["right"] as Vector3) * Vector3(1, 0, 1)).normalized()
		var p: Vector3 = fr["pos"]
		var top := p.y + CURB_H
		var cur := {}
		for side in [-1, 1]:
			var e0 := (edges.y if side > 0 else -edges.x) * float(side)
			# e0, e1: odległość ze znakiem (lewa strona ujemna).
			var e1 := e0 + PLAZA * float(side)
			var q0 := Vector3(p.x, 0.0, p.z) + right * e0
			var q1 := Vector3(p.x, 0.0, p.z) + right * e1
			cur[side] = [q0 + Vector3.UP * top, q1 + Vector3.UP * top, q0, q1]
		if not prev.is_empty():
			for side in [-1, 1]:
				var A: Array = prev[side]
				var B: Array = cur[side]
				# Wierzch chodnika i lico krawężnika (od jezdni).
				_quad(st, faces, A[0], B[0], B[1], A[1], side)
				_quad(st, faces, A[2] + Vector3.UP * (p.y - 0.05), B[2] + Vector3.UP * (p.y - 0.05), B[0], A[0], side)
				# Zewnętrzna ściana pasa, do ziemi (odwrotna orientacja).
				_quad(st, faces, A[3], B[3], B[1], A[1], -side)
		prev = cur
		if d >= b:
			break
		d = minf(d + 4.0, b)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Scenery._vc_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	return root


## Czworokąt a-b-c-d (dwa trójkąty); kolejność zależna od strony, żeby
## ściany patrzyły na zewnątrz (dla prawej strony jak w Scenery._cone).
static func _quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, side: int) -> void:
	# Odwrócone względem pierwszej wersji (jak w _box): Godot - przód zgodnie
	# z ruchem wskazówek zegara; wcześniej wierzch chodnika był odrzucany,
	# a widać było tylko ściany (ciemne kliny przy budynkach na renderach).
	var tri := [a, c, b, a, d, c] if side < 0 else [a, b, c, a, c, d]
	for v in tri:
		st.add_vertex(v)
		faces.append(v)


## Tablica z numerem kilometra na słupku kilometrowym (Label3D - jedna na
## km, kilka w zasięgu wzroku; MultiMesh nie ma tekstu).
static func _km_label(samples: Array, d: float, lat: float, km: int) -> Label3D:
	var fr := frame_at(samples, d)
	var right: Vector3 = ((fr["right"] as Vector3) * Vector3(1, 0, 1)).normalized()
	var fwd := Vector3.UP.cross(right).normalized()
	var p: Vector3 = (fr["pos"] as Vector3) + right * lat
	var l := Label3D.new()
	l.name = "KmLabel%d" % km
	l.text = str(km)
	l.pixel_size = 0.004
	l.font_size = 64
	l.modulate = Color(0.05, 0.05, 0.05)
	l.outline_size = 0
	# Label3D czyta się od strony +Z: +Z = -fwd (do kierowcy), +X = w prawo.
	# Tuż przed tablicą słupka (1,45 m nad jezdnią).
	l.transform = Transform3D(Basis(right, Vector3.UP, -fwd), p + Vector3.UP * 1.45 - fwd * 0.02)
	l.visibility_range_end = VIS_PROPS
	return l


# --------------------------------------------------------------------------
# Próbki
# --------------------------------------------------------------------------

## Układ toru (pos, right, fwd) na dystansie d - wyszukiwanie binarne
## i interpolacja liniowa między próbkami (dist rośnie).
## Ręczne wyszukiwanie binarne celowo (D7 z przeglądu odrzucone): próbki
## przychodzą jako Array[Dictionary], a bsearch_custom na tablicy typowanej
## odrzuca szukaną wartość float (błąd _internal_validate co wywołanie).
static func frame_at(samples: Array, d: float) -> Dictionary:
	var n := samples.size()
	var lo := 0
	var hi := n - 1
	if d <= float(samples[0]["dist"]):
		return samples[0]
	if d >= float(samples[hi]["dist"]):
		return samples[hi]
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(samples[mid]["dist"]) <= d:
			lo = mid
		else:
			hi = mid
	var s0: Dictionary = samples[lo]
	var s1: Dictionary = samples[hi]
	var t := (d - float(s0["dist"])) / maxf(float(s1["dist"]) - float(s0["dist"]), 1e-6)
	return {
		"pos": (s0["pos"] as Vector3).lerp(s1["pos"], t),
		"right": (s0["right"] as Vector3).lerp(s1["right"], t).normalized(),
		"fwd": (s0["fwd"] as Vector3).lerp(s1["fwd"], t).normalized(),
		"dist": d,
	}


# --------------------------------------------------------------------------
# Siatki (low-poly, kolory wierzchołków)
# --------------------------------------------------------------------------

static func mesh(kind: String) -> Mesh:
	if _cache.has(kind):
		return _cache[kind]
	var m: Mesh
	match kind:
		"conifer":
			m = Scenery.conifer()
		"broadleaf":
			m = Scenery.broadleaf()
		"rock":
			m = Scenery.rock()
		_:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Płaskie cieniowanie: bez tego generate_normals uśrednia normalne
			# wierzchołków w tym samym miejscu - pudła wyglądały na zaokrąglone,
			# a facade.gdshader (oś ściany z normalnej) dzielił okna po
			# przekątnej (przegląd renderów 2026-11-10).
			st.set_smooth_group(0xFFFFFFFF)
			match kind:
				"building":
					_box(st, Vector3(0, 0.5, 0), Vector3(1, 1, 1), Color.WHITE)
				"hm_post":
					# Biały słupek 1 m z czarnym paskiem (konwencja ogólna).
					_box(st, Vector3(0, 0.5, 0), Vector3(0.12, 1.0, 0.12), Color(0.95, 0.95, 0.95))
					_box(st, Vector3(0, 0.82, 0), Vector3(0.125, 0.12, 0.125), Color(0.08, 0.08, 0.08))
				"km_post":
					# Słupek z białą tablicą przodem do nadjeżdżających (lokalne
					# +Z = kierunek jazdy, patrz _upright_xf); numer: Label3D.
					_box(st, Vector3(0, 0.75, 0.04), Vector3(0.1, 1.5, 0.1), Color(0.6, 0.6, 0.6))
					_box(st, Vector3(0, 1.45, 0), Vector3(0.55, 0.4, 0.02), Color(0.97, 0.97, 0.97))
				"lamp":
					# Słup 9 m z wysięgnikiem nad jezdnię (+X) i oprawą.
					_box(st, Vector3(0, 4.5, 0), Vector3(0.18, 9.0, 0.18), Color(0.45, 0.47, 0.5))
					_box(st, Vector3(0.9, 8.9, 0), Vector3(1.8, 0.1, 0.1), Color(0.45, 0.47, 0.5))
					_box(st, Vector3(1.75, 8.8, 0), Vector3(0.6, 0.12, 0.25), Color(0.9, 0.9, 0.82))
				"noise_wall":
					# Panel 4 m × 4 m: cokół z betonu + ekran (zielonoszary).
					_box(st, Vector3(0, 0.4, 0), Vector3(0.25, 0.8, NOISE_WALL_PANEL), Color(0.6, 0.6, 0.58))
					_box(st, Vector3(0, 2.4, 0), Vector3(0.15, 3.2, NOISE_WALL_PANEL - 0.12), Color(0.42, 0.5, 0.46))
					_box(st, Vector3(0, 2.2, NOISE_WALL_PANEL * 0.5 - 0.06), Vector3(0.22, 4.4, 0.12), Color(0.35, 0.36, 0.38))
				"bush":
					Scenery._cone(st, 6, 0.0, 0.7, 0.9, 1.1, Color(0.24, 0.36, 0.16), 0.0)
					Scenery._cone(st, 6, 0.7, 1.4, 1.1, 0.3, Color(0.28, 0.4, 0.18), 0.5)
				"cactus":
					var g := Color(0.3, 0.45, 0.25)
					Scenery._cone(st, 7, 0.0, 3.2, 0.28, 0.24, g)
					Scenery._cone(st, 7, 3.2, 3.5, 0.24, 0.0, g)
					_box(st, Vector3(0.45, 1.5, 0), Vector3(0.7, 0.32, 0.32), g)
					Scenery._cone(st, 6, 1.5, 2.6, 0.17, 0.15, g, 0.0)
				"palm":
					_palm(st)
				"turbine":
					_turbine(st)
				_:
					push_warning("HighwayScenery: nieznany obiekt '%s'" % kind)
					_box(st, Vector3(0, 0.5, 0), Vector3.ONE, Color.MAGENTA)
			st.generate_normals()
			st.set_material(Scenery._vc_material())
			m = st.commit()
	_cache[kind] = m
	return m


## Prostopadłościan (ściany na zewnątrz, płaskie cieniowanie).
static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	# Jedno pudło w całym kodzie (StuntTrack.obox, przegląd D4). Uwaga
	# historyczna: ściany muszą być zgodne z ruchem wskazówek zegara
	# z zewnątrz (przód w Godocie) - odwrotnie budynki były "otwarte".
	st.set_color(col)
	StuntTrack.obox(st, c, Vector3.RIGHT, Vector3.BACK, s)


## Palma: lekko pochylony pień z kilku walców i 6 opadających liści.
static func _palm(st: SurfaceTool) -> void:
	var trunk := Color(0.45, 0.36, 0.25)
	for i in range(4):
		var y0 := i * 1.8
		Scenery._cone(st, 6, y0, y0 + 1.8, 0.22 - i * 0.025, 0.2 - i * 0.025, trunk.lightened(i * 0.04), float(i))
	var top := Vector3(0, 7.2, 0)
	var leaf := Color(0.22, 0.42, 0.16)
	st.set_color(leaf)
	for k in range(6):
		var a := TAU * k / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * 0.45
		var mid := top + dir * 1.8 + Vector3.UP * 0.4
		var tip := top + dir * 3.4 - Vector3.UP * 0.9
		for v in [top, mid + side, mid - side, mid + side, tip, mid - side]:
			st.add_vertex(v)
		# Druga strona liścia (bez cull_disabled w materiale wspólnym).
		for v in [top, mid - side, mid + side, mid + side, mid - side, tip]:
			st.add_vertex(v)


## Turbina wiatrowa: wieża 60 m, gondola, trzy łopaty (nieruchome w siatce;
## obrót - osobny węzeł, jeśli pomiar na Queście pozwoli).
static func _turbine(st: SurfaceTool) -> void:
	var white := Color(0.92, 0.93, 0.94)
	Scenery._cone(st, 8, 0.0, 60.0, 2.0, 1.2, white)
	_box(st, Vector3(0, 61.0, -0.8), Vector3(2.2, 2.4, 6.0), white)
	var hub := Vector3(0, 61.0, 2.6)
	st.set_color(white)
	for k in range(3):
		var a := TAU * k / 3.0 + 0.3
		var dir := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-dir.y, dir.x, 0) * 0.9
		var tip := hub + dir * 38.0
		for v in [hub + side, tip, hub - side, hub - side, tip, hub + side]:
			st.add_vertex(v)


static var _facade: ShaderMaterial
static func _facade_material() -> ShaderMaterial:
	if _facade == null:
		_facade = ShaderMaterial.new()
		_facade.shader = load("res://shaders/facade.gdshader")
	return _facade
