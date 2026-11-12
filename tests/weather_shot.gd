extends SceneTree
## Zrzuty pogody (wymaga okna): ten sam kadr z kokpitu przy pogodzie
## i w ulewie (WeatherPlan.look - ciemnoszare niebo, słabsze słońce, mgła).
##   godot --xr-mode off --resolution 960x600 -s res://tests/weather_shot.gd -- KATALOG </dev/null

var main
var f := 0
var out := "/tmp"
const SHOTS := [["pogodnie", {"cloud": 0.0, "rain": 0.0, "fog": 0.0, "kind": ""}],
		["chmury", {"cloud": 0.6, "rain": 0.0, "fog": 0.1, "kind": "rain"}],
		["ulewa", {"cloud": 1.0, "rain": 2.0, "fog": 0.35, "kind": "rain"}]]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	root.get_node("GameSettings").persist = false
	root.get_node("GameSettings").track_mode = "autostrada"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(d: float) -> bool:
	f += 1
	if f < 60:
		return false
	var i := (f - 60) / 40
	if i >= SHOTS.size():
		return true
	var w: Dictionary = SHOTS[i][1]
	main._weather_now = w
	main._wx_smooth = {"cloud": w["cloud"], "fog": w["fog"]}
	main._wx_t = 0.0
	main._update_weather_look(0.0)
	main._rain_target = w["rain"]
	main._update_rain(d)
	main.camera.current = true
	if (f - 60) % 40 == 38:
		root.get_viewport().get_texture().get_image().save_png("%s/pogoda_%s.png" % [out, SHOTS[i][0]])
	return false
