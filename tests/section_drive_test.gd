extends SceneTree
## Przekroje jezdni w grze (SectionPlan, etap 2; zlecenie etap2-przekroje
## pkt 5). Autostrada 33 (pierwsze zwężenie 10,8-12 km). Gracz jedzie do
## strefy szybko, w strefie 26 m/s (~94 km/h) środkiem otwartego pasa
## (lanes_at - jak kierowca, który patrzy na pachołki). Sprawdza:
## pachołki i znaki stoją, gracz nie przewraca pachołków, przewraca je,
## gdy zjedzie na zamknięty pas (drugi przejazd), żaden bot nie jedzie
## zamkniętym pasem w pełnym przekroju, ograniczenie w strefie.
##   godot --headless --xr-mode off -s res://tests/section_drive_test.gd </dev/null
##   (zrzuty: godot --xr-mode off -s res://tests/section_drive_test.gd -- KATALOG)

const ZONE_FROM := 10800.0
const ZONE_TO := 12000.0
var main
var f := 0
var fails := 0
var out_dir := ""
var phase := 0                     # 0 dojazd, 1 strefa
var bot_in_closed := 0
var bot_samples := 0
var lim_in := INF
var items_seen := 0
var shots := [["przed", ZONE_FROM - 250.0], ["skos", ZONE_FROM + 120.0], ["srodek", ZONE_FROM + 500.0]]
var shot_i := 0
var pending := ""
var pend_f := 0
var cam: Camera3D
var hit_on_purpose := false
var hits_clean := -1
var spun := {}


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	gs.weather = "dry"
	gs.crash_replay = false
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	EndlessTrack.test_seed = 33
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
	if f < 8:
		return false
	main._grace_t = 1.0
	var p: float = main._last_safe_dist
	var sp: SectionPlan = main.track.sections
	var v := 70.0 if p < ZONE_FROM - 600.0 else 26.0
	# Drugi przejazd: zamknięty pas (lewy) przez 150 m - pachołki lecą.
	var x_goal: float = main.hwy_lane_at(0, p + 30.0)
	if phase == 2:
		x_goal = main.hwy_lane_off(1)
	var cxf: Transform3D = main.track.transform_at_distance(p + 2.0)
	var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - x_goal
	main.car.global_basis = cxf.basis
	main.car.linear_velocity = -cxf.basis.z * v - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
	main.car.angular_velocity = Vector3.ZERO
	# Gracz prowadzony na siłę (70 m/s na dojeździe) taranowałby ruch -
	# boty po zderzeniu cofają z pobocza i psują pomiar pasów.
	for b in main._bots:
		main.car.add_collision_exception_with(b)
	# Diagnostyka: pierwszy obrót bota - z czym miał kontakt.
	for b in main._bots:
		if b.angular_velocity.length() > 1.2 and not spun.has(b):
			spun[b] = true
			var drv0: BotDriver = main._drv(b)
			print("  OBRÓT %s d_gracz=%.0f x_lok v=%.0f lead=%.1f/%.1f side=%s tgt=%.2f kontakt=%s lod=%d" % [b.name, drv0.dist - p, b.speed * 3.6, drv0._lead_gap, drv0._lead_v, drv0._side_block, drv0._tgt_off_s, str(b.last_hit.get("what", "?")), drv0.lod])
	# Boty w pełnym przekroju strefy: żaden na zamkniętym pasie.
	var z: Dictionary = sp.zone_at(p)
	if not z.is_empty():
		lim_in = minf(lim_in, float(main.track.sample_at(p)["limit"]))
	for b in main._bots:
		var drv: BotDriver = main._drv(b)
		if drv.persona == "extremist":
			continue                       # jedzie zamkniętym pasem przez pachołki - jego charakter
		var zb: Dictionary = sp.zone_at(drv.dist)
		if zb.is_empty() or drv.dist < float(zb["start"]) + float(zb["t_in"]) + 20.0 or drv.dist > float(zb["end"]) - float(zb["t_out"]):
			continue
		var la: Dictionary = sp.lanes_at(drv.dist)
		var bx: Transform3D = main.track.transform_at_distance(drv.dist)
		var x: float = (b.global_position - bx.origin).dot(bx.basis.x)
		bot_samples += 1
		var near := INF
		for lx in la["fwd"]:
			near = minf(near, absf(x - float(lx)))
		if near > 2.2:
			bot_in_closed += 1
			if bot_in_closed % 100 == 1:
				print("  ZAMKNIĘTY: %s x=%.2f fwd=%s rail=%s lod=%d szał=%.1f zd=%s pas=%d d_od_startu=%.0f v=%.0f" % [b.name, x, str(la["fwd"]), drv.on_rail, drv.lod, drv.rage, drv.event, drv.lane, drv.dist - float(zb["start"]), b.speed * 3.6])
	if phase == 0 and p > ZONE_FROM:
		phase = 1
		var chunk: StuntTrack = main.track._chunk_for(p + 100.0)
		items_seen = chunk._knock.size()
	if phase == 1 and p > ZONE_FROM + 650.0:
		hits_clean = main.cones_hit
		phase = 2
	if phase == 2 and p > ZONE_FROM + 800.0:
		hit_on_purpose = main.cones_hit > hits_clean
		phase = 3
	# Zrzuty: kamera za i nad autem.
	if out_dir != "":
		if cam == null:
			cam = Camera3D.new()
			cam.fov = 70.0
			root.add_child(cam)
		var cf: Transform3D = main.track.transform_at_distance(p - 14.0)
		cam.global_position = cf.origin + cf.basis.y * 5.0 + cf.basis.x * 1.0
		cam.look_at(main.track.transform_at_distance(p + 40.0).origin, Vector3.UP)
		cam.current = true
		if pending != "" and f >= pend_f:
			root.get_viewport().get_texture().get_image().save_png("%s/przekroj_zwezenie_%s.png" % [out_dir, pending])
			print("zrzut ", pending)
			pending = ""
		if shot_i < shots.size() and pending == "" and p > float(shots[shot_i][1]):
			pending = shots[shot_i][0]
			pend_f = f + 3
			shot_i += 1
	if p > ZONE_TO + 100.0 and pending == "":
		return _end()
	return false


func _end() -> bool:
	_check(items_seen > 30, "pachołki w kawałku ze strefą (%d)" % items_seen)
	_check(lim_in <= 100.0, "ograniczenie w strefie %.0f" % lim_in)
	_check(hits_clean == 0, "gracz po otwartym pasie - pachołków przewróconych %d" % hits_clean)
	_check(hit_on_purpose, "zjazd na zamknięty pas przewraca pachołki (razem %d)" % main.cones_hit)
	_check(bot_in_closed == 0, "boty w pełnym przekroju na zamkniętym pasie: %d z %d próbek" % [bot_in_closed, bot_samples])
	print("section_drive_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
