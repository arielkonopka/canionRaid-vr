extends SceneTree
## Test TrackPath (plan wydajności C3/C4): na prawdziwych kawałkach trasy
## bez końca (wąwóz i tor na filarach, z przerwami) porównuje zapytania
## TrackPath z dzisiejszymi zapytaniami StuntTrack, a profil prędkości
## z pętlą BotDriver (_calm_speed / _curve_speed) przepisaną tu 1:1.
## Na końcu czas: ta sama liczba zapytań starym i nowym sposobem.
##   godot --headless --xr-mode off -s res://tests/track_path_test.gd -- [ziarno] </dev/null
## Wynik: "TRACK_PATH: OK" albo "TRACK_PATH: BŁĘDY n" (kod wyjścia 1).

var f := 0
var tracks: Array[EndlessTrack] = []
var errors := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 12345
	for canyon in [true, false]:
		var et := EndlessTrack.new()
		et.seed_value = seed_v
		et.canyon = canyon
		root.add_child(et)
		tracks.append(et)


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	for et in tracks:
		# Kilka sekcji dalej - różne typy dróg (autostrada co 5 odcinków).
		for i in range(6):
			et.update_progress(et._chunks[et._current].total_length() + 1.0)
		for c in et._chunks:
			_check_chunk(c, "wąwóz" if et.canyon else "filary")
	print("TRACK_PATH: OK" if errors == 0 else "TRACK_PATH: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)
	return true


func _fail(what: String) -> void:
	errors += 1
	if errors <= 20:
		print("  BŁĄD: ", what)


func _check_chunk(c: StuntTrack, kind: String) -> void:
	var samples: Array = c._samples
	if samples.size() < 20:
		return
	var tp := TrackPath.from_samples(samples)
	var r := c.dist_range()
	var inv := c.global_transform.affine_inverse()
	var n_gaps := tp.gaps.size() / 2
	print("%s %s: %d próbek, %.0f-%.0f m, przerw %d, metadanych %d" % [
			kind, c.name, tp.size(), r.x, r.y, n_gaps, tp.meta.size()])

	# --- zapytania po dystansie ---
	var d := r.x - 3.0
	while d < r.y + 3.0:
		if tp.is_gap_at(d) != c.is_gap_at(d):
			_fail("%s is_gap_at(%.2f)" % [c.name, d])
		var a := tp.last_gap_end_before(d)
		var b := c.last_gap_end_before(d)
		if not (a == b or is_equal_approx(a, b)):
			_fail("%s last_gap_end_before(%.2f): %f vs %f" % [c.name, d, a, b])
		var xa := tp.transform_at_distance(d)
		var xb := inv * c.transform_at_distance(d)
		if not xa.is_equal_approx(xb):
			_fail("%s transform_at_distance(%.2f)" % [c.name, d])
		if d >= r.x and d <= r.y:
			var i := tp.index_from(d)
			if not is_equal_approx(tp.dist[i], float(c._sample_near(d)["dist"])):
				_fail("%s index_from(%.2f)" % [c.name, d])
		d += 0.37

	# --- najbliższa próbka: z podpowiedzią i bez ---
	var hint := 0
	for k in range(0, tp.size(), 7):
		var p: Vector3 = tp.pos[k] + tp.right[k] * 2.3 + tp.up[k] * 0.5
		var s := c.nearest_sample(c.to_global(p))
		var i1 := tp.nearest_index(p, hint)
		var i2 := tp.track_index(p, maxi(k - 3, 0))
		hint = i1
		if not is_equal_approx(tp.dist[i1], float(s["dist"])):
			_fail("%s nearest_index przy %d: %.1f vs %.1f" % [c.name, k, tp.dist[i1], float(s["dist"])])
		if not is_equal_approx(tp.dist[i2], float(s["dist"])):
			_fail("%s track_index przy %d: %.1f vs %.1f" % [c.name, k, tp.dist[i2], float(s["dist"])])

	# --- profil prędkości vs pętla BotDriver ---
	var calm := tp.speed_profile(0.6, 5.0, true, 200.0 / 3.6)
	var rage := tp.speed_profile(0.8, 6.0, false, 400.0 / 3.6)
	var max_fast := 0.0          # o ile profil szybszy od pętli [km/h]
	var max_slow := 0.0          # o ile wolniejszy
	var n_q := 0
	var t_old := 0
	var t_new := 0
	d = r.x + 20.0
	while d < r.y - 200.0:
		var t0 := Time.get_ticks_usec()
		var window: Array = c.samples_from(d - 15.0, 195.0)
		var ref_calm := _ref_calm(window, d)
		var ref_curve := _ref_curve(window, d)
		t_old += Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		var p_calm := tp.speed_at(calm, d, 5.0) * 3.6
		var p_curve := tp.speed_at(rage, d, 6.0) * 3.6
		t_new += Time.get_ticks_usec() - t0
		for pair in [[p_calm, ref_calm], [p_curve, ref_curve]]:
			max_fast = maxf(max_fast, pair[0] - pair[1])
			max_slow = maxf(max_slow, pair[1] - pair[0])
		n_q += 1
		d += 1.3
	if n_q > 0:
		print("   profil: %d zapytań, najwyżej szybszy o %.1f km/h, wolniejszy o %.1f km/h; czas pętla %.0f us, profil %.0f us" % [
				n_q, max_fast, max_slow, t_old, t_new])
		# Szybszy może być tylko przez próbki tuż za botem (pętla bierze
		# do 2 m wstecz) - kilka km/h na wyjściu z łuku. Więcej = błąd.
		if max_fast > 8.0:
			_fail("%s profil szybszy od pętli BotDriver o %.1f km/h" % [c.name, max_fast])


# Przepisane 1:1 z BotDriver._calm_speed (stan na main @ dfeaa34).
func _ref_calm(window: Array, dist: float) -> float:
	var target := 200.0
	for i in range(0, window.size() - 12, 4):
		var a0: Dictionary = window[i]
		var k := float(a0["dist"]) - dist
		if k < -2.0:
			continue
		var lim := float(a0["limit"]) / 3.6
		target = minf(target, sqrt(lim * lim + 2.0 * 5.0 * maxf(k, 0.0)) * 3.6)
		var a1: Dictionary = window[i + 12]
		var f0: Vector3 = (a0["fwd"] as Vector3) * Vector3(1, 0, 1)
		var f1: Vector3 = (a1["fwd"] as Vector3) * Vector3(1, 0, 1)
		var ang := f0.angle_to(f1)
		if ang > 0.01:
			var span := float(a1["dist"]) - float(a0["dist"])
			var grip: float = StuntTrack.SURFACES[a0["surface"]]["grip"]
			var vc := sqrt(0.6 * grip * 9.8 * span / ang)
			target = minf(target, sqrt(vc * vc + 2.0 * 5.0 * maxf(k, 0.0)) * 3.6)
	return target


# Przepisane 1:1 z BotDriver._curve_speed.
func _ref_curve(window: Array, dist: float) -> float:
	var target := 400.0
	for i in range(0, window.size() - 12, 4):
		var a0: Dictionary = window[i]
		var k := float(a0["dist"]) - dist
		if k < -2.0:
			continue
		var a1: Dictionary = window[i + 12]
		var f0: Vector3 = (a0["fwd"] as Vector3) * Vector3(1, 0, 1)
		var f1: Vector3 = (a1["fwd"] as Vector3) * Vector3(1, 0, 1)
		var ang := f0.angle_to(f1)
		if ang > 0.01:
			var span := float(a1["dist"]) - float(a0["dist"])
			var grip: float = StuntTrack.SURFACES[a0["surface"]]["grip"]
			var vc := sqrt(0.8 * grip * 9.8 * span / ang)
			target = minf(target, sqrt(vc * vc + 2.0 * 6.0 * maxf(k, 0.0)) * 3.6)
	return target
