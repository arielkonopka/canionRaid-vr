extends SceneTree
## Bot "ekstremista" w grze (inbox bot-ekstremista): autostrada, gracz jedzie
## ~110 km/h prawym pasem, wolne auto przed nim na lewym pasie, ekstremista
## pojawia się za graczem. W 60 s ma: wyprzedzić gracza, trąbić, mrugać
## długimi, nie hamować przed autami (tylko łuki - tryb "lift": nigdy),
## dać punkty za przepuszczenie (bez kontaktu).
##   godot --headless --xr-mode off -s res://tests/extremist_play_test.gd </dev/null

var main
var f := 0
var t := 0.0
var fails := 0
var horn_seen := false
var beam_seen := false
var max_brake := 0.0
var passed := false
var max_kmh := 0.0
var pts0 := 0


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	gs.weather = "dry"
	# Stała trasa: na losowej czasem łuk przy 280 km/h - ekstremista w trybie
	# "lift" (nigdy nie hamuje) wtedy wylatuje, zgodnie z zasadą.
	var a := OS.get_cmdline_user_args()
	EndlessTrack.test_seed = int(a[0]) if a.size() > 0 else 33
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
		main._traffic_t = 1e9
		main._bot_timer = 1e9
		main._osk_next_d = 1e9
		main._bot_rng.seed = 7
		# Gracz dalej na trasie - za nim musi być droga dla ekstremisty.
		main.car.place(main._safe_pose(900.0))
		main.car._settle_t = 0.0
		main._last_safe_dist = 900.0
		main._sec_d0 = 900.0                  # premia za odcinek bez "teleportu"
		main._sec_t0 = main.race_time
		# Wolne auto daleko przed graczem na lewym pasie (ekstremista zmienia pas
		# albo trąbi; przy 150 m przed graczem po wyprzedzeniu nie miał miejsca
		# i czasem taranował - zgodnie z zasadą "nigdy nie hamuje").
		main._spawn_bot(main._last_safe_dist + 500.0, 1, 90.0)
	if f == 30:
		for i in range(20):
			main._spawn_extremist()
			if main._extremist:
				break
		_check(main._extremist != null, "ekstremista się pojawił")
		pts0 = main.score.points
		if main._extremist == null:
			return _end()
	if f <= 30:
		return false
	t += delta
	# Gracz prowadzony po prawym pasie ~110 km/h (jak feud_play_test).
	var cxf: Transform3D = main.track.transform_at_distance(main._last_safe_dist + 2.0)
	var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - main.hwy_lane_off(0)
	main.car.global_basis = cxf.basis
	main.car.linear_velocity = -cxf.basis.z * 30.0 - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
	main.car.angular_velocity = Vector3.ZERO
	var x: StuntCar = main._extremist
	if x and is_instance_valid(x) and x.get_node_or_null("Driver"):
		var drv: BotDriver = x.get_node("Driver")
		if drv._x_horn:
			horn_seen = true
		if not drv._x_out.is_empty() and float(drv._x_out.get("beam", 0.0)) > 0.0:
			beam_seen = true
		max_brake = maxf(max_brake, x.brake)
		max_kmh = maxf(max_kmh, x.speed * 3.6)
		if drv.dist - main._last_safe_dist > 6.0:
			passed = true

	if t > 60.0 or (passed and t > 15.0):
		return _end()
	return false


func _end() -> bool:
	_check(passed, "wyprzedził gracza (maks. %.0f km/h)" % max_kmh)
	_check(horn_seen, "trąbił")
	_check(beam_seen, "mrugał długimi")
	_check(max_brake < 0.01, "nie hamował (maks. hamulec %.2f)" % max_brake)
	_check(main._x_passes == 1, "premia za przepuszczenie (%d)" % main._x_passes)
	# Auto ekstremisty wraca do puli w trakcie mrugania (przegląd chmury
	# 2026-11-13): następny bot z tego węzła ma zwykłą moc i zgaszone długie.
	var x: StuntCar = main._extremist
	if x and is_instance_valid(x):
		x.set_high_beam(1.0)
		main._extremist = null
		main._bots.erase(x)
		main._retire_bot(x)
		var b: StuntCar = main._take_bot()
		_check(b == x, "to samo auto z puli")
		_check(absf(b.engine_power_kw - 250.0) < 0.5, "moc po puli %.0f kW" % b.engine_power_kw)
		var lit := false
		for mi in b._beam_stars:
			lit = lit or mi.visible
		_check(not lit, "długie zgaszone po puli")
		main._park_bot(b)
	print("extremist_play_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
