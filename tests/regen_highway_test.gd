extends SceneTree
## Odzysk przy dużej prędkości na prawdziwej autostradzie (zgłoszenie
## 2026-11-10: "kontrola trakcji przy rekuperacji pozostawia wiele do
## życzenia"; log: 212 km/h, gaz puszczony, poślizg kół 84-109%, potem
## auto na boku). Ustawienia użytkownika: elektryk 1000 kW w kołach, 4x4,
## 2500 kg, opływowość sportowa, odzysk mocny, wspomagania wł. Autopilot
## (jak endless_test) trzyma pas; cykl: gaz do V, 4 s bez gazu, powtórka.
##   godot --headless --xr-mode off -s res://tests/regen_highway_test.gd -- [V=150] [czas=90] [odzysk=strong] [old] </dev/null
## "old" - stary autopilot (porównanie; sam rozbujał auto przy 210 km/h).
## CANION_TIME_SCALE=1.3 - tempo gry jak u użytkownika.

var main
var car: StuntCar
var f := 0
var t := 0.0
var fails := 0
var v_target := 210.0
var limit := 90.0
var lift_t := -1.0
var lifts := 0
var max_slip := 0.0
var max_lock := 0.0
var max_off := 0.0
var max_beta := 0.0
var rolled := false
var old_ap := false
const AP = preload("res://tests/_autopilot.gd")


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	v_target = float(a[0]) if a.size() > 0 else 150.0
	limit = float(a[1]) if a.size() > 1 else 90.0
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	gs.engine_type = "electric"
	gs.engine_power = 1000
	gs.motor_layout = "hub"
	gs.drive_layout = "awd"
	gs.body_mass = 2500
	gs.aero = "sport"
	gs.regen = a[2] if a.size() > 2 else "strong"
	old_ap = a.size() > 3 and a[3] == "old"
	gs.transmission = "auto"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._traffic_t = 1e9
		main._bot_timer = 1e9
		car = main.car
	if f <= 5:
		return false
	# Krok sceny wyłączony (jak endless_test) - inaczej wejście gry nadpisuje
	# gaz i kierownicę; przesuwanie świata i diagnostykę wołamy sami.
	main.set_physics_process(false)
	main._check_origin_shift()
	main._watch_incident(delta)
	t += delta
	main._watch_track(delta)
	var info: Dictionary = main.track.lateral_offset(car.global_position)
	if not info.has("sample"):
		return false
	var s: Dictionary = info["sample"]
	var fwd: Vector3 = -car.global_basis.z
	var head_err := fwd.signed_angle_to(s["fwd"], car.global_basis.y)
	var lane: float = main.hwy_lane_off(0) if main.has_method("hwy_lane_off") else 0.0
	var off: float = float(info["offset"]) - lane
	if old_ap:
		var gain := clampf(25.0 / maxf(car.speed, 1.0), 0.3, 1.0)
		car.steer = clampf((-off * 0.25 - head_err * 2.5) * gain, -1, 1)
	else:
		car.steer = AP.steer(car, off, head_err)
	var kmh := car.speed * 3.6
	# Ograniczenia (miasta) ważniejsze od testu - tam bez cyklu.
	var lim: float = main.current_limit * 1.1
	var tgt := minf(v_target, maxf(lim, 0.0)) if lim < 139.0 else v_target
	if lift_t >= 0.0:
		car.throttle = 0.0
		lift_t += delta
		if lift_t > 4.0:
			lift_t = -1.0
	else:
		car.throttle = 1.0 if kmh < tgt else 0.0
		if kmh >= v_target - 3.0 and tgt == v_target:
			lift_t = 0.0
			lifts += 1
	if lift_t >= 0.0 and car.wheels_on_ground >= 3:
		for w in car.wheels:
			max_slip = maxf(max_slip, w.slip)
			max_lock = maxf(max_lock, 1.0 - absf(w.omega) * car.wheel_radius / maxf(car.speed, 1.0))
		var beta: float = AP.beta_deg(car)
		if car.speed > 10.0:
			if beta > max_beta and beta > 5.0:
				print("  znoszenie %.1f° przy %.0f km/h, %.1f s po puszczeniu gazu, krzywizna %.4f, skręt %.2f, ESP %s" % [beta, kmh, lift_t, float(s.get("curve", 0.0)), car.steer, car.esp_active])
			max_beta = maxf(max_beta, beta)
		max_off = maxf(max_off, absf(off))
	if car.global_basis.y.y < 0.5:
		rolled = true
	if f % 300 == 0:
		print("  t=%.0f %.0f km/h cel %.0f, gaz %.1f, bieg %d, koła %d, ogr %.0f" % [t, kmh, tgt, car.throttle, car.gear, car.wheels_on_ground, main.current_limit])
	if t > limit or rolled:
		print("odpuszczeń gazu przy %.0f km/h: %d; poślizg łączny maks %.0f%%, blokada koła maks %.0f%%, znoszenie maks %.1f°, zjazd z pasa maks %.1f m" % [
				v_target, lifts, max_slip * 100.0, max_lock * 100.0, max_beta, max_off])
		_check(not rolled, "auto nie przewróciło się")
		_check(lifts >= 3, "co najmniej 3 odpuszczenia gazu")
		_check(max_lock < 0.15, "koła nie blokują się (blokada < 15%)")
		_check(max_beta < 5.0, "auto prosto na prostej (znoszenie < 5°)")
		print("regen_highway_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
		return true
	return false
