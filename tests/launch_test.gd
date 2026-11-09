extends SceneTree
## Ruszanie na suchym (użytkownik 2026-11-09: "przy ruszaniu też chyba
## przyczepność robi różnicę"): 0-50 i 0-100 km/h z TCS i bez, średni
## poślizg tylnych kół przez pierwsze 3 s i średni mnożnik TCS.
## Po poprawce (TCS z wyprzedzeniem, sprzęgło międzyosiowe skalowane
## momentem): 4x4 700 kW 2500 kg 0-100 3,56 s (było 3,86), TCS trzyma
## poślizg 0,10 (było 0,28). Tylny napęd 700 kW 1200 kg ~5 s - granica
## przyczepności tyłu (~0,6 g), nie błąd.
##   godot --headless --xr-mode off -s res://tests/launch_test.gd </dev/null
const START := Vector3(-300.0, 0.75, 600.0)
var main; var car; var cur := -1; var t := 0.0
var runs := [["rwd",180,1200.0,true],["rwd",180,1200.0,false],["fwd",180,1200.0,true],["fwd",180,1200.0,false],["fwd",350,1200.0,true],["awd",700,2500.0,true],["awd",700,2500.0,false],["rwd",700,1200.0,true],["rwd",700,1200.0,false]]
var fails := 0
var t50 := -1.0; var t100 := -1.0; var ks := 0.0; var n := 0; var tf := 0.0
func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main); car = main.get_node("Car")
	main.get_node("Ground").set_meta("grip", 1.0); main.get_node("Ground").set_meta("surface", "dry")
func _physics_process(d: float) -> bool:
	main.set_physics_process(false)
	var done := cur < 0
	if cur >= 0:
		t += d
		car.throttle = 1.0 if t > 0.3 else 0.0; car.brake = 0.0; car.steer = 0.0
		var kmh: float = car.speed * 3.6
		if t > 0.3 and t < 3.3:
			var k := 0.0
			for i in [2, 3]: k += car.wheels[i].kappa
			ks += k / 2.0; tf += car._tcs_factor; n += 1
		if t50 < 0 and kmh >= 50: t50 = t - 0.3
		if t100 < 0 and kmh >= 100: t100 = t - 0.3
		if t > 12.0:
			var r = runs[cur]
			print("%s %4d kW %4.0f kg TCS %-5s: 0-50 %.2f s, 0-100 %.2f s, śr. poślizg tyłu (3 s) %.2f, TCS %.2f" % [r[0], r[1], r[2], r[3], t50, t100, ks / n, tf / n])
			if r[3] and ks / n > 0.2:
				fails += 1
				print("  BŁĄD: TCS dopuszcza za duży poślizg")
			done = true
	if done:
		cur += 1
		if cur >= runs.size():
			print("launch_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
		var r = runs[cur]
		car.tires = "all_season"; car.drive_layout = r[0]; car.hub_motors = false; car.apply_engine("petrol", r[1]); car.set_body_mass(r[2])
		car.tcs_enabled = r[3]; car.esp_enabled = false; car.automatic = true
		car.repair(); car.fuel = 1.0; car.place(Transform3D(Basis(), START)); car._settle_t = 0.0
		t = 0.0; t50 = -1.0; t100 = -1.0; ks = 0.0; n = 0; tf = 0.0
	return false
