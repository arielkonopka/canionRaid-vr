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

## Strefy trasy 33: zwężenie 10,8-12 km, roboty 28,5-29,4 km.
const ZONES := {"zwezenie": [10800.0, 12000.0], "roboty": [28500.0, 29400.0], "jedna": [46800.0, 48300.0],
		"dwa": [66000.0, 67800.0], "trzy": [61200.0, 63300.0]}
const LIMITS := {"zwezenie": 100.0, "roboty": 80.0, "jedna": 90.0, "dwa": 90.0, "trzy": 140.0}
## Trasa (EndlessTrack.test_seed): 2+1 jest wcześnie dopiero na trasie 77.
const TRACKS := {"dwa": 77}
var kind := "zwezenie"
var ZONE_FROM := 10800.0
var ZONE_TO := 12000.0
var onc_ours := 0                  # auta z naprzeciwka na naszym lewym pasie (pełny przekrój)
var onc_other := 0
var loose_wrong := 0               # auto z naprzeciwka po przejściu na fizykę na naszym prawym pasie
var gap_checked := false
var gap_open := false
var barrier_elsewhere := false                 # ... na swojej (zamkniętej) jezdni w pełnym przekroju
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
var crashed := {}
var x_spawned := false
var x_closed := 0                  # próbki ekstremisty na zamkniętym pasie (pełny przekrój)
var x_samples := 0
var x_crashed := false
var wait_t := 0.0
var x_cones_seen := 0
var x_cones_clean := 0


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	gs.weather = "dry"
	gs.crash_replay = false
	var a := OS.get_cmdline_user_args()
	for arg in a:
		if ZONES.has(arg):
			kind = arg
		elif arg != "":
			out_dir = arg
	ZONE_FROM = float(ZONES[kind][0])
	ZONE_TO = float(ZONES[kind][1])
	shots = [["przed", ZONE_FROM - 250.0], ["skos", ZONE_FROM + 120.0], ["srodek", ZONE_FROM + 500.0]]
	if kind in ["roboty", "jedna", "dwa"]:
		shots.append(["przejazd", ZONE_TO - 170.0])
	EndlessTrack.test_seed = int(TRACKS.get(kind, 33))
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
	var v := (90.0 if ZONE_FROM > 40000.0 else 70.0) if p < ZONE_FROM - 600.0 else 26.0
	# Drugi przejazd: po linii pachołków przez 150 m - pachołki lecą.
	var x_goal: float = main.hwy_lane_at(0, p + 30.0)
	if phase == 2 and kind in ["zwezenie", "roboty"]:
		# Po linii pachołków (między pasami, co 18 m) - przecięcie jej
		# w poprzek trwa ~0,3 s i trafienie było losowe.
		x_goal = (main.hwy_lane_off(0) + main.hwy_lane_off(1)) * 0.5
	var cxf: Transform3D = main.track.transform_at_distance(p + 2.0)
	var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - x_goal
	main.car.global_basis = cxf.basis
	main.car.linear_velocity = -cxf.basis.z * v - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
	main.car.angular_velocity = Vector3.ZERO
	# Gracz prowadzony na siłę (70 m/s na dojeździe) taranowałby ruch -
	# boty po zderzeniu cofają z pobocza i psują pomiar pasów.
	for b in main._bots:
		main.car.add_collision_exception_with(b)
	# Ekstremista (decyzja użytkownika: zna otwarte pasy) - wypuszczony za
	# graczem, gdy ten jest w strefie: przejeżdża ją od skosu.
	if kind == "zwezenie" and not x_spawned and p > ZONE_FROM + 40.0:
		x_spawned = true
		for i in range(20):
			main._spawn_extremist()
			if main._extremist:
				break
		print("  ekstremista: %s" % ("jest" if main._extremist else "nie pojawił się"))
	var xb: StuntCar = main._extremist
	if x_spawned and f % 60 == 0 and OS.has_environment("X_DEBUG"):
		var xd0: BotDriver = main._drv(xb) if xb and is_instance_valid(xb) else null
		print("  X: %s" % ("brak" if xd0 == null else "d_gracz=%.0f rail=%s lod=%d v=%.0f strefa=%s pas=%s tgt=%.2f luki=%s" % [xd0.dist - p, xd0.on_rail, xd0.lod, xb.speed * 3.6, str(not sp.zone_at(xd0.dist).is_empty()), str(xd0._x_out.get("lane", "?")), xd0._tgt_off_s, str(xd0._x_ctx.get("lanes", []))]))
	if xb and is_instance_valid(xb):
		var xd: BotDriver = main._drv(xb)
		var zx: Dictionary = sp.zone_at(xd.dist) if xd else {}
		# Po taranie (charakter ekstremisty) auto wiruje - dalej to fizyka
		# zderzenia, nie wybór pasa.
		if float(xb.last_hit.get("j", 0.0)) > 3000.0:
			x_crashed = true
		if xd and not x_crashed and not xd.on_rail and not zx.is_empty() and xd.dist > float(zx["start"]) + float(zx["t_in"]) + 20.0 \
				and xd.dist < float(zx["end"]) - float(zx["t_out"]):
			var xxf: Transform3D = main.track.transform_at_distance(xd.dist)
			var xx: float = (xb.global_position - xxf.origin).dot(xxf.basis.x)
			# Zamknięty = blisko osi pasa 2+2, którego nie ma wśród otwartych
			# (pobocze przy zamkniętym lewym pasie jest dozwolone - zlecenie
			# ekstremista-zna-przekroje pkt 2).
			var fwd_l: Array = sp.lanes_at(xd.dist)["fwd"]
			x_samples += 1
			for li in range(2):
				var lx: float = main.hwy_lane_off(li)
				var is_open := false
				for fx in fwd_l:
					if absf(float(fx) - lx) < 1.3:
						is_open = true
				if not is_open and absf(xx - lx) < 1.4:
					x_closed += 1
			# Pachołki od ekstremisty liczone tylko przy jeździe prosto (po
			# taranie auto się obraca - to już fizyka zderzenia).
			var head := absf((-xb.global_basis.z).signed_angle_to(-xxf.basis.z, Vector3.UP))
			if main.x_cones_hit > x_cones_seen:
				if head < deg_to_rad(20.0):
					x_cones_clean += main.x_cones_hit - x_cones_seen
				x_cones_seen = main.x_cones_hit
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
		if drv.hold or drv.rage > 0.05:
			continue                       # zasadzka stoi na awaryjnym; furiat jedzie po swojemu (pachołki lecą)
		# Po mocnym zderzeniu (taran ekstremisty, wypadek) albo obrocie bot
		# ląduje, gdzie fizyka go rzuci - nie liczy się do jazdy pasami.
		var hxf: Transform3D = main.track.transform_at_distance(drv.dist)
		var xname: String = String(main._extremist.name) if main._extremist and is_instance_valid(main._extremist) else "?"
		if str(b.last_hit.get("what", "")).ends_with(xname):
			crashed[b] = true                  # potrącony przez ekstremistę
		if float(b.last_hit.get("j", 0.0)) > 3000.0 \
				or absf((-b.global_basis.z).signed_angle_to(-hxf.basis.z, Vector3.UP)) > deg_to_rad(35.0):
			crashed[b] = true
		if crashed.has(b):
			continue
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
				print("      tgt=%.2f steer=%.2f side=%s lead=%.1f koła=%d strefa=%d kontakt=%s" % [drv._tgt_off_s, b.steer, drv._side_block, drv._lead_gap, b.wheels_on_ground, int(zb["section"]), str(b.last_hit.get("what", "-"))])
	if kind == "roboty" and f % 240 == 0 and OS.has_environment("SECTION_DEBUG"):
		var lst := []
		for o in main._oncoming:
			if o.works:
				var oxf2: Transform3D = main.track.transform_at_distance(o.dist)
				lst.append("d=%.0f x=%.1f cross=%.2f vis=%s loose=%s" % [o.dist, (o.car.global_position - oxf2.origin).dot(oxf2.basis.x), sp.onc_cross(o.dist), o.car.visible, o.loose])
		print("  ROBOTY-AUTA p=%.0f: %s" % [p, str(lst)])
	# Auta z naprzeciwka w pełnym przekroju robót: nasz lewy pas.
	if kind in ["roboty", "jedna", "dwa"]:
		for o in main._oncoming:
			# Drugi przejazd (po linii pachołków, 1,9 m od ich pasa) to
			# prawdziwe zderzenie - liczymy tylko jazdę otwartym pasem.
			if phase < 2 and o.loose and is_instance_valid(o.car):
				var ns: Dictionary = main.track.nearest_sample(o.car.global_position)
				if not ns.is_empty():
					var lx: float = (o.car.global_position - main.track.to_global(ns["pos"])).dot(ns["right"])
					# Na naszym otwartym pasie (2+1: środkowy pas bywa ich).
					var la2: Dictionary = sp.lanes_at(float(ns["dist"]))
					var on_fwd := false
					for fx2 in la2["fwd"]:
						if absf(lx - float(fx2)) < 1.2:
							on_fwd = true
					for ox2 in la2["onc"]:
						if absf(lx - float(ox2)) < 1.2:
							on_fwd = false
					if on_fwd and (la2["onc"] as Array).size() + (la2["fwd"] as Array).size() > 0 and lx > -0.5:
						loose_wrong += 1
						if loose_wrong % 10 == 1:
							print("  LUŹNE: %s lx=%.1f d_auta=%.0f p=%.0f osk=%s works=%s pod_prąd=%s loose_t=%.1f kontakt=%s" % [o.car.name, lx, float(ns["dist"]), p, o.osk, o.works, o.wrong_way, o.loose_t, str(o.car.last_hit.get("what", "-"))])
		for o in main._oncoming:
			var od: float = o.dist
			var zo: Dictionary = sp.zone_at(od)
			if zo.is_empty() or sp.onc_cross(od) < 0.999 or not o.car.visible:
				continue
			var oxf: Transform3D = main.track.transform_at_distance(od)
			var ox: float = (o.car.global_position - oxf.origin).dot(oxf.basis.x)
			if absf(ox - sp.onc_x(od, int(o.lane))) < 1.0:
				onc_ours += 1
			elif ox < -8.0:
				onc_other += 1
				if onc_other % 300 == 1:
					print("  NAPRZECIW d=%.0f ox=%.1f cross=%.2f loose=%s osk=%s v=%.0f d_gracz=%.0f rail=%s" % [od, ox, sp.onc_cross(od), o.loose, o.osk, o.v, od - p, str(main.track.rail_at(od).size())])
	# Przerwa w barierce pasa rozdziału w przejeździe (i bariera poza nim):
	# promień w poprzek pasa rozdziału na wysokości 0,5 m.
	if kind in ["roboty", "jedna", "dwa"] and not gap_checked and p > ZONE_FROM + 300.0:
		gap_checked = true
		var z2: Dictionary = sp.zone_at(p)
		var cr: Array = SectionPlan.crossovers(z2)
		if not cr.is_empty():
			gap_open = not _median_hit((float(cr[1][0]) + float(cr[1][1])) * 0.5)
			barrier_elsewhere = _median_hit(float(z2["start"]) - 300.0)
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
			root.get_viewport().get_texture().get_image().save_png("%s/przekroj_%s_%s.png" % [out_dir, kind, pending])
			print("zrzut ", pending)
			pending = ""
		if shot_i < shots.size() and pending == "" and p > float(shots[shot_i][1]):
			pending = shots[shot_i][0]
			pend_f = f + 3
			shot_i += 1
	if p > ZONE_TO + 100.0 and pending == "":
		# Zwężenie: czekamy, aż ekstremista (za graczem) przejedzie strefę.
		var xw: StuntCar = main._extremist
		var xwd: BotDriver = main._drv(xw) if xw and is_instance_valid(xw) else null
		if kind == "zwezenie" and xwd and xwd.dist < ZONE_TO and wait_t < 60.0:
			wait_t += _delta
			return false
		return _end()
	return false


func _median_hit(d: float) -> bool:
	var xf: Transform3D = main.track.transform_at_distance(d)
	var w := HighwayGenerator.WIDTH
	var a := xf.origin - xf.basis.x * (w * 0.5 - 0.2) + Vector3.UP * 0.5
	var b := xf.origin - xf.basis.x * (w * 0.5 + TrackGenerator.HIGHWAY_MEDIAN + 0.2) + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [main.car.get_rid()]
	var hit: Dictionary = main.car.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and not (hit["collider"] is StuntCar)


func _end() -> bool:
	var coned := kind in ["zwezenie", "roboty"]   # 1+1, 2+1, 3+3: bez pachołków
	if coned:
		_check(items_seen > 30, "pachołki w kawałku ze strefą (%d)" % items_seen)
	_check(lim_in <= float(LIMITS[kind]), "ograniczenie w strefie %.0f" % lim_in)
	_check(hits_clean <= 0, "gracz po otwartym pasie - pachołków przewróconych %d" % hits_clean)
	if coned:
		_check(hit_on_purpose, "zjazd na zamknięty pas przewraca pachołki (razem %d)" % main.cones_hit)
	if kind in ["roboty", "jedna", "dwa"]:
		_check(onc_ours > 0, "auta z naprzeciwka naszym lewym pasem (próbek %d)" % onc_ours)
		_check(gap_open and barrier_elsewhere, "przerwa w barierce w przejeździe (otwarta %s, bariera poza nim %s)" % [gap_open, barrier_elsewhere])
		_check(loose_wrong == 0, "auto z naprzeciwka po przejściu na fizykę nie wjeżdża na nasz prawy pas (%d)" % loose_wrong)
		_check(onc_other == 0, "auta z naprzeciwka na zamkniętej drugiej jezdni: %d" % onc_other)
	if kind == "zwezenie":
		# Próbek bywa 0: przy korku w jedynym pasie ekstremista taranuje jeszcze
		# w skosie (jego charakter) - liczy się, że nie wybiera zamkniętego pasa.
		_check(x_closed == 0 and (x_samples > 0 or x_crashed), "ekstremista na zamkniętym pasie: %d z %d próbek%s" % [x_closed, x_samples, " (potem taran)" if x_crashed else ""])
		_check(x_cones_clean == 0, "pachołki przewrócone przez ekstremistę jadącego prosto: %d (razem %d)" % [x_cones_clean, main.x_cones_hit])
	_check(bot_in_closed == 0, "boty w pełnym przekroju na zamkniętym pasie: %d z %d próbek (po zderzeniu nie liczone: %d aut)" % [bot_in_closed, bot_samples, crashed.size()])
	print("section_drive_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
