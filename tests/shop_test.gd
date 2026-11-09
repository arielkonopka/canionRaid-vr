extends SceneTree
## Sklep warsztatu i stacji (użytkownik 2026-11-09: punkty za każdą rzecz -
## wymianę silnika, naprawę; naprawy też na stacji): ceny w punktach,
## zakup bez punktów się nie udaje, menu zostaje otwarte do "Wyjazd".
##   godot --headless --xr-mode off -s res://tests/shop_test.gd </dev/null

var main
var f := 0
var fails := 0


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "canyon"
	gs.engine_power = 130
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _find(kind: String, id := "") -> int:
	for i in range(main._ws_options.size()):
		var o: Dictionary = main._ws_options[i]
		if kind == "engine":
			if str(o.get("id", "")).begins_with("engine:"):
				return i
		elif o["kind"] == kind and (id == "" or o.get("id", "") == id):
			return i
	return -1


func _physics_process(_d: float) -> bool:
	f += 1
	if f != 5:
		return false
	var car: StuntCar = main.car
	main.race_state = main.Race.RACING
	# Stacja: tylko naprawy.
	car.damage["engine"] = 0.5
	main.score.points = 0
	main._enter_workshop(0, "station")
	_check(main.race_state == main.Race.WORKSHOP, "postój na stacji otwiera sklep")
	_check(_find("engine") < 0, "na stacji nie ma wymiany silnika")
	var ri := _find("offer", "repair:engine")
	_check(ri >= 0, "naprawa silnika na liście")
	main.workshop_choose(ri)
	_check(car.damage["engine"] > 0.4, "bez punktów naprawa się nie udaje")
	main.score.points = 2000
	main.workshop_choose(_find("offer", "repair:engine"))
	_check(car.damage["engine"] == 0.0 and main.score.points < 2000, "naprawa za punkty (%d pkt zostało)" % main.score.points)
	_check(main.race_state == main.Race.WORKSHOP, "po zakupie menu dalej otwarte")
	main.workshop_choose(main.ws_exit_index())
	_check(main.race_state == main.Race.RACING, "Wyjazd zamyka sklep")
	# Warsztat: wymiana silnika za punkty.
	main._next_ws = {"stop": 0.0}
	main._enter_workshop(0)
	var ei := _find("engine")
	_check(ei >= 0, "w warsztacie jest wymiana silnika")
	var kw0: float = car.engine_power_kw
	var pts0: int = main.score.points
	main.workshop_choose(ei)
	_check(car.engine_power_kw > kw0 and main.score.points < pts0,
			"silnik %d -> %d kW za %d pkt" % [kw0, car.engine_power_kw, pts0 - main.score.points])
	_check(not "dźwig" in main._ws_label.text, "w menu nie ma dźwigu")
	main.workshop_choose(main.ws_exit_index())
	print("shop_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
	return true
