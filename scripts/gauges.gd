extends Node3D
class_name Gauges

## Zegary w desce rozdzielczej, jak w aucie z epoki: dwie okrągłe tarcze
## (prędkościomierz, obrotomierz) za kierownicą. W dolnej, wolnej części
## prędkościomierza okienko LCD z obrysem auta z góry (prośba użytkownika:
## osobna tabliczka na desce wyglądała sztucznie). Strefy jak segmenty LCD:
##   zielony    - sprawne (< 25%)
##   żółty      - uszkodzone średnio (< 60%)
##   czerwony   - uszkodzone krytycznie (< 100%)
##   zgaszony   - zniszczone (100%), widać tylko blady "duch" segmentu
## Wszystko z prymitywów 3D (tarcza, kreski, liczby Label3D, wskazówka),
## materiały bez cieniowania - czytelne także w cieniu ściany wąwozu.
## Kontrolki wspomagań (ABS, TCS, ESP, ograniczenie skrętu) w górnej części
## prędkościomierza: trójkąty jak znak ostrzegawczy ze skrótem w środku
## (prośba użytkownika). Zgaszona = system włączony; świeci = wyłączony;
## miga = system włączony i właśnie ingeruje (jak kontrolka ESP w aucie).
## Oś tarczy: lokalne +Z patrzy na kierowcę.

const SWEEP := deg_to_rad(270.0)           # zakres wskazówki
const START := deg_to_rad(225.0)           # 0 na skali: lewy dół (od osi +X, przeciwnie do zegara)

var _speed_needle: Node3D
var _rpm_needle: Node3D
var _rpm_dial: Node3D
var _speed_max := 400.0
var _rpm_max := 8000.0
var _zones := {}                           # nazwa strefy -> [materiał, segment]
var _fuel_needle: Node3D
var _fuel_light: MeshInstance3D
var _fuel_light_mat: StandardMaterial3D
var _face_mat: StandardMaterial3D
var _mark_mat: StandardMaterial3D
var _red_mat: StandardMaterial3D
var _needle_mat: StandardMaterial3D
var _chrome: StandardMaterial3D
var _gear_label: Label3D                   # okienko biegu w obrotomierzu
var _gear_text := ""
var _lamps := {}                           # klucz -> [materiał obrysu, Label3D, świeci?]


func _init() -> void:
	_face_mat = _unshaded(Color(0.05, 0.05, 0.055))
	_mark_mat = _unshaded(Color(0.92, 0.9, 0.82))
	_red_mat = _unshaded(Color(0.9, 0.15, 0.1))
	_needle_mat = _unshaded(Color(1.0, 0.45, 0.08))
	_chrome = StandardMaterial3D.new()
	_chrome.albedo_color = Color(0.85, 0.86, 0.88)
	_chrome.metallic = 1.0
	_chrome.roughness = 0.15


## Buduje zestaw: `cluster` - pozycja zestawu zegarów (układ auta).
func build(cluster: Vector3, tilt_deg: float) -> void:
	var cl := Node3D.new()
	cl.name = "Cluster"
	cl.position = cluster
	cl.rotation = Vector3(deg_to_rad(-tilt_deg), 0.0, 0.0)
	add_child(cl)
	# Obudowa zestawu (daszek nad tarczami chroni je przed słońcem w aucie).
	var hood := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.36, 0.17, 0.05)
	# Prawie czarna, jak osłona zegarów we wnętrzu sedana (stunt_car.gd).
	hb.material = _unshaded(Color(0.035, 0.035, 0.04))
	hood.mesh = hb
	hood.position = Vector3(0, 0, -0.03)
	cl.add_child(hood)
	# "km/h" wyżej niż na obrotomierzu - między górnymi kontrolkami.
	var sp := _dial(cl, Vector3(-0.085, 0.0, 0.0), 0.075, _speed_max, 25.0, 50.0, -1.0, "km/h",
			LAMP_UNIT_Y)
	_speed_needle = sp
	_build_assist_lamps(sp.get_parent())
	var lcd := Node3D.new()
	lcd.name = "DamageLCD"
	lcd.position = Vector3(-0.085, -0.042, 0.0045)
	cl.add_child(lcd)
	_build_damage(lcd)
	_rpm_dial = Node3D.new()
	_rpm_dial.position = Vector3(0.085, 0.0, 0.0)
	cl.add_child(_rpm_dial)
	set_rpm_range(_rpm_max, 7200.0)


## Obrotomierz od nowa - zakres zależy od silnika (benzyna, diesel, elektryk).
func set_rpm_range(max_rpm: float, redline: float) -> void:
	for c in _rpm_dial.get_children():
		c.queue_free()
	_rpm_max = ceilf(max_rpm / 1000.0) * 1000.0
	var major := 1000.0 if _rpm_max <= 9000.0 else 2000.0
	# "x1000 obr" pod piastą - nad nią okienko biegu.
	_rpm_needle = _dial(_rpm_dial, Vector3.ZERO, 0.075, _rpm_max / 1000.0, major / 2000.0,
			major / 1000.0, redline / 1000.0, "x1000 obr", GEAR_UNIT_Y)
	_build_fuel(_rpm_dial)
	_build_gear(_rpm_dial)


## Okienko biegu (użytkownik 2026-11-10: bieg był napisem pod zegarami -
## "resztka starego interfejsu"): LCD po lewej stronie obrotomierza, między
## piastą a liczbami 1-2, tryb skrzyni + bieg ("A3", "M2", "R", "N"). Górę
## tarczy z fotela zasłania wieniec kierownicy; wskazówka zasłania okienko
## tylko na wolnych obrotach (w jeździe stoi u góry).
const GEAR_LCD_POS := Vector2(-0.027, -0.004)   # środek okienka względem osi [m]
const GEAR_LCD_SIZE := Vector2(0.020, 0.012)
const GEAR_UNIT_Y := -0.24                 # "x1000 obr" w promieniach tarczy


func _build_gear(parent: Node3D) -> void:
	var lcd := Node3D.new()
	lcd.name = "GearLCD"
	lcd.position = Vector3(GEAR_LCD_POS.x, GEAR_LCD_POS.y, 0.0045)
	parent.add_child(lcd)
	_plate(lcd, GEAR_LCD_SIZE + Vector2(0.003, 0.003), Vector2.ZERO, -0.0015, _chrome)
	_plate(lcd, GEAR_LCD_SIZE, Vector2.ZERO, 0.0, _unshaded(LCD_BG))
	_gear_label = Label3D.new()
	_gear_label.font_size = 48
	_gear_label.pixel_size = 0.00018       # ~8 mm wysokości cyfr
	_gear_label.outline_size = 0
	_gear_label.shaded = false
	_gear_label.modulate = Color(0.2, 0.8, 0.25)
	_gear_label.position = Vector3(0, 0, 0.0012)
	_gear_label.text = _gear_text
	lcd.add_child(_gear_label)


## Tryb skrzyni i bieg w okienku obrotomierza (zmiana tekstu tylko przy
## zmianie biegu).
func set_gear(text: String) -> void:
	if text == _gear_text:
		return
	_gear_text = text
	if _gear_label and is_instance_valid(_gear_label):
		_gear_label.text = text


## Wskaźnik paliwa w dolnej części obrotomierza (jak w autach z epoki):
## łuk 90° od E (lewo) do F (prawo), własna wskazówka, kontrolka rezerwy.
func _build_fuel(parent: Node3D) -> void:
	var c := Vector3(0.0, -0.047, 0.006)
	var r := 0.022
	for i in range(5):
		var a := deg_to_rad(135.0 - 22.5 * i)       # 135° (E) ... 45° (F)
		var tick := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.005, 0.0012, 0.001)
		b.material = _red_mat if i == 0 else _mark_mat
		tick.mesh = b
		tick.position = c + Vector3(cos(a) * r, sin(a) * r, 0.0)
		tick.rotation = Vector3(0, 0, a)
		parent.add_child(tick)
	for lab in [["E", 135.0], ["F", 45.0]]:
		var l := Label3D.new()
		l.text = lab[0]
		l.font_size = 14
		l.pixel_size = 0.0004
		l.modulate = _mark_mat.albedo_color
		l.outline_size = 0
		l.shaded = false
		var a: float = deg_to_rad(lab[1])
		l.position = c + Vector3(cos(a) * r * 1.45, sin(a) * r * 1.45, 0.0)
		parent.add_child(l)
	_fuel_needle = Node3D.new()
	_fuel_needle.position = c + Vector3(0, 0, 0.001)
	parent.add_child(_fuel_needle)
	var n := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(r * 0.9, 0.0018, 0.001)
	nb.material = _needle_mat
	n.mesh = nb
	n.position = Vector3(r * 0.45, 0, 0)
	_fuel_needle.add_child(n)
	_fuel_light = MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = 0.0035
	lc.bottom_radius = 0.0035
	lc.height = 0.001
	_fuel_light_mat = _unshaded(Color(0.25, 0.15, 0.0))
	lc.material = _fuel_light_mat
	_fuel_light.mesh = lc
	_fuel_light.rotation = Vector3(PI * 0.5, 0, 0)
	_fuel_light.position = c + Vector3(0, -0.009, 0)
	parent.add_child(_fuel_light)


## Paliwo 0..1: wskazówka E-F i kontrolka rezerwy (< 15%, miga przy < 5%).
func set_fuel(f: float) -> void:
	if _fuel_needle == null or not is_instance_valid(_fuel_needle):
		return
	_fuel_needle.rotation = Vector3(0, 0, deg_to_rad(135.0 - 90.0 * clampf(f, 0.0, 1.0)))
	var on := f < 0.15 and (f >= 0.05 or int(Time.get_ticks_msec() / 300) % 2 == 0)
	_fuel_light_mat.albedo_color = Color(1.0, 0.6, 0.05) if on else Color(0.25, 0.15, 0.0)


## Tarcza: kreski co `minor`, liczby co `major`, czerwone pole od `red`
## (-1 = bez). Zwraca węzeł wskazówki.
func _dial(parent: Node3D, pos: Vector3, r: float, vmax: float, minor: float, major: float,
		red: float, unit: String, unit_y: float = 0.32) -> Node3D:
	var d := Node3D.new()
	d.position = pos
	parent.add_child(d)
	var face := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = r
	fc.bottom_radius = r
	fc.height = 0.004
	fc.radial_segments = 32
	fc.rings = 1
	fc.material = _face_mat
	face.mesh = fc
	face.rotation = Vector3(PI * 0.5, 0, 0)
	d.add_child(face)
	var bezel := MeshInstance3D.new()
	var tb := TorusMesh.new()
	tb.inner_radius = r
	tb.outer_radius = r + 0.007
	tb.rings = 32
	tb.ring_segments = 6
	tb.material = _chrome
	bezel.mesh = tb
	bezel.rotation = Vector3(PI * 0.5, 0, 0)
	d.add_child(bezel)
	var n := int(round(vmax / minor))
	for i in range(n + 1):
		var v := i * minor
		var is_major := is_equal_approx(fmod(v + 0.0001, major), 0.0) or fmod(v + 0.0001, major) < 0.001
		var a := _angle(v, vmax)
		var length := r * (0.18 if is_major else 0.09)
		var tick := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(length, 0.003 if is_major else 0.0018, 0.001)
		b.material = _red_mat if (red > 0.0 and v >= red) else _mark_mat
		tick.mesh = b
		var rr := r * 0.92 - length * 0.5
		tick.position = Vector3(cos(a) * rr, sin(a) * rr, 0.004)
		tick.rotation = Vector3(0, 0, a)
		d.add_child(tick)
		if is_major:
			var l := Label3D.new()
			l.text = str(int(round(v)))
			l.font_size = 20
			l.pixel_size = 0.0004
			l.modulate = _red_mat.albedo_color if (red > 0.0 and v >= red) else _mark_mat.albedo_color
			l.outline_size = 0
			var lr := r * 0.62
			l.position = Vector3(cos(a) * lr, sin(a) * lr, 0.005)
			l.shaded = false
			d.add_child(l)
	var ul := Label3D.new()
	ul.text = unit
	ul.font_size = 14
	ul.pixel_size = 0.0004
	ul.modulate = Color(0.7, 0.7, 0.65)
	# Nad środkiem tarczy - dół obrotomierza zajmuje wskaźnik paliwa.
	ul.position = Vector3(0, r * unit_y, 0.005)
	ul.outline_size = 0
	d.add_child(ul)
	# Wskazówka: obraca się wokół osi tarczy (lokalne Z).
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, 0.007)
	d.add_child(pivot)
	var needle := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(r * 0.85, 0.004, 0.002)
	nb.material = _needle_mat
	needle.mesh = nb
	needle.position = Vector3(r * 0.85 * 0.5 - 0.01, 0, 0)
	pivot.add_child(needle)
	var hub := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.008
	hc.bottom_radius = 0.008
	hc.height = 0.004
	hc.material = _chrome
	hub.mesh = hc
	hub.rotation = Vector3(PI * 0.5, 0, 0)
	pivot.add_child(hub)
	pivot.set_meta("vmax", vmax)
	_set_needle(pivot, 0.0)
	return pivot


func _angle(v: float, vmax: float) -> float:
	return START - SWEEP * clampf(v / vmax, 0.0, 1.0)


func _set_needle(pivot: Node3D, v: float) -> void:
	pivot.rotation = Vector3(0, 0, _angle(v, pivot.get_meta("vmax")))


## Kontrolki wspomagań: [klucz, skrót, kąt na tarczy w stopniach od +X].
## Ułożone na łuku LAMP_RING wokół osi, symetrycznie, z przerwą u góry na
## "km/h". Wymiary sprawdzone tak, żeby trójkąty nie nachodziły na siebie,
## na liczby skali (promień 0,62 r), piastę wskazówki ani okienko LCD
## (tests/gauges_test.gd liczy odstępy). Wskazówka przesuwa się nad nimi.
const ASSIST_LAMPS := [["abs", "ABS", 168.0], ["tcs", "TCS", 127.0],
		["esp", "ESP", 53.0], ["steer", "SKR", 12.0]]
const LAMP_SIDE := 0.018                   # bok trójkąta (m)
const LAMP_BORDER := 0.0011                # grubość świecącego obrysu (m)
const LAMP_RING := 0.029                   # promień łuku środków trójkątów (m)
const LAMP_UNIT_Y := 0.467                 # "km/h": wysokość w promieniach tarczy
const LAMP_LIT := Color(1.0, 0.62, 0.06)   # bursztyn, jak kontrolki w aucie
const LAMP_OFF := Color(0.17, 0.15, 0.12)  # zgaszona: widać tylko zarys
const LAMP_BLINK_MS := 250                 # miganie przy ingerencji (2 Hz)


## Środek kontrolki `i` (układ tarczy, środek ciężkości trójkąta).
static func lamp_center(i: int) -> Vector2:
	var a := deg_to_rad(ASSIST_LAMPS[i][2])
	return Vector2(cos(a), sin(a)) * LAMP_RING


## Wierzchołki trójkąta o boku `side` wokół środka ciężkości `c`, ostrzem w górę.
static func lamp_triangle(c: Vector2, side: float) -> PackedVector2Array:
	var h := side * sqrt(3.0) * 0.5
	return PackedVector2Array([c + Vector2(-side * 0.5, -h / 3.0),
			c + Vector2(side * 0.5, -h / 3.0), c + Vector2(0.0, h * 2.0 / 3.0)])


## Czy kontrolka świeci: wyłączony system świeci stale, włączony gaśnie,
## a w czasie ingerencji miga.
static func lamp_lit(enabled: bool, active: bool, t_ms: int) -> bool:
	if not enabled:
		return true
	return active and (t_ms / LAMP_BLINK_MS) % 2 == 0


func _build_assist_lamps(dial: Node3D) -> void:
	# Obrys: pełny trójkąt w kolorze kontrolki, na nim czarny trójkąt
	# mniejszy o LAMP_BORDER z każdej strony; skrót w kolorze kontrolki.
	# Wszystko płaskie, bez cieniowania, 3 draw calle na kontrolkę.
	var inner_side := LAMP_SIDE - 2.0 * sqrt(3.0) * LAMP_BORDER
	var inner_mat := _unshaded(_face_mat.albedo_color)
	inner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var h := LAMP_SIDE * sqrt(3.0) * 0.5
	for i in range(ASSIST_LAMPS.size()):
		var c := lamp_center(i)
		var lamp := Node3D.new()
		lamp.name = "Lamp" + ASSIST_LAMPS[i][1]
		lamp.position = Vector3(c.x, c.y, 0.0045)
		dial.add_child(lamp)
		var mat := _unshaded(LAMP_OFF)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var outer := MeshInstance3D.new()
		outer.mesh = _triangle_mesh(LAMP_SIDE, mat)
		lamp.add_child(outer)
		var inner := MeshInstance3D.new()
		inner.mesh = _triangle_mesh(inner_side, inner_mat)
		inner.position = Vector3(0, 0, 0.0004)
		lamp.add_child(inner)
		var l := Label3D.new()
		l.text = ASSIST_LAMPS[i][1]
		# Duży font i mały piksel: ostre litery przy wysokości ~4 mm.
		l.font_size = 42
		l.pixel_size = 0.0001
		l.outline_size = 0
		l.shaded = false
		l.modulate = LAMP_OFF
		# Skrót w dolnej, szerszej części trójkąta.
		l.position = Vector3(0, h * 0.26 - h / 3.0, 0.0008)
		lamp.add_child(l)
		_lamps[ASSIST_LAMPS[i][0]] = [mat, l, false]


func _triangle_mesh(side: float, mat: Material) -> ArrayMesh:
	var v := PackedVector3Array()
	for p in lamp_triangle(Vector2.ZERO, side):
		v.append(Vector3(p.x, p.y, 0.0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


## Stan systemu wspomagania: `key` z ASSIST_LAMPS, `active` = właśnie ingeruje.
## Materiał zmienia się tylko przy zmianie stanu.
func set_assist(key: String, enabled: bool, active: bool) -> void:
	var lamp: Array = _lamps.get(key, [])
	if lamp.is_empty():
		return
	var lit := lamp_lit(enabled, active, Time.get_ticks_msec())
	if lit == lamp[2]:
		return
	lamp[2] = lit
	var c := LAMP_LIT if lit else LAMP_OFF
	lamp[0].albedo_color = c
	lamp[1].modulate = c


## Czy kontrolka świeci (dla testów).
func assist_lit(key: String) -> bool:
	return _lamps.has(key) and _lamps[key][2]


## LCD uszkodzeń: obrys auta z góry, przód u góry. Okienko 36×50 mm
## mieści się między wskazówką a dolną krawędzią tarczy (łuk bez skali).
## Każdy segment ma pod spodem bladego "ducha" - jak nieświecący segment LCD.
const LCD_ZONES := {
	# nazwa: [rozmiar (x, y), środek (x, y)] w metrach
	"engine": [Vector2(0.015, 0.011), Vector2(0.0, 0.0145)],
	"cabin": [Vector2(0.015, 0.017), Vector2(0.0, 0.0)],
	"rear": [Vector2(0.015, 0.010), Vector2(0.0, -0.0145)],
	"w0": [Vector2(0.0036, 0.008), Vector2(-0.0108, 0.0115)],
	"w1": [Vector2(0.0036, 0.008), Vector2(0.0108, 0.0115)],
	"w2": [Vector2(0.0036, 0.008), Vector2(-0.0108, -0.0115)],
	"w3": [Vector2(0.0036, 0.008), Vector2(0.0108, -0.0115)],
}
const LCD_BG := Color(0.03, 0.055, 0.045)
const LCD_GHOST := Color(0.07, 0.11, 0.09)


func _build_damage(parent: Node3D) -> void:
	_plate(parent, Vector2(0.040, 0.054), Vector2.ZERO, -0.0015, _chrome)
	_plate(parent, Vector2(0.036, 0.050), Vector2.ZERO, 0.0, _unshaded(LCD_BG))
	var ghost := _unshaded(LCD_GHOST)
	for k in LCD_ZONES:
		var z: Array = LCD_ZONES[k]
		_plate(parent, z[0], z[1], 0.0006, ghost)
		var m := _unshaded(Color(0.2, 0.8, 0.25))
		_zones[k] = [m, _plate(parent, z[0], z[1], 0.0012, m)]
	# Lekki połysk szybki LCD.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.9, 0.85, 0.06)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plate(parent, Vector2(0.036, 0.050), Vector2.ZERO, 0.002, glass)


func _plate(parent: Node3D, size: Vector2, at: Vector2, z: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(size.x, size.y, 0.0008)
	b.material = mat
	mi.mesh = b
	mi.position = Vector3(at.x, at.y, z)
	parent.add_child(mi)
	return mi


static func damage_color(d: float) -> Color:
	if d >= 0.6:
		return Color(0.95, 0.15, 0.1)           # krytycznie
	if d >= 0.25:
		return Color(0.98, 0.82, 0.15)          # średnio
	return Color(0.25, 0.9, 0.35)               # sprawne


func _set_zone(k: String, d: float) -> void:
	var z: Array = _zones[k]
	z[0].albedo_color = damage_color(d)
	# Zniszczone: segment gaśnie, zostaje duch.
	z[1].visible = d < 1.0


## Aktualizacja co klatkę.
func update_values(kmh: float, rpm: float, damage: Dictionary) -> void:
	if _speed_needle:
		_set_needle(_speed_needle, minf(kmh, _speed_max))
	if _rpm_needle and is_instance_valid(_rpm_needle):
		_set_needle(_rpm_needle, rpm / 1000.0)
	if _zones.is_empty():
		return
	_set_zone("engine", damage["engine"])
	_set_zone("cabin", damage["structure"])
	_set_zone("rear", damage["gearbox"])
	for i in range(4):
		_set_zone("w%d" % i, maxf(damage["brakes"][i], damage["suspension"][i]))


## Ograniczenie prędkości i ostrzeżenie o przekroczeniu (limit <= 0: puste).
func _mark_mat_white() -> StandardMaterial3D:
	return _unshaded(Color(0.97, 0.97, 0.95))


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
