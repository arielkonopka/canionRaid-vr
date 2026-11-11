extends SceneTree
## Test AirWheel (kierownica w powietrzu) bez sceny i bez gogli.
##   godot --headless --xr-mode off -s res://tests/air_wheel_test.gd </dev/null
## Każdy przypadek jedzie w dwóch układach: prostym (kolumna wzdłuż Z)
## i pochylonym/obróconym (kolumna jak w aucie, nachylona i odwrócona),
## żeby znak nie zależał od ułożenia kolumny w świecie.

const R := 0.18          # promień wieńca [m]
const DT := 1.0 / 72.0

var fails := 0
var center := Vector3.ZERO
var right := Vector3.RIGHT
var up := Vector3.UP


func _initialize() -> void:
	var frames := [
		["prosto", Basis(), Vector3.ZERO],
		["pochylona", Basis.from_euler(Vector3(deg_to_rad(-25.0), deg_to_rad(170.0), deg_to_rad(5.0))),
			Vector3(0.3, 1.1, -0.4)],
	]
	for f in frames:
		var b: Basis = f[1]
		right = b.x
		up = b.y
		center = f[2]
		print("== układ: %s" % f[0])
		_test_two_hands_cw()
		_test_grab_no_jump()
		_test_regrip_no_jump()
		_test_one_hand()
		_test_center_return()
		_test_clamp()
		_test_axis_offset()
		_test_small_radius()
	print("air_wheel_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


## Punkt na wieńcu pod kątem th [°] (0 = 3:00, 90 = 12:00), z przesunięciem
## wzdłuż osi kolumny (dłoń przed albo za płaszczyzną wieńca).
func _pt(th: float, radius := R, along := 0.0) -> Vector3:
	var t := deg_to_rad(th)
	var axis := right.cross(up)
	return center + right * cos(t) * radius + up * sin(t) * radius + axis * along


func _hands(lth: float, lheld: bool, rth: float, rheld: bool) -> Array:
	return [[_pt(lth), lheld], [_pt(rth), rheld]]


func _check(name: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s %s %s" % ["ok  " if ok else "BŁĄD", name, info])


## Obrót obu rąk o deg (dodatni = zgodnie z ruchem wskazówek) krokami 3°.
func _rotate(w: AirWheel, from_l: float, from_r: float, deg: float, lheld := true, rheld := true) -> void:
	var n := int(ceil(absf(deg) / 3.0))
	for i in range(1, n + 1):
		var k := -deg * float(i) / float(n)   # zgodnie z ruchem wskazówek = kąt maleje
		w.update(_hands(from_l + k, lheld, from_r + k, rheld), center, right, up, DT)


func _test_two_hands_cw() -> void:
	var w := AirWheel.new()
	w.update(_hands(180.0, true, 0.0, true), center, right, up, DT)
	_rotate(w, 180.0, 0.0, 90.0)
	_check("dwie ręce: 90° zgodnie z zegarem -> w prawo", w.steer() > 0.0 and absf(w.angle - 90.0) < 0.5,
		"(kąt %.2f, steer %.3f)" % [w.angle, w.steer()])
	_rotate(w, 90.0, -90.0, -180.0)
	_check("dwie ręce: potem 180° przeciwnie -> w lewo", w.steer() < 0.0 and absf(w.angle + 90.0) < 0.5,
		"(kąt %.2f)" % w.angle)


func _test_grab_no_jump() -> void:
	var w := AirWheel.new()
	# Ręce złapane krzywo (40° od poziomu) - kierownica nie może skoczyć.
	var s := w.update(_hands(220.0, true, 40.0, true), center, right, up, DT)
	_check("złapanie krzywo: bez skoku", absf(s) < 1e-6, "(steer %.4f)" % s)
	# Złapanie przy obróconej kierownicy (kąt z wcześniej) - też bez skoku.
	w.reset()
	w.angle = 60.0
	s = w.update(_hands(170.0, true, -10.0, true), center, right, up, DT)
	_check("złapanie obróconej: bez skoku", absf(w.angle - 60.0) < 1e-4, "(kąt %.3f)" % w.angle)


func _test_regrip_no_jump() -> void:
	var w := AirWheel.new()
	w.update(_hands(180.0, true, 0.0, true), center, right, up, DT)
	_rotate(w, 180.0, 0.0, 60.0)
	var before := w.angle
	# Prawa puszcza, przesuwa się na 1:00 i łapie znowu; lewa cały czas trzyma.
	w.update(_hands(120.0, true, 0.0, false), center, right, up, DT)
	_check("puszczenie jednej ręki: bez skoku", absf(w.angle - before) < 1e-4, "(kąt %.3f)" % w.angle)
	w.update(_hands(120.0, true, 60.0, false), center, right, up, DT)
	w.update(_hands(120.0, true, 60.0, true), center, right, up, DT)
	_check("ponowny chwyt: bez skoku", absf(w.angle - before) < 1e-4, "(kąt %.3f)" % w.angle)
	_rotate(w, 120.0, 60.0, 30.0)
	_check("po przełożeniu dalej się kręci", absf(w.angle - (before + 30.0)) < 0.5, "(kąt %.2f)" % w.angle)


func _test_one_hand() -> void:
	for hand in [0, 1]:
		var w := AirWheel.new()
		var th := 180.0 if hand == 0 else 0.0
		var lh: bool = hand == 0
		w.update(_hands(th, lh, th, not lh), center, right, up, DT)
		_rotate(w, th, th, 45.0, lh, not lh)
		_check("jedna ręka (%s): 45° w prawo" % ["lewa", "prawa"][hand],
			w.steer() > 0.0 and absf(w.angle - 45.0) < 0.5, "(kąt %.2f)" % w.angle)


func _test_center_return() -> void:
	var w := AirWheel.new()
	w.angle = 90.0
	w.update(_hands(0.0, false, 0.0, false), center, right, up, 0.1)
	_check("puszczona: wraca o center_rate*dt", absf(w.angle - (90.0 - w.center_rate * 0.1)) < 1e-3,
		"(kąt %.2f)" % w.angle)
	for i in range(72):
		w.update(_hands(0.0, false, 0.0, false), center, right, up, DT)
	_check("puszczona: po 1 s na środku", absf(w.angle) < 1e-4, "(kąt %.4f)" % w.angle)
	w.angle = -120.0
	for i in range(144):
		w.update(_hands(0.0, false, 0.0, false), center, right, up, DT)
	_check("puszczona w lewo: wraca do zera, nie przelatuje", absf(w.angle) < 1e-4, "(kąt %.4f)" % w.angle)
	# Trzymana nieruchomo nie wraca.
	w.angle = 50.0
	for i in range(72):
		w.update(_hands(180.0, true, 0.0, true), center, right, up, DT)
	_check("trzymana: nie wraca sama", absf(w.angle - 50.0) < 1e-4, "(kąt %.3f)" % w.angle)


func _test_clamp() -> void:
	var w := AirWheel.new()
	w.update(_hands(180.0, true, 0.0, true), center, right, up, DT)
	_rotate(w, 180.0, 0.0, 400.0)
	_check("ograniczenie w prawo: steer = 1", is_equal_approx(w.steer(), 1.0) and w.angle <= w.half_range,
		"(kąt %.2f)" % w.angle)
	# Po oparciu o ogranicznik ruch wstecz działa od razu (ręce "ślizgają się").
	_rotate(w, 180.0 - 400.0, -400.0, -90.0)
	_check("od ogranicznika 90° wstecz", absf(w.angle - (w.half_range - 90.0)) < 0.5, "(kąt %.2f)" % w.angle)
	_rotate(w, 180.0 - 310.0, -310.0, -700.0)
	_check("ograniczenie w lewo: steer = -1", is_equal_approx(w.steer(), -1.0), "(steer %.3f)" % w.steer())
	for hr in [45.0, 90.0, 135.0, 225.0]:
		var w2 := AirWheel.new()
		w2.half_range = hr
		w2.update(_hands(180.0, true, 0.0, true), center, right, up, DT)
		_rotate(w2, 180.0, 0.0, hr * 0.5)
		_check("zakres +-%d°: pół obrotu = pół skrętu" % int(hr), absf(w2.steer() - 0.5) < 0.01,
			"(steer %.3f)" % w2.steer())


func _test_axis_offset() -> void:
	# Dłonie przed/za płaszczyzną wieńca - liczy się tylko rzut na płaszczyznę.
	var w := AirWheel.new()
	var axis := right.cross(up)
	var h := [[_pt(180.0) + axis * 0.08, true], [_pt(0.0) - axis * 0.05, true]]
	w.update(h, center, right, up, DT)
	h = [[_pt(150.0) + axis * 0.12, true], [_pt(-30.0) - axis * 0.02, true]]
	w.update(h, center, right, up, DT)
	_check("dłonie poza płaszczyzną: 30° w prawo", absf(w.angle - 30.0) < 0.5, "(kąt %.2f)" % w.angle)


func _test_small_radius() -> void:
	# Jedna dłoń przy samym środku - kierownica stoi, potem bez skoku.
	var w := AirWheel.new()
	w.angle = 20.0
	w.update([[_pt(0.0), false], [_pt(0.0, 0.01), true]], center, right, up, DT)
	_check("dłoń przy środku: stoi", absf(w.angle - 20.0) < 1e-4, "(kąt %.3f)" % w.angle)
	w.update([[_pt(0.0), false], [_pt(-130.0), true]], center, right, up, DT)
	_check("wyjście ze środka: bez skoku", absf(w.angle - 20.0) < 1e-4, "(kąt %.3f)" % w.angle)
