extends SceneTree
## Wjazd na skocznię bez gazu (użytkownik 2026-11-09: "z przednim napędem,
## noga z gazu, ponad 100 km/h - wjazd na wyskocznię niemożliwy, auto jakby
## uderza w przeszkodę"; też nagłe zatrzymanie po puszczeniu gazu
## i dachowanie na prostej). Prawdziwy odcinek wąwozu ze skocznią z
## generatora; auto wjeżdża z zadaną prędkością na luzie gazu albo na
## pełnym gazie. Mierzy największe opóźnienie, uderzenia nadwozia
## (StuntCar.last_hit), dobicie zawieszenia i przechył.
##   godot --headless --xr-mode off -s res://tests/ramp_entry_test.gd </dev/null

var main
var car
var chunk: StuntTrack
var runs := []
var cur := -1
var t := 0.0
var f := 0
var ramp_d := 0.0
var max_dec := 0.0
var max_tilt := 0.0
var min_spring := 9.0
var hits := []
var v_prev := 0.0
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	chunk = StuntTrack.new()
	chunk.name = "RampChunk"
	var start := {"pos": Vector3(0.0, 6.0, 3000.0), "yaw": 0.0, "pitch": 0.0,
			"bank": 0.0, "width": 14.8, "dist": 0.0}
	# Sekcja 2: pierwsza ze skocznią w wąwozie.
	chunk.segments.assign(TrackGenerator.generate_section(2, start, rng, true))
	chunk.canyon = true
	chunk.start_state = start
	chunk.build_lines = false
	root.add_child(chunk)
	for layout in [["fwd", 700], ["rwd", 180], ["awd", 700]]:
		for kmh in [80.0, 110.0, 140.0]:
			for thr in [0.0, 1.0]:
				runs.append([layout[0], layout[1], kmh, thr])


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	f += 1
	if f < 3:
		return false
	if car == null:
		car = main.get_node("Car")
		var sign_d := chunk.runup_start_before(chunk.total_length())
		# Początek rampy: pierwsze miejsce za znakiem, gdzie jezdnia wznosi się > 3°.
		ramp_d = sign_d
		while ramp_d < chunk.total_length():
			var b: Basis = chunk.transform_at_distance(ramp_d).basis
			if rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0))) > 3.0:
				break
			ramp_d += 1.0
		print("znak rozbiegu %.0f m, rampa od %.0f m, odcinek %.0f m" % [sign_d, ramp_d, chunk.total_length()])
	if cur >= 0:
		t += delta
		var r: Array = runs[cur]
		car.throttle = r[3] if t > 0.6 else 0.0
		car.brake = 0.0
		car.steer = 0.0
		if t >= 0.55 and t - delta < 0.55:
			# Po osiadaniu (place() trzyma auto 0,5 s): prędkość wjazdu.
			car.linear_velocity = -car.global_basis.z * r[2] / 3.6
			for w in car.wheels:
				w.omega = r[2] / 3.6 / car.wheel_radius
			car.gear = clampi(int(r[2] / 30.0), 1, 5)
			v_prev = car.linear_velocity.length()
		var v: float = car.linear_velocity.length()
		if t > 0.7:
			max_dec = maxf(max_dec, (v_prev - v) / delta / 9.81)
		v_prev = v
		max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(car.global_basis.y.y, -1.0, 1.0))))
		for w in car.wheels:
			if w.contact:
				min_spring = minf(min_spring, w.spring_len)
		if OS.get_cmdline_user_args().size() > 0 and cur == int(OS.get_cmdline_user_args()[0]) and absf(t - roundf(t * 4.0) / 4.0) < delta * 0.5:
			var sm: Dictionary = chunk.nearest_sample(car.global_position)
			var cs := ""
			for w in car.wheels:
				cs += "K" if w.contact else "-"
			print("  t%.2f %3.0f km/h g%d %4.0f obr. d=%.0f wys.nad jezdnią %.2f pochyl %.0f° %s kontakt %s" % [t, v * 3.6, car.gear, car.engine_rpm, float(sm.get("dist", -1)), (car.global_position - chunk.to_global(sm["pos"])).dot(car.global_basis.y), rad_to_deg(car.global_rotation.x), cs, str(car.last_hit.get("what", "")).get_file()])
		var h: Dictionary = car.last_hit
		if not h.is_empty() and Time.get_ticks_msec() - int(h["ms"]) < 50 and h["j"] > 1500.0:
			var txt := "%s %.0f N·s %s" % [str(h["what"]).get_file(), h["j"], str((h["at"] as Vector3).snapped(Vector3.ONE * 0.1))]
			if hits.is_empty() or hits[-1] != txt:
				hits.append(txt)
		if t > 7.0:
			print("%s %3d kW %3.0f km/h gaz %.0f: maks opóźnienie %4.1f g, przechył %3.0f°, min. ugięcie %.2f m, uderzenia nadwozia: %s | po 7 s %3.0f km/h" % [
					r[0], r[1], r[2], r[3], max_dec, max_tilt, min_spring,
					", ".join(hits.slice(0, 4)) if not hits.is_empty() else "brak", v * 3.6])
			if max_dec > 3.0 and hits.size() > 0:
				fails += 1
			_next()
		return false
	_next()
	return false


func _next() -> void:
	cur += 1
	if cur >= runs.size():
		print("ramp_entry_test: ", "OK" if fails == 0 else "BŁĄD (%d wjazdów z uderzeniem nadwozia)" % fails)
		quit()
		return
	var r: Array = runs[cur]
	car.drive_layout = r[0]
	car.hub_motors = false
	car.apply_engine("petrol", r[1])
	car.repair()
	car.fuel = 1.0
	var xf: Transform3D = chunk.transform_at_distance(ramp_d - 50.0)
	xf.origin += xf.basis.y * 0.6
	car.place(xf)
	car.linear_velocity = -xf.basis.z * r[2] / 3.6
	for w in car.wheels:
		w.omega = r[2] / 3.6 / car.wheel_radius
	t = 0.0
	max_dec = 0.0
	max_tilt = 0.0
	min_spring = 9.0
	hits = []
	v_prev = car.linear_velocity.length()
