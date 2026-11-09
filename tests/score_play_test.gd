extends SceneTree
## Wpięcie ScoreKeepera w scenę jazdy: zdarzenia takie, jak zgłaszają je
## BotDriver i _update_bots (pościg z posiłków, unik, obrażenia zadane,
## zgubienie; osobno mandat za uderzenie spokojnego bota) - punkty w
## portfelu, napisy z puli, wynik w kolumnie przy mapce.
##   godot --headless --xr-mode off -s res://tests/score_play_test.gd </dev/null
var f := 0
var main
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	root.get_node("GameSettings").track_mode = "canyon"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(name: String, ok: bool, info: String) -> void:
	if not ok:
		fails += 1
	print("  %-38s %s  %s" % [name, info, "OK" if ok else "BŁĄD"])


func _process(_d: float) -> bool:
	f += 1
	if f < 10:
		return false
	main.race_state = main.Race.RACING
	main.race_time = 50.0
	main.car.linear_velocity = -main.car.global_basis.z * 25.0      # ~90 km/h
	main.car.speed = 25.0
	var a := StuntCar.new()
	var b := StuntCar.new()
	root.add_child(a)
	root.add_child(b)
	# Pościg z posiłków: unik, obrażenia zadane, zgubienie.
	main.score_chase_open(a, "reinforce")
	var p0: int = main.score.points
	main.score_end_attack(a, false, 0.6, "ram")
	_check("unik (bez kontaktu, minął o 0,6 m)", main.score.points > p0, "%d pkt" % main.score.points)
	var p1: int = main.score.points
	main.score_contact(a)
	main.score_damage(a, 0.35)
	_check("obrażenia zadane 35%", main.score.points > p1, "%d pkt" % main.score.points)
	var p2: int = main.score.points
	main.race_time += 20.0
	main.score_chase_close(a, "lost")
	_check("zgubiony", main.score.points > p2, "%d pkt" % main.score.points)
	# Zasadzka: unik z premią.
	main.score_chase_open(b, "overtake")
	var p3: int = main.score.points
	main.score_end_attack(b, false, 0.4, "ambush")
	var gain: int = main.score.points - p3
	_check("unik zasadzki (premia)", gain > 0, "+%d pkt" % gain)
	# Uderzenie spokojnego bota: bez mandatu, pościg płaci (2026-11-09).
	var c := StuntCar.new()
	root.add_child(c)
	var p4: int = main.score.points
	main.score_chase_open(c, "player_hit")
	_check("bez mandatu", main.score.points == p4, "%d pkt" % main.score.points)
	var p5: int = main.score.points
	main.score_end_attack(c, false, 0.5, "ram")
	_check("sprowokowany pościg płaci za unik", main.score.points > p5, "%d pkt" % main.score.points)
	# Napisy i kolumna przy mapce.
	var shown := 0
	for l in main._popups:
		if l.visible:
			shown += 1
	_check("napisy z puli widoczne", shown > 0, "%d z %d" % [shown, main._popups.size()])
	main.update_race(0.016)
	_check("wynik w kolumnie przy mapce", "pkt" in main._race_label.text, main._race_label.text.replace("\n", " | "))
	print("score_play_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	return true
