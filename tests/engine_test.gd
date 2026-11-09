extends SceneTree
## Test napędów: pełny gaz od zera na płaskiej ziemi przez 25 s.
## Dla rodzaju napędu, mocy i układu (tył / 4x4 / silniki w kołach) podaje
## 0-100 i 0-200 km/h, prędkość po 25 s, bieg i obroty. Automat, TCS i ESP
## włączone.
##   godot --headless --xr-mode off -s res://tests/engine_test.gd [-- dry|wet|ice [petrol|diesel|electric]] </dev/null

const START := Vector3(-300.0, 0.75, 600.0)
const POWERS := [90, 180, 350, 700]

var main
var car
var runs := []
var cur := -1
var t := 0.0
var t100 := -1.0
var t200 := -1.0
var max_kmh := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	var ground: Node = main.get_node("Ground")
	var surf: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "dry"
	ground.set_meta("grip", StuntTrack.SURFACES[surf]["grip"])
	ground.set_meta("surface", surf)
	print("nawierzchnia: ", surf)
	var only: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	for e in ["petrol", "diesel", "electric"]:
		if only != "" and e != only:
			continue
		for p in POWERS:
			runs.append([e, p, "rwd"])
			if p == 180:
				runs.append([e, p, "fwd"])
			if p >= 350:
				runs.append([e, p, "awd"])
				if e == "electric":
					runs.append([e, p, "hub"])
		if e == "electric":
			runs.append([e, 1000, "hub"])     # próg tylko dla silników w kołach


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	if cur < 0 or t >= 25.0:
		if cur >= 0:
			print("%-8s %3d kW %-3s (%4d Nm, %4d kg):  0-100 %s,  0-200 %s,  po 25 s %3.0f km/h,  bieg %d, %5.0f obr., poz %s, maks %3.0f km/h" % [
				runs[cur][0], runs[cur][1], runs[cur][2], car.peak_torque(), car.mass,
				("%4.1f s" % t100) if t100 > 0.0 else "  -   ",
				("%4.1f s" % t200) if t200 > 0.0 else "  -   ", car.speed * 3.6, car.gear, car.engine_rpm, car.global_position.round(), max_kmh])
		cur += 1
		if cur >= runs.size():
			return true
		car.drive_layout = runs[cur][2] if runs[cur][2] != "hub" else "awd"
		car.hub_motors = runs[cur][2] == "hub"
		car.apply_engine(runs[cur][0], runs[cur][1])
		car.automatic = true
		car.tcs_enabled = true
		car.esp_enabled = true
		car.place(Transform3D(Basis(), START))
		# Bez naprawy uszkodzenia silnika z poprzednich przejazdów się
		# sumowały (objaw: kolejne auta coraz wolniejsze, ostatnie stoi).
		car.repair()
		car.fuel = 1.0         # bak pusty po kilku przejazdach - silnik gasł (fuel_test)
		t = 0.0
		t100 = -1.0
		t200 = -1.0
		max_kmh = 0.0
		return false
	t += delta
	car.throttle = 1.0 if t > 0.5 else 0.0
	car.brake = 0.0
	car.steer = 0.0
	if t100 < 0.0 and car.speed * 3.6 >= 100.0:
		t100 = t - 0.5
	max_kmh = maxf(max_kmh, car.speed * 3.6)
	if t200 < 0.0 and car.speed * 3.6 >= 200.0:
		t200 = t - 0.5
	return false
