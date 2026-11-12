extends SceneTree
## Logika wibracji (Haptics) bez gogli: zderzenie raz na kontakt, lądowanie,
## ABS w ręce hamulca, TCS w ręce gazu, pobocze, siła wg opcji, kierownica
## w powietrzu - tylko trzymające ręce.
##   godot --headless --xr-mode off -s res://tests/haptics_test.gd </dev/null

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _hands(pulses: Array) -> Array:
	var h := []
	for p in pulses:
		if not h.has(p[0]):
			h.append(p[0])
	h.sort()
	return h


func _initialize() -> void:
	var hp := Haptics.new()
	var base := {"speed": 30.0, "hit_j": 0.0, "hit_ms": 0, "abs": false, "tcs": false, "slip": 0.0,
			"rough": 0.0, "brake_hand": 0, "gas_hand": 1, "holding": []}
	_check(hp.step(0.1, base).is_empty(), "spokojna jazda - cisza")
	var s := base.duplicate()
	s["hit_j"] = 9000.0
	s["hit_ms"] = 1234
	var p := hp.step(0.1, s)
	_check(_hands(p) == [0, 1] and p[0][1] > 0.1, "zderzenie - obie ręce")
	_check(hp.step(0.1, s).is_empty(), "to samo zderzenie drugi raz - nic")
	hp.on_landed(9.0)
	p = hp.step(0.1, base)
	_check(_hands(p) == [0, 1], "lądowanie - obie ręce")
	s = base.duplicate()
	s["abs"] = true
	p = hp.step(0.1, s)
	_check(_hands(p) == [0], "ABS - ręka hamulca (lewa)")
	s = base.duplicate()
	s["tcs"] = true
	p = hp.step(0.1, s)
	_check(_hands(p) == [1], "kontrola trakcji - ręka gazu (prawa)")
	s = base.duplicate()
	s["rough"] = 1.0
	p = hp.step(0.1, s)
	_check(_hands(p) == [0, 1], "pobocze - obie ręce")
	# Kierownica w powietrzu: trzyma tylko prawa - ABS czuć w prawej.
	s = base.duplicate()
	s["abs"] = true
	s["holding"] = [false, true]
	p = hp.step(0.1, s)
	_check(_hands(p) == [1], "w powietrzu: ABS w trzymającej ręce")
	s["holding"] = [false, false]
	_check(hp.step(0.1, s).is_empty(), "w powietrzu, nic nie trzyma - cisza")
	# Siła.
	s = base.duplicate()
	s["abs"] = true
	hp.strength = 1.0
	var strong: float = hp.step(0.1, s)[0][1]
	hp.strength = 0.5
	var weak: float = hp.step(0.1, s)[0][1]
	_check(strong > weak * 1.9, "Mocne ~2x Słabe (%.2f / %.2f)" % [strong, weak])
	hp.strength = 0.0
	_check(hp.step(0.1, s).is_empty(), "Wył. - nic")
	print("haptics_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
