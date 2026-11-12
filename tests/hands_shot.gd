extends SceneTree
## Zrzuty kierownicy w powietrzu z dłońmi manekina (wymaga okna, bez gogli):
## dłonie ustawione na wieńcu na 9:00 i 3:00 jak kontrolery w gripie,
## kierownica prosto i obrócona o 60° w prawo.
##   godot --xr-mode off --resolution 960x600 -s res://tests/hands_shot.gd -- KATALOG </dev/null

var main
var car: StuntCar
var cam: Camera3D
var f := 0
var out := "/tmp"
var hands: Array[MeshInstance3D] = []
const SHOTS := [["fotel_prosto", 0.0, "eye"], ["fotel_60", 60.0, "eye"], ["bok_60", 60.0, "side"]]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	cam = Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	for s in ["L", "R"]:
		var mi := MeshInstance3D.new()
		mi.mesh = load("res://models/dummy/dummy_hand_%s.obj" % s)
		root.add_child(mi)
		hands.append(mi)


func _process(_d: float) -> bool:
	f += 1
	main.set_physics_process(false)
	if f < 60:
		return false
	var i := (f - 60) / 12
	if i >= SHOTS.size():
		return true
	var sh: Array = SHOTS[i]
	var fr: Array = car.steering_frame()
	var c: Vector3 = fr[0]
	var r: Vector3 = fr[1]
	var u: Vector3 = fr[2]
	var ax := r.cross(u)
	var th := deg_to_rad(float(sh[1]))
	car.steering_wheel_deg = float(sh[1])
	car._visual_step(0.0)
	var rr := r * cos(th) - u * sin(th)         # obrót zgodny z zegarem z widoku kierowcy
	var uu := u * cos(th) + r * sin(th)
	for k in range(2):
		var side := -1.0 if k == 0 else 1.0
		var p := c + rr * side * 0.19
		# Dłoń w gripie: palce (-Z) wzdłuż wieńca do góry tarczy, kciuk (+Y)
		# w stronę kierowcy - przybliżenie póz kontrolera trzymanego na wieńcu.
		var z := -uu
		var y := ax
		var x := y.cross(z).normalized()
		hands[k].global_transform = Transform3D(Basis(x, y, z), p)
	var eye: Vector3 = car.seat.global_position
	cam.current = true
	if sh[2] == "eye":
		cam.global_position = eye
		cam.look_at(c + u * 0.05 - ax * 0.0, car.global_basis.y)
	else:
		cam.global_position = c + car.global_basis.x * -0.9 + car.global_basis.y * 0.25 + car.global_basis.z * 0.1
		cam.look_at(c, car.global_basis.y)
	if (f - 60) % 12 == 10:
		root.get_viewport().get_texture().get_image().save_png("%s/dlonie_%s.png" % [out, sh[0]])
	return false
