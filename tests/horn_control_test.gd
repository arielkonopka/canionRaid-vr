extends SceneTree
## Klakson nie może sam rozbijać botów (użytkownik 2026-11-11: "Boty, gdy
## na nie zatrąbić, często tracą kontrolę nad jazdą... Zdarza się, że tylko
## od tego mają wypadek"). Gracz jedzie przepisowo za kilkoma botami,
## trąbi; przez 10 s żaden bot nie może: obrócić się (> 60° od kierunku
## drogi przy > 20 km/h), przewrócić ani wypaść poza jezdnię. Wypisuje też
## największe przyspieszenie boczne bota (dla oceny "ostro, ale rozsądnie").
## Dwa przebiegi: wąwóz i autostrada.
##   godot --headless --xr-mode off -s res://tests/horn_control_test.gd </dev/null
##   godot --headless --xr-mode off -s res://tests/horn_control_test.gd -- autostrada </dev/null

var main
var car: StuntCar
var f := 0
var horn_f := -1
var worst_head := 0.0
var worst_lat := 0.0
var worst_off := 0.0
var flipped := 0
var prev_v := {}
const SPAWN := [70.0, 110.0, 150.0, 200.0]


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada" if OS.get_cmdline_user_args().has("autostrada") else "canyon"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		car = main.get_node("Car")
		main._bot_timer = 9999.0
		main.race_state = main.Race.RACING
		for d in SPAWN:
			main._spawn_bot(main._last_safe_dist + d)
		print("boty: %d" % main._bots.size())
	if f < 5:
		return false
	# Gracz jedzie prosto osią swojego pasa ~ ograniczenia (bez kolizji z botami
	# - jest daleko za nimi i wolniej od szału).
	car.throttle = 0.6 if car.speed < 16.0 else 0.0
	car.brake = 0.0
	car.steer = 0.0
	if f == 240:                       # 2 s rozpędu
		main.player_horn()
		horn_f = f
		var n := 0
		for b in main._bots:
			if (b.get_node("Driver") as BotDriver).rage > 0.9:
				n += 1
		print("klakson: %d botów w szale" % n)
		if n == 0:
			print("horn_control_test: BŁĄD (nikt nie wpadł w szał)")
			return true
	if horn_f < 0:
		return false
	for b in main._bots:
		if not is_instance_valid(b):
			continue
		var drv: BotDriver = b.get_node("Driver")
		if drv.on_rail:
			continue
		var xf: Transform3D = main.track.transform_at_distance(drv.dist)
		var road_fwd := -xf.basis.z
		var fwd := -b.global_basis.z
		var kmh := absf(b.speed) * 3.6
		if kmh > 20.0 and drv._reverse_t <= 0.0:
			worst_head = maxf(worst_head, rad_to_deg(fwd.angle_to(road_fwd)))
		var smp: Array = main.track.samples_from(drv.dist, 1.0)
		if not smp.is_empty():
			var off := absf((b.global_position - (smp[0]["pos"] as Vector3)).dot(smp[0]["right"]))
			worst_off = maxf(worst_off, off - float(smp[0]["width"]) * 0.5)
		if b.global_basis.y.y < 0.3:
			flipped += 1
		var id := b.get_instance_id()
		var v: Vector3 = b.linear_velocity
		if prev_v.has(id) and kmh > 20.0:
			var a: Vector3 = (v - prev_v[id]) / delta
			worst_lat = maxf(worst_lat, absf(a.dot(b.global_basis.x)))
		prev_v[id] = v
	if f == horn_f + 1200:             # 10 s po klaksonie
		print("najgorzej: obrót %.0f°, poza jezdnią %.1f m, a_bok %.1f m/s², przewrotek %d"
				% [worst_head, worst_off, worst_lat, flipped])
		var ok := worst_head < 60.0 and worst_off < 1.0 and flipped == 0
		print("horn_control_test: ", "OK" if ok else "BŁĄD")
		return true
	return false
