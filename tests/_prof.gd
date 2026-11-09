extends SceneTree
const START := Vector3(-300.0, 0.75, 600.0)
var main; var car; var t := 0.0; var v0 := 0.0; var nxt := 0.0
func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main); car = main.get_node("Car")
	main.get_node("Ground").set_meta("grip", 1.0); main.get_node("Ground").set_meta("surface", "dry")
func _physics_process(d: float) -> bool:
	main.set_physics_process(false)
	if t == 0.0:
		car.tires = "all_season"; car.drive_layout = "fwd"; car.hub_motors = false; car.apply_engine("petrol", 180); car.set_body_mass(1200.0)
		car.tcs_enabled = true; car.esp_enabled = false; car.automatic = true
		car.repair(); car.fuel = 1.0; car.place(Transform3D(Basis(), START)); car._settle_t = 0.0
	t += d
	car.throttle = 1.0 if t > 0.3 else 0.0; car.brake = 0.0; car.steer = 0.0
	if t >= nxt:
		var a: float = (car.speed - v0) / 0.25 / 9.81
		var k := []; var l := []; var f := []
		for w in car.wheels: k.append("%.2f" % w.kappa); l.append("%.1f" % (w.load/1000.0))
		print("t %.2f %5.1f km/h a %.2f g bieg %d %5.0f obr sprz %s tcs %.2f kappa %s load %s" % [t, car.speed*3.6, a, car.gear, car.engine_rpm, car._clutch_engaged, car._tcs_factor, ",".join(k), ",".join(l)])
		v0 = car.speed; nxt += 0.25
	return t > 3.0
