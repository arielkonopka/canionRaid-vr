extends SceneTree
## TrafficAudio: Doppler, umowne obroty, wybór najbliższych aut, wypalone
## próbki (pętla, czas), przejazd auta obok słuchacza (ton wyżej przed,
## niżej po minięciu), przesunięcie świata bez skoku tonu.
##   godot --headless --xr-mode off -s res://tests/traffic_audio_test.gd </dev/null

var fails := 0
var ta: TrafficAudio
var car: StuntCar
var f := 0
var pitch_before := 0.0
var pitch_after := 0.0
var max_jump := 0.0
var prev_pitch := 0.0
var shifted := false
var pick_nodes: Array = []


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	var z := Vector3.ZERO
	var up := TrafficAudio.doppler_ratio(Vector3(0, 0, -50), Vector3(0, 0, 40), z, z)
	var down := TrafficAudio.doppler_ratio(Vector3(0, 0, 50), Vector3(0, 0, 40), z, z)
	var side := TrafficAudio.doppler_ratio(Vector3(30, 0, 0), Vector3(0, 0, 40), z, z)
	_check(up > 1.12 and up < 1.15, "zbliża się 40 m/s: %.3f (teoria 1.132)" % up)
	_check(down < 0.90 and down > 0.88, "oddala się 40 m/s: %.3f (teoria 0.896)" % down)
	_check(absf(side - 1.0) < 0.001, "bokiem: %.3f" % side)
	var same := TrafficAudio.doppler_ratio(Vector3(0, 0, -50), Vector3(0, 0, 30), z, Vector3(0, 0, 30))
	_check(absf(same - 1.0) < 0.001, "jadą razem: %.3f" % same)
	var r0 := TrafficAudio.fake_rpm(0.0)
	var ok_rpm := true
	for i in range(80):
		var r := TrafficAudio.fake_rpm(i * 1.0)
		if r < 800.0 or r > 4900.0:
			ok_rpm = false
	_check(ok_rpm and r0 < 900.0, "umowne obroty 800-4900")
	var t0 := Time.get_ticks_usec()
	var e := TrafficAudio.bake_engine()
	var n := TrafficAudio.bake_noise()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  wypalenie próbek: %.1f ms (PC)" % ms)
	_check(e.loop_mode == AudioStreamWAV.LOOP_FORWARD and e.data.size() == int(TrafficAudio.MIX_RATE * TrafficAudio.LOOP_S) * 2, "pętla silnika")
	_check(n.loop_mode == AudioStreamWAV.LOOP_FORWARD and n.data.size() == TrafficAudio.MIX_RATE * 2, "pętla szumu")
	var peak := 0
	for i in range(0, e.data.size(), 2):
		peak = maxi(peak, absi(e.data.decode_s16(i)))
	_check(peak > 8000 and peak < 32000, "głośność silnika (szczyt %d)" % peak)
	# Szew pętli silnika: ostatnia i pierwsza próbka blisko siebie.
	var seam := absi(e.data.decode_s16(0) - e.data.decode_s16(e.data.size() - 2))
	_check(seam < 3000, "szew pętli silnika (%d)" % seam)
	# Wybór najbliższych - w pierwszej klatce (węzły muszą być w drzewie).
	for d in [100.0, 10.0, 50.0, 30.0, 70.0, 20.0]:
		var nd := Node3D.new()
		nd.position = Vector3(d, 0, 0)
		root.add_child(nd)
		pick_nodes.append(nd)
	# Przejazd: auto 35 m/s wzdłuż -Z, słuchacz w zerze, 3 m obok.
	ta = TrafficAudio.new()
	root.add_child(ta)
	car = StuntCar.new()
	car.is_bot = true
	root.add_child(car)
	car.freeze = true
	car.position = Vector3(3, 0, 60)


func _process(delta: float) -> bool:
	if ta == null:
		return false
	f += 1
	if f == 1:
		var pk := TrafficAudio.pick_nearest(pick_nodes, Vector3.ZERO, 4, 80.0)
		var dists: Array = []
		for p in pk:
			dists.append(int((p as Node3D).global_position.x))
		_check(dists == [10, 20, 30, 50], "najbliższe 4 w 80 m: %s" % str(dists))
		for nd in pick_nodes:
			nd.queue_free()
	var dt := 1.0 / 60.0
	car.global_position += Vector3(0, 0, -35.0 * dt)   # w środku umownego biegu (granica 39 m/s)
	# Przesunięcie świata w połowie dojazdu: wszystko o -1000 m w X.
	if not shifted and car.global_position.z < 30.0:
		shifted = true
		var s := Vector3(1000, 0, 0)
		car.global_position -= s
		ta.listener_pos -= s
		ta.shift(s)
	ta.update([car], dt)
	var eng: AudioStreamPlayer3D = ta._slots[0]["eng"]
	if ta.active() == 1 and f > 5:
		if prev_pitch > 0.0:
			max_jump = maxf(max_jump, absf(eng.pitch_scale - prev_pitch))
		prev_pitch = eng.pitch_scale
		var z := car.global_position.z
		if z > 20.0 and z < 22.0:
			pitch_before = eng.pitch_scale
		if z < -20.0 and z > -22.0:
			pitch_after = eng.pitch_scale
	if car.global_position.z < -90.0 or f > 600:
		_check(pitch_before > 0.0 and pitch_after > 0.0 and pitch_before / pitch_after > 1.2,
				"ton przed / po minięciu: %.2f / %.2f" % [pitch_before, pitch_after])
		_check(max_jump < 0.1, "bez skoku tonu przy przesunięciu świata (maks. %.3f na klatkę)" % max_jump)
		_check(ta.active() == 0, "auto poza 80 m - slot wolny")
		print("traffic_audio_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
		quit(1 if fails else 0)
		return true
	return false
