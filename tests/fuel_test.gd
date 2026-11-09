extends SceneTree
## Pusty bak (użytkownik: "brak paliwa, silnik gaśnie"): benzyna i diesel
## gasną - obroty do zera, brak napędu, auto się toczy; po zatankowaniu
## silnik pracuje i auto rusza. Elektryk bez prądu nie ma momentu.
##   godot --headless --xr-mode off -s res://tests/fuel_test.gd </dev/null

const START := Vector3(-300.0, 0.75, 600.0)

var main
var car
var engines := ["petrol", "diesel", "electric"]
var cur := -1
var t := 0.0
var fails := 0
var v_out := -1.0
var rpm_out := 0.0
var ran_out_t := -1.0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")


func _check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		print("  BŁĄD: ", what)


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	if cur < 0 or t >= 14.0:
		if cur >= 0:
			var e: String = engines[cur]
			print("%-8s paliwo skończyło się po %.1f s; 2 s później %.0f km/h, %.0f obr.; po zatankowaniu %.0f km/h, silnik %s" % [
				e, ran_out_t, v_out, rpm_out, car.speed * 3.6, "pracuje" if car.engine_running else "stoi"])
			_check(ran_out_t > 0.0, e + ": bak się nie opróżnił")
			if e != "electric":
				_check(rpm_out < 300.0, e + ": obroty po zgaśnięciu %.0f" % rpm_out)
			_check(car.engine_running and car.speed * 3.6 > v_out, e + ": po zatankowaniu nie przyspiesza")
		cur += 1
		if cur >= engines.size():
			print("fuel_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
		car.drive_layout = "rwd"
		car.hub_motors = false
		car.apply_engine(engines[cur], 180)
		car.automatic = true
		car.repair()
		car.place(Transform3D(Basis(), START))
		car._settle_t = 0.0
		car.fuel = 0.004
		t = 0.0
		ran_out_t = -1.0
		v_out = -1.0
		return false
	t += delta
	car.throttle = 1.0
	car.brake = 0.0
	car.steer = 0.0
	if ran_out_t < 0.0 and car.fuel <= 0.0:
		ran_out_t = t
	if ran_out_t > 0.0 and v_out < 0.0 and t >= ran_out_t + 2.0:
		v_out = car.speed * 3.6
		rpm_out = car.engine_rpm
		car.refuel(1.0)
	return false
