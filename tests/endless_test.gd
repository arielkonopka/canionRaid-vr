extends SceneTree
## Test trasy bez końca: autopilot jedzie, aż skończą się dźwigi (3) albo
## minie limit czasu. Zna znaki z prędkością skoku (przed rampą pełny gaz)
## i zwalnia przed łukami według przyczepności nawierzchni.
##   godot --headless --xr-mode off -s res://tests/endless_test.gd -- [kW] [napęd] [ziarno] [limit s] [endless|canyon] [km/h na skoczniach] </dev/null
## Wypisuje każdy upadek (gdzie, przy jakiej prędkości wybicia) i wynik.

var main
var car
var trk
var t := 0.0
var frame := 0
var limit := 240.0
var seed_v := 777
const AP = preload("res://tests/_autopilot.gd")
var autostrada_ap := false
var _stuck_t := 0.0
var _rev_t := 0.0
var last_cranes := -1
var last_bots := 0
## 6. argument: prędkość wjazdu na wielkie skocznie autostrady [km/h] (długie loty -
## reguła upadku nie może zabierać życia w powietrzu, 2026-11-09).
var jump_override := 0.0
var _air := 0.0
var _dbg_v := 0.0
var _air_v := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = args[4] if args.size() > 4 else "endless"   # endless / canyon / autostrada
	autostrada_ap = gs.track_mode == "autostrada"
	gs.cranes = 3
	gs.engine_power = int(args[0]) if args.size() > 0 else 180
	gs.engine_type = args[1] if args.size() > 1 else "petrol"
	# "hub" = elektryk z silnikami w kołach (4x4), "awd" = 4x4 z dyferencjałem.
	if gs.engine_type == "hub":
		gs.engine_type = "electric"
		gs.motor_layout = "hub"
	elif args.size() > 6:
		gs.drive_layout = args[6]
	seed_v = int(args[2]) if args.size() > 2 else 777
	limit = float(args[3]) if args.size() > 3 else 240.0
	jump_override = float(args[5]) if args.size() > 5 else 0.0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(delta: float) -> bool:
	if car and car.airtime > 0.0:
		if _air == 0.0:
			_air_v = car.speed * 3.6
		_air = car.airtime
	elif _air > 0.5:
		print("  lot %.1f s, wybicie %.0f km/h, %.2f km" % [_air, _air_v, main._last_safe_dist / 1000.0])
		_air = 0.0
	else:
		_air = 0.0
	frame += 1
	main.set_physics_process(false)
	# Krok sceny jest wyłączony (autopilot steruje sam) - przesuwanie świata
	# trybu Autostrada trzeba wołać tutaj.
	if frame > 3:
		main._check_origin_shift()
		main._watch_incident(delta)
		# DBG_STOP=1: szczegóły klatki, gdy prędkość pozioma spada > 2 km/h
		# w jednym kroku (diagnostyka "nagłego zatrzymania", 2026-11-09).
		if OS.has_environment("DBG_STOP") and car:
			var hv: float = Vector2(car.linear_velocity.x, car.linear_velocity.z).length() * 3.6
			if _dbg_v - hv > 2.0:
				var ws := ""
				for w in car.wheels:
					ws += " [%s n%s s%.2f L%.0f]" % ["K" if w.contact else "-", str(w.normal.snapped(Vector3.ONE * 0.01)), w.spring_len, w.load]
				var bodies := []
				for b in car.get_colliding_bodies():
					bodies.append(str(b.get_path()).get_file())
				var sm: Dictionary = trk.nearest_sample(car.global_position)
				print("  STOP %.0f -> %.0f km/h, poz %s, v %s, pochylenie auta %.1f°, próbka d=%.0f pochyl %.1f° wys %.2f, kolizje %s, koła%s" % [_dbg_v, hv, str(car.global_position.snapped(Vector3.ONE * 0.01)), str(car.linear_velocity.snapped(Vector3.ONE * 0.1)), rad_to_deg(car.global_rotation.x), float(sm.get("dist", 0)), rad_to_deg(float(sm.get("pitch", 0))), (car.global_position - trk.to_global(sm["pos"])).y, str(bodies), ws])
			_dbg_v = hv
	if frame == 1:
		return false
	if frame == 2:
		# Stałe ziarno: ta sama trasa dla każdego auta (porównanie uczciwe).
		car = main.get_node("Car")
		trk = main.track
		print("auto: %s %d kW, trasa ziarno %d" % [car.engine_type, car.engine_power_kw, seed_v])
		return false
	if frame == 3:
		# Podmiana trasy na tę z ustalonym ziarnem.
		var et := EndlessTrack.new()
		et.seed_value = seed_v
		et.canyon = root.get_node("GameSettings").track_mode == "canyon"
		et.autostrada = root.get_node("GameSettings").track_mode == "autostrada"
		et.road_material = trk.road_material
		et.pillar_material = trk.pillar_material
		trk.queue_free()
		main.add_child(et)
		main.track = et
		trk = et
		return false
	if frame == 4:
		main.restart_race()
		last_cranes = main.cranes_left
		return false

	t += delta
	main.update_race(delta)
	if main.race_state == main.Race.WORKSHOP:
		# Kierowca testowy: ten sam rodzaj napędu, następny próg mocy
		# (domyślnie podświetlona opcja) - gdy auto już stoi.
		if car.linear_velocity.length() < 0.5:
			print("  warsztat t=%.0f s, %.2f km: %s" % [t, main._last_safe_dist / 1000.0,
					main._ws_options[main._ws_selected]["label"]])
			# Sklep: najdroższa dostępna wymiana silnika, potem wyjazd.
			for i in range(main._ws_options.size()):
				if str(main._ws_options[i].get("id", "")).begins_with("engine:") and int(main._ws_options[i]["cost"]) <= main.score.points:
					main.workshop_choose(i)
					break
			main.workshop_choose(main.ws_exit_index())
		return false
	if main.race_state == main.Race.FINISHED:
		print("KONIEC po %.0f s: odcinek %d, %.2f km, stan auta %d%%" % [t, trk.section_at(main._max_dist), main._max_dist / 1000.0, roundi((1.0 - car.damage["structure"]) * 100)])
		return true
	main._watch_track(delta)
	main._update_bots(delta)
	if main._bots.size() != last_bots:
		print("  boty: %d (t=%.0f s)" % [main._bots.size(), t])
		last_bots = main._bots.size()
	for b in main._bots:
		var r: float = b.get_node("Driver").rage
		if r > 0.9 and not b.has_meta("raged"):
			b.set_meta("raged", true)
			print("  bot w szale t=%.0f s, stan bota %d%%, stan gracza %d%%" % [t, roundi((1.0 - b.damage["structure"]) * 100), roundi((1.0 - car.damage["structure"]) * 100)])
	if main.cranes_left != last_cranes:
		var sd: float = main._last_safe_dist
		print("  upadek t=%.0f s, odcinek %d, %.2f km, dźwigi: %d" % [t, trk.section_at(sd), sd / 1000.0, main.cranes_left])
		last_cranes = main.cranes_left

	var info: Dictionary = trk.lateral_offset(car.global_position)
	if not info.has("sample"):
		return t > limit
	var s: Dictionary = info["sample"]
	var here := float(s["dist"])
	# Auto stoi z kołami na ziemi (zawieszenie po locie, 2026-11-11): co 5 s
	# gdzie i w co patrzy - autopilot nie umie wycofać.
	# Autopilot nie umiał wycofać: po locie auto stawało w poprzek drogi
	# przodem w barierze i stało do końca testu (ziarna 222, 3333). Gracz
	# by cofnął - test też: po 2 s postoju 2,5 s wstecz (automat: hamulec
	# na postoju = wsteczny) ze skrętem w drugą stronę.
	if car.linear_velocity.length() < 0.5 and car.wheels_on_ground >= 3 and t > 5.0 and _rev_t <= 0.0:
		_stuck_t += delta
		if _stuck_t > 2.0:
			_stuck_t = 0.0
			_rev_t = 2.5
			var hd := rad_to_deg((-car.global_basis.z).signed_angle_to(s["fwd"], car.global_basis.y))
			print("  STOI t=%.0f s, d %.0f, w poprzek %.1f m, kąt do toru %.0f°, ostatni kontakt %s - cofam" % [
					t, here, float(info["offset"]), hd, str(car.last_hit.get("what", "-"))])
	else:
		_stuck_t = 0.0
	var fwd: Vector3 = -car.global_basis.z
	var head_err := fwd.signed_angle_to(s["fwd"], car.global_basis.y)
	# Wzmocnienie maleje z prędkością - przy 220 km/h na autostradzie stałe
	# wzmocnienie rozbujało regulator (wychylenie z pasa rosło do pełnego skrętu).
	# Autopilot: na autostradzie wspólny z regen_highway_test
	# (tests/_autopilot.gd - stałe wzmocnienia rozbujały auto przy 210 km/h).
	# W wąwozie stary: porównanie 2026-11-11 niejednoznaczne (ziarno 777:
	# nowy 4,95 km i upadek po skoku, stary 6,95 km bez; ziarno 31: nowy
	# 5,11 km, stary 3,36 km). OLD_AP=1 / NEW_AP=1 wymusza.
	var steer: float
	var old_ap := OS.has_environment("OLD_AP") or (not autostrada_ap and not OS.has_environment("NEW_AP"))
	if old_ap:
		var gain := clampf(25.0 / maxf(car.speed, 1.0), 0.3, 1.0)
		steer = clampf((-info["offset"] * 0.25 - head_err * 2.5) * gain, -1, 1)
	else:
		# Krzywizna toru z kierunku 10 m dalej [rad/m, + w lewo] - człon
		# wyprzedzający na łukach (bez niego wąwóz: łuk łapany z opóźnieniem).
		var ahead_fwd: Vector3 = -trk.transform_at_distance(here + 10.0).basis.z
		var curve: float = (s["fwd"] as Vector3).signed_angle_to(ahead_fwd, car.global_basis.y) / 10.0
		steer = AP.steer(car, float(info["offset"]), head_err, curve)
	var kmh: float = car.speed * 3.6
	if OS.has_environment("DBG_D") and absf(here - float(OS.get_environment("DBG_D"))) < 150.0 and frame % 15 == 0:
		print("  dbg d=%.0f off %.2f head %.3f steer %.2f %3.0f km/h krzywizna %.4f szer %.1f poz %s próbka %s" % [here, info["offset"], head_err, steer, kmh, float(s.get("curve", 0.0)), float(s["width"]), str(car.global_position.snapped(Vector3.ONE * 0.1)), str((s["pos"] as Vector3).snapped(Vector3.ONE * 0.1))])

	# Prędkość: łuki (pozioma krzywizna, przyczepność nawierzchni) i skoki.
	var ahead: Array = trk.samples_from(here, 250.0)
	var target := 230.0
	if trk.autostrada:
		# Autostrada: trzymaj się ograniczeń (+10%) - miasta 30, dojazdy 70/50.
		target = main.current_limit * 1.1
	var jump_v := 0.0
	var in_runup := false
	for i in range(0, ahead.size() - 15, 5):
		var a0: Dictionary = ahead[i]
		var a1: Dictionary = ahead[i + 15]
		var k := float(a0["dist"]) - here
		var f0: Vector3 = a0["fwd"] * Vector3(1, 0, 1)
		var f1: Vector3 = a1["fwd"] * Vector3(1, 0, 1)
		var span := float(a1["dist"]) - float(a0["dist"])
		var ang := f0.angle_to(f1)
		if ang > 0.01:
			var grip: float = StuntTrack.SURFACES[a0["surface"]]["grip"]
			var v_curve := sqrt(0.75 * grip * 9.8 * span / ang)
			target = minf(target, sqrt(v_curve * v_curve + 2.0 * 5.0 * k) * 3.6)
		# Garb: znak z prędkością maksymalną (szczyt ~30 m za znakiem).
		if a0["meta"].has("v_warn"):
			var vw: float = a0["meta"]["v_warn"]
			target = minf(target, sqrt(vw * vw + 2.0 * 5.0 * (k + 30.0)) * 3.6)
		if a0["meta"].has("sign") and jump_v == 0.0:
			jump_v = a0["meta"]["v_sign"] * 3.6
			in_runup = true
	# Na rozbiegu (znak za nami, rampa przed nami) - prędkość ze znaku +10%.
	# Za szybko też źle: przy 3x prędkości projektowej przejście na rampę
	# ściska zawieszenie ~4 g i auto przekręca się nosem w dół w locie.
	var behind: float = trk.runup_start_before(here)
	if behind >= 0.0:
		var runup_samples: Array = trk.samples_from(behind, 1.0)
		var vs := 0.0
		var big := false
		for rs in runup_samples:
			if rs["meta"].has("v_sign"):
				vs = rs["meta"]["v_sign"] * 3.6
				big = rs["meta"].get("big_jump", false)
		if big and jump_override > 0.0:
			target = jump_override           # wielka skocznia autostrady
		elif vs > 0.0:
			target = vs * 1.10
	car.throttle = 1.0 if kmh < target else 0.0
	car.brake = clampf((kmh - target - 2.0) * 0.15, 0.0, 1.0)
	car.steer = steer if car.wheels_on_ground > 0 else 0.0
	if _rev_t > 0.0:
		_rev_t -= delta
		car.throttle = 0.0
		car.brake = 1.0
		car.steer = -steer
	if car.wheels_on_ground == 0:
		# W locie bez pedałów - gaz albo hamulec obracają auto (reakcja napędu).
		car.throttle = 0.0
		car.brake = 0.0
	if int(t * 240.0) % (240 * 10) == 0:
		for b in main._bots:
			var drv = b.get_node("Driver")
			var lim := 0.0
			var ws: Array = trk.samples_from(drv.dist, 2.0)
			if not ws.is_empty():
				lim = ws[0]["limit"]
			print("    bot: %.0f m przed graczem, %.0f km/h (ograniczenie %.0f), stan %d%%, szał %.1f" % [
				drv.dist - main._last_safe_dist, b.speed * 3.6, lim, roundi((1.0 - b.damage["structure"]) * 100), drv.rage])
	if t > limit:
		print("LIMIT %.0f s: odcinek %d, %.2f km, dźwigi: %d, stan auta %d%%, silnik %d%%" % [t, trk.section_at(main._max_dist), main._max_dist / 1000.0, main.cranes_left, roundi((1.0 - car.damage["structure"]) * 100), roundi(car.damage["engine"] * 100)])
		return true
	return false
