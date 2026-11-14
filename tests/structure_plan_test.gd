extends SceneTree
## Test budowli (StructurePlan): te same strefy i wysokości co
## tools/structure_plan_sim.py, profil bez skoków pochylenia, płaskie
## budowle poziomo, teren pod jezdnią, filary, kolejność pytań, wersja
## płaska, biomy i miasta z HighwayPlan. Bez sceny, sekundy.
##   godot --headless --xr-mode off -s res://tests/structure_plan_test.gd -- [ziarno] </dev/null
## Wynik: "STRUCTURE_PLAN: OK" albo "STRUCTURE_PLAN: BŁĘDY n" (kod wyjścia 1).
## Liczby z Pythona: python3 tools/structure_plan_sim.py 777 300

var errors := 0


func _fail(what: String) -> void:
	errors += 1
	if errors <= 30:
		print("  BŁĄD: ", what)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 777
	_python_twin()
	_invariants(StructurePlan.new(SegmentCode.new(seed_v)), 300000.0, "bez planu")
	_invariants(StructurePlan.new(SegmentCode.new(seed_v), null, false), 300000.0, "płasko")
	var plan := HighwayPlan.new(seed_v)
	var sp := StructurePlan.new(SegmentCode.new(seed_v), plan)
	_invariants(sp, 300000.0, "z planem")
	_with_plan(sp, plan, 300000.0)
	_order(seed_v)
	print("STRUCTURE_PLAN: OK" if errors == 0 else "STRUCTURE_PLAN: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)


func _python_twin() -> void:
	var sp := StructurePlan.new(SegmentCode.new(777))
	var expect := [[18, 2, 21800.0, 22320.0, 0.0], [19, 4, 23000.0, 24200.0, 0.0],
			[23, 4, 27800.0, 30200.0, 0.0], [27, 2, 32600.0, 32970.0, 85.4],
			[30, 3, 36200.0, 36214.0, 23.6], [34, 1, 41000.0, 41400.0, 0.0]]
	var zs := sp.zones(0.0, 100000.0)
	for i in expect.size():
		var e: Array = expect[i]
		if i >= zs.size():
			_fail("brak budowli %s" % [e])
			continue
		var z: Dictionary = zs[i]
		if int(z["k"]) != int(e[0]) or int(z["structure"]) != int(e[1]) or absf(float(z["start"]) - float(e[2])) > 0.01 \
				or absf(float(z["end"]) - float(e[3])) > 0.01 or absf(float(z["h"]) - float(e[4])) > 0.01:
			_fail("budowla %d: %s, Python %s" % [i, z, e])
	for c in [[23600.0, 30.0, 0.05], [29000.0, 66.0, 0.055], [32800.0, 85.4, 0.0], [50000.0, 0.0, 0.0]]:
		if absf(sp.height_at(c[0]) - float(c[1])) > 0.01 or absf(sp.grade_at(c[0]) - float(c[2])) > 0.0005:
			_fail("wysokość na %.0f m: %.3f / %.4f, Python %s" % [c[0], sp.height_at(c[0]), sp.grade_at(c[0]), c])
	var g := sp.ground_at(32800.0)
	if not bool(g["water"]) or absf(float(g["y"]) - 70.4) > 0.01:
		_fail("rzeka pod mostem na 32,8 km: %s" % g)
	if sp.piers(0.0, 100000.0).size() != 125:
		_fail("filarów do 100 km: %d, Python 125" % sp.piers(0.0, 100000.0).size())


func _invariants(sp: StructurePlan, d1: float, label: String) -> void:
	var zs := sp.zones(0.0, d1)
	var prev := -1e9
	var kinds := {}
	for z in zs:
		kinds[int(z["structure"])] = true
		if float(z["start"]) < prev + StructurePlan.GAP - 0.001:
			_fail("%s: budowle za blisko %s" % [label, z])
		prev = float(z["end"])
		if not sp.slopes and int(z["structure"]) in [4, 5]:
			_fail("%s: podjazd przy płaskiej drodze" % label)
	var d := 0.0
	var hp := sp.height_at(0.0)
	var gp := 0.0
	var h_max := 0.0
	while d < d1:
		var h := sp.height_at(d)
		h_max = maxf(h_max, h)
		if h < -0.001 or h > StructurePlan.H_MAX + 0.001:
			_fail("%s: wysokość %.1f na %.0f m" % [label, h, d])
		var g := (h - hp) / 5.0
		if d > 0.0 and absf(g) > 0.08 + 0.0001:
			_fail("%s: pochylenie %.1f%% na %.0f m" % [label, g * 100.0, d])
		if d > 5.0 and absf(g - gp) > 0.004:
			_fail("%s: skok pochylenia na %.0f m" % [label, d])
		if not sp.slopes and absf(h) > 0.001:
			_fail("%s: płasko, a wysokość %.1f" % [label, h])
		var z := sp.zone_at(d)
		if not z.is_empty() and int(z["structure"]) in [1, 2, 3, 6]:
			var u := d - float(z["start"])
			if absf(sp.height_at(float(z["start"])) - h) > 0.05 and u > StructurePlan.VC_MIN \
					and u < float(z["length"]) - StructurePlan.VC_MIN:
				_fail("%s: budowla %d nie jest pozioma na %.0f m" % [label, z["structure"], d])
		if float(sp.ground_at(d)["y"]) > h + 0.001:
			_fail("%s: teren nad jezdnią na %.0f m" % [label, d])
		hp = h
		gp = g
		d += 5.0
	for p in sp.piers(0.0, d1):
		if float(p["top"]) - float(p["bottom"]) < StructurePlan.PIER_MIN:
			_fail("%s: filar za niski %s" % [label, p])
	print("  %s: budowli %d, rodzaje %s, wysokość max %.0f m" % [label, zs.size(), kinds.keys(), h_max])


func _with_plan(sp: StructurePlan, plan: HighwayPlan, d1: float) -> void:
	for z in sp.zones(0.0, d1):
		var st := int(z["structure"])
		var a := float(z["start"])
		var b := float(z["end"])
		for dd in [a, (a + b) * 0.5, b]:
			if not (st in StructurePlan.BIOME_OK[plan.biome_at(dd)]):
				_fail("budowla %d w biomie %s na %.0f m" % [st, plan.biome_at(dd), dd])
		var d := a
		while d < b:
			if plan.limit_at(d) < HighwayPlan.LIMIT_HIGHWAY:
				_fail("budowla %d w mieście na %.0f m" % [st, d])
				break
			d += 50.0


## Pytanie o daleki punkt najpierw nie zmienia bliższych.
func _order(seed_v: int) -> void:
	var a := StructurePlan.new(SegmentCode.new(seed_v))
	var b := StructurePlan.new(SegmentCode.new(seed_v))
	b.height_at(250000.0)
	for d in [1000.0, 23600.0, 61234.0, 150000.0, 249000.0]:
		if absf(a.height_at(d) - b.height_at(d)) > 1e-6:
			_fail("kolejność pytań zmienia wysokość na %.0f m" % d)
	var za := a.zones(0.0, 200000.0)
	var zb := b.zones(0.0, 200000.0)
	if za.size() != zb.size():
		_fail("kolejność pytań zmienia budowle")
