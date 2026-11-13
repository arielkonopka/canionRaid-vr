extends SceneTree
## Zrzuty powtórki wypadku (inbox powtorka-wypadku): autostrada 33, gracz
## ~100 km/h prawym pasem z botem obok, potem zjeżdża w prawą barierę
## (prawdziwe uderzenie), "auto rozbite" -> powtórka z kamery obserwatora.
## Zrzuty: przed uderzeniem, w zwolnieniu, po uderzeniu, wybuch.
##   godot --xr-mode off -s res://tests/replay_shot.gd -- KATALOG </dev/null  (okno)

var main
var f := 0
var phase := 0
var phase_t := 0.0
var out_dir := "/tmp"
var shots := [["1_przed", -1.2], ["2_uderzenie", 0.15], ["3_po", 0.9]]
var shot_i := 0
var pending := ""
var pend_f := 0
var hit_seen := false


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	gs.weather = "dry"
	gs.crash_replay = true
	EndlessTrack.test_seed = 33
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._traffic_t = 1e9
		main._bot_timer = 1e9
		main._osk_next_d = 1e9
		main._bot_rng.seed = 7
		main.car.place(main._safe_pose(600.0))
		main.car._settle_t = 0.0
		main._last_safe_dist = 600.0
	if f == 60:
		main._spawn_bot(main._last_safe_dist + 25.0, 1, 100.0)
	if f <= 60:
		return false
	phase_t += delta
	if pending != "" and f >= pend_f:
		root.get_viewport().get_texture().get_image().save_png("%s/powtorka_%s.png" % [out_dir, pending])
		print("zrzut ", pending)
		pending = ""
	match phase:
		0:
			var cxf: Transform3D = main.track.transform_at_distance(main._last_safe_dist + 2.0)
			var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - main.hwy_lane_off(0)
			# Po 6 s skręt w prawą barierę (bez sterowania prędkością - prawdziwe uderzenie).
			var aim := -off * 2.0 if phase_t < 6.0 else 9.0
			main.car.linear_velocity = -cxf.basis.z * 28.0 + cxf.basis.x * aim + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
			if phase_t < 6.0:
				main.car.global_basis = cxf.basis
				main.car.angular_velocity = Vector3.ZERO
			if main.car.hit_j > 2000.0:
				hit_seen = true
				phase = 1
				phase_t = 0.0
			elif phase_t > 9.0:
				print("BŁĄD: brak uderzenia")
				phase = 1
				phase_t = 0.0
		1:
			if phase_t > 1.2:
				main.lose_life("auto rozbite")
				phase = 2
				phase_t = 0.0
		2:
			if main.race_state == main.Race.REPLAY:
				if shot_i < shots.size() and pending == "" and absf(main._rp_t - (main._rp_key + shots[shot_i][1])) < 0.02 and main._rp_label and main._rp_label.visible:
					pending = shots[shot_i][0]
					pend_f = f + 2
					shot_i += 1
			elif main.race_state == main.Race.EXPLODING:
				if phase_t > 0.0 and pending == "" and main._cine_t > 0.6:
					pending = "4_wybuch"
					pend_f = f + 2
					phase = 3
		3:
			if pending == "":
				print("replay_shot: uderzenie %s, zrzutów %d" % [hit_seen, shot_i + 1])
				quit(0)
				return true
	if phase_t > 30.0:
		quit(1)
		return true
	return false
