extends SceneTree
## Powtórka wypadku w grze (inbox powtorka-wypadku): autostrada, gracz jedzie
## ~100 km/h z botem obok. "auto rozbite" -> REPLAY (boty wyłączone, auto
## z zapisu, kamera nad autem) -> EXPLODING -> RACING. "nowe auto" - od razu
## wybuch. Spust pomija powtórkę (nie w pierwszych 0,8 s po ściemnieniu).
##   godot --headless --xr-mode off -s res://tests/replay_play_test.gd </dev/null

var main
var f := 0
var t := 0.0
var fails := 0
var phase := 0
var phase_t := 0.0
var bot: StuntCar
var seen_replay := false
var replay_len := 0.0
var bot_disabled := false
var cam_above := true
var car_moved := false
var xf_crash: Transform3D
var early_checked := false


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	gs.weather = "dry"
	gs.crash_replay = true
	EndlessTrack.test_seed = 33
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _drive() -> void:
	var cxf: Transform3D = main.track.transform_at_distance(main._last_safe_dist + 2.0)
	var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - main.hwy_lane_off(0)
	main.car.global_basis = cxf.basis
	main.car.linear_velocity = -cxf.basis.z * 28.0 - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
	main.car.angular_velocity = Vector3.ZERO


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._traffic_t = 1e9
		main._bot_timer = 1e9
		main._osk_next_d = 1e9
		main.car.place(main._safe_pose(600.0))
		main.car._settle_t = 0.0
		main._last_safe_dist = 600.0
		main._spawn_bot(main._last_safe_dist + 30.0, 1, 100.0)
		bot = main._bots[-1] if not main._bots.is_empty() else null
	if f <= 5:
		return false
	t += delta
	phase_t += delta
	match phase:
		0:   # 8 s jazdy, potem wypadek
			_drive()
			if phase_t > 8.0:
				_check(main._rec.count() > 300, "zapis %d klatek" % main._rec.count())
				xf_crash = main.car.global_transform
				main.lose_life("auto rozbite")
				_check(main.race_state == main.Race.REPLAY, "auto rozbite -> powtórka")
				phase = 1
				phase_t = 0.0
		1:   # powtórka
			if main.race_state == main.Race.REPLAY:
				seen_replay = true
				replay_len = phase_t
				if bot and bot.process_mode == Node.PROCESS_MODE_DISABLED:
					bot_disabled = true
				if phase_t > 0.5:
					if main.origin.global_position.y < main.car.global_position.y + 1.5:
						cam_above = false
					if main.car.global_position.distance_to(xf_crash.origin) > 50.0:
						car_moved = true
			elif main.race_state == main.Race.EXPLODING:
				_check(seen_replay and replay_len > 6.0 and replay_len < 11.0, "powtórka trwała %.1f s" % replay_len)
				_check(bot_disabled, "boty wyłączone w powtórce")
				_check(car_moved, "auto jedzie z zapisu (ponad 50 m)")
				_check(cam_above, "kamera nad autem")
				_check(main.car.global_position.distance_to(xf_crash.origin) < 0.5, "wybuch w miejscu wypadku")
				_check(bot == null or bot.process_mode != Node.PROCESS_MODE_DISABLED, "boty z powrotem")
				phase = 2
				phase_t = 0.0
			elif phase_t > 15.0:
				_check(false, "powtórka nie skończyła się (stan %d)" % main.race_state)
				return _end()
		2:   # wybuch -> jazda
			if main.race_state == main.Race.RACING:
				_check(main._rec.count() == 0 or main._rec.count() < 10, "zapis wyczyszczony po odrodzeniu")
				phase = 3
				phase_t = 0.0
			elif phase_t > 10.0:
				_check(false, "brak odrodzenia")
				return _end()
		3:   # "nowe auto" - bez powtórki
			_drive()
			if phase_t > 5.0:
				main.lose_life("nowe auto")
				_check(main.race_state == main.Race.EXPLODING, "nowe auto -> od razu wybuch")
				phase = 4
				phase_t = 0.0
		4:
			if main.race_state == main.Race.RACING:
				phase = 5
				phase_t = 0.0
			elif phase_t > 10.0:
				_check(false, "brak odrodzenia po nowym aucie")
				return _end()
		5:   # pominięcie spustem
			_drive()
			if phase_t > 5.0:
				main.lose_life("upadek")
				phase = 6
				phase_t = 0.0
		6:
			# Spust w pierwszych 0,8 s po ściemnieniu (gaz po uderzeniu) - nic.
			if phase_t > 0.6 and phase_t < 0.62:
				main._on_xr_button("trigger_click", true)
			if phase_t > 0.9 and not early_checked:
				early_checked = true
				_check(main.race_state == main.Race.REPLAY, "spust zaraz po ściemnieniu nie pomija")
			if phase_t > 1.3 and phase_t < 1.32:
				main._on_xr_button("trigger_click", true)
			if main.race_state == main.Race.EXPLODING:
				_check(phase_t > 1.3 and phase_t < 1.6, "spust pomija powtórkę (%.2f s)" % phase_t)
				return _end()
			if phase_t > 5.0:
				_check(false, "pominięcie nie zadziałało")
				return _end()
	return false


func _end() -> bool:
	print("replay_play_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
