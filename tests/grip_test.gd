extends SceneTree
## Przyczepność na suchym (użytkownik 2026-11-09: "przyczepność w prawdziwych
## samochodach jest chyba lepsza, zwłaszcza na suchej"). Mierzy:
## - maksymalne przeciążenie boczne: stałe 80 km/h, skręt narasta powoli
##   (bez ograniczenia skrętu i ESP), a_lat = v * prędkość odchylenia,
##   średnia z 0,5 s;
## - hamowanie 100 -> 0 km/h z ABS (droga).
## Odniesienie (prawdziwe auta, suchy asfalt): opony całoroczne ~0,85-0,95 g
## w zakręcie, hamowanie 100-0 ~38-42 m; letnie sportowe ~1,0-1,1 g, ~34-36 m.
## Po poprawce 2026-11-09 (ABS z wyprzedzeniem, hamulce skalowane masą):
## całoroczne 0,93-0,94 g, 40,5 m; letnie 0,97-0,98 g, 38 m. Przed: 51-55 m.
##   godot --headless --xr-mode off -s res://tests/grip_test.gd </dev/null

const START := Vector3(-300.0, 0.75, 600.0)
const V_LAT := 80.0 / 3.6

var main
var car
var runs := []
var cur := -1
var phase := ""
var t := 0.0
var hist: Array[float] = []
var best_lat := 0.0
var brake_start := Vector3.ZERO
var braking := false
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	var ground: Node = main.get_node("Ground")
	ground.set_meta("grip", StuntTrack.SURFACES["dry"]["grip"])
	ground.set_meta("surface", "dry")
	for cfg in [["all_season", 1200.0, "rwd", 180], ["all_season", 1200.0, "fwd", 180], ["all_season", 2500.0, "awd", 700],
			["summer", 1200.0, "rwd", 180], ["summer", 2500.0, "awd", 700]]:
		runs.append(cfg + ["lat"])
		runs.append(cfg + ["brake"])


func _start(r: Array) -> void:
	car.tires = r[0]
	car.drive_layout = r[2]
	car.hub_motors = false
	car.apply_engine("petrol", r[3])
	car.set_body_mass(r[1])
	car.automatic = true
	car.abs_enabled = true
	car.tcs_enabled = true
	car.esp_enabled = false
	car.steer_assist = false
	car.repair()
	car.fuel = 1.0
	car.place(Transform3D(Basis(), START))
	car._settle_t = 0.0
	t = 0.0
	hist.clear()
	best_lat = 0.0
	braking = false


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	var done := cur < 0
	if cur >= 0:
		var r: Array = runs[cur]
		t += delta
		var v: float = car.speed
		if r[4] == "lat":
			# Rozpędzanie prosto, potem skręt narasta przez 10 s.
			var target := V_LAT
			car.throttle = clampf((target - v) * 0.8, 0.0, 1.0)
			car.brake = clampf((v - target) * 0.3, 0.0, 1.0)
			var ts := t - 8.0
			car.steer = clampf(ts / 10.0, 0.0, 1.0) if ts > 0.0 else 0.0
			if ts > 0.0:
				hist.append(absf(v * car.angular_velocity.y))
				if hist.size() > 60:
					hist.pop_front()
				var s := 0.0
				for x in hist:
					s += x
				if absf(v - target) < 2.0:
					best_lat = maxf(best_lat, s / hist.size())
			if t > 18.5:
				print("%-10s %4.0f kg %-3s: maks. przeciążenie boczne %.2f g" % [r[0], r[1], r[2], best_lat / 9.81])
				if best_lat / 9.81 < 0.85:
					fails += 1
					print("  BŁĄD: za mało przyczepności bocznej")
				done = true
		else:
			car.steer = 0.0
			if not braking:
				car.throttle = 1.0
				car.brake = 0.0
				if v * 3.6 >= 100.0:
					braking = true
					brake_start = car.global_position
			else:
				car.throttle = 0.0
				car.brake = 1.0
				if v < 0.3:
					print("%-10s %4.0f kg %-3s: hamowanie 100-0 km/h %.1f m" % [r[0], r[1], r[2],
							(car.global_position - brake_start).length()])
					if (car.global_position - brake_start).length() > 44.0:
						fails += 1
						print("  BŁĄD: za długa droga hamowania")
					done = true
			if t > 40.0:
				print("hamowanie: przekroczony czas")
				done = true
	if done:
		cur += 1
		if cur >= runs.size():
			print("grip_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
		_start(runs[cur])
	return false
