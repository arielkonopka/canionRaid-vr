extends SceneTree
## Prędkość maksymalna dla opływowości nadwozia (StuntCar.AERO) i mocy.
## Pełny gaz na płaskiej, nieskończonej ziemi (z dala od toru demo) do
## ustalenia prędkości (jazda w -Z: w +X przy 700 kW z tyłu auto wpada
## w dryf - patrz HANDOVER, niestabilność przy dużej prędkości) (przyrost < 0,3 km/h na s) albo 120 s. Sprawdza
## obietnicę z menu: przy najmocniejszej opcji > 300 km/h na każdej
## opływowości (użytkownik 2026-11-09).
##   godot --headless --xr-mode off -s res://tests/topspeed_test.gd [-- petrol|diesel|electric] </dev/null

const START := Vector3(3000.0, 0.75, 3000.0)

var main
var car
var runs := []
var cur := -1
var t := 0.0
var last_kmh := 0.0
var last_t := 0.0
var t100 := -1.0
var t200 := -1.0
var t300 := -1.0
var fails := 0
var finished := false


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	main.get_node("Ground").set_meta("grip", 1.0)
	main.get_node("Ground").set_meta("surface", "dry")
	var e: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "petrol"
	for p in [130, 350, 700]:
		for a in ["classic", "modern", "sport", "record"]:
			runs.append([e, p, a])


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	if cur >= 0:
		t += delta
		car.throttle = 1.0
		car.fuel = 1.0          # pełny gaz 700 kW wypala bak w ~40 s
		car.brake = 0.0
		car.steer = 0.0
		var kmh: float = car.speed * 3.6
		if t100 < 0.0 and kmh >= 100.0:
			t100 = t
		if t200 < 0.0 and kmh >= 200.0:
			t200 = t
		if t300 < 0.0 and kmh >= 300.0:
			t300 = t
		var done := t > 120.0
		if t - last_t >= 4.0:
			if t > 20.0 and (kmh - last_kmh) / (t - last_t) < 0.3:
				done = true
			last_kmh = kmh
			last_t = t
		if done:
			finished = true
			var r: Array = runs[cur]
			var fmt := func(x: float) -> String: return "%5.1f s" % x if x >= 0.0 else "   -   "
			print("%-8s %3d kW %-8s CdA %.2f: maks %3.0f km/h po %3.0f s (bieg %d, %4.0f obr.), 0-100 %s, 0-200 %s, 0-300 %s" % [
					r[0], r[1], r[2], car.aero_drag / (0.5 * 1.225), kmh, t, car.gear, car.engine_rpm,
					fmt.call(t100), fmt.call(t200), fmt.call(t300)])
			if r[1] == 700 and kmh < 300.0:
				print("topspeed_test: BŁĄD - najmocniejsza opcja poniżej 300 km/h")
				fails += 1
	if cur < 0 or finished:
		finished = false
		cur += 1
		if cur >= runs.size():
			print("topspeed_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
			return true
		var r: Array = runs[cur]
		car.drive_layout = "rwd"
		car.hub_motors = false
		car.apply_engine(r[0], r[1])
		car.set_aero(r[2])
		car.automatic = true
		car.repair()
		car.fuel = 1.0
		car.place(Transform3D(Basis(), START))
		t = 0.0
		last_t = 0.0
		last_kmh = 0.0
		t100 = -1.0
		t200 = -1.0
		t300 = -1.0
	return false

