extends SceneTree
## Potyczka na drugiej jezdni w grze (OncomingSkirmish wpięty w xr_main):
## autostrada, gracz jedzie ~100 km/h. Scenka ma się pojawić, wystartować
## (klimaks przed graczem), auta mają stać na drugiej jezdni (za pasem
## rozdziału), a po końcu wrócić do puli i zwolnić miejsce na następną.
##   godot --headless --xr-mode off -s res://tests/oncoming_play_test.gd </dev/null

var main
var f := 0
var t := 0.0
var fails := 0
var seen := false
var started_at := -1.0
var start_gap := 0.0
var ended := false
var worst_side := -INF


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


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._traffic_t = 1e9                 # bez zwykłego ruchu
		main._osk_next_d = 0.0
	if f <= 5:
		return false
	t += delta
	# Auto prowadzone po trasie (prosto pchane wypadało na łukach z drogi,
	# a odrodzenie kasuje scenkę).
	# Jedzie fizycznie (kontakt z jezdnią - gra liczy dystans gracza), test
	# ustawia tylko kierunek wzdłuż trasy i prędkość z korektą do pasa.
	var cxf: Transform3D = main.track.transform_at_distance(main._last_safe_dist + 2.0)
	var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - main.hwy_lane_off(0)
	main.car.global_basis = cxf.basis
	main.car.linear_velocity = -cxf.basis.z * 28.0 - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
	main.car.angular_velocity = Vector3.ZERO
	if main._osk != null:
		if not seen:
			seen = true
			print("scenka: ", main._osk.kind)
		if main._osk_started and started_at < 0.0:
			started_at = t
			start_gap = float(main._osk_cars["b"]["dist"]) - main._last_safe_dist
		# Auta scenki po drugiej stronie pasa rozdziału.
		for who in ["a", "b"]:
			var o: Dictionary = main._osk_cars[who]
			var c: StuntCar = o["car"]
			if not c.visible:
				continue
			var xf: Transform3D = main.track.transform_at_distance(float(o["dist"]))
			var side: float = (c.global_position - xf.origin).dot(xf.basis.x)
			worst_side = maxf(worst_side, side)
	elif seen and not ended:
		ended = true
		_check(started_at > 0.0, "scenka wystartowała (odstęp %.0f m)" % start_gap)
		_check(worst_side < -(HighwayGenerator.WIDTH * 0.5 + TrackGenerator.HIGHWAY_MEDIAN),
				"auta na drugiej jezdni (najbliżej %.1f m od osi naszej jezdni)" % worst_side)
		_check(main._osk_next_d > main._last_safe_dist + 1000.0, "następna scenka najwcześniej za 1,2 km")
		var in_scene := 0
		for o in main._oncoming:
			if o.has("osk"):
				in_scene += 1
		_check(in_scene == 0, "auta scenki zwolnione")
		print("oncoming_play_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
		return true
	if t > 60.0:
		_check(false, "scenka w 60 s (pojawiła się: %s, start: %s)" % [seen, started_at > 0.0])
		print("oncoming_play_test: BŁĄD (%d)" % fails)
		return true
	return false
