extends SceneTree
## Auto z naprzeciwka tuż przy graczu przechodzi z jazdy po szynie
## (kinematyczne) na pełną fizykę z tą samą prędkością - zasada użytkownika
## 2026-11-11: bot uderzony przez gracza zawsze reaguje zgodnie z fizyką.
##   godot --headless --xr-mode off -s res://tests/oncoming_loose_test.gd </dev/null

var main
var f := 0
var fails := 0
var o: OncomingCar


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


func _physics_process(_d: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._traffic_t = 1e9
		main._osk_next_d = 1e9
		main._spawn_oncoming(main._last_safe_dist + 60.0, 0, 100.0)
		o = main._oncoming.back()
		_check(o.car.freeze, "auto z naprzeciwka na szynie (kinematyczne)")
	if f == 6:
		# Gracz przeniesiony tuż obok (jak po przeskoczeniu bariery).
		var c: StuntCar = o.car
		main.car.global_position = c.global_position + c.global_basis.x * 3.0
	if f == 8:
		var c: StuntCar = o.car
		_check(o.loose and not c.freeze, "przy graczu - pełna fizyka")
		var v := c.linear_velocity.length() * 3.6
		_check(absf(v - 100.0) < 10.0, "zachowuje prędkość (%.0f km/h)" % v)
		print("oncoming_loose_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
		return true
	return false
