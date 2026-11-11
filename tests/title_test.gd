extends SceneTree
## Test ekranu tytułowego bez okna: zmienia opcje, wciska START
## i sprawdza, czy scena jazdy dostała wybrane ustawienia.
##   godot --headless --xr-mode off -s res://tests/title_test.gd
var f := 0
var title
func _initialize() -> void:
	title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
func _process(_d: float) -> bool:
	f += 1
	if f == 5:
		# Ustawia opcje przez to samo API, którego używa wejście: wejście do
		# grupy, wybór wiersza, zmiana wartości, wyjście.
		var want := {"engine_type": "diesel", "engine_power": 250, "transmission": "manual",
				"suspension": "stiff", "esp_enabled": false, "paint": "avocado",
				"stick_sensitivity": 70, "cockpit_alpha": 60}
		var gs = root.get_node("GameSettings")
		gs.persist = false        # nie nadpisujemy ustawień gracza
		# Wybór modelu ustawia fabryczny silnik, napęd, zawieszenie i masę.
		gs.set_option("body_model", "muscle")
		var fab := [gs.engine_type, gs.engine_power, gs.drive_layout, gs.suspension, gs.body_mass, gs.factory_mass()]
		print("muscle fabrycznie: ", fab, "  ", "OK" if fab == ["petrol", 180, "rwd", "soft", 0, 1550.0] else "FAIL")
		gs.set_option("body_model", "sedan")
		for g in gs.GROUPS:
			title.enter_group(g["id"])
			for i in range(title._entries.size()):
				var e: Dictionary = title._entries[i]
				if e["type"] != "option" or not want.has(e["opt"]["key"]):
					continue
				var key: String = e["opt"]["key"]
				title._selected = i
				var guard := 0
				while gs.get(key) != want[key] and guard < 10:
					title._change(1)
					guard += 1
				print("  ", key, " -> ", gs.get(key), "   podpowiedź: ", title._hint.text.replace("\n", " | "))
			title._cancel()       # powrót do menu głównego
		print("menu główne: ", title._rows.map(func(r): return r.text).filter(func(t): return t != ""))
		print("skrót grupy 'car': ", title._group_summary("car"))
		title._selected = title._entries.size() - 1   # START
		title._accept()
	if f == 15:
		var scene = current_scene
		print("scena: ", scene.name if scene else "?")
		var car = scene.get_node_or_null("Car") if scene else null
		if car:
			print("czułość=%d%%, przezroczystość=%d%%, lakier=%s  auto: napęd=%s %d kW (moment %d Nm, masa %d kg) automat=%s k=%d abs=%s tcs=%s esp=%s" % [root.get_node("GameSettings").stick_sensitivity, root.get_node("GameSettings").cockpit_alpha, car._paint_mat.albedo_color, car.engine_type, car.engine_power_kw, car.peak_torque(), car.mass, car.automatic, car.spring_k, car.abs_enabled, car.tcs_enabled, car.esp_enabled])
		# Opcja Cienie działa od razu na słońcu sceny jazdy.
		var gs2 = root.get_node("GameSettings")
		var sun: DirectionalLight3D = scene.get_node("Sun")
		var res := []
		for v in ["off", "near", "full"]:
			gs2.shadows = v
			gs2.apply_shadows(sun)
			res.append([sun.shadow_enabled, sun.directional_shadow_max_distance])
		print("cienie: ", res, "  ", "OK" if res == [[false, 80.0], [true, 40.0], [true, 80.0]] else "FAIL")
		return true
	return false
