extends SceneTree
## Test logiki waśni między botami (FeudDirector) - bez sceny.
##   godot --headless --xr-mode off -s res://tests/feud_test.gd </dev/null
## Kod wyjścia 1 przy błędzie.

const FD := preload("res://scripts/feud_director.gd")
const A := 101
const B := 202
const C := 303

var fails := 0


func _initialize() -> void:
	_test_contact_feud()
	_test_alliance()
	_test_provocation_and_wreck()
	_test_chances()
	print("feud_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  BŁĄD: ", what)


## A (gang 1) i B (gang 2) to wrogowie, C (gang 1) kolega A.
func _make():
	var fd = FD.new()
	fd.rng.seed = 7
	fd.add_bot(A, 1)
	fd.add_bot(B, 2)
	fd.add_bot(C, 1)
	fd.set_hostile(1, 2, true)
	return fd


func _test_contact_feud() -> void:
	var fd = _make()
	_check(fd.on_contact(A, B, 0.0, false).is_empty(), "poza wzrokiem gracza - bez potyczki")
	var ev: Array = fd.on_contact(A, B, 1.0, true)
	_check(ev.size() == 2 and ev[0]["kind"] == "skirmish", "zderzenie wrogów = potyczka")
	_check(fd.target_of(A) == B and fd.target_of(B) == A, "cele: nawzajem")
	_check(fd.on_contact(A, C, 2.0, true).is_empty(), "ten sam gang - bez potyczki")
	var end: Array = fd.update(1.0 + FD.FEUD_TIMEOUT + 0.1)
	_check(end.size() == 2 and fd.target_of(A) == FD.NONE, "potyczka gaśnie po czasie")


func _test_alliance() -> void:
	var fd = _make()
	fd.on_contact(A, B, 1.0, true)
	var ev: Array = fd.on_contact(FD.PLAYER, A, 2.0, true)
	_check(ev.size() == 1 and ev[0]["kind"] == "alliance", "atak gracza na bota w potyczce = sojusz")
	_check(fd.target_of(A) == FD.PLAYER and fd.target_of(B) == FD.PLAYER, "obaj na gracza")
	_check(fd.allied(1, 2, 3.0) and not fd.hostile(A, B, 3.0), "gangi w sojuszu")
	_check(fd.on_contact(A, B, 4.0, true).is_empty(), "sojusznicy nie walczą")
	_check(not fd.allied(1, 2, 2.0 + FD.ALLIANCE_TIME + 0.1), "sojusz wygasa")
	fd.calm(A)
	fd.calm(B)
	var again: Array = fd.on_contact(A, B, 2.0 + FD.ALLIANCE_TIME + 1.0, true)
	_check(again.size() == 2, "po sojuszu znów wrogowie")
	# Uderzenie bota spoza potyczki: bez sojuszu, cel prowadzi BotDriver.
	var fd2 = _make()
	_check(fd2.on_contact(FD.PLAYER, C, 1.0, true).is_empty() and fd2.target_of(C) == FD.NONE,
			"zwykłe uderzenie - bez sojuszu")


func _test_provocation_and_wreck() -> void:
	var fd = _make()
	fd.on_contact(FD.PLAYER, A, 10.0, true)          # gracz pcha A...
	var ev: Array = fd.on_contact(A, B, 11.0, true)  # ...w B
	_check(ev.size() == 2 and bool(ev[0]["provoked"]) and int(ev[0]["points"]) > 0,
			"prowokacja: punkty za wywołanie potyczki")
	var w: Array = fd.remove_bot(B, 20.0, true)
	var kinds := w.map(func(e): return e["kind"])
	_check("feud_wreck" in kinds and "feud_end" in kinds, "wrak w potyczce + koniec dla A (%s)" % str(kinds))
	for e in w:
		if e["kind"] == "feud_wreck":
			_check(bool(e["provoked"]) and int(e["points"]) == FD.POINTS["feud_wreck"], "punkty za wrak z prowokacji")
	_check(fd.target_of(A) == FD.NONE, "A bez celu po wraku B")
	var fd2 = _make()
	fd2.on_contact(A, B, 1.0, true)
	var w2: Array = fd2.remove_bot(B, 5.0, true)
	for e in w2:
		if e["kind"] == "feud_wreck":
			_check(int(e["points"]) == 0, "wrak bez prowokacji - bez punktów")


func _test_chances() -> void:
	var hits := 0
	for i in 400:
		var fd = _make()
		fd.rng.seed = i
		if not fd.on_overtake(A, B, 0.0, true).is_empty():
			hits += 1
	_check(hits > 150 and hits < 250, "wyprzedzenie: ~50%% (%d/400)" % hits)
	var fd = _make()
	_check(fd.on_overtake(A, B, 0.0, false).is_empty(), "wyprzedzenie poza wzrokiem - nic")
	fd.set_hostile(1, 2, false)
	var none := 0
	for i in 200:
		none += fd.on_overtake(A, B, 0.0, true).size()
	_check(none == 0, "neutralni nie wpadają w szał po wyprzedzeniu")
	var sparks := 0
	var fd3 = _make()
	for i in 1000:
		fd3.calm(A)
		fd3.calm(B)
		if not fd3.on_near(A, B, 1.0, 0.0, true).is_empty():
			sparks += 1
	_check(sparks > 40 and sparks < 130, "iskra obok siebie ~8%%/s (%d/1000)" % sparks)
	var lo = FD.new()
	var hi = FD.new()
	var lo_n := 0
	var hi_n := 0
	var gangs := [1, 2, 3, 4, 5, 6, 7, 8]
	for s in 50:
		lo.rng.seed = s
		hi.rng.seed = s
		lo.roll_relations(gangs, 1)
		hi.roll_relations(gangs, 40)
		lo_n += lo._hostile.size()
		hi_n += hi._hostile.size()
	_check(hi_n > lo_n, "więcej wrogości na dalszych odcinkach (%d < %d)" % [lo_n, hi_n])
