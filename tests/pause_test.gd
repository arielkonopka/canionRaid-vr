extends SceneTree
## Menu pauzy z radiem (użytkownik 2026-11-09: radio sterowane z pauzy).
## Pauza zatrzymuje auto, radio gra dalej i pokazuje "co gra"; powrót
## wznawia jazdę.
##   godot --headless --xr-mode off -s res://tests/pause_test.gd </dev/null

var main
var f := 0
var fails := 0
var z0 := 0.0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		print("  BŁĄD: ", what)


func _process(_d: float) -> bool:
	f += 1
	var car = main.car
	match f:
		60:
			# Gaz nadpisuje co klatkę wejście sceny - auto dostaje prędkość.
			car.linear_velocity = -car.global_basis.z * 20.0
		90:
			_check(main._pause != null and main._radio != null, "menu pauzy i radio zbudowane")
			main._set_paused(true)
			_check(paused and main._pause.is_open(), "pauza otwarta, drzewo stoi")
			z0 = car.global_position.z
			main._pause.selected = PauseMenu.ITEMS.find("radio")
			main._pause.accept()
			_check(main._radio.is_on, "radio włączone z pauzy")
		150:
			_check(absf(car.global_position.z - z0) < 0.01, "auto stoi w pauzie")
			print("radio: '", main._radio_label.text.replace("\n", " | "), "'")
			_check(main._radio_label.text != "" and not "brak" in main._radio_label.text, "napis co gra")
			var st: int = main._radio.station
			main._pause.selected = PauseMenu.ITEMS.find("station")
			main._pause.change(1)
			_check(main._radio.station != st, "zmiana stacji")
			var v := PauseMenu.volume_index
			main._pause.selected = PauseMenu.ITEMS.find("volume")
			main._pause.change(-1)
			_check(PauseMenu.volume_index == v - 1, "głośność")
			print(main._pause.label.text)
			main._pause.selected = PauseMenu.ITEMS.find("resume")
			main._pause.accept()
			_check(not paused and not main._pause.is_open(), "powrót do jazdy")
			car.linear_velocity = -car.global_basis.z * 20.0
		200:
			_check(absf(car.global_position.z - z0) > 0.5, "auto jedzie po pauzie")
			print("pause_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
	return false
