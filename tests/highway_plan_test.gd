extends SceneTree
## Test planu trybu Autostrada (HighwayPlan) i decyzji ruchu (TrafficZone):
## biomy co 50 ± 10 km, miasta co 25 / 100 km, ograniczenia, objazdy,
## słupki, gęstość ruchu i znikanie aut tylko poza wzrokiem. Bez sceny,
## sekundy.
##   godot --headless --xr-mode off -s res://tests/highway_plan_test.gd -- [ziarno] </dev/null
## Wynik: "HIGHWAY_PLAN: OK" albo "HIGHWAY_PLAN: BŁĘDY n" (kod wyjścia 1).

var errors := 0


func _fail(what: String) -> void:
	errors += 1
	if errors <= 30:
		print("  BŁĄD: ", what)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 777
	var plan := HighwayPlan.new(seed_v)
	_biomes(plan, seed_v)
	_cities(plan)
	_limits(plan)
	_jumps(plan)
	_posts(plan)
	_traffic(plan, seed_v)
	print("HIGHWAY_PLAN: OK" if errors == 0 else "HIGHWAY_PLAN: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)


func _biomes(plan: HighwayPlan, seed_v: int) -> void:
	if plan.biome_at(0.0) != HighwayPlan.FIRST_BIOME:
		_fail("pierwszy biom %s" % plan.biome_at(0.0))
	# Pytania w losowej kolejności (leniwe liczenie nie może zależeć od kolejności).
	var other := HighwayPlan.new(seed_v)
	for d in [450000.0, 10.0, 230000.0, 99999.0]:
		other.biome_at(d)
	var line := PackedStringArray()
	for k in range(12):
		var r := plan.biome_range(k)
		var len_km := (r.y - r.x) / 1000.0
		line.append("%s %.0f" % [plan.biome_at(r.x + 1.0), len_km])
		if len_km < 39.999 or len_km > 60.001:
			_fail("biom %d ma %.1f km" % [k, len_km])
		if k > 0 and plan.biome_at(r.x + 1.0) == plan.biome_at(r.x - 1.0):
			_fail("biom %d taki sam jak poprzedni" % k)
		if other.biome_at(r.x + 1.0) != plan.biome_at(r.x + 1.0):
			_fail("biom %d zależy od kolejności pytań" % k)
		var bl := plan.biome_blend(r.x)
		if k > 0 and absf(float(bl["t"]) - 0.5) > 0.01:
			_fail("mieszanie na granicy %d: t %.2f" % [k, bl["t"]])
	print("biomy [km]: ", ", ".join(line))
	var diff := HighwayPlan.new(seed_v + 1)
	var same := true
	for k in range(12):
		if diff.biome_range(k) != plan.biome_range(k):
			same = false
	if same:
		_fail("inne ziarno daje te same biomy")


func _cities(plan: HighwayPlan) -> void:
	for n in range(1, 13):
		var c := plan.city(n)
		var big := n % 4 == 0
		if c["big"] != big:
			_fail("miasto %d: big %s" % [n, c["big"]])
		var want_len := HighwayPlan.BIG_CITY_LEN if big else HighwayPlan.SMALL_CITY_LEN
		if not is_equal_approx(float(c["end"]) - float(c["start"]), want_len):
			_fail("miasto %d: długość %.0f" % [n, float(c["end"]) - float(c["start"])])
		if not is_equal_approx(float(c["start"]), n * 25000.0):
			_fail("miasto %d: start %.0f" % [n, c["start"]])
		if plan.city_at(float(c["start"]) + 1.0).get("index", -1) != n:
			_fail("city_at w mieście %d" % n)
		if not plan.city_at(float(c["start"]) - 1.0).is_empty() or not plan.city_at(float(c["end"]) + 1.0).is_empty():
			_fail("city_at poza miastem %d" % n)
		var dens: float = c["density"]
		if dens < 3.0 or dens > 5.0:
			_fail("miasto %d: gęstość %.2f" % [n, dens])
	if not plan.city_at(12000.0).is_empty():
		_fail("miasto przed 25. km")


func _limits(plan: HighwayPlan) -> void:
	var c := plan.city(2)
	var s: float = c["start"]
	var cases := [[s - 1000.0, 140.0], [s - 500.0, 70.0], [s - 100.0, 50.0], [s + 10.0, 30.0],
			[float(c["end"]) - 1.0, 30.0], [float(c["end"]) + 1.0, 140.0]]
	for cs in cases:
		var got := plan.limit_at(cs[0])
		if not is_equal_approx(got, cs[1]):
			_fail("limit na %.0f: %.0f zamiast %.0f" % [cs[0], got, cs[1]])
	# limit_changes zgodne z limit_at na całej długości 0-300 km.
	var changes := plan.limit_changes(0.0, 300000.0)
	var cur := HighwayPlan.LIMIT_HIGHWAY
	var ci := 0
	var d := 5.0
	while d < 300000.0:
		while ci < changes.size() and float(changes[ci][0]) <= d:
			cur = changes[ci][1]
			ci += 1
		if not is_equal_approx(plan.limit_at(d), cur):
			_fail("limit_changes a limit_at na %.0f m: %.0f / %.0f" % [d, cur, plan.limit_at(d)])
			break
		d += 10.0
	print("zmian ograniczenia na 300 km: %d" % changes.size())


func _jumps(plan: HighwayPlan) -> void:
	var js := plan.jumps_between(0.0, 1000000.0)
	for j in js:
		if float(j["start"]) < HighwayPlan.JUMP_FIRST:
			_fail("objazd przed %.0f m" % HighwayPlan.JUMP_FIRST)
		if not plan.cities_between(float(j["start"]) - 2000.0, float(j["end"]) + 2000.0).is_empty():
			_fail("objazd przy mieście: %.0f" % j["start"])
	print("objazdów ze skocznią na 1000 km: %d (oczekiwane ~20-35)" % js.size())
	if js.size() < 10 or js.size() > 50:
		_fail("liczba objazdów %d" % js.size())


func _posts(plan: HighwayPlan) -> void:
	var p := plan.posts_between(0.0, 10000.0)
	var majors := 0
	for x in p:
		if x["major"]:
			majors += 1
	if p.size() != 99 or majors != 9:
		_fail("słupki 0-10 km: %d, kilometrowych %d" % [p.size(), majors])
	var q := plan.posts_between(123450.0, 124050.0)
	if q.is_empty() or not is_equal_approx(float(q[0]["dist"]), 123500.0) or int(q[0]["km"]) != 123 or int(q[0]["hm"]) != 5:
		_fail("słupek po 123,45 km: %s" % [q])


## Symulacja: gracz jedzie 0-60 km ze stałą prędkością, auta ruchu jadą
## swoją prędkością, widoczne są te 0-500 m przed graczem. Sprawdza:
## gęstość w strefie miasta, brak ruchu daleko od miast, brak usuwania
## aut widocznych i w furii.
func _traffic(plan: HighwayPlan, seed_v: int) -> void:
	var tz := TrafficZone.new(plan)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cars := []
	var next_id := 0
	var v_player := 30.0
	var dt := 0.5
	var t := 0.0
	var in_zone_short := 0
	var in_zone_checks := 0
	var far_cars := 0          # najwięcej aut w oknie między miastami
	var far_sum := 0
	var far_checks := 0
	var raging_id := -1
	while t * v_player < 60000.0:
		var pd := t * v_player
		for c in cars:
			c["dist"] += float(c["speed"]) * dt * (-1.0 if c["oncoming"] else 1.0)
			c["visible"] = float(c["dist"]) > pd and float(c["dist"]) < pd + 500.0
		# Jedno auto wpada w furię w strefie pierwszego miasta.
		if raging_id < 0 and pd > 23000.0 and not cars.is_empty():
			raging_id = cars[0]["id"]
			cars[0]["raging"] = true
		var r := tz.step(pd, cars, rng)
		for id in r["despawn"]:
			for c in cars:
				if c["id"] == id:
					if c["visible"]:
						_fail("usunięte widoczne auto %d" % id)
					if c["raging"]:
						_fail("usunięte auto w furii %d" % id)
			cars = cars.filter(func(c): return c["id"] != id)
		for s in r["spawn"]:
			if float(s["dist"]) < pd + TrafficZone.SPAWN_MIN_AHEAD - 0.01:
				_fail("auto dodane za blisko: %.0f m" % (float(s["dist"]) - pd))
			cars.append({"id": next_id, "dist": s["dist"], "lane": s["lane"], "oncoming": s["oncoming"],
					"raging": false, "visible": false, "speed": float(s["speed_kmh"]) / 3.6})
			next_id += 1
		# Gęstość: w środku strefy (21-30 km) po rozruchu.
		if pd > 21500.0 and pd < 29500.0:
			in_zone_checks += 1
			var n := 0
			for c in cars:
				if not c["oncoming"] and float(c["dist"]) > pd - 300.0 and float(c["dist"]) < pd + 1500.0:
					n += 1
			if n < tz.wanted(pd) - 3:
				in_zone_short += 1
		if pd > 37000.0 and pd < 42000.0:      # strefa miasta 1 do 31 km, miasta 2 od 45 km
			var n_far := 0
			for c in cars:
				if not c["raging"] and not c["oncoming"] and float(c["dist"]) > pd - 300.0 and float(c["dist"]) < pd + 1500.0:
					n_far += 1
			far_cars = maxi(far_cars, n_far)
			far_sum += n_far
			far_checks += 1
		t += dt
	var far_avg := float(far_sum) / maxf(far_checks, 1)
	print("ruch: aut łącznie %d, w strefie za mało w %d/%d krokach, między miastami średnio %.1f (najwięcej %d, chciane %d)" % [
			next_id, in_zone_short, in_zone_checks, far_avg, far_cars, tz.wanted(40000.0)])
	if in_zone_checks == 0 or in_zone_short > in_zone_checks / 5:
		_fail("za mało aut w strefie miasta")
	# Między miastami rzadki ruch 0,5-1/km (nie pusto i nie jak w mieście).
	if far_avg < 0.3 or far_cars > tz.wanted(40000.0) + TrafficZone.SURPLUS + 2:
		_fail("ruch między miastami: średnio %.1f, najwięcej %d" % [far_avg, far_cars])
	# Gęstości z planu.
	if not is_equal_approx(plan.base_traffic(0.0), HighwayPlan.BASE_TRAFFIC_MIN) \
			or not is_equal_approx(plan.base_traffic(400000.0), HighwayPlan.BASE_TRAFFIC_MAX):
		_fail("base_traffic: %.2f / %.2f" % [plan.base_traffic(0.0), plan.base_traffic(400000.0)])
	if plan.traffic_density(12500.0) > 1.0 or plan.traffic_density(22000.0) < 3.0:
		_fail("gęstość 12,5 km %.2f, 22 km %.2f" % [plan.traffic_density(12500.0), plan.traffic_density(22000.0)])
	# Pasy autostrady: prawy/lewy na naszej jezdni i lustrzanie na drugiej,
	# żaden na pasie awaryjnym.
	var lanes := [HighwayGenerator.lane_center(0), HighwayGenerator.lane_center(1),
			HighwayGenerator.lane_center(0, true), HighwayGenerator.lane_center(1, true)]
	var want_l := [0.75, -3.0, -15.0, -11.25]
	for i in range(4):
		if absf(float(lanes[i]) - float(want_l[i])) > 1e-4:
			_fail("lane_center %d: %.2f zamiast %.2f" % [i, lanes[i], want_l[i]])
