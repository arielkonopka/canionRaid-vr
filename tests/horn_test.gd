extends SceneTree
## Klakson gracza (klik lewego drążka / H, użytkownik 2026-11-09): wpędza
## w szał boty w promieniu HORN_RADIUS, dalszych nie. Potem żetony pościgu:
## 7 botów w szale, fizykę w szale ma najwyżej CHASE_TOKENS (najbliższe).
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
		if not ok:
			print("horn_test: BŁĄD")
			return true
		for i in range(6):
			main._spawn_bot(main._last_safe_dist + 40.0 + i * 30.0)
		main._horn_cd = 0.0                   # blokada 1 s między klaksonami
		main.player_horn()
	if f == 80:
		var held := 0
		var raging := 0
		var nearest_ok := true
		for b in main._bots:
			var drv: BotDriver = b.get_node("Driver")
			if drv.rage > 0.0:
				raging += 1
			if drv.has_token:
				held += 1
				# Żeton nie może trafić do dalszego bota, gdy bliższy w szale go nie ma.
				for c in main._bots:
					var dc: BotDriver = c.get_node("Driver")
					if dc.rage > 0.0 and not dc.has_token and dc.dist < drv.dist and drv.dist > main._last_safe_dist + 250.0:
						nearest_ok = false
		var ok2: bool = held <= main.CHASE_TOKENS and raging > main.CHASE_TOKENS and nearest_ok
		print("żetony: w szale %d, z żetonem %d (K=%d)" % [raging, held, main.CHASE_TOKENS])
		print("horn_test: ", "OK" if ok2 else "BŁĄD")
		return true
	return false
