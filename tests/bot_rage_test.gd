extends SceneTree
## Szał drogowy bota: gracz najeżdża bota od tyłu, potem 15 s jedzie za
## szybko (130 km/h), potem przepisowo (≤ ograniczenia). Bot ma się wściec,
## gonić (trzymać się blisko) i uspokoić dopiero po przepisowej jeździe.
##   godot --headless --xr-mode off -s res://tests/bot_rage_test.gd </dev/null
var main
var car
var trk
var bot: StuntCar
var drv
var t := 0.0
var f := 0
var hit_t := -1.0
var log_t := 0.0


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "canyon"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	f += 1
	if f < 4:
		return false
	if car == null:
		car = main.get_node("Car")
		trk = main.track
		main._bot_timer = 9999.0
		main.race_state = main.Race.RACING
		car.apply_engine("petrol", 250)
		# Bot 30 m przed graczem, na środku drogi, 60 km/h.
		main._spawn_bot(60.0)
		bot = main._bots[0]
		drv = bot.get_node("Driver")
		var xb: Transform3D = trk.transform_at_distance(60.0)
		bot.place(Transform3D(xb.basis, xb.origin + xb.basis.y * 0.9))
		bot._settle_t = 0.0       # place() zjada prędkość - test nadaje ją od razu
		bot.linear_velocity = -xb.basis.z * 60.0 / 3.6
		for w in bot.wheels:
			w.omega = (60.0 / 3.6) / bot.wheel_radius
		var xp: Transform3D = trk.transform_at_distance(30.0)
		car.place(Transform3D(xp.basis, xp.origin + xp.basis.y * 0.9))
		car._settle_t = 0.0
		car.linear_velocity = -xp.basis.z * 100.0 / 3.6
		for w in car.wheels:
			w.omega = (100.0 / 3.6) / car.wheel_radius
		car.gear = 3
		car._pending_gear = 3
		return false
	t += delta
	main._watch_track(delta)
	main._update_bots(delta)
	# Bot z puli (od 2026-11-11) zostaje węzłem, ale jego kierowca jest
	# zwalniany przy powrocie do puli - test czytał wtedy zwolniony obiekt.
	if not is_instance_valid(bot) or not is_instance_valid(drv) or not main._bots.has(bot):
		print("bot zniknął (wrak / do puli) t=%.1f" % t)
		return true
	if hit_t < 0.0 and drv.rage > 0.9:
		hit_t = t
		print("t=%.1f ZDERZENIE - bot w szale, stan bota %d%%, gracza %d%%" % [t,
			roundi((1.0 - bot.damage["structure"]) * 100), roundi((1.0 - car.damage["structure"]) * 100)])
	# Sterowanie gracza: przed zderzeniem prosto w bota, potem środkiem drogi.
	var info: Dictionary = trk.lateral_offset(car.global_position)
	var s: Dictionary = info["sample"]
	var target_off := 0.0
	if hit_t < 0.0:
		target_off = (bot.global_position - trk.to_global(s["pos"])).dot(s["right"])
	var fwd: Vector3 = -car.global_basis.z
	var head_err := fwd.signed_angle_to(s["fwd"], car.global_basis.y)
	car.steer = clampf(-(info["offset"] - target_off) * 0.25 - head_err * 2.5, -1, 1)
	var want: float = 130.0 if (hit_t < 0.0 or t - hit_t < 15.0) else main.current_limit - 10.0
	var kmh: float = car.speed * 3.6
	car.throttle = 1.0 if kmh < want else 0.0
	car.brake = clampf((kmh - want - 2.0) * 0.15, 0.0, 1.0)
	if t - log_t >= 2.0:
		log_t = t
		var gap: float = (bot.global_position - car.global_position).length()
		var bs: Dictionary = trk.lateral_offset(bot.global_position).get("sample", {})
		var bh := 0.0 if bs.is_empty() else rad_to_deg((-bot.global_basis.z).signed_angle_to(bs["fwd"], Vector3.UP))
		print("    bot %s: kąt %.0f°, koła %d, bieg %d, gaz %.1f, hamulec %.1f, obr %.0f, skrzynia %d%%, cofanie %.1f, wrecked %s" % [bot.style, bh, bot.wheels_on_ground, bot.gear, bot.throttle, bot.brake, bot.engine_rpm, roundi(bot.damage["gearbox"] * 100), drv._reverse_t, bot.is_wrecked])
		print("t=%4.1f gracz %3.0f km/h (ogr. %3.0f, przepisowo: %s)  bot %3.0f km/h, odległość %4.0f m, szał %.2f" % [
			t, kmh, main.current_limit, main.player_compliant(), bot.speed * 3.6, gap, drv.rage])
	return t > 60.0 or (hit_t > 0.0 and drv.rage <= 0.0 and t - hit_t > 18.0)
