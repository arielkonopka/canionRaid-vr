extends RefCounted
class_name TrapPlan

## Pułapki złej inżynierii ruchu z kodu odcinka (bajt b2 SegmentCode) - etap 4
## urozmaiceń (zlecenie: docs/agent/inbox/2026-11-16-etap4-pulapki.md).
##
## Czysta logika jak StructurePlan / SectionPlan: gdzie jest pułapka, jak
## silna i jak zapowiedziana - funkcja ziarna i dystansu, bez sceny.
## Odpowiednik w Pythonie: tools/trap_plan_sim.py (bez HighwayPlan).
##
## POZIOM (trap_level 0-3, z SegmentCode: do km 30 najwyżej 1, do km 100
## najwyżej 2, w build/fade najwyżej 1) to dwie rzeczy naraz:
##   - zapowiedź: znak SIGN_DIST[poziom] m przed pułapką (300 / 150 / 60 m),
##     na poziomie 3 też znak, ale późno - SIGN_LATE 60 m (SIGN_AT_3 = true,
##     decyzja użytkownika 2026-11-17: "zawsze znak, najwyżej późno");
##     do tego naturalna zapowiedź, która jest ZAWSZE (rękaw wiatru, widoczny szczyt i światła
##     awaryjne, ciemna plama, pachołki, belka z wysokością);
##   - siła: tabele niżej (promień łuku, odstęp drzew, podmuch...).
##
## Pułapki 4a (HANDLED): 0 łuk po prostej, 1 zwężenie za tunelem, 6 korek
## za szczytem, 7 niski wiadukt, 9 drzewa przy jezdni, 10 wąski most,
## 11 boczny wiatr, 12 zmiana nawierzchni, 13 roboty (trudniejsze),
## 14 znak kłamie. 8 przejazd kolejowy - 4b; 2-5 węzły - 4c (tu: brak).
## Pułapka, której budowla / przekrój nie powstały (biom, miasto, odstęp),
## przepada.

const SEG_LEN := SegmentCode.SEG_LEN
const WIDTH := HighwayGenerator.WIDTH
const SIGN_DIST := [300.0, 150.0, 60.0, -1.0]
## true = na poziomie 3 znak późno (SIGN_LATE) zamiast braku znaku.
const SIGN_AT_3 := true
const SIGN_LATE := 60.0
const HANDLED := [0, 1, 6, 7, 9, 10, 11, 12, 13, 14]

const CURVE_R := [450.0, 350.0, 280.0, 220.0]
const CURVE_TIGHTEN := 0.7
const STRAIGHT_BEFORE := 1500.0
const LIE_R := 180.0
const LIE_TABLET := 120.0
const DROP_GAP := [300.0, 200.0, 120.0, 60.0]
const QUEUE_GAP := [400.0, 250.0, 150.0, 80.0]
const QUEUE_LEN := [150.0, 200.0, 250.0, 300.0]
const CLEAR := [4.6, 4.4, 4.2, 4.0]
const TREE_OFF := [3.0, 2.0, 1.2, 0.8]
const TREE_STEP := 12.0
const BRIDGE_LANE := [3.75, 3.5, 3.25, 3.0]
const GUST := [6.0, 9.0, 12.0, 15.0]
const PATCH_LEN := [30.0, 50.0, 80.0, 120.0]
const PATCH_GRIP := [0.85, 0.75, 0.6, 0.5]
const PATCH_KIND := ["milled", "oil", "ruts", "gravel"]
const WORKS_TAPER := [1.0, 0.8, 0.6, 0.45]
const WINDSOCK_STEP := 300.0
## Znak zapowiedzi pułapki ("" = bez znaku; 0 i 14: A-1 w prawo / A-2 w lewo).
const SIGN := {1: "A-12", 6: "A-30", 7: "B-16", 9: "", 10: "A-12c", 11: "A-19", 12: "A-15", 13: ""}

var code: SegmentCode
var structures: StructurePlan
var sections: SectionPlan
var _cache := {}


func _init(p_code: SegmentCode, p_structures: StructurePlan, p_sections: SectionPlan) -> void:
	code = p_code
	structures = p_structures
	sections = p_sections


static func sign_dist(level: int) -> float:
	if level == 3 and SIGN_AT_3:
		return SIGN_LATE
	return float(SIGN_DIST[level])


## Pułapka odcinka k albo {}. Pola: k, trap, level, d (miejsce pułapki) +
## pola rodzaju: 0/14 r, r_end, dir (+1 w prawo), angle [°], tablet (14);
## 1 drop_start (początek skosu zwężenia), glare; 6 queue_end (tył korka),
## queue_start, hazards; 7 clear; 9 end, tree_off; 10 end, lane_w,
## shoulder; 11 end, gust; 12 end, grip, kind; 13 end, taper_k,
## late_arrow, ghost_lines.
func trap(k: int) -> Dictionary:
	if not _cache.has(k):
		_cache[k] = _make(k)
	return _cache[k]


func _structure_in(k: int, kind: int) -> Dictionary:
	for z in structures.zones(float(k) * SEG_LEN, float(k + 1) * SEG_LEN):
		if int(z["structure"]) == kind and float(z["start"]) >= float(k) * SEG_LEN \
				and float(z["start"]) < float(k + 1) * SEG_LEN:
			return z
	return {}


func _make(k: int) -> Dictionary:
	var seg := code.segment(k)
	var t := int(seg["trap"])
	var lvl := int(seg["trap_level"])
	var v := int(seg["variant"])
	if not (t in HANDLED):
		return {}
	var base := (float(k) + (float(seg["trap_at"]) + 0.5) / 4.0) * SEG_LEN
	var tr := {"k": k, "trap": t, "level": lvl}
	match t:
		1:
			var z := _structure_in(k, 1)
			if z.is_empty():
				return {}
			tr["d"] = float(z["end"])
			tr["drop_start"] = float(z["end"]) + float(DROP_GAP[lvl])
			tr["glare"] = true
		6:
			var z := {}
			for c in structures.zones(float(k - 1) * SEG_LEN, float(k + 1) * SEG_LEN):
				if int(c["structure"]) == 4 and float(c["end"]) >= float(k - 1) * SEG_LEN \
						and float(c["end"]) < float(k + 1) * SEG_LEN:
					z = c
			if z.is_empty():
				return {}
			var q_end := float(z["end"]) + float(QUEUE_GAP[lvl])
			tr["d"] = float(z["end"])
			tr["queue_end"] = q_end
			tr["queue_start"] = q_end + float(QUEUE_LEN[lvl])
			tr["hazards"] = lvl <= 2
		7:
			var z := _structure_in(k, 3)
			if z.is_empty():
				return {}
			tr["d"] = float(z["start"])
			tr["clear"] = CLEAR[lvl]
		10:
			var z := _structure_in(k, 2)
			if z.is_empty():
				return {}
			tr["d"] = float(z["start"])
			tr["end"] = float(z["end"])
			tr["lane_w"] = BRIDGE_LANE[lvl]
			tr["shoulder"] = false
		11:
			var z := _structure_in(k, 6)
			if z.is_empty():
				return {}
			tr["d"] = float(z["start"])
			tr["end"] = float(z["end"])
			tr["gust"] = GUST[lvl]
		9, 13:
			var z := sections.zone(k)
			if z.is_empty() or int(z["section"]) != (4 if t == 9 else 6):
				return {}
			if t == 9:
				tr["d"] = float(z["start"]) + float(z["t_in"])
				tr["end"] = float(z["end"]) - float(z["t_out"])
				tr["tree_off"] = TREE_OFF[lvl]
			else:
				tr["d"] = float(z["start"])
				tr["end"] = float(z["end"])
				tr["taper_k"] = WORKS_TAPER[lvl]
				tr["late_arrow"] = lvl >= 1
				tr["ghost_lines"] = lvl >= 2
		0, 14:
			if _busy(base - STRAIGHT_BEFORE, base + 500.0):
				return {}
			var r: float = CURVE_R[lvl] if t == 0 else LIE_R
			tr["d"] = base
			tr["r"] = r
			tr["r_end"] = r * CURVE_TIGHTEN if t == 0 else r
			tr["dir"] = 1 if (v & 4) != 0 else -1
			tr["angle"] = 25.0 + 5.0 * float(v & 3)
			if t == 14:
				tr["tablet"] = LIE_TABLET
		12:
			if _busy(base - 100.0, base + 200.0):
				return {}
			tr["d"] = base
			tr["end"] = base + float(PATCH_LEN[lvl])
			tr["grip"] = PATCH_GRIP[lvl]
			tr["kind"] = PATCH_KIND[v & 3]
	return tr


## Budowla albo strefa przekroju w [d0, d1] (tam łuk / plama się nie mieści).
func _busy(d0: float, d1: float) -> bool:
	if not structures.zones(d0, d1).is_empty():
		return true
	for z in sections.zones(d0, d1):
		if float(z["end"]) > d0 and float(z["start"]) < d1:
			return true
	return false


## Pułapki, których zapowiedź albo treść wypada w [d0, d1).
func traps(d0: float, d1: float) -> Array:
	var out := []
	for k in range(maxi(int(floor(d0 / SEG_LEN)) - 2, 0), int(floor(d1 / SEG_LEN)) + 2):
		var tr := trap(k)
		if not tr.is_empty() and float(tr.get("end", tr["d"])) >= d0 - 400.0 and float(tr["d"]) - 400.0 < d1:
			out.append(tr)
	return out


## Znaki i naturalne zapowiedzi [{"d", "x", "kind"}] posortowane po d.
## kind: znak ("A-1", "A-2", "A-12", "A-12c", "A-15", "A-19", "A-30",
## "B-16"), "tablet_120" (tabliczka z prędkością pod znakiem), "U-3"
## (tablice kierujące na łuku), "clearance_bar" (belka z wysokością na
## pomoście), "hazard_lights" (tył korka miga), "windsock", "patch_<kind>"
## (widoczna plama), "tree" (z kolizją). x jak SectionPlan.lanes_at.
func items(d0: float, d1: float) -> Array:
	var out := []
	for tr in traps(d0, d1):
		for it in _items(tr):
			if float(it["d"]) >= d0 and float(it["d"]) < d1:
				out.append(it)
	out.sort_custom(func(a, b):
		return float(a["d"]) < float(b["d"]) or (float(a["d"]) == float(b["d"]) and float(a["x"]) < float(b["x"])))
	return out


func _items(tr: Dictionary) -> Array:
	var t := int(tr["trap"])
	var lvl := int(tr["level"])
	var d := float(tr["d"])
	var sd := sign_dist(lvl)
	var right := WIDTH * 0.5 + 1.0
	var out := []
	var sign := ""
	if t == 0 or t == 14:
		sign = "A-1" if int(tr["dir"]) > 0 else "A-2"
	else:
		sign = String(SIGN.get(t, ""))
	if t == 14:
		out.append({"d": d - float(SIGN_DIST[0]), "x": right, "kind": sign})
		out.append({"d": d - float(SIGN_DIST[0]), "x": right, "kind": "tablet_%d" % int(tr["tablet"])})
		return out
	if sign != "" and sd >= 0.0:
		var at := float(tr["drop_start"]) if t == 1 else float(tr.get("queue_end", d))
		out.append({"d": at - sd, "x": right, "kind": sign})
	match t:
		7:
			out.append({"d": d, "x": 0.0, "kind": "clearance_bar"})
		0:
			for i in 6:
				out.append({"d": d + 20.0 + 25.0 * float(i), "x": -right if int(tr["dir"]) > 0 else right, "kind": "U-3"})
		6:
			if bool(tr["hazards"]):
				out.append({"d": float(tr["queue_end"]), "x": 0.0, "kind": "hazard_lights"})
		11:
			var dd := d
			while dd < float(tr["end"]):
				out.append({"d": dd, "x": right + 1.0, "kind": "windsock"})
				dd += WINDSOCK_STEP
		12:
			out.append({"d": d, "x": 0.0, "kind": "patch_" + String(tr["kind"])})
		9:
			var dd := d
			while dd < float(tr["end"]):
				for x in [-1.0, 1.0]:
					out.append({"d": dd, "x": x * (4.0 + float(tr["tree_off"])), "kind": "tree"})
				dd += TREE_STEP
	return out


## Plama (pułapka 12) w miejscu d: {"kind", "grip"} albo {}.
func surface_at(d: float) -> Dictionary:
	for tr in traps(d, d + 0.001):
		if int(tr["trap"]) == 12 and d >= float(tr["d"]) and d < float(tr["end"]):
			return {"kind": tr["kind"], "grip": tr["grip"]}
	return {}


## Wiatr boczny [m/s, + w prawo względem kierunku jazdy] na estakadzie
## z pułapką 11 w chwili t [s]; 0 gdzie indziej. Porywy: dwa sinusy (7 i 2,3 s)
## z fazą z hasha, zawsze 0..gust, łagodnie na brzegach (100 m).
func gust(d: float, t: float) -> float:
	for tr in traps(d, d + 0.001):
		if int(tr["trap"]) == 11 and d >= float(tr["d"]) and d < float(tr["end"]):
			var ph := float(SegmentCode._mix(0x51ED270B, int(tr["k"]))) / 4294967296.0 * TAU
			var s := 0.5 + 0.35 * sin(TAU * t / 7.0 + ph) + 0.15 * sin(TAU * t / 2.3 + 2.0 * ph)
			var edge := minf(1.0, minf((d - float(tr["d"])) / 100.0, (float(tr["end"]) - d) / 100.0))
			var side := 1.0 if int(tr["k"]) % 2 == 0 else -1.0
			return side * float(tr["gust"]) * maxf(s, 0.0) * edge
	return 0.0
