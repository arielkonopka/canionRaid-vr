extends SceneTree
## Lądowanie z wciśniętym gazem (użytkownik 2026-11-09: "gdy samochód skacze
## i przy lądowaniu wcisnę gaz, samochód się obraca"). Auto puszczone
## z 1,5 m przy 100 km/h, lekko przechylone (jak po skoczni), gaz w locie
## i po lądowaniu. Mierzy obroty kół w locie (poślizg względem auta)
## i zmianę kursu po lądowaniu.
##   godot --headless --xr-mode off -s res://tests/landing_test.gd </dev/null

const START := Vector3(-300.0, 2.3, 600.0)

var main
var car
var runs := []
var cur := -1
var t := 0.0
var max_spin := 0.0
var landed_t := -1.0
var yaw0 := 0.0
var max_dyaw := 0.0
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	main.get_node("Ground").set_meta("grip", 1.0)
	main.get_node("Ground").set_meta("surface", "dry")
	for layout in [["awd", 700, 2500.0], ["rwd", 350, 1200.0]]:
		for tcs in [true, false]:
			for thr in [1.0, 0.0]:
				runs.append(layout + [tcs, thr])


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	var done := cur < 0
	if cur >= 0:
		var r: Array = runs[cur]
		t += delta
		car.throttle = r[4]
		car.brake = 0.0
		car.steer = 0.0
		var grounded := 0
		var spin := 0.0
		for w in car.wheels:
			if w.contact:
				grounded += 1
			spin = maxf(spin, (w.omega * car.wheel_radius - car.speed) / maxf(car.speed, 3.0))
		if landed_t < 0.0:
			max_spin = maxf(max_spin, spin)
			if grounded >= 2 and t > 0.1:
				landed_t = t
				yaw0 = car.global_rotation.y
		else:
			max_dyaw = maxf(max_dyaw, absf(angle_difference(yaw0, car.global_rotation.y)))
		if t > 4.0:
			print("%s %4d kW %4.0f kg TCS %-5s gaz %.0f: poślizg kół w locie %4.2f, zmiana kursu po lądowaniu %5.1f°, %3.0f km/h" % [
				r[0], r[1], r[2], r[3], r[4], max_spin, rad_to_deg(max_dyaw), car.speed * 3.6])
			if r[3] and max_dyaw > deg_to_rad(15.0):
				fails += 1
				print("  BŁĄD: z TCS auto obraca się po lądowaniu")
			done = true
	if done:
		cur += 1
		if cur >= runs.size():
			print("landing_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
		var r: Array = runs[cur]
		car.tires = "all_season"
		car.drive_layout = r[0]
		car.hub_motors = false
		car.apply_engine("petrol", r[1])
		car.set_body_mass(r[2])
		car.tcs_enabled = r[3]
		car.esp_enabled = false
		car.abs_enabled = false
		car.automatic = true
		car.repair()
		car.fuel = 1.0
		# Lekki przechył i kołysanie jak po wybiciu ze skoczni.
		var b := Basis(Vector3.FORWARD, deg_to_rad(4.0)) * Basis(Vector3.RIGHT, deg_to_rad(-3.0))
		car.place(Transform3D(b, START))
		car._settle_t = 0.0
		car.linear_velocity = Vector3(0.0, 0.0, -100.0 / 3.6)
		for w in car.wheels:
			w.omega = 100.0 / 3.6 / car.wheel_radius
		car.gear = 3
		t = 0.0
		max_spin = 0.0
		landed_t = -1.0
		max_dyaw = 0.0
	return false
