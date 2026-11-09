extends SceneTree
## Test logiki: reżyserowane potyczki botów na drugiej jezdni
## (OncomingSkirmish) - bez sceny i fizyki.
##   godot --headless --xr-mode off -s res://tests/oncoming_skirmish_test.gd </dev/null
## Sprawdza: każda scenka dobiega końca i wysyła swoje zdarzenia, auta nie
## przenikają się poza chwilami uderzeń (najszersza i najwęższa dozwolona jezdnia),
## pit obraca B, wrak chowa B po wybuchu, trigger_gap, losowanie.
## Kod wyjścia 1 przy błędzie.

const OS_ := preload("res://scripts/oncoming_skirmish.gd")
const DT := 1.0 / 90.0
const CAR_LEN := 4.6

var fails := 0


func _initialize() -> void:
	for k in OS_.SCENES:
		_test_scene(k)
	_test_pit_spin()
	_test_wreck()
	_test_trigger_gap()
	_test_random()
	_check(OS_.fits(14.8) and not OS_.fits(10.0), "fits: szeroka tak, wąska nie")
	print("oncoming_skirmish_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  BŁĄD: ", what)


## Przebieg całej scenki; zwraca zdarzenia z czasem.
func _run(sk) -> Array:
	var out := []
	var guard := 0
	while not sk.done and guard < 10000:
		for e in sk.step(DT):
			e["t"] = sk.t
			out.append(e)
		guard += 1
	return out


func _test_scene(kind: String) -> void:
	var sk = OS_.new(kind)
	var hits: Array = []
	for e in OS_.SCENES[kind]["events"]:
		if e[1] == "hit":
			hits.append(float(e[0]))
	var lw_min: float = (OS_.MIN_ROAD_W - 1.0) / 3.0  # jak lane_w w xr_main._oncoming_xf
	var worst := {4.6: INF, lw_min: INF}
	var guard := 0
	var evs := []
	while not sk.done and guard < 10000:
		for e in sk.step(DT):
			evs.append(e)
		guard += 1
		if bool(sk.state_b["hidden"]):
			continue
		var g: float = sk.gap
		if absf(g) >= CAR_LEN:
			continue
		var near_hit := false
		for h in hits:
			if absf(sk.t - float(h)) < 0.25:
				near_hit = true
		if near_hit:
			continue
		var dl: float = absf(float(sk.state_a["lane"]) - float(sk.state_b["lane"]))
		for lw in worst:
			worst[lw] = minf(worst[lw], dl * float(lw))
	_check(sk.done, "%s: scenka się kończy" % kind)
	_check(evs.size() == OS_.SCENES[kind]["events"].size(),
			"%s: wszystkie zdarzenia (%d/%d)" % [kind, evs.size(), OS_.SCENES[kind]["events"].size()])
	for lw in worst:
		_check(worst[lw] >= OS_.MIN_SEP,
				"%s: bez przenikania przy pasie %.1f m (min %.2f m)" % [kind, lw, worst[lw]])
	_check(is_equal_approx(sk.t, sk.duration()) or sk.t >= sk.duration(), "%s: czas do końca" % kind)
	_check(sk.step(DT).is_empty(), "%s: po końcu bez zdarzeń" % kind)


func _test_pit_spin() -> void:
	var sk = OS_.new("pit")
	_run(sk)
	var yaw: float = sk.state_b["yaw"]
	var v: float = sk.state_b["v"]
	_check(yaw > 150.0 and v < 0.05, "pit: B obrócony i stoi (yaw %.0f, v %.2f)" % [yaw, v])
	var g: float = sk.gap
	_check(g < -30.0, "pit: A odjeżdża przed B (gap %.1f)" % g)


func _test_wreck() -> void:
	var sk = OS_.new("wreck")
	var evs := _run(sk)
	var boom := evs.filter(func(e): return e["type"] == "boom")
	_check(boom.size() == 1 and boom[0]["car"] == "b", "wrak: jeden wybuch B")
	_check(bool(sk.state_b["hidden"]) and not bool(sk.state_a["hidden"]), "wrak: B schowany, A nie")


func _test_trigger_gap() -> void:
	var sk = OS_.new("cut")
	var g: float = sk.trigger_gap(70.0)
	_check(is_equal_approx(g, OS_.CLIMAX_DIST + 70.0 * float(sk.climax)), "trigger_gap (%.1f)" % g)
	_check(is_equal_approx(sk.trigger_gap(-5.0), OS_.CLIMAX_DIST), "trigger_gap bez ujemnej prędkości")


func _test_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 400:
		var sk = OS_.random(rng)
		seen[sk.kind] = int(seen.get(sk.kind, 0)) + 1
	_check(seen.size() == OS_.SCENES.size(), "losowanie: wszystkie scenki (%s)" % str(seen))
	_check(int(seen.get("wreck", 0)) < int(seen.get("cut", 0)), "losowanie: wrak rzadziej (%s)" % str(seen))
