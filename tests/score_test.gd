extends SceneTree
## Test logiki punktacji furii drogowej (ScoreKeeper) - bez sceny i fizyki.
##   godot --headless --xr-mode off -s res://tests/score_test.gd </dev/null
## Sprawdza: brak mandatu i punkty z pościgu "player_hit", unik, zgubienie,
## uspokojenie tylko bez trafień, winę za wybuch, wmanewrowanie, serię,
## portfel i wydatki. Kod wyjścia 1 przy błędzie.

const SK := preload("res://scripts/score_keeper.gd")

var fails := 0


func _initialize() -> void:
	_test_fine()
	_test_dodge_and_lost()
	_test_calmed()
	_test_wreck_blame()
	_test_combo()
	_test_wallet()
	_test_styles_balanced()
	_test_damage_and_ambush()
	_test_section_speed()
	_test_sheriff()
	print("score_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  BŁĄD: ", what)


func _sum(pays: Array) -> int:
	var s := 0
	for p in pays:
		s += int(p["points"])
	return s


func _test_fine() -> void:
	var sk = SK.new()
	sk.points = 500
	# Od 2026-11-09 bez mandatu: sprowokowany pościg płaci jak każdy inny.
	var p: Array = sk.open_chase(1, "player_hit", 0.0)
	_check(p.is_empty(), "bez mandatu przy uderzeniu spokojnego bota")
	_check(sk.points == 500, "portfel bez zmian (%d)" % sk.points)
	_check(not sk.end_attack(1, false, 0.5, 120.0, 5.0).is_empty(), "pościg player_hit daje punkty za unik")
	_check(not sk.close_chase(1, "lost", 30.0, 120.0).is_empty(), "pościg player_hit daje punkty za zgubienie")
	var sk2 = SK.new()
	sk2.points = 50
	_check(not sk2.spend(100) and sk2.points == 50, "portfel nie schodzi poniżej zera")


func _test_dodge_and_lost() -> void:
	var sk = SK.new()
	sk.open_chase(1, "overtake", 0.0)
	_check(sk.end_attack(1, true, 0.3, 100.0, 2.0).is_empty(), "trafienie to nie unik")
	_check(sk.end_attack(1, false, 2.5, 100.0, 4.0).is_empty(), "za daleko na unik")
	var d: Array = sk.end_attack(1, false, 0.8, 100.0, 6.0)
	_check(d.size() == 1 and d[0]["kind"] == "dodge" and int(d[0]["points"]) > 0, "unik daje punkty")
	var l: Array = sk.close_chase(1, "lost", 40.0, 150.0)
	_check(l.size() == 1 and l[0]["kind"] == "lost", "zgubiony pościg daje punkty")
	_check(sk.chases.is_empty(), "karta usunięta po zamknięciu")


func _test_calmed() -> void:
	var sk = SK.new()
	sk.open_chase(1, "reinforce", 0.0)
	_check(_sum(sk.close_chase(1, "calmed", 20.0, 90.0)) > 0, "uspokojenie bez trafień daje punkty")
	sk.open_chase(2, "reinforce", 30.0)
	sk.note_contact(2, 35.0)
	_check(sk.close_chase(2, "calmed", 60.0, 90.0).is_empty(), "uspokojenie po trafieniu nic nie daje")


func _test_wreck_blame() -> void:
	var sk = SK.new()
	sk.open_chase(1, "reinforce", 0.0)
	sk.note_contact(1, 10.0)
	var w: Array = sk.close_chase(1, "wreck", 12.0, 140.0)
	_check(w.size() == 1 and w[0]["kind"] == "wreck", "wybuch po kontakcie = ROZBITY")
	sk.open_chase(2, "reinforce", 20.0)
	sk.note_contact(2, 21.0)
	_check(sk.close_chase(2, "wreck", 40.0, 140.0).is_empty(), "wybuch długo po kontakcie nic nie daje")
	sk.open_chase(3, "reinforce", 50.0)
	sk.end_attack(3, false, 0.5, 140.0, 60.0)
	var o: Array = sk.close_chase(3, "wreck", 61.5, 140.0)
	_check(o.size() == 1 and o[0]["kind"] == "outmaneuver", "wybuch tuż po uniku = WMANEWROWANY")


func _test_combo() -> void:
	var sk = SK.new()
	sk.open_chase(1, "overtake", 0.0)
	var a: Array = sk.end_attack(1, false, 0.5, 100.0, 1.0)
	var b: Array = sk.end_attack(1, false, 0.5, 100.0, 5.0)
	_check(int(b[0]["combo"]) == 2 and int(b[0]["points"]) > int(a[0]["points"]), "seria mnoży punkty")
	var c: Array = sk.end_attack(1, false, 0.5, 100.0, 30.0)
	_check(int(c[0]["combo"]) == 1, "seria wygasa po COMBO_WINDOW")
	_check(String(b[0]["text"]).ends_with("x2"), "napis serii")


func _test_wallet() -> void:
	var sk = SK.new()
	sk.points = 300
	_check(not sk.spend(400), "brak punktów - wydatek odrzucony")
	_check(sk.spend(250) and sk.points == 50, "wydatek odejmuje")
	_check(not sk.spend(-5), "ujemny wydatek odrzucony")


## Uciekinier i wojownik w tym samym pościgu (60 s, 130 km/h): wojownik
## ma zarobić więcej, ale nie kilka razy więcej - różnicę ma zjadać naprawa.
func _test_styles_balanced() -> void:
	var run := SK.new()
	run.open_chase(1, "reinforce", 0.0)
	for i in 4:
		run.end_attack(1, false, 0.9, 130.0, 10.0 + 15.0 * i)
	run.close_chase(1, "lost", 60.0, 130.0)
	var fight := SK.new()
	fight.open_chase(1, "reinforce", 0.0)
	fight.end_attack(1, true, 0.0, 130.0, 20.0)
	fight.note_contact(1, 58.0)
	fight.close_chase(1, "wreck", 60.0, 130.0)
	print("  uciekinier %d pkt, wojownik %d pkt" % [run.points, fight.points])
	_check(run.points > 0 and fight.points > 0, "oba style zarabiają")
	var ratio := float(fight.points) / float(run.points)
	_check(ratio > 0.5 and ratio < 3.0, "style porównywalne (wojownik/uciekinier %.2f)" % ratio)


## Wizja (2026-11-08): punkty za obrażenia zadane, premia za eksplozję,
## premia za unik zasadzki.
func _test_damage_and_ambush() -> void:
	var sk := SK.new()
	sk.open_chase(1, "reinforce", 0.0)
	_check(sk.damage_dealt(1, 0.04, 1.0, 100.0).is_empty(), "małe obrażenia sumują się bez napisu")
	var d: Array = sk.damage_dealt(1, 0.08, 2.0, 100.0)
	_check(d.size() == 1 and d[0]["kind"] == "damage" and int(d[0]["points"]) > 0, "obrażenia 12% dają punkty")
	var before: int = sk.points
	sk.note_contact(1, 3.0)
	var w: Array = sk.close_chase(1, "wreck", 4.0, 100.0)
	_check(w.size() == 1 and sk.points > before, "eksplozja daje premię ponad obrażenia")
	var hit := SK.new()
	hit.open_chase(2, "player_hit", 0.0)
	_check(not hit.damage_dealt(2, 0.5, 1.0, 100.0).is_empty(), "sprowokowany pościg - punkty za obrażenia")
	var amb := SK.new()
	amb.open_chase(3, "overtake", 0.0)
	var a: Array = amb.end_attack(3, false, 0.8, 100.0, 1.0, "ambush")
	var plain := SK.new()
	plain.open_chase(3, "overtake", 0.0)
	var p: Array = plain.end_attack(3, false, 0.8, 100.0, 1.0)
	_check(a[0]["kind"] == "ambush_dodge" and int(a[0]["points"]) > int(p[0]["points"]),
			"unik zasadzki wart więcej niż zwykły unik")


## Premia za odcinek (użytkownik 2026-11-11): 100 km/h = 100, 200 = 1000,
## 300 = 10 000, bez mnożnika serii.
func _test_section_speed() -> void:
	_check(SK.section_points(100.0) == 100 and SK.section_points(200.0) == 1000 \
			and SK.section_points(300.0) == 10000, "100/200/300 km/h = 100/1000/10000 (%d/%d/%d)" % [
			SK.section_points(100.0), SK.section_points(200.0), SK.section_points(300.0)])
	_check(SK.section_points(150.0) == 316, "płynnie pomiędzy (150 km/h = %d)" % SK.section_points(150.0))
	var sk := SK.new()
	sk.award_free("pit", 100, 0.0)
	var p0: int = sk.points
	var r: Array = sk.section_done(200.0)
	_check(r.size() == 1 and sk.points - p0 == 1000, "odcinek bez mnożnika serii (%d)" % (sk.points - p0))


## Wzorowy szeryf i zatrzymanie bota (użytkownik 2026-11-11).
func _test_sheriff() -> void:
	var sk := SK.new()
	sk.open_chase(1, "overtake", 0.0)
	var got := 0
	var t := 0.0
	# 4 min za graczem, potem bot wyprzedza - licznik od nowa.
	while t < 240.0:
		got += _sum(sk.chase_tick(1, 30.0, 0.5, 120.0, 125.0, 0.1, t))
		t += 0.1
	sk.chase_tick(1, -5.0, 2.0, 130.0, 120.0, 0.1, t)
	while t < 480.0:
		got += _sum(sk.chase_tick(1, 30.0, 0.5, 120.0, 125.0, 0.1, t))
		t += 0.1
	_check(got == 0, "bez szeryfa, gdy bot wyprzedził przed 5 min (%d)" % got)
	while t < 600.0:
		got += _sum(sk.chase_tick(1, 30.0, 0.5, 120.0, 125.0, 0.1, t))
		t += 0.1
	_check(got == SK.BASE["sheriff"], "szeryf po 5 min bez wyprzedzenia (%d)" % got)
	# Bot daleko (> 200 m) - czas nie leci, ale też nie zeruje.
	var sk2 := SK.new()
	sk2.open_chase(2, "overtake", 0.0)
	var g2 := 0
	for i in range(4000):
		g2 += _sum(sk2.chase_tick(2, 500.0, 0.5, 120.0, 125.0, 0.1, i * 0.1))
	_check(g2 == 0, "bot daleko - bez szeryfa")
	# Zatrzymanie: bot rozpędzony, potem oba stoją, bot tuż za graczem.
	var sk3 := SK.new()
	sk3.open_chase(3, "overtake", 0.0)
	sk3.chase_tick(3, 20.0, 0.5, 110.0, 100.0, 0.1, 1.0)
	var g3 := _sum(sk3.chase_tick(3, 8.0, 0.4, 2.0, 1.0, 0.1, 20.0))
	g3 += _sum(sk3.chase_tick(3, 8.0, 0.4, 1.0, 0.5, 0.1, 21.0))
	_check(g3 == SK.BASE["stopped"], "zatrzymanie bota - premia raz (%d)" % g3)
	var sk4 := SK.new()
	sk4.open_chase(4, "overtake", 0.0)
	_check(_sum(sk4.chase_tick(4, 8.0, 0.4, 2.0, 1.0, 0.1, 1.0)) == 0, "bez premii, gdy bot nie był rozpędzony")
