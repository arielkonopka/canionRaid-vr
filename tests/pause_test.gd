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
	root.get_node("GameSettings").persist = false      # zmiany w menu pauzy nie do pliku ustawień
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
			# Menu pauzy = ustawienia gry: grupa "Radio".
			var pm: PauseMenu = main._pause
			pm.enter_group("radio")
			pm.selected = pm.find_entry("radio_on")
			pm.change(1)
			_check(main._radio.is_on, "radio włączone z pauzy (ustawienie Radio przy starcie)")
		150:
			_check(absf(car.global_position.z - z0) < 0.01, "auto stoi w pauzie")
			print("radio: '", main._radio_label.text.replace("\n", " | "), "'")
			_check(main._radio_label.text != "" and not "brak" in main._radio_label.text, "napis co gra")
			var pm: PauseMenu = main._pause
			var gs = root.get_node("GameSettings")
			var st: int = main._radio.station
			pm.selected = pm.find_entry("radio_station")
			pm.change(1)
			_check(main._radio.station != st, "zmiana stacji")
			var v: int = gs.radio_volume
			pm.selected = pm.find_entry("radio_volume")
			pm.change(-1)
			_check(gs.radio_volume == v - 1, "głośność")
			print(pm.label.text)
			# Zmiana auta: przy powrocie pytanie, B cofa zmianę.
			pm.enter_group("car")
			var kw0: int = gs.engine_power
			pm.selected = pm.find_entry("engine_power")
			pm.change(1)
			pm.try_resume()
			_check(pm._confirm and pm.is_open(), "zmiana mocy - pytanie o nową jazdę")
			print(pm.label.text)
			pm.cancel()
			_check(gs.engine_power == kw0, "B cofa zmianę auta")
			_check(not paused and not pm.is_open(), "powrót do jazdy")
			car.linear_velocity = -car.global_basis.z * 20.0
		200:
			_check(absf(car.global_position.z - z0) > 0.5, "auto jedzie po pauzie")
			# Po końcu jazdy przycisk menu = ekran tytułowy, bez pauzy (napisy
			# końca gry i pauzy nachodziły na siebie - użytkownik 2026-11-10).
			main.race_state = main.Race.FINISHED
			main._on_xr_button("menu_button", false)
			_check(not main._pause.is_open(), "po końcu jazdy menu nie otwiera pauzy")
		210:
			var cs = current_scene
			_check(cs != null and cs.scene_file_path == main.TITLE_SCENE, "po końcu jazdy menu -> ekran tytułowy (%s)" % [cs.scene_file_path if cs else "brak"])
			print("pause_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
	return false
