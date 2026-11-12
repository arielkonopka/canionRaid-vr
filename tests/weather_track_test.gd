extends SceneTree
## Pogoda w generatorze autostrady (zlecenie warstwa-pogody, krok 2):
## nawierzchnia każdego odcinka = WeatherPlan.surface na jego początku,
## a granice mokrych stref wypadają na granicach odcinków.
##   godot --headless --xr-mode off -s res://tests/weather_track_test.gd -- [ziarno=777] </dev/null

var fails := 0


func _fail(m: String) -> void:
	print("  BŁĄD: ", m)
	fails += 1


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var sv := int(a[0]) if a.size() > 0 else 777
	var plan := HighwayPlan.new(sv)
	var gen := HighwayGenerator.new(plan, sv)
	var wp := WeatherPlan.new(sv, plan)
	gen.weather = wp
	var state := HighwayGenerator.first_state()
	var wet_m := 0.0
	var total := 0.0
	var mism := 0
	while float(state["dist"]) < 150000.0:
		var segs := gen.next_chunk(state)
		for s in segs:
			var d0: float = state["dist"]
			var want := wp.surface(d0 + 0.25)
			# Wielka skocznia (TrackGenerator._big_jump: rozbieg, rampa, stół)
			# zostaje sucha - rampa ma własną nawierzchnię "kicker".
			var in_jump := false
			for j in plan.jumps_between(d0 - 400.0, d0 + 1.0):
				if d0 >= float(j["start"]) - 0.5 and d0 < float(j["start"]) + 400.0:
					in_jump = true
			if in_jump:
				var smp0 := StuntTrack.sample_segments([s], state, HighwayGenerator.STEP)
				var e0: Dictionary = smp0[-1]["end_state"]
				for k in e0:
					state[k] = e0[k]
				total += float(s["len"])
				continue
			if s["surface"] != want:
				mism += 1
				if mism < 5:
					_fail("odcinek na %.0f m: %s, a pogoda %s" % [d0, s["surface"], want])
			# Wewnątrz odcinka nie ma zmiany nawierzchni (z marginesem).
			for ch in wp.surface_changes(d0 + 1.0, d0 + float(s["len"]) - 1.0):
				_fail("zmiana nawierzchni w środku odcinka %.0f-%.0f m (na %.0f)" % [d0, d0 + float(s["len"]), float(ch["d"])])
			if s["surface"] == "wet":
				wet_m += float(s["len"])
			total += float(s["len"])
			var smp := StuntTrack.sample_segments([s], state, HighwayGenerator.STEP)
			var e: Dictionary = smp[-1]["end_state"]
			for k in e:
				state[k] = e[k]
	print("mokra jezdnia: %.1f%% trasy (%.0f km z %.0f)" % [wet_m / total * 100.0, wet_m / 1000.0, total / 1000.0])
	if wet_m <= 0.0:
		_fail("ani metra mokrej jezdni na 150 km")
	print("weather_track_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
