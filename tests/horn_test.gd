extends SceneTree
## Klakson gracza (klik lewego drążka / H, użytkownik 2026-11-09): wpędza
## w szał boty w promieniu HORN_RADIUS, dalszych nie.
##   godot --headless --xr-mode off -s res://tests/horn_test.gd </dev/null

var main
var f := 0


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "canyon"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(_d: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._spawn_bot(main._last_safe_dist + 120.0)
		main._spawn_bot(main._last_safe_dist + 600.0)
	if f == 10:
		var near: BotDriver = main._bots[0].get_node("Driver")
		var far: BotDriver = main._bots[1].get_node("Driver")
		main.player_horn()
		var ok: bool = near.rage > 0.9 and far.rage < 0.1
		print("klakson: bot 120 m szał %.1f, bot 600 m szał %.1f" % [near.rage, far.rage])
		print("horn_test: ", "OK" if ok else "BŁĄD")
		return true
	return false
