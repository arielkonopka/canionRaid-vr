extends SceneTree
## Test kodu odcinka (SegmentCode): te same kody co tools/segment_code_sim.py,
## niezmienniki reżysera (odpoczynek co 3-5 odcinków, spokojny start,
## kalendarz, pułapka z budowlą/przekrojem, gramatyka, koszt na Queście),
## kolejność pytań bez znaczenia, pack/unpack. Bez sceny, sekundy.
##   godot --headless --xr-mode off -s res://tests/segment_code_test.gd -- [ziarno] </dev/null
## Wynik: "SEGMENT_CODE: OK" albo "SEGMENT_CODE: BŁĘDY n" (kod wyjścia 1).
## Liczby z Pythona: python3 tools/segment_code_sim.py 777 300

var errors := 0


func _fail(what: String) -> void:
	errors += 1
	if errors <= 30:
		print("  BŁĄD: ", what)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 777
	_python_twin()
	_invariants(SegmentCode.new(seed_v), 250, "bez pogody")
	_invariants(SegmentCode.new(seed_v, WeatherPlan.new(seed_v)), 250, "z pogodą")
	_order(seed_v)
	_pack()
	var sc := SegmentCode.new(seed_v)
	for k in [5, 11, 40, 120]:
		print("  ", sc.describe(k))
	print("SEGMENT_CODE: OK" if errors == 0 else "SEGMENT_CODE: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)


## Ziarno 777, odcinki 0-11: kody z Pythona (bez pogody).
func _python_twin() -> void:
	var expect := [0xA00FA840, 0x602FC8A8, 0x202FA000, 0x403FB058, 0xA01F00E0, 0xCC0FC808,
			0xE03F60F8, 0x690F9890, 0x202F3810, 0xEC3FA0B0, 0x803F70E0, 0xA06C58D0]
	var sc := SegmentCode.new(777)
	for k in expect.size():
		var c := int(sc.segment(k)["code"])
		if c != int(expect[k]):
			_fail("odcinek %d: 0x%08X, Python 0x%08X" % [k, c, expect[k]])
	if sc.phase(5) != SegmentCode.PEAK or int(sc.segment(5)["event"]) != 4:
		_fail("odcinek 5 nie jest szczytem z pościgiem: %s" % sc.segment(5))


func _invariants(sc: SegmentCode, n: int, label: String) -> void:
	var lies: Array[int] = []
	var run := 0
	var last_rest := -1
	var distinct := {}
	for k in n:
		var s := sc.segment(k)
		var km := k * SegmentCode.SEG_LEN / 1000.0
		var st := int(s["structure"])
		var se := int(s["section"])
		var tr := int(s["trap"])
		var ev := int(s["event"])
		distinct["%d/%d/%d/%d" % [st, se, tr, ev]] = true
		if s["phase"] == SegmentCode.REST and (tr != SegmentCode.TRAP_NONE or ev != 0):
			_fail("%s: odpoczynek z pułapką/zdarzeniem %d" % [label, k])
		if k < SegmentCode.FIRST_CALM and (st != 0 or se != 0 or tr != SegmentCode.TRAP_NONE or ev != 0):
			_fail("%s: urozmaicenie na starcie %d" % [label, k])
		if SegmentCode.UNLOCK_STRUCT[st] > km or SegmentCode.UNLOCK_SECTION[se] > km \
				or SegmentCode.UNLOCK_TRAP[tr] > km or SegmentCode.UNLOCK_EVENT[ev] > km:
			_fail("%s: przed kalendarzem %d: %s" % [label, k, s])
		if SegmentCode.TRAP_STRUCT.has(tr) and st != int(SegmentCode.TRAP_STRUCT[tr]):
			_fail("%s: pułapka %d bez budowli w %d" % [label, tr, k])
		if SegmentCode.TRAP_SECTION.has(tr) and se != int(SegmentCode.TRAP_SECTION[tr]):
			_fail("%s: pułapka %d bez przekroju w %d" % [label, tr, k])
		if tr == 1 and se != 7:
			_fail("%s: zwężenie za tunelem bez zwężenia w %d" % [label, k])
		if se == 1 and st != 4:
			_fail("%s: pas dla wolnych poza podjazdem %d" % [label, k])
		if k > 0 and int(s["cost"]) + int(sc.segment(k - 1)["cost"]) > SegmentCode.COST_MAX:
			_fail("%s: koszt %d" % [label, k])
		if st != 0 and st != 4:
			for j in range(maxi(0, k - SegmentCode.SAME_STRUCT_GAP + 1), k):
				if int(sc.segment(j)["structure"]) == st:
					_fail("%s: budowla %d w %d i %d" % [label, st, j, k])
		if tr == SegmentCode.TRAP_LIE:
			if not lies.is_empty() and k - lies[lies.size() - 1] < SegmentCode.LIE_GAP:
				_fail("%s: znak kłamie za często %d" % [label, k])
			lies.append(k)
		var c := int(s["code"])
		if c < 0 or c >> 32 != 0:
			_fail("%s: kod > 32 bity w %d" % [label, k])
		run = run + 1 if se in SegmentCode.NARROW else 0
		if run > SegmentCode.NARROW_MAX - 1:
			_fail("%s: za długo wąsko do %d" % [label, k])
		if s["phase"] == SegmentCode.REST and k >= SegmentCode.FIRST_CALM:
			if last_rest >= 0 and (k - last_rest < SegmentCode.GROUP_MIN or k - last_rest > SegmentCode.GROUP_MAX):
				_fail("%s: odpoczynek po %d odcinkach (%d)" % [label, k - last_rest, k])
			last_rest = k
	# Python (300 km, 4 ziarna): 176-189 różnych układów.
	if distinct.size() < 120:
		_fail("%s: mało różnych układów: %d" % [label, distinct.size()])
	print("  %s: różnych układów %d na %d odcinków" % [label, distinct.size(), n])


## Pytanie o daleki odcinek najpierw nie zmienia bliższych.
func _order(seed_v: int) -> void:
	var a := SegmentCode.new(seed_v)
	var b := SegmentCode.new(seed_v)
	b.at(200000.0)
	b.phase(90)
	for k in [0, 7, 40, 99, 166]:
		if int(a.segment(k)["code"]) != int(b.segment(k)["code"]):
			_fail("kolejność pytań zmienia odcinek %d" % k)
	if SegmentCode.index_at(-5.0) != 0 or SegmentCode.index_at(2399.0) != 1:
		_fail("index_at")


func _pack() -> void:
	var sc := SegmentCode.new(4242)
	for k in range(0, 250, 7):
		var s := sc.segment(k)
		var u := SegmentCode.unpack(int(s["code"]))
		for key in u:
			if int(u[key]) != int(s[key]):
				_fail("unpack %d: %s %d != %d" % [k, key, u[key], s[key]])
