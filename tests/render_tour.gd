extends SceneTree
## Rendery trybu Autostrada (do docs/renders, dla użytkownika i chmury).
## Każde ujęcie: trasa Autostrada zaczynająca się w zadanym miejscu planu
## (EndlessTrack.start_dist - leniwa generacja: plan i kawałki liczą się od
## tego dystansu, bez budowania wcześniejszych km), kamera w układzie trasy.
## Wymaga okna (nie --headless):
##   godot --xr-mode off --resolution 1280x720 -s res://tests/render_tour.gd -- KATALOG [nazwa] </dev/null

const SEED := 777

var out := "."
var only := ""
var shots: Array = []          # [nazwa, start_dist, cam_d, cam_lat, cam_h, look_d, look_lat, look_h, biom?]
var cur := -1
var f := 0
var main
var et: EndlessTrack
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		only = args[1]
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	# Ten sam plan co w EndlessTrack: ziarno planu to pierwsze randi() z RNG
	# trasy (EndlessTrack._ready).
	var r := RandomNumberGenerator.new()
	r.seed = SEED
	var plan := HighwayPlan.new(r.randi())
	# Miasta: małe na 25 km, duże na 100 km (plan: co 25 km, co 4. duże).
	var small: Dictionary = plan.city(1)
	var big: Dictionary = plan.city(4)
	var s0: float = small["start"]
	var b0: float = big["start"]
	shots = [
		["miasto_male_wjazd", s0 - 700.0, s0 - 120.0, 0.75, 1.4, s0 + 200.0, 0.0, 2.0],
		["miasto_male_ulica", s0 - 700.0, s0 + 300.0, 0.75, 1.4, s0 + 500.0, 0.0, 3.0],
		["miasto_male_z_gory", s0 - 700.0, s0 + 150.0, 60.0, 90.0, s0 + 600.0, 0.0, 0.0],
		["miasto_duze_centrum", b0 + 1800.0, b0 + 2400.0, 0.75, 1.4, b0 + 2650.0, 0.0, 6.0],
		["miasto_duze_z_gory", b0 + 1800.0, b0 + 2200.0, 120.0, 160.0, b0 + 2900.0, 0.0, 0.0],
		["miasto_duze_detal", b0 + 1800.0, b0 + 2400.0, 28.0, 30.0, b0 + 2440.0, 8.0, 0.0],
		["warsztat_w_miescie", s0 - 700.0, s0 + 230.0, 0.75, 1.6, s0 + 420.0, 12.0, 1.5],
	]
	var st: Array = plan.stations_between(0.0, 60000.0)
	if not st.is_empty():
		var a: float = st[0]["start"]
		shots.append(["stacja_paliw", a - 600.0, a - 70.0, 0.75, 1.6, a + 60.0, 10.0, 1.5])
	var jumps: Array = plan.jumps_between(0.0, 200000.0)
	if not jumps.is_empty():
		var j: float = jumps[0]["start"]
		shots.append(["wielka_skocznia_bok", j - 400.0, j + 230.0, 70.0, 12.0, j + 230.0, 0.0, 2.0])
		shots.append(["wielka_skocznia_wjazd", j - 400.0, j + 40.0, 0.75, 1.4, j + 260.0, 0.0, 3.0])
	_next()


func _next() -> void:
	cur += 1
	f = 0
	if main:
		main.queue_free()
		main = null
	while cur < shots.size() and only != "" and shots[cur][0] != only:
		cur += 1
	if cur >= shots.size():
		quit()
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	if main == null:
		return false
	f += 1
	var sh: Array = shots[cur]
	if f == 2:
		et = EndlessTrack.new()
		et.autostrada = true
		et.canyon = false
		et.seed_value = SEED
		et.start_dist = sh[1]
		et.road_material = main.track.road_material
		et.pillar_material = main.track.pillar_material
		main.track.queue_free()
		main.add_child(et)
		main.track = et
		main._biome = ""
		main._biome_key = ""
		cam = Camera3D.new()
		cam.far = 5000.0
		main.add_child(cam)
		cam.current = true
	if f > 3 and et:
		# Trasa dobudowuje się wokół kamery (jak wokół auta).
		et.update_progress(float(sh[2]))
		main._last_safe_dist = float(sh[2])
		var c: Transform3D = et.transform_at_distance(float(sh[2]))
		var l: Transform3D = et.transform_at_distance(float(sh[5]))
		main.car.global_position = c.origin + Vector3.DOWN * 50.0     # auto z kadru
		main.car.freeze = true
		cam.global_position = c.origin + c.basis.x * float(sh[3]) + Vector3.UP * float(sh[4])
		cam.look_at(l.origin + l.basis.x * float(sh[6]) + Vector3.UP * float(sh[7]))
	if f == 240:
		root.get_texture().get_image().save_jpg("%s/%s.jpg" % [out, sh[0]], 0.85)
		print("render: ", sh[0])
		_next()
	return false
