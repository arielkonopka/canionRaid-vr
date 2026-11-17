extends SceneTree
## Test pułapek (TrapPlan): te same pułapki co tools/trap_plan_sim.py,
## pułapka tylko przy swojej budowli / przekroju, nic w odpoczynku, łuk
## i plama na prostej, drzewa poza jezdnią, porywy w granicach, znak
## kłamie rzadko, drabina zapowiedzi. Bez sceny, sekundy.
##   godot --headless --xr-mode off -s res://tests/trap_plan_test.gd -- [ziarno] </dev/null
## Wynik: "TRAP_PLAN: OK" albo "TRAP_PLAN: BŁĘDY n" (kod wyjścia 1).
## Liczby z Pythona: python3 tools/trap_plan_sim.py 777 300

var errors := 0


func _fail(what: String) -> void:
	errors += 1
	if errors <= 30:
		print("  BŁĄD: ", what)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 777
	_python_twin()
	var code := SegmentCode.new(seed_v)
	_invariants(TrapPlan.new(code, StructurePlan.new(code), SectionPlan.new(code)), 300000.0, "bez planu")
	var plan := HighwayPlan.new(seed_v)
	var code2 := SegmentCode.new(seed_v)
	var st := StructurePlan.new(code2, plan)
	var sec := SectionPlan.new(code2, plan)
	sec.structures = st
	_invariants(TrapPlan.new(code2, st, sec), 300000.0, "z planem")
	print("TRAP_PLAN: OK" if errors == 0 else "TRAP_PLAN: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)


func _python_twin() -> void:
	var code := SegmentCode.new(777)
	var tp := TrapPlan.new(code, StructurePlan.new(code), SectionPlan.new(code))
	var expect := [[11, 12, 1, 13950.0], [12, 0, 1, 14850.0], [26, 6, 1, 30200.0],
			[48, 12, 0, 57750.0], [49, 11, 1, 59000.0], [51, 10, 1, 61400.0]]
	var trs := tp.traps(0.0, 150000.0)
	for i in expect.size():
		var e: Array = expect[i]
		if i >= trs.size():
			_fail("brak pułapki %s" % [e])
			continue
		var tr: Dictionary = trs[i]
		if int(tr["k"]) != int(e[0]) or int(tr["trap"]) != int(e[1]) or int(tr["level"]) != int(e[2]) \
				or absf(float(tr["d"]) - float(e[3])) > 0.01:
			_fail("pułapka %d: %s, Python %s" % [i, tr, e])
	if trs.size() > 1 and (absf(float(trs[1]["r_end"]) - 245.0) > 0.01 or int(trs[1]["dir"]) != -1):
		_fail("łuk k 12: %s" % trs[1])
	if tp.items(0.0, 150000.0).size() != 321:
		_fail("elementów do 150 km: %d, Python 321" % tp.items(0.0, 150000.0).size())
	if absf(tp.gust(59350.0, 3.0) - (-1.89213)) > 0.001:
		_fail("poryw k 49: %f, Python -1.89213" % tp.gust(59350.0, 3.0))
	var s := tp.surface_at(13955.0)
	if String(s.get("kind", "")) != "ruts" or absf(float(s.get("grip", 0.0)) - 0.75) > 0.001:
		_fail("plama k 11: %s" % s)


func _invariants(tp: TrapPlan, d1: float, label: String) -> void:
	var trs := tp.traps(0.0, d1)
	var kinds := {}
	var lies: Array[int] = []
	for tr in trs:
		var k := int(tr["k"])
		var t := int(tr["trap"])
		kinds[t] = true
		if String(tp.code.segment(k)["phase"]) == SegmentCode.REST:
			_fail("%s: pułapka w odpoczynku %s" % [label, tr])
		if not (t in TrapPlan.HANDLED):
			_fail("%s: pułapka spoza 4a %s" % [label, tr])
		if (t == 0 or t == 14) and tp._busy(float(tr["d"]) - TrapPlan.STRAIGHT_BEFORE, float(tr["d"]) + 500.0):
			_fail("%s: łuk bez prostej %s" % [label, tr])
		var need := {1: 1, 7: 3, 10: 2, 11: 6}
		if need.has(t):
			var ok := false
			for z in tp.structures.zones(float(tr["d"]) - 1.0, float(tr["d"]) + 1.0):
				if int(z["structure"]) == int(need[t]):
					ok = true
			if not ok:
				_fail("%s: pułapka %d bez budowli %s" % [label, t, tr])
		if t == 14:
			if not lies.is_empty() and k - lies[lies.size() - 1] < SegmentCode.LIE_GAP:
				_fail("%s: znak kłamie za często %d" % [label, k])
			lies.append(k)
		if t == 11:
			for i in 100:
				if absf(tp.gust((float(tr["d"]) + float(tr["end"])) * 0.5, float(i) * 0.37)) > float(tr["gust"]) + 0.001:
					_fail("%s: poryw ponad limit %s" % [label, tr])
					break
		# Drabina: poziom 3 - znak późno (SIGN_AT_3 = true, decyzja użytkownika
		# 2026-11-17: "zawsze znak, najwyżej późno") albo bez znaku (false).
		if int(tr["level"]) == 3 and t != 14:
			var signs := 0
			for it in tp._items(tr):
				if String(it["kind"]).begins_with("A-") or String(it["kind"]).begins_with("B-"):
					signs += 1
			if not TrapPlan.SIGN_AT_3 and signs > 0:
				_fail("%s: znak na poziomie 3 %s" % [label, tr])
			var has_sign: bool = t == 0 or String(TrapPlan.SIGN.get(t, "")) != ""
			if TrapPlan.SIGN_AT_3 and has_sign and signs == 0:
				_fail("%s: poziom 3 bez znaku %s" % [label, tr])
	for it in tp.items(0.0, d1):
		if String(it["kind"]) == "tree" and absf(float(it["x"])) < 4.7:
			_fail("%s: drzewo na jezdni %s" % [label, it])
	print("  %s: pułapek %d, rodzaje %s" % [label, trs.size(), kinds.keys()])
