extends SceneTree
## Test sceny pułapek (etap 4a, TrapPlan) na autostradzie: autopilot przez
## pułapkę (prędkość ustawiana jak w structure_drive_test), sprawdza
## geometrię, znaki i nawierzchnię w scenie.
##   godot --headless --xr-mode off -s res://tests/trap_drive_test.gd -- luk </dev/null
##   (z oknem i katalogiem: zrzuty)  ... -- luk /katalog
## Rodzaje: luk (0, trasa 18), plama (12, trasa 74).

const KINDS := {"luk": [18, 0], "plama": [74, 12]}

var main
var kind := "luk"
var f := 0
var fails := 0
var out_dir := ""
var tr := {}
var lives_lost := 0
var cam: Camera3D
var shots: Array = []
var shot_i := 0
var pending := ""
var pend_f := 0
# łuk
var min_r := INF
var straight_dev := 0.0
var yaw_in := NAN
var yaw_out := NAN
var signs := {}
var u3s := {}
# plama
var patch_samples := 0
var patch_ok := 0
var patch_body := false


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


func _physics_process(_delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main.seg_rhythm = false
		main.car.place(main._safe_pose(300.0))
		main.car._settle_t = 0.0
		main._last_safe_dist = 300.0
		for t in main.track.traps.traps(0.0, 60000.0):
			if int(t["trap"]) == int(KINDS[kind][1]):
				tr = t
				break
		if tr.is_empty():
			_check(false, "brak pułapki %s na trasie" % kind)
			return _end()
		print("  pułapka %d poziom %d na %.0f m" % [tr["trap"], tr["level"], tr["d"]])
		var d0 := float(tr["d"])
		shots = [["znak", d0 - 200.0, "road"], ["przed", d0 - 60.0, "road"], ["na", d0 + 40.0, "road"]]
	if f < 8:
		return false
	if f > Engine.physics_ticks_per_second * 60 * 20:
		_check(false, "test w limicie czasu (20 min gry)")
		return _end()
	var p: float = main._last_safe_dist
	var d0 := float(tr["d"])
	var d1 := float(tr.get("end", d0 + 400.0))
	main._grace_t = 1.0
	var v := 90.0 if p < d0 - 2500.0 else 20.0
	var cxf: Transform3D = main.track.transform_at_distance(p + 2.0)
	var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - main.hwy_lane_off(0)
	main.car.global_basis = cxf.basis
	main.car.linear_velocity = -cxf.basis.z * v - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
	main.car.angular_velocity = Vector3.ZERO
	for b in main._bots:
		main.car.add_collision_exception_with(b)
	if p > d0 - 1600.0 and p < d1 + 100.0:
		if main.race_state == main.Race.EXPLODING:
			lives_lost += 1
		main._grace_t = 0.0
	if kind == "luk":
		var y: float = main.track.transform_at_distance(p).basis.get_euler().y
		if p > d0 - TrapPlan.STRAIGHT_BEFORE + 50.0 and p < d0 - 5.0:
			var y2: float = main.track.transform_at_distance(p + 5.0).basis.get_euler().y
			straight_dev = maxf(straight_dev, absf(angle_difference(y, y2)) / 5.0)
		if is_nan(yaw_in) and p > d0 - 5.0:
			yaw_in = y
		if p > d0 + 20.0 and p < d0 + 400.0:
			var y3: float = main.track.transform_at_distance(p + 10.0).basis.get_euler().y
			var k := absf(angle_difference(y, y3)) / 10.0
			if k > 1e-5:
				min_r = minf(min_r, 1.0 / k)
		if p > d0 + 600.0 and is_nan(yaw_out):
			yaw_out = y
			_scan_items(d0)
			if pending == "":
				return _end()
	if kind == "plama":
		if p > d0 + 1.0 and p < d1 - 1.0:
			var sm: Dictionary = main.track.sample_at(p)
			patch_samples += 1
			if String(sm.get("surface", "")).begins_with("patch"):
				patch_ok += 1
			if not patch_body:
				for n in main.track._chunk_for(p).get_children():
					if String(n.name).begins_with("TrackBody_patch"):
						patch_body = absf(float(n.get_meta("grip")) - float(tr["grip"])) < 0.01
		if p > d1 + 100.0 and pending == "":
			_scan_items(d0)
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
			var at: Transform3D = main.track.transform_at_distance(p)
			cam.global_position = main.car.global_position + Vector3.UP * 1.3 + at.basis.z * 0.3
			cam.look_at(main.car.global_position - at.basis.z * 60.0 + Vector3.UP * 1.0, Vector3.UP)
			pending = sh[0]
			pend_f = f + 3
			shot_i += 1
		if pending != "" and f >= pend_f:
			root.get_viewport().get_texture().get_image().save_png("%s/pulapka_%s_%s.png" % [out_dir, kind, pending])
			print("zrzut ", pending)
			pending = ""
	return false


## Znaki w kawałkach wokół pułapki (RoadSign_*, U3).
func _scan_items(d0: float) -> void:
	for dd in [d0 - 400.0, d0 - 150.0, d0, d0 + 200.0]:
		var ch = main.track._chunk_for(dd)
		if ch == null:
			continue
		for n in ch.get_children():
			var nm := String(n.name)
			if n.has_meta("u3"):
				u3s[n.get_instance_id()] = true
			elif nm.begins_with("RoadSign"):
				signs[String(n.get_meta("sign", ""))] = float(n.get_meta("d", 0.0))


func _end() -> bool:
	if not tr.is_empty():
		_check(lives_lost == 0, "przejazd przez pułapkę bez utraty życia")
		if kind == "luk":
			_check(straight_dev < 1e-3, "prosta %.0f m przed łukiem (maks. krzywizna %.5f 1/m)" % [TrapPlan.STRAIGHT_BEFORE, straight_dev])
			var turn := absf(rad_to_deg(angle_difference(yaw_in, yaw_out)))
			_check(turn > 15.0, "łuk skręca (%.1f°, plan %.0f°)" % [turn, tr["angle"]])
			_check(absf(min_r - float(tr["r_end"])) < float(tr["r_end"]) * 0.2,
					"najciaśniej R %.0f m (plan r_end %.0f)" % [min_r, tr["r_end"]])
			_check(u3s.size() >= 6, "tablice U-3 na łuku (%d)" % u3s.size())
			var want := "curve_r" if int(tr["dir"]) > 0 else "curve_l"
			var sd := TrapPlan.sign_dist(int(tr["level"]))
			_check(signs.has(want) and absf(float(signs[want]) - (float(tr["d"]) - sd)) < 5.0,
					"znak %s %.0f m przed łukiem (%s)" % [want, sd, str(signs)])
		if kind == "plama":
			_check(patch_samples > 0 and patch_ok == patch_samples, "nawierzchnia plamy na całej długości (%d z %d)" % [patch_ok, patch_samples])
			_check(patch_body, "kolizja plamy z przyczepnością %.2f" % float(tr["grip"]))
			var sd2 := TrapPlan.sign_dist(int(tr["level"]))
			_check(signs.has("slippery") and absf(float(signs["slippery"]) - (float(tr["d"]) - sd2)) < 5.0,
					"znak A-15 %.0f m przed plamą (%s)" % [sd2, str(signs)])
	print("trap_drive_test: ", "OK (0 błędów)" if fails == 0 else "BŁĄD (%d błędów)" % fails)
	return true
