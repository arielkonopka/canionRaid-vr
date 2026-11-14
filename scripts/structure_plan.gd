extends RefCounted
class_name StructurePlan

## Budowle z kodu odcinka (bajt b0 SegmentCode) i profil wysokości trasy -
## etap 3 urozmaiceń (zlecenie: docs/agent/inbox/2026-11-14-etap3-budowle.md).
##
## Czysta logika jak SectionPlan: strefy budowli, wysokość jezdni, teren pod
## nią, filary - funkcja ziarna i dystansu `d`, bez węzłów sceny. Liczona
## leniwie po kolei (wysokość zależy od wcześniejszych podjazdów), zawsze
## ~4 odcinki do przodu, więc kolejność pytań niczego nie zmienia.
## Odpowiednik w Pythonie: tools/structure_plan_sim.py (bez HighwayPlan).
##
## Budowle (SegmentCode.STRUCTURES), każda zaczyna się APPROACH m za
## początkiem odcinka, co najmniej GAP m za poprzednią:
##   1 tunel - LEN 400-2000 m, poziomo; s_param & 3: 0/3 oświetlony,
##     1 ciemny, 2 na łuku; `cover` - wysokość góry nad nim; limit 100;
##   2 most nad rzeką - rzeka 80-400 m + przęsła nad brzegami, poziomo;
##     `clear` - prześwit nad wodą 8-29 m;
##   3 wiadukt kolejowy nad drogą - pomost 14 m, prześwit 6,5 m (pułapka 7:
##     4,4 m); s_param & 3 = pociąg (0 brak, 1 z lewej, 2 z prawej, 3 dwa),
##     & 4 = towarowy (długi, wolny);
##   4 podjazd - 1,2-3,6 km pod górę, 3-8 %;
##   5 zjazd z serpentynami - w dół (tylko gdy jest skąd), limit 80,
##     `serp_r` - promień łuków 250-400 m (nawroty R 45 nie pasują do 2+2);
##   6 estakada nad doliną - 0,4-1,5 km, poziomo, dolina 20-76 m pod nią.
##   7 miasto - etap 5 (tu nic).
## Poza budowlami droga wysoko wraca na dół G_RETURN %. Węzły profilu łączą
## łuki pionowe (parabola, długość K_VC * zmiana pochylenia). Płaskie budowle
## mają LEAD m poziomo przed i za sobą.
##
## Bez pochyleń (`slopes = false`, odpowiedź użytkownika "płasko"): podjazdy
## i zjazdy nie powstają, wysokość zawsze 0.
##
## Z planem trasy: budowle tylko w pasujących biomach (BIOME_OK), nie
## w miastach (i przed nimi), na stacjach, warsztatach i skoczniach.

const SEG_LEN := SegmentCode.SEG_LEN
const APPROACH := 200.0
const GAP := 400.0
const LEN := {1: [400.0, 800.0, 1300.0, 2000.0], 2: [80.0, 150.0, 250.0, 400.0],
		3: [14.0, 14.0, 14.0, 14.0], 4: [1200.0, 1800.0, 2400.0, 3600.0],
		5: [1000.0, 1500.0, 2000.0, 2500.0], 6: [400.0, 700.0, 1000.0, 1500.0]}
const BRIDGE_BANK := 60.0
const GRADE := [3.0, 4.0, 4.5, 5.0, 5.5, 6.0, 7.0, 8.0]
const G_RETURN := 2.0
const H_MAX := 300.0
const K_VC := 60.0
const VC_MIN := 80.0
const MIN_PIECE := 150.0
const LEAD := 70.0
const CLEAR_RAIL := 6.5
const CLEAR_RAIL_LOW := 4.4
const TUNNEL_COVER := [30.0, 60.0, 90.0, 140.0]
const PIER_STEP := {2: 45.0, 6: 55.0}
const PIER_MIN := 3.0
const LIMIT := {1: 100.0, 5: 80.0}
const SERP_R := [250.0, 300.0, 350.0, 400.0]
const HANDLED := [1, 2, 3, 4, 5, 6]
## Budowle dozwolone w biomie (HighwayPlan.BIOMES).
const BIOME_OK := {"fields": [2, 3], "meadow": [1, 2, 3, 4], "desert": [3, 6],
		"mountains": [1, 2, 4, 5, 6], "seaside": [1, 2, 3, 6], "canyon": [1, 4, 5, 6]}

var code: SegmentCode
var plan: HighwayPlan = null
var slopes := true

var _zones: Array[Dictionary] = []
## Węzły profilu: [d, h, zablokowany].
var _nodes: Array = [[0.0, 0.0, true]]
var _k_done := -1
var _busy_until := -1e9
var _h := 0.0
var _d_end := 0.0


func _init(p_code: SegmentCode, p_plan: HighwayPlan = null, p_slopes := true) -> void:
	code = p_code
	plan = p_plan
	slopes = p_slopes


# --------------------------------------------------------------------------
# Budowa po kolei
# --------------------------------------------------------------------------

func _ensure(d: float) -> void:
	while _d_end < d + 4.0 * SEG_LEN:
		_step(_k_done + 1)


func _go(d_to: float, grade: float, lock := false) -> void:
	if d_to <= _d_end:
		return
	var g := grade / 100.0
	var h_to := _h + g * (d_to - _d_end)
	if g < 0.0 and h_to < 0.0:
		_node(_d_end + _h / -g, 0.0)
		_node(d_to, 0.0, lock)
	elif g > 0.0 and h_to > H_MAX:
		_node(_d_end + (H_MAX - _h) / g, H_MAX)
		_node(d_to, H_MAX, lock)
	else:
		_node(d_to, h_to, lock)


func _node(d: float, h: float, lock := false) -> void:
	var last: Array = _nodes[_nodes.size() - 1]
	if d <= float(last[0]) + 1e-6:
		return
	var n := _nodes.size()
	if n >= 2 and not bool(last[2]) and float(last[0]) - float(_nodes[n - 2][0]) < MIN_PIECE:
		_nodes.pop_back()
	n = _nodes.size()
	if n >= 2 and not bool(_nodes[n - 1][2]):
		var a: Array = _nodes[n - 2]
		var b: Array = _nodes[n - 1]
		var g1 := (float(b[1]) - float(a[1])) / (float(b[0]) - float(a[0]))
		var g2 := (h - float(b[1])) / (d - float(b[0]))
		if absf(g1 - g2) < 1e-9:
			_nodes.pop_back()
	_nodes.append([d, h, lock])
	_d_end = d
	_h = h


func _plain(d_to: float) -> void:
	_go(d_to, -minf(G_RETURN, 100.0 * _h / (2.0 * VC_MIN)) if _h > 0.0 else 0.0)


func _step(k: int) -> void:
	_k_done = k
	var seg := code.segment(k)
	var st := int(seg["structure"])
	var z := {}
	if st in HANDLED and (slopes or (st != 4 and st != 5)):
		var start := float(k) * SEG_LEN + APPROACH
		if start - LEAD >= _busy_until + GAP and start - LEAD >= _d_end - 1e-6:
			z = _zone(k, seg, start)
	if z.is_empty():
		_plain(float(k + 1) * SEG_LEN)
		return
	if st == 4 or st == 5:
		_plain(float(z["start"]))
		z["h"] = _h
		_go(float(z["end"]), float(z["grade"]) * (1.0 if st == 4 else -1.0))
	else:
		_plain(float(z["start"]) - LEAD)
		_nodes[_nodes.size() - 1][2] = true
		z["h"] = _h
		_go(float(z["end"]) + LEAD, 0.0, true)
	z["h_end"] = _h
	_zones.append(z)
	_busy_until = float(z["end"]) + (0.0 if (st == 4 or st == 5) else LEAD)
	_plain(maxf(float(k + 1) * SEG_LEN, float(z["end"])))


func _zone(k: int, seg: Dictionary, start: float) -> Dictionary:
	var st := int(seg["structure"])
	var ln := int(seg["s_len"])
	var p := int(seg["s_param"])
	var z := {"k": k, "structure": st, "start": start, "trap": int(seg["trap"])}
	match st:
		1:
			z["length"] = LEN[1][ln]
			z["lit"] = (p & 3) != 1
			z["curved"] = (p & 3) == 2
			z["cover"] = TUNNEL_COVER[p & 3]
			z["limit"] = LIMIT[1]
		2:
			var river: float = LEN[2][ln]
			z["river"] = river
			z["clear"] = 8.0 + 3.0 * float(p)
			z["length"] = river + 2.0 * BRIDGE_BANK
		3:
			z["length"] = LEN[3][ln]
			z["clear"] = CLEAR_RAIL_LOW if int(seg["trap"]) == 7 else CLEAR_RAIL
			z["train"] = p & 3
			z["freight"] = (p & 4) != 0
		4:
			z["length"] = LEN[4][ln]
			z["grade"] = GRADE[p]
		5:
			var g: float = GRADE[p]
			var ln_m := minf(float(LEN[5][ln]), _h / (g / 100.0)) if _h > 0.0 else 0.0
			if ln_m < 600.0:
				return {}
			z["length"] = ln_m
			z["grade"] = g
			z["serp_r"] = SERP_R[p & 3]
			z["limit"] = LIMIT[5]
		6:
			z["length"] = LEN[6][ln]
			z["depth"] = 20.0 + 8.0 * float(p)
	z["end"] = start + float(z["length"])
	if plan != null and not _allowed(st, start - LEAD - GAP, float(z["end"]) + LEAD):
		return {}
	return z


func _allowed(st: int, d0: float, d1: float) -> bool:
	for b in [plan.biome_at(d0), plan.biome_at((d0 + d1) * 0.5), plan.biome_at(d1)]:
		if not (st in BIOME_OK.get(String(b), [])):
			return false
	if plan.limit_at(d0) < HighwayPlan.LIMIT_HIGHWAY or not plan.limit_changes(d0, d1).is_empty():
		return false
	return plan.stations_between(d0, d1).is_empty() and plan.workshops_between(d0, d1).is_empty() \
			and plan.jumps_between(d0, d1).is_empty()


# --------------------------------------------------------------------------
# Odczyt
# --------------------------------------------------------------------------

## Budowle nachodzące na [d0, d1), po kolei. Pola: k, structure, start,
## end, length, h (wysokość na początku), h_end, trap + pola rodzaju.
func zones(d0: float, d1: float) -> Array:
	_ensure(d1)
	var out := []
	for z in _zones:
		if float(z["end"]) > d0 and float(z["start"]) < d1:
			out.append(z)
	return out


func zone_at(d: float) -> Dictionary:
	for z in zones(d, d + 0.001):
		if d >= float(z["start"]) and d < float(z["end"]):
			return z
	return {}


func _seg_index(d: float) -> int:
	var lo := 0
	var hi := _nodes.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if float(_nodes[m][0]) <= d:
			lo = m
		else:
			hi = m
	return lo


func _grade_piece(i: int) -> float:
	return (float(_nodes[i + 1][1]) - float(_nodes[i][1])) / (float(_nodes[i + 1][0]) - float(_nodes[i][0]))


## Wysokość jezdni nad poziomem bazowym (HighwayGenerator.ROAD_Y) [m].
func height_at(d: float) -> float:
	d = maxf(d, 0.0)
	_ensure(d)
	var i := _seg_index(d)
	for j in [i, i + 1]:
		if j >= 1 and j <= _nodes.size() - 2:
			var g1 := _grade_piece(j - 1)
			var g2 := _grade_piece(j)
			var dj := float(_nodes[j][0])
			var l_prev := dj - float(_nodes[j - 1][0])
			var l_next := float(_nodes[j + 1][0]) - dj
			var lc := minf(maxf(K_VC * absf(g2 - g1) * 100.0, VC_MIN), 0.9 * minf(l_prev, l_next))
			if absf(d - dj) < lc * 0.5:
				var x := d - (dj - lc * 0.5)
				return float(_nodes[j][1]) - g1 * lc * 0.5 + g1 * x + (g2 - g1) * x * x / (2.0 * lc)
	var a: Array = _nodes[i]
	var b: Array = _nodes[i + 1]
	return float(a[1]) + (float(b[1]) - float(a[1])) * (d - float(a[0])) / (float(b[0]) - float(a[0]))


## Pochylenie jezdni (dh/dd, 0,05 = 5 %).
func grade_at(d: float) -> float:
	return (height_at(d + 1.0) - height_at(d - 1.0)) * 0.5


## Teren pod jezdnią: {"y": wysokość terenu (= jezdnia poza budowlami - bez
## nasypu), "water": rzeka pod mostem, "over": szczyt góry nad tunelem albo
## NAN}. Teren w bok od drogi - generator / ground (najprościej: ten sam y
## w pasie wokół drogi, poza nim łagodnie do y bazowego - patrz zlecenie).
func ground_at(d: float) -> Dictionary:
	var h := height_at(d)
	var out := {"y": h, "water": false, "over": NAN}
	var z := zone_at(d)
	if z.is_empty():
		return out
	var u := d - float(z["start"])
	match int(z["structure"]):
		2:
			var depth := float(z["clear"]) + 1.0
			var r1 := BRIDGE_BANK + float(z["river"])
			if u >= BRIDGE_BANK and u < r1:
				out["y"] = h - depth
				out["water"] = true
			else:
				var t := u / BRIDGE_BANK if u < BRIDGE_BANK else (float(z["length"]) - u) / BRIDGE_BANK
				out["y"] = h - depth * (1.0 - t)
		6:
			out["y"] = h - float(z["depth"]) * sin(PI * u / float(z["length"]))
		1:
			out["over"] = h + 8.0 + float(z["cover"]) * sin(PI * u / float(z["length"]))
	return out


## Filary mostów i estakad w [d0, d1): [{"d", "top", "bottom"}].
func piers(d0: float, d1: float) -> Array:
	var out := []
	for z in zones(d0, d1):
		var st := int(z["structure"])
		if not PIER_STEP.has(st):
			continue
		var n := maxi(int(float(z["length"]) / float(PIER_STEP[st])), 1)
		for i in range(1, n):
			var d := float(z["start"]) + float(i) * float(z["length"]) / float(n)
			if d >= d0 and d < d1:
				var top := height_at(d)
				var bottom := float(ground_at(d)["y"])
				if top - bottom >= PIER_MIN:
					out.append({"d": d, "top": top, "bottom": bottom})
	return out


## Ograniczenie od budowli (tunel 100, zjazd 80; 140 poza nimi).
## Generator bierze min(plan, przekroje, budowle) i dzieli odcinki na
## brzegach stref (`zones`).
func limit_at(d: float) -> float:
	var z := zone_at(d)
	if not z.is_empty() and z.has("limit"):
		return float(z["limit"])
	return HighwayPlan.LIMIT_HIGHWAY
