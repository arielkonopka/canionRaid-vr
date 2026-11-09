extends SceneTree
## Puszczony gaz przy dużej prędkości (użytkownik 2026-11-09: "jechałem
## rozpędzony, puściłem gaz, a samochód gwałtownie się zatrzymał").
## Auto rozpędzane pełnym gazem do 150 km/h, potem gaz 0 (bez hamulca)
## przez 6 s. Opóźnienie ma być jak przy hamowaniu silnikiem i oporach
## (~0,1-0,3 g), nie jak hamowanie (~1 g).
##   godot --headless --xr-mode off -s res://tests/coast_test.gd </dev/null

const START := Vector3(-300.0, 0.75, 600.0)
const TARGET_KMH := 150.0

var main
var car
var runs := []
var cur := -1
var t := 0.0
var phase := 0
var v_lift := 0.0
var t_lift := 0.0
var max_dec := 0.0
var v_prev := 0.0
var log_line := ""
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	main.get_node("Ground").set_meta("grip", 1.0)
	main.get_node("Ground").set_meta("surface", "dry")
	for e in ["petrol", "diesel", "electric"]:
		for l in ["rwd", "fwd", "awd"]:
			runs.append([e, 130, l, "auto"])
	runs.append(["petrol", 130, "rwd", "manual"])
	runs.append(["petrol", 350, "rwd", "auto"])


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	if cur >= 0:
		t += delta
		var r: Array = runs[cur]
		var kmh: float = car.speed * 3.6
		car.steer = 0.0
		car.brake = 0.0
		if phase == 0:
			car.throttle = 1.0
			if r[3] == "manual":
				var up_rpm: float = car.redline_rpm * 0.93
				if car.engine_rpm > up_rpm and car.gear < car.gear_ratios.size():
					car.shift_up()
			if kmh >= TARGET_KMH or t > 60.0:
				phase = 1
				v_lift = car.speed
				t_lift = t
				v_prev = car.speed
				log_line = ""
		else:
			car.throttle = 0.0
			var dec: float = (v_prev - car.speed) / delta / 9.81
			v_prev = car.speed
			max_dec = maxf(max_dec, dec)
			var tt := t - t_lift
			if absf(tt - roundf(tt)) < delta * 0.5 and roundf(tt) >= 1.0:
				log_line += " %d s: %3.0f" % [roundi(tt), kmh]
			if tt >= 6.0:
				var avg: float = (v_lift - car.speed) / 6.0 / 9.81
				print("%-8s %3d kW %s %-6s puszczony gaz przy %3.0f km/h:%s km/h | śr. %.2f g, maks %.2f g, bieg %d, %4.0f obr." % [
						r[0], r[1], r[2], r[3], v_lift * 3.6, log_line, avg, max_dec, car.gear, car.engine_rpm])
				if avg > 0.35 or max_dec > 0.8:
					print("coast_test: BŁĄD - auto hamuje jak hamulcem")
					fails += 1
				phase = 2
	if cur < 0 or phase == 2:
		cur += 1
		if cur >= runs.size():
			print("coast_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
			return true
		var r: Array = runs[cur]
		car.drive_layout = r[2]
		car.hub_motors = false
		car.apply_engine(r[0], r[1])
		car.automatic = r[3] == "auto"
		car.repair()
		car.fuel = 1.0
		car.place(Transform3D(Basis(), START))
		t = 0.0
		phase = 0
		max_dec = 0.0
	return false
