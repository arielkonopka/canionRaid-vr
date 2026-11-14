extends SceneTree
## Budowle w grze (StructurePlan, etap 3; zlecenie etap3-budowle pkt 8).
## Rodzaj z argumentu: most (trasa 33, 31,4 km). Gracz jedzie szybko do
## budowli, na niej ~90 km/h prawym pasem. Sprawdza: przejazd bez utraty
## życia, woda i filary w scenie, ziemia z dziurą na rzekę (wariant
## shadera) przy moście i bez niej daleko, upadek do rzeki po zrzuceniu
## auta obok pomostu. Z KATALOGIEM - zrzuty z boku i z drogi.
##   godot --headless --xr-mode off -s res://tests/structure_drive_test.gd -- most </dev/null
##   godot --xr-mode off -s res://tests/structure_drive_test.gd -- most KATALOG </dev/null

const KINDS := {"most": [33, 2]}
var kind := "most"
var main
var f := 0
var fails := 0
var out_dir := ""
var z := {}
var phase := 0
var lives_lost := 0
var river_shader_on := false
var water_seen := false
var piers_seen := 0
var fell := false
var river_bot: StuntCar
var fall_t := 0.0
var cam: Camera3D
var shots: Array = []
var shot_i := 0
var pending := ""
var pend_f := 0


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	gs.weather = "dry"
	gs.crash_replay = false
	for a in OS.get_cmdline_user_args():
		if KINDS.has(a):
			kind = a
		elif a != "":
			out_dir = a
	EndlessTrack.test_seed = int(KINDS[kind][0])
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
		main.seg_rhythm = false
		main.car.place(main._safe_pose(300.0))
		main.car._settle_t = 0.0
		main._last_safe_dist = 300.0
		for zz in main.track.structures.zones(0.0, 90000.0):
			if int(zz["structure"]) == int(KINDS[kind][1]):
				z = zz
				break
		if z.is_empty():
			_check(false, "brak budowli %s na trasie" % kind)
			return _end()
		print("  %s: %.0f-%.0f %s" % [kind, z["start"], z["end"], str(z)])
		var s0 := float(z["start"])
		var e0 := float(z["end"])
		shots = [["przed", s0 - 120.0, "road"], ["na", s0 + 40.0, "road"], ["bok", (s0 + e0) * 0.5, "side"]]
	if f < 8:
		return false
	var p: float = main._last_safe_dist
	var s0 := float(z["start"])
	var e0 := float(z["end"])
	if phase == 0:
		main._grace_t = 1.0
		var v := 90.0 if p < s0 - 1500.0 else 25.0
		var cxf: Transform3D = main.track.transform_at_distance(p + 2.0)
		var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - main.hwy_lane_off(0)
		main.car.global_basis = cxf.basis
		main.car.linear_velocity = -cxf.basis.z * v - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
		main.car.angular_velocity = Vector3.ZERO
		for b in main._bots:
			main.car.add_collision_exception_with(b)
		if p > s0 - 300.0:
			var mat := (main.get_node("Ground/GroundMesh") as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
			if mat.shader == main._GROUND_RIVER_SH:
				river_shader_on = true
		if p > s0 and p < e0:
			var ch: StuntTrack = main.track._chunk_for(p)
			for n in ch.get_children():
				if n.name.begins_with("River"):
					water_seen = true
			piers_seen = main.track.structures.piers(s0, e0).size()
			main._grace_t = 0.0                # na moście bez ochrony - nie może stracić życia
			if main.race_state == main.Race.EXPLODING:
				lives_lost += 1
		if p > e0 + 60.0 and pending == "":
			phase = 1
			# Zrzut auta obok pomostu nad wodą: ma być upadek.
			var r0 := s0 + StructurePlan.BRIDGE_BANK
			var mid := r0 + float(z["river"]) * 0.5
			var mxf: Transform3D = main.track.transform_at_distance(mid)
			main.car.global_position = mxf.origin + mxf.basis.x * 12.0 + Vector3.UP * 1.0
			# Bot zrzucony do rzeki (z fizyką) - ma wrócić do puli.
			main._spawn_bot(mid + 30.0, 0, 50.0)
			if not main._bots.is_empty():
				river_bot = main._bots[-1]
				main._drv(river_bot).lod = BotLod.NEAR
				river_bot.global_position = mxf.origin + mxf.basis.x * 20.0 - mxf.basis.z * 5.0 + Vector3.UP * 0.5
			main.car.linear_velocity = Vector3.ZERO
			main._last_safe_dist = mid
			main._grace_t = 0.0
			main.race_state = main.Race.RACING
			main._update_river()
			fall_t = 0.0
	elif phase == 1:
		fall_t += delta
		if main.race_state == main.Race.EXPLODING or main.race_state == main.Race.REPLAY:
			fell = true
		if fell or fall_t > 4.0:
			return _end()
	# Zrzuty.
	if out_dir != "":
		if cam == null:
			cam = Camera3D.new()
			cam.fov = 70.0
			cam.far = 3000.0
			root.add_child(cam)
		cam.current = true
		if shot_i < shots.size() and pending == "" and p > float(shots[shot_i][1]):
			var sh: Array = shots[shot_i]
			var at: Transform3D = main.track.transform_at_distance(float(sh[1]))
			if sh[2] == "side":
				cam.global_position = at.origin + at.basis.x * 70.0 - at.basis.z * 40.0 + Vector3.UP * 2.0
				cam.look_at(at.origin - Vector3.UP * 6.0, Vector3.UP)
			else:
				cam.global_position = main.car.global_position + at.basis.z * 14.0 + Vector3.UP * 5.0
				cam.look_at(main.car.global_position - at.basis.z * 40.0, Vector3.UP)
			pending = sh[0]
			pend_f = f + 3
			shot_i += 1
		if pending != "" and f >= pend_f:
			root.get_viewport().get_texture().get_image().save_png("%s/budowla_%s_%s.png" % [out_dir, kind, pending])
			print("zrzut ", pending)
			pending = ""
	return false


func _end() -> bool:
	if not z.is_empty():
		_check(lives_lost == 0, "przejazd po moście bez utraty życia")
		_check(river_shader_on, "ziemia z dziurą na rzekę przy moście")
		_check(water_seen, "woda pod mostem")
		_check(piers_seen > 0, "filary mostu (%d)" % piers_seen)
		_check(fell, "spadnięcie z mostu do rzeki = upadek")
		_check(river_bot != null and not main._bots.has(river_bot), "bot w rzece wraca do puli")
	print("structure_drive_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
