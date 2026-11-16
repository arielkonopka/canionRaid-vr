extends SceneTree
## Budowle w grze (StructurePlan, etap 3; zlecenie etap3-budowle pkt 8).
## Rodzaj z argumentu: most (trasa 33, 31,4 km). Gracz jedzie szybko do
## budowli, na niej ~90 km/h prawym pasem. Sprawdza: przejazd bez utraty
## życia, woda i filary w scenie, ziemia z dziurą na rzekę (wariant
## shadera) przy moście i bez niej daleko, upadek do rzeki po zrzuceniu
## auta obok pomostu. Z KATALOGIEM - zrzuty z boku i z drogi.
##   godot --headless --xr-mode off -s res://tests/structure_drive_test.gd -- most </dev/null
##   godot --xr-mode off -s res://tests/structure_drive_test.gd -- most KATALOG </dev/null

const KINDS := {"most": [33, 2], "tunel": [1, 1], "wiadukt": [33, 3], "podjazd": [1, 4], "estakada": [119, 6], "tunel_luk": [26, 1], "wolny": [47, 4]}
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
var roof_hits := 0
var roof_probes := 0
var lim_in := INF
var dry_in := true
var overpass_seen := false
var h_err := 0.0
var h_probes := 0
var ground_err := 0.0
var bot_slow := 0
var bot_samples := 0
var top_h := 0.0
var h_base := 0.0
var train_over := false
var fall_t := 0.0
var side_done := false
var side_ok := false
var side_info := ""
var side_p := 0.0
var valley_probes := 0
var slow_zone := false
var slow_w := 0.0
var slow_on := 0
var slow_cand := 0
var slow_bot: StuntCar
var valley_err := 0.0
var valley_info := ""
var valley_hits := {}
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
		h_base = main.track.transform_at_distance(300.0).origin.y - HighwayGenerator.ROAD_Y - main.track.structures.height_at(300.0)
		var s0 := float(z["start"])
		var e0 := float(z["end"])
		shots = [["przed", s0 - 120.0, "road"], ["na", s0 + 40.0, "road"], ["bok", (s0 + e0) * 0.5, "side"]]
		if kind in ["podjazd", "wolny"]:
			shots = [["przed", s0 - 100.0, "road"], ["na", (s0 + e0) * 0.5, "road"], ["bok", (s0 + e0) * 0.5 + 100.0, "side"], ["szczyt", e0 + 50.0, "road"]]
		if kind == "wiadukt":
			shots = [["przed", s0 - 300.0, "road"], ["blisko", s0 - 120.0, "road"], ["bok", s0 - 60.0, "side"]]
		if kind == "estakada":
			shots = [["przed", s0 - 150.0, "road"], ["na", (s0 + e0) * 0.5, "road"], ["bok", (s0 + e0) * 0.5, "side"]]
		if kind.begins_with("tunel"):
			shots = [["przed", s0 - 150.0, "road"], ["wlot", s0 - 30.0, "road"], ["w1", s0 + 60.0, "eye"], ["w2", s0 + 200.0, "eye"],
					["srodek", (s0 + e0) * 0.5, "eye"], ["w4", e0 - 150.0, "eye"], ["wylot", e0 - 20.0, "eye"], ["bok", s0 + 100.0, "side"]]
	if f < 8:
		return false
	if f > Engine.physics_ticks_per_second * 60 * 20:
		_check(false, "test w limicie czasu (20 min gry)")
		return _end()
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
		if kind in ["podjazd", "wolny"] and p > s0 - 200.0:
			# Jezdnia na wysokości planu, ziemia (kolizja) przy terenie.
			var sp: StructurePlan = main.track.structures
			var rxf: Transform3D = main.track.transform_at_distance(p)
			# Pas dla wolnych (przekrój 1) w środku podjazdu.
			if p > s0 + 300.0 and p < e0 - 300.0:
				var sz: Dictionary = main.track.sections.zone_at(p)
				if not sz.is_empty() and int(sz["section"]) == 1:
					slow_zone = true
				var sm1: Dictionary = main.track.sample_at(p)
				if not sm1.is_empty():
					slow_w = maxf(slow_w, float(sm1["width"]))
				# Wolne auto (60% limitu) na prawym pasie przed graczem.
				if slow_bot == null and kind == "wolny":
					main._spawn_bot(p + 120.0, 0, 84.0)
					if not main._bots.is_empty():
						slow_bot = main._bots[-1]
						main._drv(slow_bot).speed_k = 0.6
				elif is_instance_valid(slow_bot) and main._bots.has(slow_bot):
					var bd2: BotDriver = main._drv(slow_bot)
					var sxb: float = main.track.sections.lanes_at(bd2.dist)["slow"]
					if not is_nan(sxb) and bd2.dist > s0 + 600.0:
						var bx: Transform3D = main.track.transform_at_distance(bd2.dist)
						slow_cand += 1
						if absf((slow_bot.global_position - bx.origin).dot(bx.basis.x) - sxb) < 1.2:
							slow_on += 1
			var want: float = HighwayGenerator.ROAD_Y + sp.height_at(p)
			h_probes += 1
			h_err = maxf(h_err, absf(rxf.origin.y - (want + h_base)))
			top_h = maxf(top_h, sp.height_at(p))
			# Kolizja ziemi nigdy nad jezdnią (płaszczyzna na najniższym terenie
			# w zasięgu - boty na zboczu pod nią były wypychane).
			var gy: float = (main.get_node("Ground/GroundShape") as CollisionShape3D).position.y
			ground_err = maxf(ground_err, gy - (rxf.origin.y - HighwayGenerator.ROAD_Y))
			if main.race_state == main.Race.EXPLODING:
				lives_lost += 1
			main._grace_t = 0.0
			for b in main._bots:
				var bd: BotDriver = main._drv(b)
				if bd and not bd.on_rail and bd.rage < 0.05 and bd.event == "" and absf(sp.grade_at(bd.dist)) > 0.04:
					bot_samples += 1
					if absf(b.speed) * 3.6 < 30.0:
						bot_slow += 1
						if bot_slow % 400 == 1:
							print("  WOLNY %s v=%.0f gaz=%.2f ham=%.2f bieg=%d obr=%.0f nachylenie=%.1f%% lod=%d koła=%d cel_gap=%.0f kontakt=%s" % [b.name, b.speed * 3.6, b.throttle, b.brake, b.gear, b.engine_rpm, sp.grade_at(bd.dist) * 100.0, bd.lod, b.wheels_on_ground, bd._lead_gap, str(b.last_hit.get("what", "-"))])
			# Zepchnięcie za barierę na stromym podjeździe (uwagi do PR #108):
			# auto ma stanąć na trawie, nie spaść przez teren.
			if not side_done and p > (s0 + e0) * 0.5 and absf(sp.grade_at(p + 30.0)) > 0.06:
				side_done = true
				side_p = p
				phase = 2
				fall_t = 0.0
				var sxf: Transform3D = main.track.transform_at_distance(p + 30.0)
				var srh := (sxf.basis.x * Vector3(1, 0, 1)).normalized()
				var hw := float(main.track.sample_at(p + 30.0).get("width", 11.0)) * 0.5
				main.car.global_position = sxf.origin + srh * (hw + 0.6 + 7.0) + Vector3.UP * 1.5
				main.car.global_basis = sxf.basis
				main.car.linear_velocity = Vector3.ZERO
				main.car.angular_velocity = Vector3.ZERO
				main._grace_t = 0.0
				return false
			if p > e0 + 2500.0 and pending == "":
				return _end()
		if kind == "wiadukt":
			if p > s0 - 600.0 and p < s0:
				for n in main.track._chunk_for(s0).get_children():
					if n.name.begins_with("Overpass"):
						overpass_seen = true
				# Pociąg nad drogą (±20 m od osi wiaduktu w poprzek), gdy gracz
				# jest 100-500 m przed nim.
				var vxf: Transform3D = main.track.transform_at_distance((s0 + e0) * 0.5)
				for n in main.get_children():
					if n is RailTrain:
						var rel: Vector3 = (n as Node3D).global_position - vxf.origin
						var along: float = rel.dot((vxf.basis.x * Vector3(1, 0, 1)).normalized())
						# Skład ciągnie się za czołem - nad drogą, jeśli czoło minęło
						# oś, a koniec jeszcze nie.
						var dirn: float = float(n.get_meta("dir", 1.0))
						var tail: float = along - dirn * (n as RailTrain).length
						if (along * dirn > -20.0 and tail * dirn < 20.0) and s0 - p > 100.0 and s0 - p < 500.0:
							train_over = true
			if p > s0 and p < e0:
				if main.race_state == main.Race.EXPLODING:
					lives_lost += 1
				main._grace_t = 0.0
			if p > e0 + 60.0 and pending == "":
				return _end()
		if kind.begins_with("tunel") and p > s0 + 20.0 and p < e0 - 20.0:
			# Dach nad jezdnią (rura) - promień w górę od auta.
			var q := PhysicsRayQueryParameters3D.create(main.car.global_position + Vector3.UP * 1.0, main.car.global_position + Vector3.UP * 20.0)
			q.exclude = [main.car.get_rid()]
			roof_probes += 1
			if not main.car.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				roof_hits += 1
			var sm: Dictionary = main.track.sample_at(p)
			if not sm.is_empty():
				lim_in = minf(lim_in, float(sm["limit"]))
				if String(sm.get("surface", "dry")) != "dry":
					dry_in = false
			if main.race_state == main.Race.EXPLODING:
				lives_lost += 1
			main._grace_t = 0.0
		if kind == "most" and p > s0 and p < e0:
			var ch: StuntTrack = main.track._chunk_for(p)
			for n in ch.get_children():
				if n.name.begins_with("River"):
					water_seen = true
			piers_seen = main.track.structures.piers(s0, e0).size()
			main._grace_t = 0.0                # na moście bez ochrony - nie może stracić życia
			if main.race_state == main.Race.EXPLODING:
				lives_lost += 1
		if kind == "estakada" and p > s0 and p < e0:
			piers_seen = main.track.structures.piers(s0, e0).size()
			main._grace_t = 0.0
			if main.race_state == main.Race.EXPLODING:
				lives_lost += 1
			# Promień z boku pomostu (8 m za barierą) w dół: trafia w dno doliny
			# (kolizja terenu na dnie), nie w nasyp ani płaszczyznę niżej.
			var sp6: StructurePlan = main.track.structures
			var drop: float = sp6.drop_at(p + 20.0)
			if drop > 10.0:
				var exf: Transform3D = main.track.transform_at_distance(p + 20.0)
				var erh := (exf.basis.x * Vector3(1, 0, 1)).normalized()
				var ehw := float(main.track.sample_at(p + 20.0).get("width", 11.0)) * 0.5
				var from: Vector3 = exf.origin + erh * (ehw + 0.6 + 8.0) + Vector3.UP * 2.0
				var q6 := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 300.0)
				q6.exclude = [main.car.get_rid()]
				var hit: Dictionary = main.car.get_world_3d().direct_space_state.intersect_ray(q6)
				# Dno widoczne (łamana co TERRAIN_GRID) - tam ma być kolizja.
				var want: float = exf.origin.y - HighwayGenerator.ROAD_Y - sp6.drop_lin(p + 20.0)
				valley_probes += 1
				var cn: String = "brak" if hit.is_empty() else String((hit["collider"] as Node).name)
				valley_hits[cn] = int(valley_hits.get(cn, 0)) + 1
				if cn == "Ground" and OS.get_environment("VALLEY_TRACE") != "":
					var q7 := PhysicsRayQueryParameters3D.create(q6.from, q6.to)
					q7.exclude = [main.car.get_rid(), (hit["collider"] as CollisionObject3D).get_rid()]
					var h7: Dictionary = main.car.get_world_3d().direct_space_state.intersect_ray(q7)
					print("  bez Ground: ", "nic" if h7.is_empty() else "%s y %.2f (want %.2f, Ground y %.2f)" % [(h7["collider"] as Node).name, (h7["position"] as Vector3).y, want, (hit["position"] as Vector3).y])
					var chk = main.track._chunk_for(p + 20.0)
					print("  dziura: d %.1f (kawałek %.1f-%.1f, próbek %d)" % [p + 20.0, float(chk._samples[0]["dist"]), float(chk._samples[-1]["dist"]), chk._samples.size()])
				var e: float = absf(float((hit["position"] as Vector3).y) - want) if not hit.is_empty() else 999.0
				if e > valley_err:
					valley_err = e
					valley_info = "dolina %.0f m, trafienie %s" % [drop, "brak" if hit.is_empty() else "%.1f m od dna (%s)" % [e, (hit["collider"] as Node).name]]
		if kind == "estakada" and p > e0 + 60.0 and pending == "":
			return _end()
		if kind.begins_with("tunel") and p > e0 + 60.0 and pending == "":
			return _end()
		if kind == "most" and p > e0 + 60.0 and pending == "":
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
	elif phase == 2:
		fall_t += delta
		main._grace_t = 0.0
		var ty: float = main.track.transform_at_distance(side_p + 30.0).origin.y - HighwayGenerator.ROAD_Y
		if main.race_state != main.Race.RACING:
			# Po upadku gra wybucha i odradza auto - jazda dalej nie ma sensu.
			side_info = "upadek po %.1f s" % fall_t
			return _end()
		elif fall_t > 3.0:
			var gy: float = (main.get_node("Ground/GroundShape") as CollisionShape3D).position.y
			var dy: float = main.car.global_position.y - ty
			side_ok = main.car.wheels_on_ground >= 3 and absf(dy) < 2.0
			side_info = "koła %d, nad terenem %.2f m, płaszczyzna %.1f m niżej" % [main.car.wheels_on_ground, dy, ty - gy]
			phase = 3
		if phase == 3:
			# Z powrotem na jezdnię, jazda dalej.
			var bxf: Transform3D = main.track.transform_at_distance(side_p)
			main.car.global_position = bxf.origin + bxf.basis.x * main.hwy_lane_off(0) + Vector3.UP * 0.6
			main.car.global_basis = bxf.basis
			main.car.linear_velocity = -bxf.basis.z * 25.0
			main.race_state = main.Race.RACING
			main._last_safe_dist = side_p
			phase = 0
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
			elif sh[2] == "eye":
				# Wzrok kierowcy (w rurze kamera nad autem siedziałaby w górze).
				cam.global_position = main.car.global_position + Vector3.UP * 1.2 + at.basis.z * 0.5
				cam.look_at(main.car.global_position - at.basis.z * 60.0 + Vector3.UP * 1.0, Vector3.UP)
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
	if not z.is_empty() and kind == "estakada":
		_check(lives_lost == 0, "przejazd estakadą bez utraty życia")
		_check(piers_seen > 0, "filary estakady (%d)" % piers_seen)
		_check(valley_probes > 0 and valley_err < 0.3 and valley_hits.get("Ground", 0) == 0, "z boku pomostu kolizja na dnie doliny (%d próbek %s, najgorsza: %s)" % [valley_probes, str(valley_hits), valley_info])
	elif not z.is_empty() and kind in ["podjazd", "wolny"]:
		_check(h_probes > 0 and h_err < 0.8, "jezdnia na wysokości planu (maks. odchyłka %.2f m, szczyt %.0f m)" % [h_err, top_h])
		_check(ground_err < 0.1, "kolizja ziemi nie nad terenem przy aucie (maks. %.2f m)" % ground_err)
		_check(lives_lost == 0, "przejazd podjazdem bez utraty życia")
		if kind == "podjazd":                # zepchnięcie na >= 6% (trasa 1: 8%)
			_check(side_done and side_ok, "auto za barierą na podjeździe stoi na trawie (%s)" % side_info)
		_check(bot_samples == 0 or bot_slow * 10 < bot_samples, "boty na podjeździe nie stają (%d z %d próbek < 30 km/h)" % [bot_slow, bot_samples])
		if kind == "podjazd":
			# 8% na 1,2 km - za krótki na pas dla wolnych (StructurePlan.slow_lane).
			_check(not slow_zone, "krótki podjazd bez pasa dla wolnych")
		if kind == "wolny":
			_check(slow_zone, "pas dla wolnych na podjeździe")
			_check(slow_w > HighwayGenerator.WIDTH + 3.0, "jezdnia szersza o pas (%.2f m)" % slow_w)
			_check(slow_cand > 0 and slow_on * 2 > slow_cand, "wolne auto (60%% limitu, prawy pas) na pasie dla wolnych (%d z %d próbek)" % [slow_on, slow_cand])
	elif not z.is_empty() and kind == "wiadukt":
		_check(overpass_seen, "wiadukt stoi")
		_check(lives_lost == 0, "przejazd pod wiaduktem bez utraty życia")
		if int(z.get("train", 0)) > 0:
			_check(main.trains_spawned > 0, "pociąg wyjechał (%d)" % main.trains_spawned)
			_check(train_over, "pociąg nad drogą, gdy gracz 100-500 m przed wiaduktem")
	elif not z.is_empty() and kind.begins_with("tunel"):
		_check(lives_lost == 0, "przejazd tunelem bez utraty życia")
		_check(roof_probes > 0 and roof_hits * 10 >= roof_probes * 9, "dach nad jezdnią (%d z %d próbek)" % [roof_hits, roof_probes])
		_check(lim_in <= 100.0, "ograniczenie w tunelu %.0f" % lim_in)
		_check(dry_in, "w tunelu sucho")
		if kind == "tunel_luk":
			var y0: float = main.track.transform_at_distance(float(z["start"]) + 1.0).basis.get_euler().y
			var y1: float = main.track.transform_at_distance(float(z["end"]) - 1.0).basis.get_euler().y
			var turn := absf(rad_to_deg(angle_difference(y0, y1)))
			_check(bool(z.get("curved", false)) and turn > 5.0, "łuk w tunelu (zmiana kursu %.1f°)" % turn)
	elif not z.is_empty():
		_check(lives_lost == 0, "przejazd po moście bez utraty życia")
		_check(river_shader_on, "ziemia z dziurą na rzekę przy moście")
		_check(water_seen, "woda pod mostem")
		_check(piers_seen > 0, "filary mostu (%d)" % piers_seen)
		_check(fell, "spadnięcie z mostu do rzeki = upadek")
		_check(river_bot != null and not main._bots.has(river_bot), "bot w rzece wraca do puli")
	print("structure_drive_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
