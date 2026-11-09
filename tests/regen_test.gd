extends SceneTree
## Rekuperacja elektryka (opcja menu, użytkownik 2026-11-09): po puszczeniu
## gazu przy 100 km/h przez 6 s - opóźnienie rośnie z poziomem, a bateria
## się ładuje (wył. = toczenie bez odzysku).
##   godot --headless --xr-mode off -s res://tests/regen_test.gd </dev/null

const START := Vector3(3000.0, 0.75, 3000.0)
const LEVELS := ["off", "weak", "normal", "strong"]

var main
var car
var cur := -1
var t := 0.0
var phase := 0
var v0 := 0.0
var fuel0 := 0.0
var res := []
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	main.get_node("Ground").set_meta("grip", 1.0)
	main.get_node("Ground").set_meta("surface", "dry")


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	car.steer = 0.0
	car.brake = 0.0
	if cur >= 0:
		t += delta
		if phase == 0:
			car.throttle = 1.0
			if car.speed * 3.6 >= 100.0:
				phase = 1
				t = 0.0
				v0 = car.speed
				fuel0 = car.fuel
		else:
			car.throttle = 0.0
			if t >= 6.0:
				var dec: float = (v0 - car.speed) / 6.0 / 9.81
				var gain: float = (car.fuel - fuel0) * car.tank_kwh * 1000.0     # Wh
				res.append([LEVELS[cur], dec, gain])
				print("rekuperacja %-7s: opóźnienie %.2f g, po 6 s %3.0f km/h, odzysk %+.0f Wh" % [LEVELS[cur], dec, car.speed * 3.6, gain])
				phase = 2
	if cur < 0 or phase == 2:
		cur += 1
		if cur >= LEVELS.size():
			_check()
			return true
		car.drive_layout = "rwd"
		car.hub_motors = false
		car.regen_level = LEVELS[cur]
		car.apply_engine("electric", 180)
		car.repair()
		car.fuel = 0.5
		car.place(Transform3D(Basis(), START))
		t = 0.0
		phase = 0
	return false


func _check() -> void:
	for i in range(1, res.size()):
		if res[i][1] <= res[i - 1][1]:
			print("regen_test: BŁĄD - %s nie hamuje mocniej niż %s" % [res[i][0], res[i - 1][0]])
			fails += 1
	if absf(res[0][2]) > 0.5:
		print("regen_test: BŁĄD - wyłączona rekuperacja zmienia baterię (%.1f Wh)" % res[0][2])
		fails += 1
	if res[3][2] <= res[1][2] or res[1][2] <= 0.0:
		print("regen_test: BŁĄD - odzysk nie rośnie z poziomem")
		fails += 1
	print("regen_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
