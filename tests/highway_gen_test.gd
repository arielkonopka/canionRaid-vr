extends SceneTree
## Test generatora jezdni trybu Autostrada (HighwayGenerator) "na płasko":
## generuje N km kawałków tak, jak zrobi to trasa (każdy kawałek we własnym
## układzie, węzeł w miejscu końca poprzedniego) i sprawdza:
##   - płasko (pitch 0, stała wysokość), stała szerokość 2+2 pasy,
##   - kurs w granicach MAX_YAW, promienie łuków,
##   - ciągłość dystansu i kursu między kawałkami,
##   - współrzędne lokalne kawałków małe (precyzja float32),
##   - ograniczenia z planu dokładnie na granicach odcinków, meta miast
##     i objazdów,
##   - zabudowa miast (HighwayScenery) nie stoi na jezdni ani chodniku,
## a na końcu wypisuje błąd, jaki dałyby współrzędne bez przesuwania
## początku świata (float32 vs float64), i czasy budowy.
##   godot --headless --xr-mode off -s res://tests/highway_gen_test.gd -- [ziarno] [km] </dev/null
## Wynik: "HIGHWAY_GEN: OK" albo "HIGHWAY_GEN: BŁĘDY n" (kod wyjścia 1).

var errors := 0


func _fail(what: String) -> void:
	errors += 1
	if errors <= 30:
		print("  BŁĄD: ", what)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 4242
	var km := float(args[1]) if args.size() > 1 else 300.0
	var plan := HighwayPlan.new(seed_v)
	var gen := HighwayGenerator.new(plan, seed_v)
	var state := HighwayGenerator.first_state()
	# Położenie węzła kawałka: float64 (dwie liczby) i float32 (Vector3, jak
	# dziś bez przesuwania początku świata).
	var ox := 0.0
	var oz := 0.0
	var o32 := Vector3.ZERO
	var max_local := 0.0
	var max_err32 := 0.0
	var prev_end := {}
	var t_gen := 0
	var t_scn := 0
	var n_chunks := 0
	var cities_seen := {}
	var detours := 0
	var detours_meta := 0
	var buildings := 0
	var scenery_chunks := 0
	var max_curve_open := 0.0
	var edges := HighwayScenery.edges_for(HighwayGenerator.WIDTH)
	var marks := {}
	for m in plan.limit_changes(0.0, km * 1000.0):
		marks[snappedf(float(m[0]), 0.01)] = true
	while float(state["dist"]) < km * 1000.0:
		var t0 := Time.get_ticks_usec()
		var segs := gen.next_chunk(state)
		t_gen += Time.get_ticks_usec() - t0
		n_chunks += 1
		var smp := StuntTrack.sample_segments(segs, state, HighwayGenerator.STEP)
		# --- ciągłość ---
		if not prev_end.is_empty():
			if absf(float(smp[0]["dist"]) - float(prev_end["dist"])) > 1e-6:
				_fail("kawałek %d: skok dystansu" % n_chunks)
			if absf(float(smp[0]["yaw"]) - float(prev_end["yaw"])) > 1e-9:
				_fail("kawałek %d: skok kursu" % n_chunks)
		if (smp[0]["pos"] as Vector3).distance_to(Vector3(0, HighwayGenerator.ROAD_Y, 0)) > 1e-6:
			_fail("kawałek %d nie zaczyna się w (0, y, 0)" % n_chunks)
		# --- próbki ---
		for s in smp:
			var p: Vector3 = s["pos"]
			max_local = maxf(max_local, maxf(absf(p.x), absf(p.z)))
			if absf(float(s["pitch"])) > 1e-9 or absf(p.y - HighwayGenerator.ROAD_Y) > 1e-3:
				_fail("kawałek %d: nie płasko na %.0f m (y %.3f)" % [n_chunks, s["dist"], p.y])
				break
			if absf(float(s["width"]) - HighwayGenerator.WIDTH) > 1e-6:
				_fail("szerokość %.2f na %.0f m" % [s["width"], s["dist"]])
				break
			if absf(float(s["yaw"])) > HighwayGenerator.MAX_YAW + 1e-6:
				_fail("kurs %.1f° na %.0f m" % [rad_to_deg(s["yaw"]), s["dist"]])
				break
			var d: float = s["dist"]
			var near_mark := marks.has(snappedf(d, 0.01)) or marks.has(snappedf(d - 0.01, 0.01)) \
					or marks.has(snappedf(d + 0.01, 0.01))
			if not near_mark and not is_equal_approx(float(s["limit"]), plan.limit_at(d + 0.01)):
				_fail("ograniczenie %.0f zamiast %.0f na %.2f m" % [s["limit"], plan.limit_at(d + 0.01), d])
				break
		# --- odcinki ---
		var dd: float = state["dist"]
		for seg in segs:
			var k := absf(float(seg.get("curve", 0.0)))
			var in_city := not plan.city_at(dd + 1.0).is_empty()
			var kmax := rad_to_deg(1.0 / (HighwayGenerator.R_MIN_CITY if in_city else HighwayGenerator.R_MIN))
			if k > kmax + 1e-9:
				_fail("łuk za ciasny na %.0f m: R %.0f" % [dd, 1.0 / deg_to_rad(k)])
			if not in_city:
				max_curve_open = maxf(max_curve_open, k)
			var meta: Dictionary = seg.get("meta", {})
			if meta.has("city_start"):
				cities_seen[int(meta["city_start"]["index"])] = true
				if absf(float(meta["city_start"]["start"]) - dd) > 0.01:
					_fail("meta city_start w złym miejscu: %.2f / %.2f" % [dd, meta["city_start"]["start"]])
			if meta.has("detour"):
				detours_meta += 1
				if absf(float(meta["detour"]["start"]) - dd) > 0.01 or absf(float(seg["curve"])) > 0.0:
					_fail("objazd: start %.2f / %.2f, łuk %s" % [dd, meta["detour"]["start"], seg["curve"]])
			dd += float(seg["len"])
		# --- zabudowa (pierwsze kawałki z miastem i kilka zwykłych) ---
		var d0 := float(smp[0]["dist"])
		var d1 := float(smp[-1]["dist"])
		var has_city := not plan.cities_between(d0, d1).is_empty()
		if (has_city and scenery_chunks < 10) or n_chunks % 50 == 1:
			scenery_chunks += 1
			var rng := RandomNumberGenerator.new()
			rng.seed = n_chunks
			var t1 := Time.get_ticks_usec()
			var nodes := HighwayScenery.build(smp, plan, rng, edges)
			t_scn += Time.get_ticks_usec() - t1
			for n in nodes:
				if n is MultiMeshInstance3D and n.name == "Hwy_building":
					buildings += _check_buildings(n.multimesh, smp, edges)
				n.free()
		# --- położenie następnego kawałka ---
		var e: Dictionary = smp[-1]["end_state"]
		var ep: Vector3 = e["pos"]
		ox += ep.x
		oz += ep.z
		o32 += Vector3(ep.x, 0.0, ep.z)
		max_err32 = maxf(max_err32, Vector2(o32.x - ox, o32.z - oz).length())
		prev_end = e
		var loc := HighwayGenerator.localize({"pos": ep, "yaw": e["yaw"], "pitch": e["pitch"], "bank": e["bank"],
				"width": e["width"], "dist": e["dist"], "limit": e["limit"]})
		state = loc["state"]
	for j in plan.jumps_between(0.0, float(state["dist"])):
		if float(j["start"]) > 1.0:
			detours += 1
	var n_cities := plan.cities_between(0.0, float(state["dist"])).size()
	print("kawałków %d (średnio %.0f m), %.1f km, koniec w (%.1f, %.1f) km" % [
			n_chunks, float(state["dist"]) / n_chunks, float(state["dist"]) / 1000.0, ox / 1000.0, oz / 1000.0])
	print("największa współrzędna lokalna %.0f m; float32 bez przesuwania: błąd położenia %.1f mm" % [
			max_local, max_err32 * 1000.0])
	print("najciaśniejszy łuk poza miastem R %.0f m" % (1.0 / deg_to_rad(maxf(max_curve_open, 1e-9))))
	print("miast %d (z meta %d), objazdów %d (z meta %d), budynków sprawdzonych %d w %d kawałkach" % [
			n_cities, cities_seen.size(), detours, detours_meta, buildings, scenery_chunks])
	print("czas: generator %.2f ms/kawałek, zabudowa+obiekty %.1f ms/kawałek (PC; Quest ~4-6x)" % [
			t_gen / 1000.0 / n_chunks, t_scn / 1000.0 / maxi(scenery_chunks, 1)])
	if max_local > 2500.0:
		_fail("współrzędne lokalne kawałka do %.0f m" % max_local)
	if cities_seen.size() != n_cities:
		_fail("meta city_start: %d z %d miast" % [cities_seen.size(), n_cities])
	if detours_meta != detours:
		_fail("meta detour: %d z %d objazdów" % [detours_meta, detours])
	if n_cities > 0 and buildings == 0:
		_fail("brak budynków w miastach")
	print("HIGHWAY_GEN: OK" if errors == 0 else "HIGHWAY_GEN: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)


## Żaden budynek nie wchodzi na jezdnię ani chodnik: środek budynku
## w układzie najbliższej próbki, minus pół głębokości, dalej niż krawędź
## asfaltu + chodnik. Zwraca liczbę budynków.
func _check_buildings(mm: MultiMesh, smp: Array, edges: Vector2) -> int:
	for i in range(mm.instance_count):
		var xf := mm.get_instance_transform(i)
		var c := xf.origin
		var half_depth := xf.basis.z.length() * 0.5
		var best := INF
		var lat := 0.0
		for s in smp:
			var p: Vector3 = s["pos"]
			var dsq := Vector2(p.x - c.x, p.z - c.z).length_squared()
			if dsq < best:
				best = dsq
				var r: Vector3 = ((s["right"] as Vector3) * Vector3(1, 0, 1)).normalized()
				lat = (c - Vector3(p.x, c.y, p.z)).dot(r)
		var inner := lat - half_depth if lat > 0.0 else -lat - half_depth
		var edge := edges.y if lat > 0.0 else -edges.x
		if inner < edge + HighwayScenery.SIDEWALK - 0.05:
			_fail("budynek %d na jezdni/chodniku: %.1f m od osi (krawędź %.1f)" % [i, inner, edge])
			break
	return mm.instance_count
