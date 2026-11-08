extends SceneTree
## Test wgnieceń: auto spada dachem na ziemię z 3 m, potem bokiem z 2 m.
## Podaje liczbę wgnieceń, największe przesunięcie wierzchołka per materiał
## i czas jednego wgniecenia.
##   godot --headless --xr-mode off -s res://tests/dent_test.gd </dev/null

var main
var car
var f := 0
var phase := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")


func _drop(roll_deg: float, h: float) -> void:
	var b := Basis(Vector3.BACK, deg_to_rad(roll_deg))
	car.place(Transform3D(b, Vector3(-300, h, 300)))
	car._settle_t = 0.0   # bez uspokajania z place() - auto ma spadać swobodnie
	car.repair()


func _report(label: String) -> void:
	var parts := []
	var total := 0
	for k in car._dent_groups:
		var g: Dictionary = car._dent_groups[k]
		var mx := 0.0
		for i in range(g["verts"].size()):
			mx = maxf(mx, g["verts"][i].distance_to(g["orig"][i]))
		total += g["verts"].size()
		parts.append("%s %.0f cm" % [k, mx * 100.0])
	print("%s: wgnieceń %d, max przesunięcie: %s  (wierzchołków karoserii: %d)" % [label, car.dent_count, ", ".join(parts), total])
	var d: Dictionary = car.damage
	print("   uszkodzenia: stan %d%%, silnik %d%%, skrzynia %d%%, hamulce %s, zawieszenie %s" % [
		roundi(d["structure"] * 100), roundi(d["engine"] * 100), roundi(d["gearbox"] * 100),
		d["brakes"].map(func(x): return roundi(x * 100)), d["suspension"].map(func(x): return roundi(x * 100))])


var wall: StaticBody3D


## Auto jedzie na wprost w betonową ścianę z prędkością kmh.
func _wall_hit(kmh: float) -> void:
	if wall == null:
		wall = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10, 4, 1)
		cs.shape = box
		wall.add_child(cs)
		root.add_child(wall)
	wall.global_position = Vector3(-300, 1.5, 280)
	car.place(Transform3D(Basis(), Vector3(-300, 0.75, 292)))
	car.repair()
	var v := kmh / 3.6
	car.linear_velocity = Vector3(0, 0, -v)
	for w in car.wheels:
		w.omega = v / car.wheel_radius


func _physics_process(_d: float) -> bool:
	main.set_physics_process(false)
	f += 1
	if f == 2:
		_drop(180.0, 3.0)
	elif f == 2 + 480:
		_report("dachem z 3 m")
		_drop(90.0, 2.0)
	elif f == 2 + 960:
		_report("bokiem z 2 m")
		_wall_hit(30.0)
	elif f == 2 + 1440:
		_report("przodem w ścianę 30 km/h")
		_wall_hit(60.0)
	elif f == 2 + 1920:
		_report("przodem w ścianę 60 km/h")
		var t0 := Time.get_ticks_usec()
		for i in range(10):
			car.dent(Vector3(0, 0.1, -1.4), Vector3.DOWN, 0.05)
		print("czas jednego wgniecenia: %.2f ms" % ((Time.get_ticks_usec() - t0) / 10000.0))
		return true
	return false
