extends SceneTree
## Zrzuty biomów trybu Autostrada (etap 2): dla każdego biomu trasa z tym
## biomem na starcie, ujęcie zza auta w kierunku jazdy i w lewo (morze).
## Wymaga okna (nie --headless):
##   godot --xr-mode off --resolution 960x600 -s res://tests/biome_shots.gd -- KATALOG </dev/null

const BIOMES := ["meadow", "fields", "desert", "mountains", "seaside", "canyon"]
var out := "."
var main
var cur := -1
var f := 0
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	_next()


func _next() -> void:
	cur += 1
	f = 0
	if main:
		main.queue_free()
		main = null
	if cur >= BIOMES.size():
		quit()
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	if main == null:
		return false
	f += 1
	if f == 2:
		# Własna trasa z biomem na starcie (jak endless_test podmienia trasę).
		var et := EndlessTrack.new()
		et.autostrada = true
		et.canyon = false
		et.seed_value = 777
		et.first_biome = BIOMES[cur]
		et.road_material = main.track.road_material
		et.pillar_material = main.track.pillar_material
		main.track.queue_free()
		main.add_child(et)
		main.track = et
		main._biome = ""
		main._biome_key = ""
		main.car.place(et.transform_at_distance(400.0))
		main._last_safe_dist = 400.0
		cam = Camera3D.new()
		main.add_child(cam)
		cam.current = true
		cam.far = 4000.0
	if f > 3 and cam:
		main.car.linear_velocity = Vector3.ZERO
		var xf: Transform3D = main.track.transform_at_distance(400.0)
		var fwd := -xf.basis.z
		var left := -xf.basis.x
		if f < 40:
			cam.global_position = xf.origin + Vector3.UP * 4.0 - fwd * 12.0
			cam.look_at(xf.origin + fwd * 200.0 + Vector3.UP * 2.0)
		else:
			cam.global_position = xf.origin + Vector3.UP * 6.0 + left * 4.0
			cam.look_at(xf.origin + left * 400.0 + fwd * 150.0)
	if f == 38:
		root.get_texture().get_image().save_png("%s/biome_%s_fwd.png" % [out, BIOMES[cur]])
	if f == 70:
		root.get_texture().get_image().save_png("%s/biome_%s_left.png" % [out, BIOMES[cur]])
		_next()
	return false
