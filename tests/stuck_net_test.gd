extends SceneTree
## Siatka bezpieczeństwa dla auta zawieszonego (użytkownik przez chmurę
## 2026-11-11): automatyczne stawianie na koła 1. i 2. w miejscu, 3. 15 m
## dalej, 4. utrata życia "utknięcie". Przycisk gracza tego nie liczy.
##   godot --headless --xr-mode off -s res://tests/stuck_net_test.gd </dev/null

var main
var f := 0
var fails := 0


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _dist() -> float:
	return float(main.track.lateral_offset(main.car.global_position)["sample"]["dist"])


func _physics_process(_d: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._grace_t = 0.0
		main._traffic_t = 1e9
		main._bot_timer = 1e9
		main.car.place(main._safe_pose(400.0))
	if f != 30:
		return false
	var d0 := _dist()
	# Przycisk gracza: nigdy nie przestawia dalej.
	for i in range(4):
		main._use_crane()
	_check(absf(_dist() - d0) < 9.0 and main.race_state == main.Race.RACING,
			"przycisk 4x: auto w miejscu, bez utraty życia (%.1f -> %.1f m)" % [d0, _dist()])
	main._auto_rights.clear()
	var lives: int = main.cranes_left
	main._use_crane(true)
	main._use_crane(true)
	var d2 := _dist()
	main._use_crane(true)
	var d3 := _dist()
	_check(d3 - d2 > 10.0, "3. automatyczne: 15 m dalej (%.1f -> %.1f m)" % [d2, d3])
	main._use_crane(true)
	_check(main.race_state != main.Race.RACING or main.cranes_left < lives,
			"4. automatyczne: utrata życia (stan %d)" % main.race_state)
	print("stuck_net_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
