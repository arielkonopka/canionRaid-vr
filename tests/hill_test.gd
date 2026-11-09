extends SceneTree
## Ruszanie pod górę: pełny gaz od zera na pochylni (StaticBody, sucho) przez
## 12 s. Zgłoszenie użytkownika (2026-11-09): "auto praktycznie nie jest
## w stanie ruszyć pod górę" - konfiguracja z gogli: benzyna 1000->700 kW,
## 4x4, automat, 2500 kg, TCS wł.
## Sprawdzone wtedy: fizyka wjeżdża (25% - 158 km/h, 50% - 101 km/h po
## 12 s); w teście bez tankowania auto stawało po dwóch przejazdach, bo
## 700 kW na pełnym gazie opróżnia bak (3,6 kWh) w ~25 s - stąd tankowanie.
##   godot --headless --xr-mode off -s res://tests/hill_test.gd </dev/null

const GRADES := [0.15, 0.35]
## Minimalna prędkość po 12 s pod górę [km/h] - poniżej: BŁĄD.
const MIN_KMH := 30.0

var main
var car
var runs := []
var cur := -1
var t := 0.0
var ramp: StaticBody3D
var log_t := 0.0
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	for cfg in [
			["petrol", 700, "awd", 2500.0, true],
			["petrol", 180, "rwd", 1200.0, true],
			["diesel", 90, "rwd", 1200.0, true],
			["electric", 1000, "hub", 2500.0, true]]:
		for g in GRADES:
			runs.append(cfg + [g])


func _make_ramp(grade: float) -> Transform3D:
	if ramp:
		ramp.free()
	ramp = StaticBody3D.new()
	ramp.set_meta("grip", StuntTrack.SURFACES["dry"]["grip"])
	ramp.set_meta("surface", "dry")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 1.0, 600.0)
	cs.shape = box
	ramp.add_child(cs)
	var ang := atan(grade)
	# Wzniesienie w kierunku -Z (przód auta).
	var b := Basis(Vector3.RIGHT, ang)
	var base := Vector3(0.0, 200.0, 0.0)
	ramp.transform = Transform3D(b, base)
	main.add_child(ramp)
	# Auto na górnej powierzchni, w połowie pochylni od dołu.
	var top := base + b * Vector3(0.0, 0.5, 200.0)
	return Transform3D(b, top + b * Vector3(0.0, 0.75, 0.0))


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	if cur < 0 or t >= 12.5:
		if cur >= 0:
			var r: Array = runs[cur]
			print("%-8s %4d kW %-3s %4.0f kg TCS %-3s  wzniesienie %2.0f%%:  po 12 s %5.1f km/h, bieg %d, %5.0f obr., poślizg kół %s" % [
				r[0], r[1], r[2], r[3], "wł." if r[4] else "wył.", r[5] * 100.0,
				car.speed * 3.6, car.gear, car.engine_rpm, _slips()])
			if car.speed * 3.6 < MIN_KMH:
				fails += 1
				print("  BŁĄD: nie wjeżdża (< %.0f km/h)" % MIN_KMH)
		cur += 1
		if cur >= runs.size():
			print("hill_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
		var r: Array = runs[cur]
		var xf := _make_ramp(r[5])
		car.drive_layout = "rwd" if r[2] == "rwd" else "awd"
		car.hub_motors = r[2] == "hub"
		car.apply_engine(r[0], r[1])
		car.set_body_mass(r[3])
		car.automatic = true
		car.tcs_enabled = r[4]
		car.esp_enabled = false
		car.abs_enabled = false
		car.repair()
		car.fuel = 1.0
		car.place(xf)
		car._settle_t = 0.0
		t = 0.0
		log_t = 0.0
		return false
	t += delta
	car.throttle = 1.0 if t > 0.5 else 0.0
	car.brake = 0.0
	car.steer = 0.0
	return false


func _slips() -> String:
	var a := []
	for w in car.wheels:
		a.append("%.2f%s" % [w.slip, "" if w.contact else "!"])
	return ",".join(a) + " poz " + str(car.global_position.round()) + " paliwo %.2f" % car.fuel
