extends SceneTree
## Jezdnia nigdzie nie schodzi pod teren ani pod morze (błąd 2026-11-08:
## "droga pod wodą / pod łąką"). Sam generator, bez sceny: dla kilku ziaren
## buduje po kolei sekcje wąwozu z autostradą (jak EndlessTrack) i sprawdza
## najniższy punkt jezdni - także niższą krawędź na przechyłce.
## Teren z trawą leży na y = 0, morze na StuntTrack.SEA_Y.
##   godot --headless --xr-mode off -s res://tests/track_height_test.gd -- [sekcji] </dev/null

## Najniżej dopuszczalna jezdnia: d.hmin generatora (2 m) z małym zapasem
## na próbkowanie.
const FLOOR := 1.9


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var sections := int(args[0]) if args.size() > 0 else 40
	var fails := 0
	var worst := INF
	var worst_at := ""
	for seed_v in [777, 12345, 1, 2, 3, 4, 5, 6, 7, 8]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var state := {"pos": Vector3(0.0, 6.0, 0.0), "yaw": 0.0, "pitch": 0.0,
				"bank": 0.0, "width": 14.8, "dist": 0.0}
		for i in range(1, sections + 1):
			var segs := TrackGenerator.generate_section(i, state, rng, true)
			var low := TrackGenerator.lowest_edge(segs, state)
			var kind := "autostrada" if TrackGenerator.is_highway(i) else "wąwóz"
			if low < worst:
				worst = low
				worst_at = "ziarno %d, odcinek %d (%s)" % [seed_v, i, kind]
			if low < FLOOR:
				fails += 1
				print("  za nisko: ziarno %d, odcinek %d (%s), jezdnia %.2f m" % [seed_v, i, kind, low])
			var smp := StuntTrack.sample_segments(segs, state, 2.0)
			state = smp[-1]["end_state"]
	print("najniższa jezdnia %.2f m (%s), teren 0, morze %.1f" % [worst, worst_at, StuntTrack.SEA_Y])
	if fails > 0:
		print("track_height_test: BŁĄD - %d odcinków pod %.1f m" % [fails, FLOOR])
	else:
		print("track_height_test: OK")
	quit()
