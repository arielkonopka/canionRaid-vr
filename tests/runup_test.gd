extends SceneTree
## Ile prędkości auto zyskuje na rozbiegu: start z 60 km/h (wyjście z łuku),
## pełny gaz, prędkość po 60/90/120/150 m. Dla każdego progu mocy
## i napędu - do strojenia trudności trasy pod warsztaty.
##   godot --headless --xr-mode off -s res://tests/runup_test.gd </dev/null

const START := Vector3(-300.0, 0.75, 900.0)
const MARKS := [60.0, 90.0, 120.0, 150.0]
var main
var car
var runs := []
var cur := -1
var dist := 0.0
var res := []
var f := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for kw in [90, 130, 180, 250, 350, 500, 700]:
		for e in ["petrol", "diesel", "electric"]:
			runs.append([e, kw])


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	f += 1
	if f < 3:
		return false
	if car == null:
		car = main.get_node("Car")
		main.get_node("Ground").set_meta("grip", 1.0)
	if cur < 0 or res.size() >= MARKS.size():
		if cur >= 0:
			print("%-8s %3d kW: %s" % [runs[cur][0], runs[cur][1], "  ".join(res)])
		cur += 1
		if cur >= runs.size():
			return true
		car.apply_engine(runs[cur][0], runs[cur][1])
		car.automatic = true
		car.place(Transform3D(Basis(), START))
		car._settle_t = 0.0      # place() zjada prędkość przez 0,5 s - start z 60 km/h od razu
		var v0 := 60.0 / 3.6
		car.linear_velocity = Vector3(0, 0, -v0)
		for w in car.wheels:
			w.omega = v0 / car.wheel_radius
		var g := mini(2, car.gear_ratios.size())   # elektryk ma jeden bieg
		car.gear = g
		car._pending_gear = g
		dist = 0.0
		res = []
		return false
	car.throttle = 1.0
	car.brake = 0.0
	car.steer = 0.0
	dist += car.speed * delta
	if dist >= MARKS[res.size()]:
		res.append("%3.0f m: %3.0f km/h" % [MARKS[res.size()], car.speed * 3.6])
	return false
