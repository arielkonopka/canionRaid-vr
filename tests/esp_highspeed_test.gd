extends SceneTree
## Drobne korekty kierownicą przy ~300 km/h (użytkownik 2026-11-11: "auto
## wpadało w oscylacje, jakby drobna korekta kierownicą powodowała
## przepychanie z kontrolą trakcji"). Hatchback, elektryk w kołach 4x4
## (ustawienia użytkownika), płaski teren. Rozpędzenie prosto, potem 4 s
## sinusa skrętu (mała amplituda, 0,5 Hz) i 6 s bez skrętu. Mierzy: ile
## razy ESP hamował, najmniejszy mnożnik napędu (ESP/TCS), największy kąt
## znoszenia i amplitudę obrotu auta w ostatnich 3 s (czy kołysanie gaśnie).
##   godot --headless --xr-mode off -s res://tests/esp_highspeed_test.gd -- [esp=on|off] [km/h=300] [amplituda=0.05] [grip] </dev/null
## "grip" - ograniczenie skrętu "Wg przyczepności" (opcja menu).

const START := Vector3(0.0, 0.75, 1800.0)
const AP = preload("res://tests/_autopilot.gd")
var main
var car: StuntCar
var t := 0.0
var phase := 0
var t_phase := 0.0
var esp_on := true
var v_target := 300.0
var amp := 0.05
var esp_frames := 0
var esp_brake_max := 0.0
var min_drive := 1.0
var max_beta := 0.0
var late_yaw_max := 0.0
var yaw_in_max := 0.0
var grip := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	esp_on = not (a.size() > 0 and a[0] == "off")
	v_target = float(a[1]) if a.size() > 1 else 300.0
	amp = float(a[2]) if a.size() > 2 else 0.05
	grip = a.size() > 3 and a[3] == "grip"
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	main.get_node("Ground").set_meta("grip", 1.0)
	main.get_node("Ground").set_meta("surface", "dry")


func _physics_process(d: float) -> bool:
	main.set_physics_process(false)
	if t == 0.0:
		car.apply_style("hatchback")
		car.tires = "all_season"
		car.drive_layout = "awd"
		car.hub_motors = true
		car.apply_engine("electric", 700)
		car.regen_level = "normal"
		car.apply_suspension_preset("sport")
		car.tcs_enabled = true
		car.abs_enabled = true
		car.esp_enabled = esp_on
		car.steer_assist = true
		car.steer_grip = grip
		car.automatic = true
		car.repair()
		car.fuel = 1.0
		car.place(Transform3D(Basis(), START))
		car._settle_t = 0.0
	t += d
	t_phase += d
	var kmh: float = car.speed * 3.6
	# Kurs na -Z (prosto), odchyłka od osi X = 0.
	var fwd: Vector3 = -car.global_basis.z
	var head_err := fwd.signed_angle_to(Vector3.FORWARD, car.global_basis.y)
	var off: float = car.global_position.x
	car.brake = 0.0
	car.throttle = 1.0 if kmh < v_target else 0.35
	match phase:
		0:
			car.steer = AP.steer(car, off, head_err) if t > 0.3 else 0.0
			if kmh >= v_target - 2.0:
				phase = 1
				t_phase = 0.0
				print("  %.0f km/h po %.1f s, x %.1f m" % [kmh, t, off])
			elif t > 40.0:
				print("esp_highspeed_test: BŁĄD (nie rozpędził się: %.0f km/h)" % kmh)
				quit(1)
				return true
		1:
			# Kierowca: drobne korekty sinusem, bez sprzężenia.
			car.steer = amp * sin(TAU * 0.5 * t_phase)
			if t_phase > 4.0:
				phase = 2
				t_phase = 0.0
		2:
			car.steer = 0.0
	if phase >= 1:
		var r := absf(car.angular_velocity.dot(car.global_basis.y))
		if phase == 1:
			yaw_in_max = maxf(yaw_in_max, r)
		if phase == 2 and t_phase > 3.0:
			late_yaw_max = maxf(late_yaw_max, r)
		if car.esp_active:
			esp_frames += 1
		for i in range(4):
			esp_brake_max = maxf(esp_brake_max, car._esp_brake[i])
			min_drive = minf(min_drive, car._hub_tcs[i])
		min_drive = minf(min_drive, car._esp_factor)
		max_beta = maxf(max_beta, AP.beta_deg(car))
		if car.global_basis.y.y < 0.5:
			print("esp_highspeed_test: BŁĄD (przewrotka)")
			quit(1)
			return true
	if phase == 2 and t_phase > 6.0:
		print("ESP %s%s, %.0f km/h, amplituda skrętu %.2f: ESP aktywne %.2f s, hamowanie ESP maks %.0f Nm, napęd min %.2f, znoszenie maks %.1f°, obrót przy korektach %.3f rad/s, po 3 s spokoju %.3f rad/s" % [
				"wł." if esp_on else "wył.", ", skręt wg przyczepności" if grip else "", car.speed * 3.6, amp, esp_frames / 120.0, esp_brake_max, min_drive, max_beta, yaw_in_max, late_yaw_max])
		# Warunek (tylko "grip"): korekta 30% drążka bez przepychanki z ESP
		# (było: 30% przy limicie 6° = ESP 3 s, napęd 5%, 9,5°), a po
		# korektach auto się uspokaja. Pełny drążek celowo dochodzi do granicy
		# przyczepności (chmura: zapas 0,5° na znoszenie przodu).
		var ok := not grip or (late_yaw_max < 0.05 and (amp > 0.5 or (esp_frames == 0 and max_beta < 3.0)))
		print("esp_highspeed_test: ", "OK" if ok else "BŁĄD")
		quit(0)
		return true
	return false
