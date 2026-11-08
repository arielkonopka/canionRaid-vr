extends SceneTree
## Test jazdy bez gogli i bez okna: ładuje scenę główną, autopilot trzyma
## się osi toru i zwalnia przed zakrętami, a skrypt loguje stan auta co 0,5 s.
##
## Uruchomienie (z katalogu projektu):
##   godot --headless --xr-mode off -s res://tests/drive_test.gd -- 95
## Argumenty po "--": prędkość docelowa w km/h (domyślnie 95),
## zawieszenie soft/sport/stiff, skrzynia auto/manual. Np. -- 95 stiff manual
## W manualu autopilot sam zmienia biegi przez shift_up()/shift_down().
## --xr-mode off jest konieczne: bez runtime'u OpenXR Godot wisi przy wyjściu.
##
## Na co patrzeć: "kola" = liczba kół z kontaktem, "up.y" < 0 = auto na dachu,
## ">> RESPAWN" = dźwig postawił auto na torze, "d" = przejechane metry toru.
var main: Node
var car
var trk
var t := 0.0
var frame := 0
var target_kmh := 95.0
var respawns := 0
var finished_printed := false
var stop_t := -1.0
var esp_frames := 0
var esp_over := 0
var tcs_frames := 0
var abs_frames := 0

func _initialize() -> void:
	# Argumenty: prędkość [km/h], zawieszenie (soft/sport/stiff), skrzynia (auto/manual).
	# Ustawiamy je w GameSettings, tak jak robi to ekran tytułowy - scena
	# główna przy starcie sama przenosi je na auto. Nie zapisujemy ich na dysk.
	var args := OS.get_cmdline_user_args()
	var gs = root.get_node("GameSettings")
	gs.persist = false            # rekord z testu nie trafia do ustawień gracza
	gs.best_time = 0.0
	gs.track_mode = "demo"        # autopilot jeździ po trasie pokazowej (z metą)
	if args.size() > 0: target_kmh = float(args[0])
	gs.suspension = args[1] if args.size() > 1 else "sport"
	gs.transmission = args[2] if args.size() > 2 else "auto"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	trk = main.get_node("Track")
	car.landed.connect(func(v): print("   >> ladowanie %.1f m/s, t=%.2f" % [v, t]))

func _physics_process(delta: float) -> bool:
	t += delta
	frame += 1
	main.set_physics_process(false)
	var before = car.global_position
	main.update_race(delta)
	if main.race_state != main.Race.FINISHED:
		main._watch_track(delta)
	if car.global_position.distance_to(before) > 3.0:
		respawns += 1
		print("   >> RESPAWN t=%.2f" % t)
	var info = trk.lateral_offset(car.global_position)
	var s = info["sample"]
	var fwd: Vector3 = -car.global_basis.z
	var tf: Vector3 = trk.global_basis * s["fwd"]
	var head_err := fwd.signed_angle_to(tf, car.global_basis.y)  # dodatni = tor w lewo
	var steer: float = clampf(-info["offset"] * 0.25 - head_err * 2.5, -1, 1)
	var kmh: float = car.speed * 3.6
	# Prędkość dopuszczalna teraz = minimum po punktach przed autem:
	# v² = v_zakrętu² + 2·a·odległość, gdzie v_zakrętu z krzywizny 15-metrowego okna.
	var target := target_kmh
	var here := float(s["dist"])
	for k in range(0, 90, 5):
		var a0 = _sample_at(here + k)
		var a1 = _sample_at(here + k + 15.0)
		# Tylko krzywizna w poziomie - rampa to nie zakręt.
		var f0: Vector3 = a0["fwd"] * Vector3(1, 0, 1)
		var f1: Vector3 = a1["fwd"] * Vector3(1, 0, 1)
		var ang := f0.angle_to(f1)
		if ang > 0.02:
			# Przyczepność z nawierzchni odcinka, jak kierowca, który widzi mokrą jezdnię.
			var grip: float = StuntTrack.SURFACES[a0.get("surface", "dry")]["grip"]
			var v_curve := sqrt(0.75 * grip * 9.8 * 15.0 / ang)
			var v_now := sqrt(v_curve * v_curve + 2.0 * 5.0 * k)
			target = minf(target, v_now * 3.6)
	var target_kmh_saved := target_kmh
	target_kmh = target
	if main.race_state == main.Race.FINISHED:
		# Po mecie auto hamuje samo (update_race); czekamy na zatrzymanie.
		if not finished_printed:
			finished_printed = true
			print("   >> META t=%.2f, czas przejazdu %s" % [t, main._fmt_time(main.race_time)])
		if car.linear_velocity.length() < 0.3 and stop_t < 0.0:
			stop_t = t
			var left: float = trk.total_length() - trk.lateral_offset(car.global_position)["sample"]["dist"]
			print("   >> auto stanęło %.0f m przed końcem toru" % left)
		return t > 70.0 or (stop_t > 0.0 and t > stop_t + 0.5)
	car.throttle = 1.0 if (t > 0.8 and kmh < target_kmh) else 0.0
	car.brake = clampf((kmh - target_kmh - 2.0) * 0.15, 0.0, 1.0)
	target_kmh = target_kmh_saved
	if not car.automatic and car.wheels_on_ground > 0 and not car.is_shifting():
		if car.engine_rpm > 6600 and car.gear < 6 and car.gear >= 1: car.shift_up()
		elif car.engine_rpm < 2500 and car.gear > 1: car.shift_down()
	car.steer = steer if car.wheels_on_ground > 0 else 0.0
	if car.esp_active:
		esp_frames += 1
		if car.esp_oversteer: esp_over += 1
	if car.tcs_active: tcs_frames += 1
	if car.abs_active: abs_frames += 1
	if frame == 7200 or (main.race_state == main.Race.FINISHED and car.linear_velocity.length() < 0.3 and frame % 60 == 0):
		print("wgniecenia po przejeździe: %d" % car.dent_count)
		print("systemy aktywne (klatki z %d): ESP %d (nadsterowność %d), TCS %d, ABS %d" % [frame, esp_frames, esp_over, tcs_frames, abs_frames])
	if frame == 10:
		print("zawieszenie k=%d, automat=%s" % [car.spring_k, car.automatic])
	if frame % 120 == 0:
		print("t=%5.2f y=%5.1f v=%5.1f km/h bieg=%d rpm=%4.0f kola=%d up.y=%.2f off=%5.2f on=%s d=%.0f/%.0f safe=%.0f" % [
			t, car.global_position.y, kmh, car.gear, car.engine_rpm, car.wheels_on_ground, car.global_basis.y.y,
			info["offset"], info.get("on_track"), s["dist"], trk.total_length(), main._last_safe_dist])
	return t > 70.0

func _sample_at(d: float) -> Dictionary:
	for x in trk._samples:
		if float(x["dist"]) >= d: return x
	return trk._samples[-1]
