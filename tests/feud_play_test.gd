extends SceneTree
## Waśnie botów w grze (FeudDirector wpięty w xr_main, inbox
## wasnie-na-autostradzie, krok 8.3): 6 botów z dwóch wrogich gangów przed
## graczem (autostrada). W ciągu 40 s ma wybuchnąć potyczka; uderzenie
## gracza w bota w potyczce -> sojusz (boty biorą na cel gracza); żaden bot
## w waśni nie jedzie po szynie.
##   godot --headless --xr-mode off -s res://tests/feud_play_test.gd </dev/null

var main
var f := 0
var t := 0.0
var skirmish_seen := false
var fails := 0


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
		# Ruch autostrady wyłączony (test steruje botami sam).
		main._traffic_t = 1e9
		main.feud.set_hostile(0, 1, true)
		for i in range(6):
			main._bot_rng.seed = 1000 + i          # gang = randi() % GANGS
			main._spawn_bot(main._last_safe_dist + 60.0 + i * 22.0, i % 2, 100.0)
			var b: StuntCar = main._bots[-1]
			main.feud.add_bot(b.get_instance_id(), i % 2)
	if f <= 5:
		return false
	t += delta
	# Gracz jedzie za botami (prędkość wprost - test nie steruje gazem).
	main.car.linear_velocity = -main.car.global_basis.z * 26.0
	for b in main._bots:
		var id: int = b.get_instance_id()
		var drv: BotDriver = b.get_node("Driver")
		if main.feud.in_feud(id) and main.feud.target_of(id) != FeudDirector.PLAYER:
			skirmish_seen = true
			if drv.lod == BotLod.RAIL:
				_check(false, "bot w waśni na szynie")
	if skirmish_seen and t > 1.0 and f % 60 == 0:
		# Gracz uderza bota w potyczce -> sojusz.
		for b in main._bots:
			var id: int = b.get_instance_id()
			if main.feud.in_feud(id) and main.feud.target_of(id) != FeudDirector.PLAYER:
				main.feud_player_hit(b)
				var drv: BotDriver = b.get_node("Driver")
				_check(main.feud.target_of(id) == FeudDirector.PLAYER, "po uderzeniu gracza bot w sojuszu (cel: gracz)")
				_check(drv.foe == null and drv.rage > 0.0, "bot ściga gracza (foe null, szał)")
				print("feud_play_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
				return true
	if t > 40.0:
		_check(skirmish_seen, "potyczka w ciągu 40 s")
		print("feud_play_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
		return true
	return false
