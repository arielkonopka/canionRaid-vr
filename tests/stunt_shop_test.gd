extends SceneTree
## Test logiki: detektor sztuczek (StuntTracker) i cennik warsztatu
## (WorkshopShop) - bez sceny i fizyki, dane syntetyczne.
##   godot --headless --xr-mode off -s res://tests/stunt_shop_test.gd </dev/null
## Kod wyjścia 1 przy błędzie.

const ST := preload("res://scripts/stunt_tracker.gd")
const WS := preload("res://scripts/workshop_shop.gd")
const SK := preload("res://scripts/score_keeper.gd")
const DT := 1.0 / 120.0

var fails := 0


func _initialize() -> void:
	_test_plain_jump()
	_test_flip()
	_test_roof_landing()
	_test_loop()
	_test_hills_no_loop()
	_test_shop()
	print("stunt_shop_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  BŁĄD: ", what)


## Symulacja: `phases` = [[czas, oś lokalna (albo ZERO), rad/s, koła], ...].
## Basis obracany zgodnie z prędkością kątową. Zwraca wszystkie sztuczki.
func _run(phases: Array, track_up_fn: Callable = Callable()) -> Array:
	var st = ST.new()
	var b := Basis.IDENTITY
	var out := []
	for ph in phases:
		var n := int(round(float(ph[0]) / DT))
		for i in n:
			var axis_local: Vector3 = ph[1]
			var w_world := Vector3.ZERO
			if axis_local != Vector3.ZERO:
				w_world = (b * axis_local).normalized() * float(ph[2])
				b = Basis(w_world.normalized(), float(ph[2]) * DT) * b
				b = b.orthonormalized()
			var up: Vector3 = track_up_fn.call(b) if track_up_fn.is_valid() else Vector3.UP
			out.append_array(st.step(DT, b, w_world, int(ph[3]), 30.0, up))
	return out


func _test_plain_jump() -> void:
	var r := _run([[0.5, Vector3.ZERO, 0.0, 4], [1.2, Vector3.ZERO, 0.0, 0], [0.5, Vector3.ZERO, 0.0, 4]])
	_check(r.size() == 1 and r[0]["kind"] == "jump", "zwykły skok wykryty")
	if r.size() == 1:
		_check(bool(r[0]["clean"]) and int(r[0]["flips"]) == 0, "czysty skok bez obrotów")
		_check(int(r[0]["points"]) == 0, "lot 1,2 s bez punktów za czas (próg 2 s)")
	var long := _run([[0.5, Vector3.ZERO, 0.0, 4], [2.5, Vector3.ZERO, 0.0, 0], [0.5, Vector3.ZERO, 0.0, 4]])
	_check(long.size() == 1 and int(long[0]["points"]) >= 100, "lot 2,5 s daje punkty (%s)" % str(long))
	# Skala użytkownika (2026-11-09): 2-10 s 1, potem co 5 s do 30, co 2 s do 40, co 1 s.
	for c in [[1.9, 0], [2.0, 1], [9.9, 1], [10.0, 1], [15.0, 2], [30.0, 5], [32.0, 6], [40.0, 10], [43.0, 13]]:
		_check(ST.air_units(c[0]) == c[1], "air_units(%.1f) = %d (jest %d)" % [c[0], c[1], ST.air_units(c[0])])
	var hop := _run([[0.5, Vector3.ZERO, 0.0, 4], [0.2, Vector3.ZERO, 0.0, 0], [0.5, Vector3.ZERO, 0.0, 4]])
	_check(hop.is_empty(), "podskok < MIN_AIR to nie skok")


func _test_flip() -> void:
	# Salto w tył: 1 s w powietrzu, 2π rad/s wokół osi x auta.
	var r := _run([[0.3, Vector3.ZERO, 0.0, 4], [1.0, Vector3.RIGHT, TAU, 0], [0.5, Vector3.ZERO, 0.0, 4]])
	_check(r.size() == 1 and int(r[0].get("flips", 0)) == 1, "salto policzone (%s)" % str(r))
	var rr := _run([[0.3, Vector3.ZERO, 0.0, 4], [1.0, Vector3.BACK, TAU, 0], [0.5, Vector3.ZERO, 0.0, 4]])
	_check(rr.size() == 1 and int(rr[0].get("rolls", 0)) == 1, "beczka w powietrzu policzona")


func _test_roof_landing() -> void:
	# Pół obrotu i lądowanie na dachu (koła "na ziemi" - test tylko logiki).
	var r := _run([[0.3, Vector3.ZERO, 0.0, 4], [1.0, Vector3.RIGHT, PI, 0], [0.5, Vector3.ZERO, 0.0, 4]])
	_check(r.size() == 1 and not bool(r[0]["clean"]) and int(r[0]["flips"]) == 0,
			"lądowanie na dachu - bez punktów za obroty")


func _test_loop() -> void:
	# Pętla: na kołach, obrót wokół x o 360° w 3 s; góra toru = basis.y auta.
	var r := _run([[0.5, Vector3.ZERO, 0.0, 4], [3.0, Vector3.RIGHT, TAU / 3.0, 4], [1.0, Vector3.ZERO, 0.0, 4]],
			func(b: Basis): return b.y)
	var loops := r.filter(func(e): return e["kind"] == "loop")
	_check(loops.size() == 1, "pętla wykryta (%d)" % loops.size())
	var r2 := _run([[3.0, Vector3.BACK, TAU / 3.0, 4]], func(b: Basis): return b.y)
	_check(r2.filter(func(e): return e["kind"] == "barrel").size() == 1, "beczka (korkociąg) wykryta")


func _test_hills_no_loop() -> void:
	# Garby: ±15° w przód i w tył wiele razy - bez pętli.
	var ph := []
	for i in 20:
		ph.append([0.5, Vector3.RIGHT, deg_to_rad(30.0), 4])
		ph.append([0.5, Vector3.RIGHT, -deg_to_rad(30.0), 4])
	_check(_run(ph).is_empty(), "garby nie dają pętli")


func _test_shop() -> void:
	var dmg := {"structure": 0.8, "engine": 0.4, "gearbox": 0.0,
			"brakes": [0.2, 0.0, 0.0, 0.0], "suspension": [0.0, 0.0, 0.0, 0.0]}
	var sk = SK.new()
	sk.points = 1000
	var off: Array = WS.offers(dmg, sk.points)
	var ids := off.map(func(o): return o["id"])
	_check("repair:full" in ids and "repair:engine" in ids and "repair:brakes" in ids, "oferty napraw")
	_check(not ("repair:gearbox" in ids), "bez oferty dla nieuszkodzonej strefy")
	_check(WS.zone_cost(dmg, "engine") == 360, "cena silnika 40%% (%d)" % WS.zone_cost(dmg, "engine"))
	_check(WS.buy("repair:engine", dmg, sk) == "repaired" and float(dmg["engine"]) == 0.0, "naprawa silnika")
	_check(sk.points == 640, "punkty po naprawie (%d)" % sk.points)
	_check(WS.buy("repair:structure", dmg, sk) == "", "za mało punktów na karoserię (800)")
	_check(sk.points == 640, "nieudany zakup nie zabiera punktów")
	_check(WS.buy("repair:brakes", dmg, sk) == "repaired" and float(dmg["brakes"][0]) == 0.0 and sk.points == 610, "naprawa hamulców (30)")
	var wreck := {"structure": 1.0, "engine": 1.0, "gearbox": 1.0,
			"brakes": [1.0, 1.0, 1.0, 1.0], "suspension": [1.0, 1.0, 1.0, 1.0]}
	var full: Dictionary = WS.offers(wreck, 0)[0]
	_check(full["id"] == "repair:full" and int(full["cost"]) == 3150 and not bool(full["affordable"]),
			"pełna naprawa wraku 3150 (%s)" % str(full))
	# Sztuczki zasilają ten sam portfel.
	var sk2 = SK.new()
	var p: Array = sk2.award_free("jump", 500, 1.0, "SALTO")
	_check(sk2.points == 500 and String(p[0]["text"]).ends_with("SALTO"), "award_free do portfela")
