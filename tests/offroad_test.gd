extends SceneTree
## Zjazd w pole na wprost od łuku (jazda 2026-11-10: gra "widziała" auto
## przy 14 767 m, a ono jechało 170 km/h w pole - trasa przestała się
## dobudowywać i "urwała się"). Auto jedzie 3 s po trasie, potem prosto
## pod kątem 9° od drogi: najbliższa próbka ma iść za autem, a daleko od
## drogi gra ma uznać zjazd (odrodzenie na trasie).
##   godot --headless --xr-mode off -s res://tests/offroad_test.gd </dev/null

var main
var f := 0
var t := 0.0
var dir := Vector3.ZERO
var pos := Vector3.ZERO
var fails := 0
var max_gap := 0.0
var respawned := false


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._traffic_t = 1e9
		main._bot_timer = 1e9
		var xf: Transform3D = main.track.transform_at_distance(300.0)
		pos = xf.origin + xf.basis.x * 20.0
		dir = (-xf.basis.z).rotated(Vector3.UP, 0.15)
	if f <= 5:
		return false
	t += delta
	pos += dir * 47.0 * delta
	if t < 8.0:
		main.car.global_transform = Transform3D(Basis.looking_at(dir), pos + Vector3.UP * 0.7)
		main.car.linear_velocity = dir * 47.0
		var s: Dictionary = main.track.nearest_sample(main.car.global_position)
		var gap: float = (main.car.global_position - main.track.to_global(s["pos"])).length()
		max_gap = maxf(max_gap, gap)
	elif not respawned:
		var s: Dictionary = main.track.nearest_sample(main.car.global_position)
		respawned = (main.car.global_position - main.track.to_global(s["pos"])).length() < 5.0
	if t > 12.0:
		_check(max_gap < 400.0, "najbliższa próbka idzie za autem (największa odległość %.0f m)" % max_gap)
		_check(respawned, "daleko od drogi - odrodzenie na trasie")
		print("offroad_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
		return true
	return false
