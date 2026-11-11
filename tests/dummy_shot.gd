extends SceneTree
## Zrzuty aut botów z manekinem crash-test i fotelem (wymaga okna):
##   godot --xr-mode off --resolution 900x600 -s res://tests/dummy_shot.gd -- KATALOG </dev/null
var f := 0
var cars := []
var cam: Camera3D
var out := "/tmp"
const STYLES := ["sedan", "kabriolet", "klin", "terenowka"]
var shots := []
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	var root3 := Node3D.new()
	root.add_child(root3)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root3.add_child(env)
	for i in STYLES.size():
		var c := StuntCar.new()
		c.is_bot = true
		root3.add_child(c)
		c.freeze = true
		c.position = Vector3(0.0, 0.0, i * 8.0)
		cars.append(c)
	cam = Camera3D.new()
	cam.fov = 40
	root3.add_child(cam)
	cam.current = true
	for i in STYLES.size():
		var p := Vector3(0.0, 0.0, i * 8.0)
		shots.append([STYLES[i] + "_bok", p + Vector3(-4.5, 1.6, 0.3), p + Vector3(0, 0.6, 0.3)])
		shots.append([STYLES[i] + "_przod", p + Vector3(-2.0, 2.2, -4.5), p + Vector3(0, 0.6, 0)])
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		# Styl dopiero po _ready aut (w _initialize węzły jeszcze nie są gotowe).
		for k in cars.size():
			cars[k].apply_style(STYLES[k])
	var i := f / 6 - 2
	if f % 6 == 0 and i >= 0 and i < shots.size():
		var s = shots[i]
		cam.look_at_from_position(s[1], s[2])
	if f % 6 == 4 and i >= 0 and i < shots.size():
		root.get_viewport().get_texture().get_image().save_png(out + "/bot_" + shots[i][0] + ".png")
	return i >= shots.size()
