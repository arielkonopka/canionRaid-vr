extends SceneTree
## Odrodzenie po wybuchu: auto nie może wirować (zgłoszenie użytkownika).
## Wybuch na zwykłej prostej i na rozwidleniu (na osi drogi stoi wyspa).
## Mierzy największą prędkość obrotu i stan auta 1-4 s po odrodzeniu.
##   godot --headless --xr-mode off -s res://tests/respawn_test.gd </dev/null
var main
var car
var f := 0
var cases := []
var cur := -1
var t := 0.0
var max_w := 0.0


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
		var trk = main.track
		cases.append(["prosta", 30.0])
		cases.append(["na dachu (gra sama)", 120.0])
		cases.append(["rozbite po upadku z 15 m", 200.0])
		cases.append(["poza wąwozem na trawie", 260.0])
		var d := 10.0
		while cases.size() < 2 and d < 15000.0:
			trk.update_progress(d)
			for s in trk.samples_from(d, 400.0):
				if s["meta"].has("island"):
					cases.append(["rozwidlenie", float(s["dist"]) + 45.0 + 30.0])
					break
			d += 400.0
		main.race_state = main.Race.RACING
	if cur < 0 or t > main.CINE_TOTAL + 7.0:
		if cur >= 0:
			var lo: Dictionary = main.track.lateral_offset(car.global_position)
			print("%s: max obrót po odrodzeniu %.2f rad/s, koła %d, góra.y %.2f, stan gry %d, od osi %.1f m" % [
				cases[cur][0], max_w, car.wheels_on_ground, car.global_basis.y.y, main.race_state, lo.get("offset", 999.0)])
		cur += 1
		if cur >= cases.size():
			return true
		# Auto na osi drogi w danym miejscu, potem wybuch.
		var xf: Transform3D = main.track.transform_at_distance(cases[cur][1])
		car.freeze = false
		car.visible = true
		car.place(Transform3D(xf.basis, xf.origin + xf.basis.y * 0.9))
		main.race_state = main.Race.RACING
		main._grace_t = 0.0
		if cases[cur][0].begins_with("poza"):
			# 80 m w bok od jezdni, na ziemi (y = 0) - poza wąwozem.
			var p: Vector3 = xf.origin + xf.basis.x * 80.0
			car.place(Transform3D(Basis(), Vector3(p.x, 1.0, p.z)))
		elif cases[cur][0].begins_with("rozbite"):
			# Prawie rozbite auto spada z wysoka - uszkodzenia dobijają je do 100%.
			car.place(Transform3D(xf.basis, xf.origin + xf.basis.y * 15.0))
			car.damage["structure"] = 0.97
			for i in range(4):
				car.damage["suspension"][i] = 0.9
				car.damage["brakes"][i] = 0.9
			car.damage["engine"] = 0.9
		elif cases[cur][0].begins_with("na dachu"):
			# Auto do góry kołami na jezdni - utrata życia ma przyjść z gry.
			car.place(Transform3D(xf.basis.rotated(xf.basis.z, PI), xf.origin + xf.basis.y * 1.6))
		else:
			main.lose_life("test")
		t = 0.0
		max_w = 0.0
		return false
	t += delta
	main._watch_track(delta)
	main.update_race(delta)
	main._process(delta)
	car.throttle = 0.0
	car.brake = 0.0
	car.steer = 0.0
	if main.race_state == main.Race.EXPLODING and not has_meta("expl"):
		set_meta("expl", true)
		print("  wybuch t=%.1f" % t)
	if t > main.CINE_TOTAL + 1.0 and main.race_state == main.Race.RACING:
		max_w = maxf(max_w, car.angular_velocity.length())
	return false
