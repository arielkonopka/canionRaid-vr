extends SceneTree
## Zrzuty ekranu auta z kilku ujęć - do sprawdzania wyglądu bez gogli.
## Wymaga okna (nie --headless): na chwilę otwiera się okno Godota.
##   godot --xr-mode off --resolution 960x600 -s res://tests/screenshot.gd -- /ścieżka/do/katalogu [dent] </dev/null
## Z "rain" pada ulewa (krople, wycieraczki, smugi).
## Z "dent" auto dostaje kilka wgnieceń (przód z lewej, dach, prawy bok) przed zdjęciami.
## Zapisuje car_<ujęcie>.png. Ujęcia w układzie auta (przód = -Z).

var shots := [
	["front34", Vector3(-3.2, 0.9, -4.2), Vector3(0, 0.0, 0)],
	["rear34", Vector3(3.4, 1.2, 4.6), Vector3(0, 0.0, 0.3)],
	["side", Vector3(-6.5, 0.4, 0.0), Vector3(0, -0.1, 0)],
	["cockpit", Vector3(-0.38, 0.45, 0.30), Vector3(-0.38, 0.25, -2.0)],
	["chase", Vector3(0.0, 2.2, 7.5), Vector3(0, 0.5, -4.0)],
	["overview", Vector3(45.0, 22.0, 35.0), Vector3(0, -12.0, -70.0)],
	["gauges", Vector3(-0.30, 0.42, 0.20), Vector3(-0.20, 0.21, -0.40)],
]
var f := 0
var out := "."
var main
var car
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	cam = Camera3D.new()
	cam.fov = 60
	cam.near = 0.03
	root.add_child(cam)


func _process(_d: float) -> bool:
	f += 1
	# Auto stoi: scena nie czyta wejścia ani nie przesuwa kamery gracza.
	main.set_physics_process(false)
	main.set_process(false)
	# HUD trasy odświeża scena jazdy w _process - tu ręcznie, bo jest wyłączona.
	if main._track_hud and f > 10:
		main._track_hud.refresh(1.0, car.global_transform,
				func(): return main.track.samples_from(0.0, 1520.0), 8.0)
	# Pierwsze klatki: rozgrzewka renderera. Każde ujęcie trzyma 10 klatek,
	# bo tekstura viewportu pokazuje obraz z opóźnieniem - przy krótszym
	# czasie zrzut łapie poprzednie ujęcie.
	if f == 20 and OS.get_cmdline_user_args().has("dent"):
		car.dent(Vector3(-0.75, 0.0, -2.25), Vector3(0.6, 0.0, 0.8), 0.15)
		car.dent(Vector3(0.0, 0.69, 0.4), Vector3.DOWN, 0.14)
		car.dent(Vector3(0.9, -0.1, 0.3), Vector3.LEFT, 0.10)
	# Z "rain": ulewa (krople na szybie, wycieraczki, smugi deszczu).
	if OS.get_cmdline_user_args().has("rain"):
		main._rain_target = 2.0
		main._update_rain(_d)
	if f < 60:
		return false
	var i := (f - 60) / 10
	if i >= shots.size():
		return true
	var s: Array = shots[i]
	var xf: Transform3D = car.get_global_transform_interpolated()
	cam.current = true
	# Z kokpitu kabina prześwituje (domyślne 40%), z zewnątrz auto pełne.
	car.set_cockpit_transparency(0.4 if s[0] == "cockpit" else 0.0)
	cam.fov = 40.0 if s[0] == "gauges" else 60.0
	cam.global_position = xf * s[1]
	cam.look_at(xf * s[2], xf.basis.y)
	if (f - 60) % 10 == 9:
		root.get_viewport().get_texture().get_image().save_png("%s/car_%s.png" % [out, s[0]])
	return false
