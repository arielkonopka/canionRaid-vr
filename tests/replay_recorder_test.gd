extends SceneTree
## ReplayRecorder bez sceny: bufor kołowy (zawinięcie, stały rozmiar),
## interpolacja, przesunięcie świata, kluczowa chwila, mapa tempa, inne auta.
##   godot --headless --xr-mode off -s res://tests/replay_recorder_test.gd </dev/null

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _frame(x: float, hit := 0.0, ground := 4.0) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(ReplayRecorder.P_STRIDE)
	f[0] = x
	var q := Quaternion(Vector3.UP, x * 0.01)
	f[3] = q.x
	f[4] = q.y
	f[5] = q.z
	f[6] = q.w
	f[ReplayRecorder.I_CTRL_L + 6] = 1.0
	f[ReplayRecorder.I_CTRL_R + 6] = 1.0
	f[ReplayRecorder.I_HIT] = hit
	f[ReplayRecorder.I_GROUND] = ground
	return f


func _initialize() -> void:
	var r := ReplayRecorder.new()
	var size0: int = r._p.size()
	# 20 s jazdy co krok fizyki 120 Hz: x = t * 10.
	var t := 0.0
	while t < 20.0:
		var hit := 9000.0 if absf(t - 17.0) < 0.004 else 0.0
		r.push(t, _frame(t * 10.0, hit))
		t += 1.0 / 120.0
	_check(r._p.size() == size0, "stały rozmiar bufora (bez alokacji)")
	_check(r.count() == r._pcap, "bufor pełny po zawinięciu (%d)" % r.count())
	_check(absf(r.t_end() - r.t_start() - ReplayRecorder.WINDOW) < 0.1,
			"okno ~6 s (%.2f - %.2f)" % [r.t_start(), r.t_end()])
	var mid := r.player_at(16.0 + 1.0 / 240.0)
	_check(absf(mid[0] - 160.04) < 0.05, "interpolacja pozycji (%.3f)" % mid[0])
	_check(absf(r.key_time() - 17.0) < 0.02, "kluczowa chwila = uderzenie (%.3f)" % r.key_time())
	r.shift(Vector3(100.0, 0.0, 0.0))
	_check(absf(r.player_at(16.0)[0] - 60.0) < 0.05, "przesunięcie świata")
	# Bez uderzenia: oderwanie kół.
	var r2 := ReplayRecorder.new()
	t = 0.0
	while t < 5.0:
		r2.push(t, _frame(t, 0.0, 0.0 if t > 3.2 else 4.0))
		t += 1.0 / 60.0
	_check(absf(r2.key_time() - 3.2) < 0.05, "kluczowa chwila = oderwanie kół (%.3f)" % r2.key_time())
	# Mapa tempa: ciągła, monotoniczna, zwolnienie wokół klucza.
	var key := 3.0
	var rt := 0.0
	var prev := -1.0
	var mono := true
	var play := 0.0
	var min_s := 1.0
	while rt < 6.0:
		var s := ReplayRecorder.speed_at(rt, key)
		min_s = minf(min_s, s)
		rt = ReplayRecorder.advance(rt, 1.0 / 72.0, key)
		if rt <= prev:
			mono = false
		prev = rt
		play += 1.0 / 72.0
	_check(mono, "tempo monotoniczne")
	_check(absf(min_s - ReplayRecorder.SLOW) < 1e-6, "zwolnienie do %.2f" % min_s)
	_check(play > 6.0 and play < 10.0, "powtórka 6 s okna trwa %.1f s" % play)
	# Inne auta.
	var r3 := ReplayRecorder.new()
	for i in range(10):
		var ids := PackedInt64Array([111, 222])
		var poses := PackedFloat32Array()
		for s in range(2):
			poses.append_array([float(i), 0.0, float(s), 0.0, 0.0, 0.0, 1.0, 0.1])
		r3.push_others(i / 30.0, ids, poses)
	var o := r3.others_at(4.5 / 30.0)
	_check(o.has(111) and o.has(222) and absf((o[111][0] as Transform3D).origin.x - 4.5) < 0.01, "inne auta - interpolacja")
	print("replay_recorder_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
