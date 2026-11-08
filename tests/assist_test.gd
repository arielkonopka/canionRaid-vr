extends SceneTree
## Test systemów wspomagania (ABS, TCS, ESP) na płaskiej ziemi, z dala od toru.
## Każdy scenariusz jedzie dwa razy: z systemem włączonym i wyłączonym.
##   godot --headless --xr-mode off -s res://tests/assist_test.gd -- dry </dev/null
## Argument: nawierzchnia dry / wet / ice (domyślnie dry). Ziemia dostaje
## przyczepność tej nawierzchni z StuntTrack.SURFACES.
##
## Scenariusze:
##   ABS - hamowanie awaryjne ze 100 km/h, po 0,2 s skręt (ominięcie przeszkody).
##         Z ABS auto powinno skręcić; z zablokowanymi kołami jedzie prosto.
##   TCS - ruszanie pełnym gazem na jedynce. Z TCS mniej buksowania.
##   ESP - gwałtowna zmiana pasa przy 90 km/h bez gazu. Z ESP mniejszy kąt
##         znoszenia (β) i brak obrotu.
## Scena główna ma wyłączony _physics_process, więc nie czyta wejścia
## i dźwig nie zabiera auta z ziemi.

const START := Vector3(-300.0, 0.75, 300.0)

var main
var car
var scenarios := []
var cur := -1
var t := 0.0
var stats := {}


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	var args := OS.get_cmdline_user_args()
	var surf: String = args[0] if args.size() > 0 else "dry"
	var ground: Node = main.get_node("Ground")
	ground.set_meta("grip", StuntTrack.SURFACES[surf]["grip"])
	ground.set_meta("surface", surf)
	print("nawierzchnia: %s (grip %.2f)" % [surf, StuntTrack.SURFACES[surf]["grip"]])
	for sys in ["abs", "tcs", "esp"]:
		for on in [true, false]:
			scenarios.append([sys, on])


func _begin(sc: Array) -> void:
	var sys: String = sc[0]
	var on: bool = sc[1]
	# Tylko testowany system zmienia stan, pozostałe włączone.
	car.abs_enabled = on if sys == "abs" else true
	car.tcs_enabled = on if sys == "tcs" else true
	car.esp_enabled = on if sys == "esp" else true
	car.automatic = true
	car.apply_suspension_preset("sport")
	car.place(Transform3D(Basis(), START))
	# place() uspokaja auto przez 0,5 s (zeruje prędkość) - test nadaje
	# prędkość startową od razu, więc bez uspokajania.
	car._settle_t = 0.0
	var v0: float = {"abs": 100.0, "tcs": 0.0, "esp": 90.0}[sys] / 3.6
	# Na lodzie 90 km/h to loteria w każdym aucie - test przy rozsądnej prędkości.
	if car.wheels[0].grip < 0.5 or main.get_node("Ground").get_meta("grip") < 0.5:
		v0 *= 0.5
	car.linear_velocity = Vector3(0, 0, -v0)
	for w in car.wheels:
		w.omega = v0 / car.wheel_radius
	var g: int = {"abs": 4, "tcs": 1, "esp": 3}[sys]
	car.gear = g
	car._pending_gear = g
	t = 0.0
	stats = {"max_beta": 0.0, "locked": 0, "frames": 0, "slip_sum": 0.0, "slip_n": 0,
			"tcs_frames": 0, "esp_frames": 0, "abs_frames": 0, "spun": false}


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	if cur < 0 or _done():
		if cur >= 0:
			_report()
		cur += 1
		if cur >= scenarios.size():
			return true
		_begin(scenarios[cur])
		return false

	t += delta
	var sys: String = scenarios[cur][0]
	match sys:
		"abs":
			car.throttle = 0.0
			car.brake = 1.0
			car.steer = 0.0 if t < 0.2 else 0.7
		"tcs":
			car.throttle = 1.0
			car.brake = 0.0
			car.steer = 0.0
		"esp":
			car.throttle = 0.0
			car.brake = 0.0
			car.steer = 0.0 if t < 0.3 else (1.0 if t < 1.1 else (-1.0 if t < 1.9 else 0.0))

	stats["frames"] += 1
	var v: Vector3 = car.linear_velocity
	var fwd: Vector3 = -car.global_basis.z
	if v.length() > 3.0:
		var beta := rad_to_deg(fwd.signed_angle_to(v, Vector3.UP))
		stats["max_beta"] = maxf(stats["max_beta"], absf(beta))
		if absf(beta) > 70.0:
			stats["spun"] = true
		for w in car.wheels:
			if w.contact and absf(w.omega) < 0.5:
				stats["locked"] += 1
	if sys == "tcs" and v.length() > 0.5:
		var v_ref: float = (car.wheels[0].omega + car.wheels[1].omega) * 0.5 * car.wheel_radius
		var v_rear: float = (car.wheels[2].omega + car.wheels[3].omega) * 0.5 * car.wheel_radius
		stats["slip_sum"] += (v_rear - v_ref) / maxf(v_ref, 3.0)
		stats["slip_n"] += 1
	if car.tcs_active: stats["tcs_frames"] += 1
	if car.esp_active: stats["esp_frames"] += 1
	if car.abs_active: stats["abs_frames"] += 1
	return false


func _done() -> bool:
	var sys: String = scenarios[cur][0]
	match sys:
		"abs":
			return (t > 0.5 and car.linear_velocity.length() < 1.0) or t > 15.0
		"tcs":
			return t > 3.0
		_:
			return t > 4.0


func _report() -> void:
	var sys: String = scenarios[cur][0]
	var on: bool = scenarios[cur][1]
	var p: Vector3 = car.global_position - START
	var heading := rad_to_deg(Vector3(0, 0, -1).signed_angle_to(-car.global_basis.z, Vector3.UP))
	var label := "%s %s" % [sys.to_upper(), "WŁ. " if on else "WYŁ."]
	match sys:
		"abs":
			print("%s  droga hamowania %.1f m, zjazd w bok %.1f m, obrót %.0f°, koła zablokowane %.0f%% czasu, ABS aktywny %d klatek" % [
				label, -p.z, -p.x, heading, 100.0 * stats["locked"] / maxf(stats["frames"] * 4.0, 1.0), stats["abs_frames"]])
		"tcs":
			print("%s  po 3 s: %.1f km/h, %.1f m, średni poślizg tyłu %.2f, TCS aktywny %d klatek" % [
				label, car.linear_velocity.length() * 3.6, -p.z,
				stats["slip_sum"] / maxf(stats["slip_n"], 1.0), stats["tcs_frames"]])
		"esp":
			print("%s  max kąt znoszenia β %.1f°, obrót %s, końcowy kurs %.0f°, prędkość %.0f km/h, ESP aktywny %d klatek" % [
				label, stats["max_beta"], "TAK" if stats["spun"] else "nie", heading,
				car.linear_velocity.length() * 3.6, stats["esp_frames"]])
