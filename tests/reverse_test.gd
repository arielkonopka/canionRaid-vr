extends SceneTree
## Wsteczny z osobnego przycisku: przy 40 km/h żądanie wstecznego nie
## wrzuca biegu; po zatrzymaniu wchodzi R i gaz jedzie do tyłu; puszczenie
## przycisku na postoju wraca na 1.
##   godot --headless --xr-mode off -s res://tests/reverse_test.gd </dev/null
var main
var car
var t := 0.0
var f := 0
var log_t := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	f += 1
	if f < 3:
		return false
	if car == null:
		car = main.get_node("Car")
		main.get_node("Ground").set_meta("grip", 1.0)
		car.place(Transform3D(Basis(), Vector3(-300, 0.75, 300)))
		car.linear_velocity = Vector3(0, 0, -40.0 / 3.6)
		for w in car.wheels:
			w.omega = (40.0 / 3.6) / car.wheel_radius
		car.dedicated_reverse = true
	t += delta
	car.steer = 0.0
	car.handbrake = 0.0
	if t < 1.0:          # żądanie wstecznego w ruchu, bez hamowania
		car.reverse_request = true; car.throttle = 0.0; car.brake = 0.0
	elif t < 5.0:        # hamowanie do zera, przycisk dalej trzymany
		car.reverse_request = true; car.throttle = 0.0; car.brake = 1.0
	elif t < 8.0:        # gaz na wstecznym
		car.reverse_request = true; car.throttle = 0.6; car.brake = 0.0
	elif t < 11.0:       # hamulec do zera, puszczony przycisk
		car.reverse_request = false; car.throttle = 0.0; car.brake = 1.0
	else:
		car.reverse_request = false; car.throttle = 0.6; car.brake = 0.0
	if t - log_t >= 1.0:
		log_t = t
		print("t=%4.1f  bieg %2d  prędkość %+5.1f km/h" % [t, car.gear, car.speed * 3.6])
	return t > 13.0
