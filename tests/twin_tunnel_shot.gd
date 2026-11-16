extends SceneTree
## Zrzut wnętrza dwururowego tunelu wąwozu (lampy nad osiami rur, nie nad
## wyspą). Wymaga okna:
##   godot --xr-mode off -s res://tests/twin_tunnel_shot.gd -- /katalog </dev/null

var f := 0
var out := "."
var chunk: StuntTrack
var cam: Camera3D
var shots := []
var main


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var start := {"pos": Vector3(0.0, 6.0, 3000.0), "yaw": 0.0, "pitch": 0.0,
			"bank": 0.0, "width": 14.8, "dist": 0.0}
	var segs := []
	var state := start.duplicate()
	TrackGenerator._push(segs, state, {"len": 60.0, "pitch": 0.0, "bank": 0.0})
	# Losowanie: szukamy ziarna, które da dwie nitki (40%).
	for sd in range(1, 50):
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var tmp := []
		var st2 := state.duplicate()
		TrackGenerator._tunnel(tmp, st2, {}, rng)
		var twin := false
		for s in tmp:
			if (s.get("meta", {}) as Dictionary).has("twin"):
				twin = true
		if twin:
			segs.append_array(tmp)
			break
	chunk = StuntTrack.new()
	chunk.name = "TwinTunnel"
	chunk.segments.assign(segs)
	chunk.canyon = true
	chunk.start_state = start
	chunk.build_lines = false
	root.add_child(chunk)
	cam = Camera3D.new()
	cam.fov = 75.0
	root.add_child(cam)
	cam.current = true


func _process(_d: float) -> bool:
	f += 1
	main.set_process(false)
	main.set_physics_process(false)
	cam.current = true
	if f == 5:
		shots = [[160.0, "polowa"], [300.0, "srodek"]]
	if f >= 10 and not shots.is_empty() and f % 6 == 0:
		var sh: Array = shots[0]
		var xf: Transform3D = chunk.transform_at_distance(float(sh[0]))
		var hw := float(chunk.sample_at(float(sh[0]))["width"]) * 0.25
		# Prawa nitka, wzrok kierowcy.
		cam.global_position = xf.origin + xf.basis.x * (hw + 1.25) + Vector3.UP * 1.2
		cam.look_at(cam.global_position - xf.basis.z * 40.0, Vector3.UP)
		if f % 12 == 0:
			root.get_viewport().get_texture().get_image().save_png("%s/tunel_dwie_nitki_%s.png" % [out, sh[1]])
			print("zrzut ", sh[1])
			shots.pop_front()
	if f > 120:
		return true
	return false
