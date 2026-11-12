extends SceneTree
## Zrzuty manekina gracza (wymaga okna, bez gogli): ręce IK do "kontrolerów"
## na wieńcu (9:00 i 3:00, jak w hands_shot.gd), noga na gazie / hamulcu.
##   godot --xr-mode off --resolution 960x600 -s res://tests/player_dummy_shot.gd -- KATALOG </dev/null

var main
var car: StuntCar
var cam: Camera3D
var pd: PlayerDummy
var f := 0
var out := "/tmp"
var ctrl: Array[Node3D] = []
## [nazwa, kąt kierownicy, ujęcie, gaz, hamulec]
const SHOTS := [["fotel", 0.0, "eye", 1.0, 0.0], ["w_dol", 30.0, "down", 0.0, 1.0],
		["bok", 0.0, "side", 1.0, 0.0], ["przod", 30.0, "front", 0.0, 1.0]]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	cam = Camera3D.new()
	cam.fov = 75.0
	root.add_child(cam)
	for s in ["L", "R"]:
		var c := Node3D.new()
		root.add_child(c)
		var mi := MeshInstance3D.new()
		mi.mesh = load("res://models/dummy/dummy_hand_%s.obj" % s)
		c.add_child(mi)
		ctrl.append(c)


func _process(d: float) -> bool:
	f += 1
	main.set_physics_process(false)
	if f == 5:
		pd = PlayerDummy.new()
		pd.setup(car, ctrl[0], ctrl[1])
		car.set_cockpit_transparency(0.0)
	if f < 60:
		return false
	var i := (f - 60) / 15
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
	var rr := r * cos(th) - u * sin(th)
	var uu := u * cos(th) + r * sin(th)
	for k in range(2):
		var side := -1.0 if k == 0 else 1.0
		var z := -uu
		var y := ax
		var x := y.cross(z).normalized()
		ctrl[k].global_transform = Transform3D(Basis(x, y, z), c + rr * side * 0.19)
	pd.update(float(sh[3]), float(sh[4]), 1.0)
	var eye: Vector3 = car.seat.global_position
	var b: Basis = car.global_basis
	cam.current = true
	match sh[2]:
		"eye":
			cam.global_position = eye
			cam.look_at(c, b.y)
		"down":
			cam.global_position = eye
			cam.look_at(eye - b.z * 0.4 - b.y * 0.9, b.y)
		"side":
			cam.global_position = eye + b.x * -1.6 + b.y * 0.1 + b.z * 0.2
			cam.look_at(eye - b.y * 0.45, b.y)
		"front":
			cam.global_position = eye - b.z * 1.2 + b.y * 0.1 + b.x * -0.2
			cam.look_at(eye - b.y * 0.4, b.y)
	if (f - 60) % 15 == 13:
		root.get_viewport().get_texture().get_image().save_png("%s/manekin_gracza_%s.png" % [out, sh[0]])
	return false
