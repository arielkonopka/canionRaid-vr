extends SceneTree
## Test logiki bota "ekstremista" (ExtremistBrain) - bez sceny.
##   godot --headless --xr-mode off -s res://tests/extremist_test.gd </dev/null
## Kod wyjścia 1 przy błędzie.

const EB := preload("res://scripts/extremist_brain.gd")
const DT := 1.0 / 60.0
const V := 70.0                          # ~250 km/h

var fails := 0


func _initialize() -> void:
	_test_ttc()
	_test_lane_choice()
	_test_shoulder_and_ram()
	_test_horn_and_beams()
	_test_throttle_modes()
	_test_v_safe()
	_test_helpers()
	print("extremist_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  BŁĄD: ", what)


func _free() -> Dictionary:
	return {"gap": INF, "v": 0.0}


func _car(gap: float, v: float) -> Dictionary:
	return {"gap": gap, "v": v}


## Kroki przez `sec` sekund przy stałej sytuacji; zwraca ostatni wynik.
func _run(b, sec: float, ctx: Dictionary) -> Dictionary:
	var r := {}
	for i in int(sec / DT):
		r = b.step(DT, ctx)
	return r


func _test_ttc() -> void:
	_check(EB.ttc(V, _free()) == INF, "wolny pas - INF")
	_check(EB.ttc(V, _car(3.0, 90.0)) == 0.0, "auto obok - pas zajęty")
	_check(EB.ttc(V, _car(100.0, 80.0)) == INF, "szybszy przed nim - INF")
	_check(absf(EB.ttc(V, _car(100.0, 30.0)) - 2.5) < 0.01, "100 m, różnica 40 m/s = 2,5 s")


func _test_lane_choice() -> void:
	var b = EB.new()
	# Wolna droga: zostaje na lewym.
	var r := _run(b, 1.0, {"v": V, "lanes": [_free(), _free()]})
	_check(r["lane"] == EB.PREF_LANE, "wolna droga - lewy pas")
	_check(r["throttle"] == 1.0 and r["brake"] == 0.0, "wolna droga - pełny gaz")
	# Wolniejsze auto na lewym blisko: zjeżdża na prawy.
	r = _run(b, 0.2, {"v": V, "lanes": [_free(), _car(90.0, 33.0)]})
	_check(r["lane"] == 0, "auto na lewym (TTC ~2,4 s) - zmiana na prawy")
	# Zaraz potem lewy wolny: nie skacze z powrotem przed LANE_HOLD.
	r = b.step(DT, {"v": V, "lanes": [_free(), _free()]})
	_check(r["lane"] == 0, "bez szarpania - trzyma pas przez LANE_HOLD")
	r = _run(b, EB.LANE_HOLD + 0.1, {"v": V, "lanes": [_free(), _free()]})
	_check(r["lane"] == EB.PREF_LANE, "po chwili wraca na lewy")
	# Auto daleko (TTC > SWITCH_TTC): nie zmienia pasa, tylko trąbi/mruga.
	var b2 = EB.new()
	r = _run(b2, 0.5, {"v": V, "lanes": [_free(), _car(200.0, 30.0)]})
	_check(r["lane"] == EB.PREF_LANE, "TTC 5 s - jeszcze bez zmiany pasu")
	# Ktoś obok na prawym: nie wjeżdża w niego, choć na lewym zagrożenie.
	var b3 = EB.new()
	r = _run(b3, 0.3, {"v": V, "lanes": [_car(2.0, V), _car(80.0, 30.0)]})
	_check(r["lane"] == EB.PREF_LANE, "auto obok na prawym - zostaje")


func _test_shoulder_and_ram() -> void:
	# Oba pasy zablokowane, TTC < SHOULDER_TTC, pobocze wolne: pobocze.
	var b = EB.new()
	var blocked := {"v": V, "lanes": [_car(50.0, 25.0), _car(50.0, 25.0)], "shoulder": _free()}
	var r: Dictionary = b.step(DT, blocked)
	_check(r["lane"] == EB.SHOULDER, "oba pasy zatkane - pobocze")
	_check(r["brake"] == 0.0 and r["throttle"] == 1.0, "nawet wtedy nie hamuje")
	# Bez pobocza: zostaje i taranuje (nie hamuje).
	var b2 = EB.new()
	r = _run(b2, 0.5, {"v": V, "lanes": [_car(50.0, 25.0), _car(50.0, 25.0)]})
	_check(r["lane"] == EB.PREF_LANE and r["brake"] == 0.0, "bez wyjścia - taran, bez hamulca")
	_check(r["horn"] == true, "przed taranem klakson ciągły")
	# Z pobocza wraca na wolny pas.
	r = _run(b, EB.LANE_HOLD + 0.1, {"v": V, "lanes": [_free(), _car(30.0, 40.0)], "shoulder": _free()})
	_check(r["lane"] == 0, "z pobocza na wolny prawy pas")


func _test_horn_and_beams() -> void:
	var b = EB.new()
	var ctx := {"v": V, "lanes": [_car(140.0, 30.0), _free()]}   # auto na prawym, ma lewy
	var horn_on := 0
	var beam_on := 0
	var n := int(EB.HORN_PERIOD * 5.0 / DT)
	for i in n:
		var r: Dictionary = b.step(DT, ctx)
		horn_on += 1 if r["horn"] else 0
		beam_on += 1 if r["beam"] > 0.5 else 0
	var hf := float(horn_on) / n
	var bf := float(beam_on) / n
	_check(hf > 0.3 and hf < 0.55, "trąbi seriami na auto na drugim pasie (%.2f)" % hf)
	_check(bf > 0.2 and bf < 0.4, "mruga długimi dwa razy na okres (%.2f)" % bf)
	var r2 := _run(EB.new(), 1.0, {"v": V, "lanes": [_free(), _free()]})
	_check(not r2["horn"] and r2["beam"] == 0.0, "pusta droga - cisza i zwykłe światła")
	var r3 := _run(EB.new(), 1.0, {"v": V, "lanes": [_free(), _car(120.0, 90.0)]})
	_check(not r3["horn"], "auto szybsze od niego - nie trąbi")
	var r4 := _run(EB.new(), 1.0, {"v": V, "lanes": [_car(230.0, 30.0), _free()]})
	_check(not r4["horn"], "230 m - jeszcze nie trąbi")


func _test_throttle_modes() -> void:
	var ctx := {"v": 60.0, "lanes": [_free(), _free()], "v_safe": 50.0}
	var lift = EB.new()
	var r: Dictionary = lift.step(DT, ctx)
	_check(r["throttle"] == 0.0 and r["brake"] == 0.0, "lift: za szybko na łuk - odpuszcza gaz, nie hamuje")
	ctx["v"] = 49.5
	r = lift.step(DT, ctx)
	_check(r["throttle"] == 0.0, "lift: histereza (49,5 > 98% v_safe)")
	ctx["v"] = 48.0
	r = lift.step(DT, ctx)
	_check(r["throttle"] == 1.0, "lift: poniżej 98% - znów gaz")
	var nev = EB.new()
	nev.curve_mode = EB.MODE_NEVER
	r = nev.step(DT, {"v": 60.0, "lanes": [_free(), _free()], "v_safe": 30.0})
	_check(r["throttle"] == 1.0 and r["brake"] == 0.0, "never: pełny gaz zawsze")
	var cur = EB.new()
	cur.curve_mode = EB.MODE_CURVES
	r = cur.step(DT, {"v": 60.0, "lanes": [_free(), _free()], "v_safe": 50.0})
	_check(r["brake"] > 0.0, "curves: hamuje przed łukiem")
	r = cur.step(DT, {"v": 60.0, "lanes": [_free(), _car(60.0, 10.0)], "v_safe": INF})
	_check(r["brake"] == 0.0, "curves: przed autem nie hamuje")


func _test_v_safe() -> void:
	# Prosta, potem łuk o vc²(0,7 g) = 900 (30 m/s) za 200 m.
	var prof := PackedFloat32Array()
	for d in range(0, 400, 4):
		var vc2 := INF if d < 200 else 900.0
		prof.append_array([float(d), 1.0e4, INF, vc2])
	var at_curve: float = EB.v_safe_from_profile(prof, 200.0, EB.DECEL_LIFT)
	var want := sqrt(900.0 * EB.CURVE_G / 0.7)
	_check(absf(at_curve - want) < 0.5, "w łuku: vc przy CURVE_G (%.1f ~ %.1f)" % [at_curve, want])
	var before: float = EB.v_safe_from_profile(prof, 0.0, EB.DECEL_LIFT)
	_check(before > at_curve + 10.0, "200 m przed łukiem wolno więcej (%.1f)" % before)
	var brake: float = EB.v_safe_from_profile(prof, 0.0, EB.DECEL_BRAKE)
	_check(brake > before, "z hamowaniem później zwalnia (%.1f > %.1f)" % [brake, before])
	_check(EB.v_safe_from_profile(PackedFloat32Array(), 0.0, 2.5) == INF, "pusty profil - INF")


func _test_helpers() -> void:
	_check(EB.engine_kw(100.0) == EB.MIN_POWER_KW, "słaby gracz - minimum mocy")
	_check(absf(EB.engine_kw(500.0) - 650.0) < 0.01, "mocny gracz - 1,3 x")
	_check(EB.pass_points(0.5) > EB.pass_points(2.0) and EB.pass_points(2.0) > EB.pass_points(3.5), "bliżej = więcej punktów")
	_check(EB.pass_points(5.0) == 0, "daleko - bez punktów")
	_check(EB.spawn_chance_per_km(1.0) == 0.0, "pierwsze 3 km bez ekstremisty")
	_check(EB.spawn_chance_per_km(10.0) > EB.spawn_chance_per_km(4.0), "częściej z dystansem")
	_check(EB.spawn_chance_per_km(500.0) <= 0.6, "górny limit szansy")
