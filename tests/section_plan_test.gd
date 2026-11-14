extends SceneTree
## Test przekrojów (SectionPlan): te same strefy co tools/section_plan_sim.py,
## pasy bez skoków, pachołki poza otwartymi pasami, ograniczenia ze
## znacznikami, strefy z HighwayPlan omijają miasta/stacje/skocznie.
## Bez sceny, sekundy.
##   godot --headless --xr-mode off -s res://tests/section_plan_test.gd -- [ziarno] </dev/null
## Wynik: "SECTION_PLAN: OK" albo "SECTION_PLAN: BŁĘDY n" (kod wyjścia 1).
## Liczby z Pythona: python3 tools/section_plan_sim.py 777 300

var errors := 0


func _fail(what: String) -> void:
	errors += 1
	if errors <= 30:
		print("  BŁĄD: ", what)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 777
	_python_twin()
	_invariants(SectionPlan.new(SegmentCode.new(seed_v)), 300000.0, "bez planu")
	var plan := HighwayPlan.new(seed_v)
	var sp := SectionPlan.new(SegmentCode.new(seed_v), plan)
	_invariants(sp, 300000.0, "z planem")
	_blocked(sp, plan, 300000.0)
	print("SECTION_PLAN: OK" if errors == 0 else "SECTION_PLAN: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)


## Ziarno 777 bez planu: strefy, pasy i elementy jak w Pythonie.
func _python_twin() -> void:
	var sp := SectionPlan.new(SegmentCode.new(777))
	var expect := [[36, 4, 43200.0, 45300.0], [62, 6, 75000.0, 75600.0], [64, 4, 77400.0, 80100.0],
			[68, 4, 81900.0, 83400.0], [73, 2, 88200.0, 89100.0], [74, 6, 89600.0, 90900.0]]
	var zs := sp.zones(0.0, 100000.0)
	for i in expect.size():
		var e: Array = expect[i]
		if i >= zs.size():
			_fail("brak strefy %s" % [e])
			continue
		var z: Dictionary = zs[i]
		if int(z["k"]) != int(e[0]) or int(z["section"]) != int(e[1]) \
				or absf(float(z["start"]) - float(e[2])) > 0.01 or absf(float(z["end"]) - float(e[3])) > 0.01:
			_fail("strefa %d: %s, Python %s" % [i, z, e])
	var n := sp.items(0.0, 100000.0).size()
	if n != 341:
		_fail("elementów do 100 km: %d, Python 341" % n)
	var l := sp.lanes_at(44000.0)
	if not (_same(l["fwd"], [1.75]) and _same(l["onc"], [-1.75]) and is_equal_approx(float(l["width"]), 8.0)
			and bool(l["single"]) and bool(l["other_closed"])):
		_fail("1+1 na 44 km: %s" % l)
	l = sp.lanes_at(75300.0)
	if not (_same(l["fwd"], [0.75]) and _same(l["onc"], [-3.0])):
		_fail("roboty na 75,3 km: %s" % l)
	if sp.limit_at(75300.0) != 80.0 or sp.limit_at(74700.0) != 100.0 or sp.limit_at(74500.0) != 140.0:
		_fail("stopniowanie ograniczenia przed robotami")
	var marks := sp.limit_marks(0.0, 100000.0)
	if marks.size() != 18 or absf(float(marks[0][0]) - 42800.0) > 0.01 or float(marks[0][1]) != 100.0:
		_fail("znaczniki ograniczeń: %d, pierwszy %s (Python 18, [42800, 100])" % [marks.size(), marks[0] if marks.size() > 0 else []])


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(float(a[i]) - float(b[i])) > 0.001:
			return false
	return true


func _invariants(sp: SectionPlan, d1: float, label: String) -> void:
	var zs := sp.zones(0.0, d1)
	var prev_end := -1e9
	var kinds := {}
	for z in zs:
		kinds[int(z["section"])] = true
		if float(z["start"]) - SectionPlan.WARN < prev_end:
			_fail("%s: zapowiedź w poprzedniej strefie %s" % [label, z])
		prev_end = float(z["end"])
	var prev := {}
	var d := 0.0
	while d < d1:
		var l := sp.lanes_at(d)
		var fwd: Array = l["fwd"]
		if fwd.is_empty():
			_fail("%s: brak pasa w naszą stronę na %.0f m" % [label, d])
		if not is_nan(float(l["closing"])) and float(l["closing"]) in fwd:
			_fail("%s: zamykany pas otwarty na %.0f m" % [label, d])
		if not prev.is_empty():
			var pf: Array = prev["fwd"]
			if pf.size() == fwd.size():
				for i in fwd.size():
					if absf(float(pf[i]) - float(fwd[i])) > 0.1:
						_fail("%s: skok pasa na %.0f m" % [label, d])
			if absf(float(prev["width"]) - float(l["width"])) > 0.1:
				_fail("%s: skok szerokości na %.0f m" % [label, d])
		for x in fwd + (l["onc"] as Array):
			if absf(float(x)) > float(l["width"]) * 0.5 - 1.5:
				_fail("%s: pas %.2f poza jezdnią %.2f na %.0f m" % [label, x, l["width"], d])
		var z := sp.zone_at(d)
		if not z.is_empty() and sp.limit_at(d) != float(z["limit"]):
			_fail("%s: ograniczenie %.0f w strefie na %.0f m" % [label, sp.limit_at(d), d])
		prev = l
		d += 2.0
	for it in sp.items(0.0, d1):
		if String(it["kind"]) != "cone" or sp.zone_at(float(it["d"])).is_empty():
			continue
		for x in sp.lanes_at(float(it["d"]))["fwd"]:
			if absf(float(it["x"]) - float(x)) < 1.2:
				_fail("%s: pachołek na otwartym pasie %.0f m" % [label, it["d"]])
	for m in sp.limit_marks(0.0, d1):
		if sp.limit_at(float(m[0]) - 0.5) == sp.limit_at(float(m[0]) + 0.5):
			_fail("%s: znacznik bez zmiany ograniczenia %s" % [label, m])
	print("  %s: stref %d, rodzaje %s" % [label, zs.size(), kinds.keys()])


## Z planem trasy strefy nie wchodzą w miasta, stacje, warsztaty, skocznie.
func _blocked(sp: SectionPlan, plan: HighwayPlan, d1: float) -> void:
	for z in sp.zones(0.0, d1):
		var a := float(z["start"]) - SectionPlan.WARN
		var b := float(z["end"]) + SectionPlan.CLEAR_AFTER
		var d := a
		while d < b:
			if plan.limit_at(d) < HighwayPlan.LIMIT_HIGHWAY:
				_fail("strefa %d w mieście na %.0f m" % [z["k"], d])
				break
			d += 50.0
		if not (plan.stations_between(a, b).is_empty() and plan.workshops_between(a, b).is_empty()
				and plan.jumps_between(a, b).is_empty()):
			_fail("strefa %d na stacji/warsztacie/skoczni" % z["k"])
