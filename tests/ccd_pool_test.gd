extends SceneTree
## Auto wracające do fizyki bez place() (z puli, z szyny) nie może dostać
## "uderzenia znikąd" z zapamiętanej prędkości poprzedniego życia
## (StuntCar._ccd_impact, przegląd chmury 2026-11-12). Auto luzem 40 m/s,
## zamrożone na 1 s (jak pula), odmrożone z 30 m/s -> 0 szkód i wgnieceń.
##   godot --headless --xr-mode off -s res://tests/ccd_pool_test.gd </dev/null

const START := Vector3(0.0, 0.75, 1500.0)
var main
var car: StuntCar
var f := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")


func _physics_process(_d: float) -> bool:
	main.set_physics_process(false)
	f += 1
	car.throttle = 0.0
	car.brake = 0.0
	car.steer = 0.0
	if f == 3:
		car.place(Transform3D(Basis(), START))
		car._settle_t = 0.0
		car.repair()
	elif f == 10:
		car.linear_velocity = Vector3(0, 0, -40.0)
		for w in car.wheels:
			w.omega = 40.0 / car.wheel_radius
	elif f == 60:
		car.freeze = true                  # do puli
	elif f == 180:
		car.global_position = START + Vector3(0, 0, -200)
		car.freeze = false                 # jak _loosen_oncoming: inna prędkość
		car.linear_velocity = Vector3(0, 0, -30.0)
		for w in car.wheels:
			w.omega = 30.0 / car.wheel_radius
	elif f == 300:
		var ok: bool = car.damage["structure"] == 0.0 and car.dent_count == 0
		print("po powrocie z puli: konstrukcja %.0f%%, wgnieceń %d, ostatni kontakt %s" % [
				car.damage["structure"] * 100.0, car.dent_count, str(car.last_hit.get("what", "-"))])
		print("ccd_pool_test: ", "OK" if ok else "BŁĄD")
		quit(0 if ok else 1)
		return true
	return false
