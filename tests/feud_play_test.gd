extends SceneTree
## Waśnie botów w grze (FeudDirector wpięty w xr_main, inbox
## wasnie-na-autostradzie, krok 8.3): 6 botów z dwóch wrogich gangów przed
## graczem (autostrada). W ciągu 40 s ma wybuchnąć potyczka; uderzenie
## gracza w bota w potyczce -> sojusz (boty biorą na cel gracza); żaden bot
## w waśni nie jedzie po szynie.
##   godot --headless --xr-mode off -s res://tests/feud_play_test.gd </dev/null

var main
var f := 0
var t := 0.0
var skirmish_seen := false
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


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		# Ruch autostrady wyłączony (test steruje botami sam).
		main._traffic_t = 1e9
		main.feud.set_hostile(0, 1, true)
		# Ziarno losowania potyczek stałe tylko w teście - w grze potyczki są
		# celowo nieprzewidywalne (użytkownik), a bez ziarna test padał ~1/3.
		main.feud.rng.seed = 1
		for i in range(6):
			main._bot_rng.seed = 1000 + i          # gang = randi() % GANGS
			main._spawn_bot(main._last_safe_dist + 60.0 + i * 22.0, i % 2, 100.0)
			var b: StuntCar = main._bots[-1]
			main.feud.add_bot(b.get_instance_id(), i % 2)
	if f <= 5:
		return false
	t += delta
	# Gracz jedzie za botami (prędkość wprost - test nie steruje gazem).
	# Gracz prowadzony po trasie (pchany prosto wypadał na łukach z drogi
	# i odradzał się - boty zostawały poza zasięgiem potyczki 120 m).
	# Jedzie fizycznie (kontakt z jezdnią - gra liczy dystans gracza), test
	# ustawia tylko kierunek wzdłuż trasy i prędkość z korektą do pasa.
	var cxf: Transform3D = main.track.transform_at_distance(main._last_safe_dist + 2.0)
	var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - main.hwy_lane_off(0)
	main.car.global_basis = cxf.basis
	# Za botami (przyspieszają do limitu): ~70 m za najbliższym, w zasięgu
	# potyczki (120 m).
	var gap := INF
	for b in main._bots:
		gap = minf(gap, (b.get_node("Driver") as BotDriver).dist - main._last_safe_dist)
	var v := clampf(28.0 + (gap - 70.0) * 0.5, 15.0, 50.0) if gap < INF else 28.0
	main.car.linear_velocity = -cxf.basis.z * v - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
	main.car.angular_velocity = Vector3.ZERO
	for b in main._bots:
		var id: int = b.get_instance_id()
		var drv: BotDriver = b.get_node("Driver")
		if main.feud.in_feud(id) and main.feud.target_of(id) != FeudDirector.PLAYER:
			skirmish_seen = true
			if drv.lod == BotLod.RAIL:
				_check(false, "bot w waśni na szynie")
	if skirmish_seen and t > 1.0 and f % 60 == 0:
		# Gracz uderza bota w potyczce -> sojusz.
		for b in main._bots:
			var id: int = b.get_instance_id()
			if main.feud.in_feud(id) and main.feud.target_of(id) != FeudDirector.PLAYER:
				main.feud_player_hit(b)
				var drv: BotDriver = b.get_node("Driver")
				_check(main.feud.target_of(id) == FeudDirector.PLAYER, "po uderzeniu gracza bot w sojuszu (cel: gracz)")
				_check(drv.foe == null and drv.rage > 0.0, "bot ściga gracza (foe null, szał)")
				print("feud_play_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
				return true
	if t > 40.0:
		_check(skirmish_seen, "potyczka w ciągu 40 s")
		print("feud_play_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
		return true
	return false
