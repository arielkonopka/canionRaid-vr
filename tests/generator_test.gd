extends SceneTree
## Test generatora trasy bez końca: buduje kolejne sekcje i wypisuje ich
## parametry - długość, wysokość, kierunek, skoki (prędkość, przerwa)
## oraz czas budowy kawałka.
##   godot --headless --xr-mode off -s res://tests/generator_test.gd -- [ziarno] </dev/null

var et: EndlessTrack
var f := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	et = EndlessTrack.new()
	et.seed_value = int(args[0]) if args.size() > 0 else 12345
	root.add_child(et)


func _process(_d: float) -> bool:
	# _ready węzłów w trybie -s odpala się dopiero w kolejnej klatce.
	f += 1
	if f < 3:
		return false
	for i in range(22):
		var t0 := Time.get_ticks_usec()
		et.update_progress(et._chunks[et._current].total_length() + 1.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms > 1.0:
			print("  (dobudowa: %.1f ms)" % ms)
	for c in et._chunks:
		var s0: Dictionary = c._samples[0]
		var e: Dictionary = c.end_state()
		var jumps := []
		var hmin := INF
		var hmax := -INF
		for s in c._samples:
			hmin = minf(hmin, s["pos"].y)
			hmax = maxf(hmax, s["pos"].y)
			var m: Dictionary = s["meta"]
			if m.has("jump"):
				jumps.append("%.0f km/h (u podstawy %.0f), przerwa %.1f m" % [
					m["jump"]["v_req"] * 3.6, m["jump"]["v_bottom"] * 3.6, m["jump"]["gap"]])
		var curves := 0
		for seg in c.segments:
			if absf(seg.get("curve", 0.0)) > 0.0:
				curves += 1
		var surf := {}
		for s in c._samples:
			surf[s["surface"]] = surf.get(s["surface"], 0) + 1
		print("%s: od %4.0f m, dł. %3.0f m, wys. %2.0f-%2.0f m, kurs %+4.0f°, łuków %d, szer. %.1f, nawierzchnie %s" % [
			c.name, s0["dist"], c.total_length() - s0["dist"], hmin, hmax,
			rad_to_deg(e["yaw"]), curves, s0["width"], surf])
		for j in jumps:
			print("     skok: ", j)
	return true
