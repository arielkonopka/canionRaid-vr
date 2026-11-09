extends SceneTree
## Kontrolki wspomagań na prędkościomierzu (Gauges.ASSIST_LAMPS):
## logika świecenia (zgaszona = system włączony, świeci = wyłączony,
## miga = ingeruje) i układ - trójkąty nie nachodzą na siebie, na liczby
## skali, "km/h", piastę wskazówki ani okienko LCD uszkodzeń.
##   godot --headless --xr-mode off -s res://tests/gauges_test.gd </dev/null

const R := 0.075                 # promień prędkościomierza (Gauges.build)
const MARGIN := 0.001            # minimalny odstęp między elementami (m)

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  BŁĄD: ", what)


func _rect(c: Vector2, size: Vector2) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y),
			c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)])


func _overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	# Odstęp MARGIN: powiększamy jeden wielokąt o margines.
	for grown in Geometry2D.offset_polygon(a, MARGIN):
		if not Geometry2D.intersect_polygons(grown, b).is_empty():
			return true
	return false


func _initialize() -> void:
	# Logika.
	_check(Gauges.lamp_lit(false, false, 0), "wyłączony system ma świecić")
	_check(Gauges.lamp_lit(false, true, 300), "wyłączony system świeci stale")
	_check(not Gauges.lamp_lit(true, false, 0), "włączony system ma być zgaszony")
	_check(Gauges.lamp_lit(true, true, 0) != Gauges.lamp_lit(true, true, Gauges.LAMP_BLINK_MS),
			"ingerencja ma migać")

	# Stan po set_assist.
	var g := Gauges.new()
	root.add_child(g)
	g.build(Vector3.ZERO, 30.0)
	for lamp in Gauges.ASSIST_LAMPS:
		var key: String = lamp[0]
		_check(g.find_child("Lamp" + lamp[1], true, false) != null, "brak węzła kontrolki " + lamp[1])
		g.set_assist(key, true, false)
		_check(not g.assist_lit(key), key + ": włączony, a świeci")
		g.set_assist(key, false, false)
		_check(g.assist_lit(key), key + ": wyłączony, a zgaszony")
		g.set_assist(key, true, false)
		_check(not g.assist_lit(key), key + ": nie zgasła po włączeniu")

	# Układ (współrzędne tarczy prędkościomierza, metry). Rozmiary napisów
	# szacowane: liczby skali font 20 × 0,0004 → ~4,8 mm na znak, 5,8 mm
	# wysokości; "km/h" font 14 → 13,6 × 5,6 mm.
	var obstacles := {}
	for i in range(9):
		var v := i * 50
		var a := Gauges.START - Gauges.SWEEP * v / 400.0
		var c := Vector2(cos(a), sin(a)) * R * 0.62
		obstacles["liczba %d" % v] = _rect(c, Vector2(0.0048 * str(v).length(), 0.0058))
	obstacles["km/h"] = _rect(Vector2(0, R * Gauges.LAMP_UNIT_Y), Vector2(0.0136, 0.0056))
	obstacles["LCD"] = _rect(Vector2(0, -0.042), Vector2(0.040, 0.054))
	var hub := PackedVector2Array()
	for k in range(16):
		hub.append(Vector2.from_angle(k * TAU / 16.0) * 0.008)
	obstacles["piasta"] = hub
	var tris := []
	for i in range(Gauges.ASSIST_LAMPS.size()):
		var t := Gauges.lamp_triangle(Gauges.lamp_center(i), Gauges.LAMP_SIDE)
		tris.append(t)
		var nm: String = Gauges.ASSIST_LAMPS[i][1]
		for o in obstacles:
			_check(not _overlaps(t, obstacles[o]), nm + " nachodzi na: " + o)
		for p in t:
			# Wewnętrzny koniec długich kresek skali: 0,92 r - 0,18 r.
			_check(p.length() < R * 0.74 - MARGIN, nm + " sięga kresek skali")
	for i in range(tris.size()):
		for j in range(i + 1, tris.size()):
			_check(not _overlaps(tris[i], tris[j]), "%s nachodzi na %s" % [
					Gauges.ASSIST_LAMPS[i][1], Gauges.ASSIST_LAMPS[j][1]])
	print("gauges_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)
