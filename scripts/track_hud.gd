extends Node3D
class_name TrackHud

## Mały, przezroczysty HUD nad kierownicą: trasa na najbliższe 1,5 km
## widziana z góry, obrócona z autem (kierunek jazdy zawsze do góry).
##   linia: kolor nawierzchni (sucha biała, mokra niebieska, lód jasnoniebieski)
##   znaczniki: skocznia/skok żółty, garb pomarańczowy, warsztat zielony,
##              brama odcinka biała kreska
## Przebudowa siatki co 0,25 s (~150 punktów) - na Queście tanio.
## Bez testu głębi: zawsze na wierzchu, także przez prześwitującą kabinę.

const RANGE := 1500.0
## Krok próbek mapki [m] (plus wszystkie próbki ze znacznikami).
const STRIDE := 8
const SIZE := Vector2(0.16, 0.13)
const REFRESH := 0.25

var _mesh_mi: MeshInstance3D
## Miniatura najbliższego znaku ostrzegawczego (pod kolumną postępu).
var _warn: Node3D
var _warn_key := ""
## Miniatura znaku ograniczenia prędkości obok znaku ostrzegawczego.
var _limit: Node3D
var _limit_label: Label3D
var _timer := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = SIZE
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.05, 0.08, 0.1, 0.28)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.no_depth_test = true
	bm.render_priority = 1
	q.material = bm
	bg.mesh = q
	add_child(bg)
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.no_depth_test = true
	_mat.render_priority = 2
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_mi = MeshInstance3D.new()
	_mesh_mi.mesh = ArrayMesh.new()
	add_child(_mesh_mi)


## Miniatura znaku ostrzegawczego w punkcie `pos` (układ rodzica HUD):
## trójkąt z czerwonym obrzeżem i żółtym polem, symbol jak na dużych znakach.
## kind: "curve_r", "curve_l", "climb", "descent", "slippery"; "" = ukryj.
func show_warning(parent: Node3D, pos: Vector3, kind: String, value := 0) -> void:
	var key := "%s%d" % [kind, value]
	if key == _warn_key:
		return
	_warn_key = key
	if _warn:
		_warn.queue_free()
		_warn = null
	if kind == "":
		return
	_warn = Node3D.new()
	_warn.position = pos
	parent.add_child(_warn)
	if kind == "repair" or kind == "fuel":
		# Zjazd do warsztatu / na stację blisko: niebieski znak ze strzałką.
		_bar(_warn, Vector2(0.024, 0.034), Vector2.ZERO, 0.0, Color(0.05, 0.25, 0.65), 4)
		_bar(_warn, Vector2(0.018, 0.018), Vector2(0.0, 0.005), 0.0, Color(0.97, 0.97, 0.95), 5)
		var ink := Color(0.04, 0.04, 0.04)
		if kind == "repair":
			_bar(_warn, Vector2(0.002, 0.012), Vector2(0.0, 0.005), 0.8, ink, 6)
		else:
			_bar(_warn, Vector2(0.006, 0.011), Vector2(-0.001, 0.004), 0.0, ink, 6)
		_bar(_warn, Vector2(0.0022, 0.009), Vector2(0.001, -0.0105), -0.785, Color(0.97, 0.97, 0.95), 6)
		_bar(_warn, Vector2(0.006, 0.0022), Vector2(0.0045, -0.0068), 0.0, Color(0.97, 0.97, 0.95), 6)
		_bar(_warn, Vector2(0.0022, 0.006), Vector2(0.0068, -0.0085), 0.0, Color(0.97, 0.97, 0.95), 6)
		return
	var r := 0.018
	_tri(_warn, r, Color(0.8, 0.08, 0.06), 0.0)
	_tri(_warn, r * 0.74, Color(0.98, 0.8, 0.1), 0.0006)
	var black := Color(0.04, 0.04, 0.04)
	match kind:
		"curve_r", "curve_l":
			var sg := 1.0 if kind == "curve_r" else -1.0
			_bar(_warn, Vector2(0.0018, 0.0075), Vector2(-0.0012 * sg, -0.003), 0.0, black)
			_bar(_warn, Vector2(0.0018, 0.0065), Vector2(0.001 * sg, 0.0026), -0.6 * sg, black)
		"slippery":
			_bar(_warn, Vector2(0.006, 0.003), Vector2(0, -0.0008), 0.0, black)
			for k in [-1.0, 1.0]:
				_bar(_warn, Vector2(0.0012, 0.005), Vector2(0.002 * k, -0.0055), 0.5 * k, black)
		_:
			var l := Label3D.new()
			l.text = "%d%%" % value
			l.font_size = 20
			l.pixel_size = 0.00028
			l.modulate = black
			l.outline_size = 0
			l.shaded = false
			l.no_depth_test = true
			l.render_priority = 4
			l.position = Vector3(0, -0.002, 0.0012)
			_warn.add_child(l)


## Znak ograniczenia (B-33) obok miniatury ostrzegawczej; miga przy
## przekroczeniu. limit <= 0 - ukryty.
func show_limit(parent: Node3D, pos: Vector3, limit: float, over: bool) -> void:
	if _limit == null:
		_limit = Node3D.new()
		parent.add_child(_limit)
		for spec in [[0.016, Color(0.8, 0.08, 0.06), 0.0], [0.012, Color(0.97, 0.97, 0.95), 0.0006]]:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = spec[0]
			cm.bottom_radius = spec[0]
			cm.height = 0.0005
			cm.radial_segments = 20
			cm.rings = 1
			var m := StandardMaterial3D.new()
			m.albedo_color = spec[1]
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.no_depth_test = true
			m.render_priority = 3
			cm.material = m
			mi.mesh = cm
			mi.position = Vector3(0, 0, spec[2])
			mi.rotation = Vector3(PI * 0.5, 0, 0)
			_limit.add_child(mi)
		_limit_label = Label3D.new()
		_limit_label.font_size = 24
		_limit_label.pixel_size = 0.00045
		_limit_label.modulate = Color.BLACK
		_limit_label.outline_size = 0
		_limit_label.shaded = false
		_limit_label.no_depth_test = true
		_limit_label.render_priority = 4
		_limit_label.position = Vector3(0, 0, 0.0012)
		_limit.add_child(_limit_label)
	_limit.position = pos
	_limit_label.text = str(roundi(limit))
	_limit.visible = limit > 0.0 and (not over or int(Time.get_ticks_msec() / 400) % 2 == 0)


func _tri(parent: Node3D, r: float, col: Color, dz: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(0, r, dz))
	st.add_vertex(Vector3(r * 0.866, -r * 0.5, dz))
	st.add_vertex(Vector3(-r * 0.866, -r * 0.5, dz))
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.render_priority = 3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	parent.add_child(mi)


func _bar(parent: Node3D, size: Vector2, at: Vector2, rot: float, col: Color, prio := 4) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(size.x, size.y, 0.0005)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.render_priority = prio            # warstwy bez testu głębi: kolejność z priorytetu
	b.material = m
	mi.mesh = b
	mi.position = Vector3(at.x, at.y, 0.0012 + 0.0001 * (prio - 4))
	mi.rotation = Vector3(0, 0, rot)
	parent.add_child(mi)


## `car_xf` - globalny układ auta, `sampler` - funkcja zwracająca próbki
## trasy przed autem (pozycje globalne; wołana tylko przy odświeżeniu),
## `here` - dystans auta.
func refresh(delta: float, car_xf: Transform3D, sampler: Callable, here: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	var samples: Array = sampler.call()
	var inv := car_xf.affine_inverse()
	var scale_m := (SIZE.y - 0.012) / RANGE
	var origin := Vector2(0.0, -SIZE.y * 0.5 + 0.008)

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var prev := Vector2.INF
	var prev_col := Color.WHITE
	var last_d := -INF
	for s in samples:
		var d := float(s["dist"])
		if d < here - 5.0 or d > here + RANGE:
			continue
		if d - last_d < float(STRIDE) and not (s["meta"] as Dictionary).size() > 0:
			continue
		last_d = d
		var rel: Vector3 = inv * (s["pos"] as Vector3)
		var p := origin + Vector2(rel.x, -rel.z) * scale_m
		if absf(p.x) > SIZE.x * 0.5 - 0.004 or p.y > SIZE.y * 0.5 - 0.004:
			prev = Vector2.INF
			continue
		var col := Color(0.95, 0.95, 0.9, 0.9)
		match s["surface"]:
			"wet":
				col = Color(0.35, 0.6, 1.0, 0.95)
			"ice":
				col = Color(0.7, 0.95, 1.0, 0.95)
		if s["gap"]:
			col = Color(0.9, 0.2, 0.15, 0.95)
		if prev != Vector2.INF:
			_segment(verts, colors, prev, p, 0.0018, prev_col)
		prev = p
		prev_col = col
		var meta: Dictionary = s["meta"]
		if meta.has("sign"):
			_dot(verts, colors, p, 0.0045, Color(1.0, 0.85, 0.1))
		if meta.has("warn"):
			_dot(verts, colors, p, 0.0038, Color(1.0, 0.5, 0.1))
		if meta.has("workshop"):
			_dot(verts, colors, p, 0.0055, Color(0.3, 0.95, 0.35))
		if meta.has("checkpoint"):
			_segment(verts, colors, p + Vector2(-0.006, 0), p + Vector2(0.006, 0), 0.0012, Color.WHITE)
	# Auto: trójkąt na dole.
	var c := origin
	for v in [c + Vector2(0, 0.007), c + Vector2(0.004, -0.004), c + Vector2(-0.004, -0.004)]:
		verts.append(Vector3(v.x, v.y, 0.001))
		colors.append(Color(1.0, 0.45, 0.1))

	var mesh: ArrayMesh = _mesh_mi.mesh
	mesh.clear_surfaces()
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _mat)


func _segment(verts: PackedVector3Array, colors: PackedColorArray, a: Vector2, b: Vector2,
		w: float, col: Color) -> void:
	var dir := (b - a)
	if dir.length() < 1e-6:
		return
	var n := Vector2(-dir.y, dir.x).normalized() * w * 0.5
	var quad := [a - n, b - n, b + n, a - n, b + n, a + n]
	for v in quad:
		verts.append(Vector3(v.x, v.y, 0.001))
		colors.append(col)


func _dot(verts: PackedVector3Array, colors: PackedColorArray, p: Vector2, r: float, col: Color) -> void:
	var quad := [p + Vector2(-r, -r), p + Vector2(r, -r), p + Vector2(r, r),
			p + Vector2(-r, -r), p + Vector2(r, r), p + Vector2(-r, r)]
	for v in quad:
		verts.append(Vector3(v.x, v.y, 0.002))
		colors.append(col)
