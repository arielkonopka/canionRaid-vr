extends RefCounted
class_name SectionPlan

## Przekroje jezdni z kodu odcinka (bajt b1 SegmentCode) - etap 2
## urozmaiceń (zlecenie: docs/agent/inbox/2026-11-14-etap2-przekroje.md,
## kolejność etapów wybrana przez użytkownika 2026-11-13).
##
## Czysta logika jak SegmentCode i WeatherPlan: strefy, pasy, ograniczenia
## i pachołki są funkcją ziarna i dystansu `d`, bez węzłów sceny.
## Odpowiednik w Pythonie: tools/section_plan_sim.py (bez HighwayPlan).
##
## STREFA: przekrój odcinka k obowiązuje od jego punktu zmiany
## p(k) = (k + change_at / 4) * SEG_LEN do punktu zmiany pierwszego odcinka
## z innym przekrojem (najwyżej MAX_SEGS odcinków). Strefa ma skos wejścia
## t_in (długość jak w MUTCD: L = W * S), środek z pełnym przekrojem
## i skos wyjścia t_out. Za krótka strefa, strefa za blisko poprzedniej
## albo nachodząca na miasto, stację, warsztat lub objazd skoczni - nie
## powstaje (przekrój zostaje 2+2).
##
## Przekroje (SegmentCode.SECTIONS):
##   7 zwężenie do jednego pasa - pachołki zamykają prawy albo lewy pas
##     (variant bit 0), ograniczenie 100;
##   6 roboty z przejazdem na drugą jezdnię - nasz lewy pas zamknięty
##     pachołkami, za skosem jedzie nim ruch z naprzeciwka (rozdzielony
##     słupkami), druga jezdnia zamknięta; ograniczenie 80;
##   4 zwykła droga 1+1 - jezdnia zwęża się do 8 m, pas w każdą stronę,
##     druga jezdnia "w budowie" (zamknięta); ograniczenie 90;
##   3 droga 2+1 - jak 1+1, 11,5 m, środkowy pas co ALT_LEN na zmianę
##     (variant bit 1: kto zaczyna); ograniczenie 90;
##   2 autostrada 3+3 - jezdnia szersza o pas (symetrycznie wokół osi, pasy
##     liczone od lewej krawędzi jak HighwayGenerator.lane_center);
##   1 pas dla wolnych i 5 rozjazd - etap 3 (z podjazdem / estakadą), tu 2+2.
##
## Wyjście: zones(d0, d1), zone_at(d), lanes_at(d), limit_at(d),
## limit_marks(d0, d1), items(d0, d1).

const SEG_LEN := SegmentCode.SEG_LEN
const LANE_W := HighwayGenerator.LANE_W
const WIDTH := HighwayGenerator.WIDTH
const SHOULDER_L := HighwayGenerator.SHOULDER_L
const X_RIGHT := 0.75
const X_LEFT := -3.0
const X_SPLIT := -1.125
const LANE_W_ROAD := 3.5

const CHANGE_F := [0.0, 0.25, 0.5, 0.75]
## Odstęp od końca poprzedniej strefy (> WARN: zapowiedź nie wpada w strefę).
const GAP_MIN := 500.0
## Najkrótszy środek strefy (pełny przekrój) [m].
const BODY_MIN := {7: 200.0, 6: 300.0, 2: 400.0, 4: 900.0, 3: 1100.0}
## Pierwsza zapowiedź (znak, ograniczenie) przed strefą (~10 s przy 140).
const WARN := 400.0
const OUT_TAPER := 60.0
const CONE_TAPER_STEP := 9.0
const CONE_BODY_STEP := 18.0
const POST_STEP := 12.0
const MAX_SEGS := 5
const LOOKBACK := MAX_SEGS + 1
const HANDLED := [2, 3, 4, 6, 7]
const ALT_LEN := 1000.0
const ALT_END := 150.0
## Zapas za strefą wolny od miast / stacji / skoczni [m].
const CLEAR_AFTER := 200.0

const LIMIT := {7: 100.0, 6: 80.0, 4: 90.0, 3: 90.0, 2: 140.0}
## Znak zapowiedzi: A-12 zwężenie jezdni, A-14 roboty, D-10 koniec drogi
## ekspresowej/autostrady (tu: "koniec autostrady" przed zwykłą drogą).
const SIGN_IN := {7: "A-12", 6: "A-14", 4: "D-10", 3: "D-10", 2: ""}

var code: SegmentCode
## Plan trasy (miasta, stacje, skocznie blokują strefy). null = bez blokad
## (testy, bliźniak w Pythonie).
var plan: HighwayPlan = null
var _zones := {}
var _last := {}


func _init(p_code: SegmentCode, p_plan: HighwayPlan = null) -> void:
	code = p_code
	plan = p_plan


## Skos zmiany pasa [m]: L = W * S (stopy, mph, MUTCD) przeliczone na
## metry: 3,75 m przy 100 km/h = 233 m, przy 80 = 186 m.
static func taper_len(w: float, v_kmh: float) -> float:
	return w * v_kmh / 1.609


## Środki n pasów autostrady od lewej krawędzi, indeks 0 = prawy.
static func hwy_lanes(n: int, width: float) -> Array:
	var out := []
	for i in n:
		out.append(-width * 0.5 + SHOULDER_L + LANE_W * (float(n - 1 - i) + 0.5))
	return out


func _p(k: int) -> float:
	return (float(k) + float(CHANGE_F[int(code.segment(k)["change_at"])])) * SEG_LEN


func _sec(k: int) -> int:
	if k < 0:
		return 0
	var v := int(code.segment(k)["section"])
	return v if v in HANDLED else 0


## Strefa zaczynająca się w odcinku k albo {}.
func zone(k: int) -> Dictionary:
	if not _zones.has(k):
		_zones[k] = _make(k)
	return _zones[k]


func _make(k: int) -> Dictionary:
	var s := _sec(k)
	if s == 0 or _sec(k - 1) == s:
		return {}
	var j := k + 1
	while _sec(j) == s and j - k < MAX_SEGS:
		j += 1
	var start := _p(k)
	var end := _p(j)
	if _sec(k - 1) != 0:
		start += GAP_MIN
	elif _sec(k - 2) != 0:
		start = maxf(start, _p(k - 1) + GAP_MIN)
	var seg := code.segment(k)
	var lim: float = LIMIT[s]
	var t_in := taper_len(LANE_W, lim) * (0.5 if s == 2 else 1.0)
	var t_out := OUT_TAPER if (s == 7 or s == 6) else t_in
	if end - start < t_in + float(BODY_MIN[s]) + t_out:
		return {}
	if plan != null and _blocked(start - WARN, end + CLEAR_AFTER):
		return {}
	return {"k": k, "section": s, "start": start, "end": end, "t_in": t_in, "t_out": t_out,
			"limit": lim, "side": int(seg["variant"]) & 1, "first": (int(seg["variant"]) >> 1) & 1}


## Miasto (i stopniowanie ograniczeń przed nim), stacja, warsztat, objazd
## skoczni w [d0, d1] - tam przekrój zostaje 2+2.
func _blocked(d0: float, d1: float) -> bool:
	if plan.limit_at(d0) < HighwayPlan.LIMIT_HIGHWAY or not plan.limit_changes(d0, d1).is_empty():
		return true
	return not (plan.stations_between(d0, d1).is_empty() and plan.workshops_between(d0, d1).is_empty()
			and plan.jumps_between(d0, d1).is_empty())


## Strefy, których zapowiedź albo treść wypada w [d0, d1], po kolei.
func zones(d0: float, d1: float) -> Array:
	var out := []
	var k0 := maxi(int(floor(d0 / SEG_LEN)) - LOOKBACK, 0)
	var k1 := int(floor(d1 / SEG_LEN)) + 1
	for k in range(k0, k1 + 1):
		var z := zone(k)
		if not z.is_empty() and float(z["end"]) > d0 - WARN and float(z["start"]) - WARN < d1:
			out.append(z)
	return out


func zone_at(d: float) -> Dictionary:
	if not _last.is_empty() and d >= float(_last["start"]) and d < float(_last["end"]):
		return _last
	for z in zones(d, d):
		if d >= float(z["start"]) and d < float(z["end"]):
			_last = z
			return z
	return {}


## Ograniczenie od stref (140 poza nimi): przy celu < 100 najpierw 100 od
## WARN, cel od WARN / 2. Generator bierze min(plan.limit_at, limit_at).
func limit_at(d: float) -> float:
	for z in zones(d, d):
		if d >= float(z["end"]):
			continue
		var lim: float = z["limit"]
		if d >= float(z["start"]) - WARN * 0.5:
			return lim
		if d >= float(z["start"]) - WARN:
			return maxf(lim, 100.0)
	return HighwayPlan.LIMIT_HIGHWAY


## Zmiany ograniczenia od stref [[d, limit]] w [d0, d1), posortowane -
## generator dzieli w nich odcinki jak przy HighwayPlan.limit_changes.
func limit_marks(d0: float, d1: float) -> Array:
	var out := []
	for z in zones(d0, d1):
		var lim: float = z["limit"]
		if lim >= HighwayPlan.LIMIT_HIGHWAY:
			continue
		var ms := [float(z["start"]) - WARN]
		if lim < 100.0:
			ms.append(float(z["start"]) - WARN * 0.5)
		ms.append(float(z["end"]))
		for m in ms:
			if m >= d0 and m < d1:
				out.append([m, limit_at(m + 0.25)])
	out.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return out


## Pasy w miejscu d: {"fwd": [x], "onc": [x], "width", "single", "closing",
## "other_closed"}. x = środek pasa [m w prawo od osi naszej jezdni; jezdnia
## symetryczna wokół osi o szerokości width]. fwd - nasz kierunek, od
## prawego; onc - kierunek przeciwny jadący po NASZEJ jezdni. closing - x
## pasa zamykanego (boty zjeżdżają z niego przed skosem) albo NAN.
## single - zwykła droga (bez pasa rozdziału po lewej); other_closed - druga
## jezdnia bez ruchu (roboty / w budowie). Pasy trwające przesuwają się
## płynnie.
func lanes_at(d: float) -> Dictionary:
	var z := zone_at(d)
	var out := {"fwd": [], "onc": [], "width": WIDTH, "single": false, "closing": NAN,
			"other_closed": false}
	if z.is_empty():
		out["fwd"] = hwy_lanes(2, WIDTH)
		return out
	var s: int = z["section"]
	var u := d - float(z["start"])
	var t_in: float = z["t_in"]
	var t_out: float = z["t_out"]
	var v := float(z["end"]) - d
	var f := minf(minf(u / t_in, 1.0), v / t_out)
	var body := u >= t_in and v > t_out
	out["other_closed"] = s == 6 or s == 4 or s == 3
	if s == 7 or s == 6:
		var lanes := hwy_lanes(2, WIDTH)
		var keep := 0 if (s == 6 or int(z["side"]) == 1) else 1
		out["fwd"] = [lanes[keep]]
		if u < t_in:
			out["closing"] = lanes[1 - keep]
		if s == 6 and body:
			out["onc"] = [lanes[1]]
	elif s == 2:
		var w := WIDTH + LANE_W * f
		out["width"] = w
		if body:
			out["fwd"] = hwy_lanes(3, w)
		else:
			out["fwd"] = hwy_lanes(2, w)
			if v <= t_out:
				out["closing"] = hwy_lanes(3, w)[0]
	else:
		var w_body := float(2 if s == 4 else 3) * LANE_W_ROAD + 1.0
		out["width"] = WIDTH + (w_body - WIDTH) * f
		out["single"] = f > 0.0
		var right := X_RIGHT + (w_body * 0.5 - 0.5 - LANE_W_ROAD * 0.5 - X_RIGHT) * f
		if not body:
			out["fwd"] = [right]
			if u < t_in:
				out["closing"] = hwy_lanes(2, WIDTH)[1]
			return out
		if s == 4:
			out["fwd"] = [right]
			out["onc"] = [right - LANE_W_ROAD]
		else:
			var ub := u - t_in
			var ours := (int(ub / ALT_LEN) + int(z["first"])) % 2 == 0
			var left_in_phase := ALT_LEN - fmod(ub, ALT_LEN)
			var mid := right - LANE_W_ROAD
			var left := right - 2.0 * LANE_W_ROAD
			var ending := left_in_phase < ALT_END or v - t_out < ALT_END
			if ours:
				if ending:
					out["fwd"] = [right]
					out["onc"] = [left]
					out["closing"] = mid
				else:
					out["fwd"] = [right, mid]
					out["onc"] = [left]
			else:
				out["fwd"] = [right]
				out["onc"] = [left] if ending else [mid, left]
	return out


## Pachołki, słupki, tablice i znaki w [d0, d1): [{"d", "x", "kind"}]
## posortowane po d. kind: "cone" (pachołek), "post" (słupek rozdzielający
## kierunki), "arrow_board" (tablica ze strzałką przed skosem), znak
## ("A-12", "A-14", "D-10"), "carriageway_closed" (zapora drugiej jezdni).
## x jak w lanes_at. Bez kolizji fizycznej (pachołek waży kilka kg) -
## patrz zlecenie.
func items(d0: float, d1: float) -> Array:
	var out := []
	for z in zones(d0, d1):
		for it in _zone_items(z):
			if float(it["d"]) >= d0 and float(it["d"]) < d1:
				out.append(it)
	out.sort_custom(func(a, b):
		return float(a["d"]) < float(b["d"]) or (float(a["d"]) == float(b["d"]) and float(a["x"]) < float(b["x"])))
	return out


func _zone_items(z: Dictionary) -> Array:
	var s: int = z["section"]
	var a: float = z["start"]
	var e: float = z["end"]
	var t: float = z["t_in"]
	var out := []
	if String(SIGN_IN[s]) != "":
		out.append({"d": a - WARN, "x": WIDTH * 0.5 + 1.0, "kind": SIGN_IN[s]})
	if s == 7 or s == 6:
		var closed := X_LEFT if (s == 6 or int(z["side"]) == 1) else X_RIGHT
		var sgn := -1.0 if closed < 0.0 else 1.0
		var outer := closed + sgn * (LANE_W * 0.5 - 0.3)
		var inner := X_SPLIT + sgn * 0.3
		out.append({"d": a - 10.0, "x": outer, "kind": "arrow_board"})
		var n := int(t / CONE_TAPER_STEP)
		for i in n + 1:
			var f := float(i) / float(n)
			out.append({"d": a + f * t, "x": outer + (inner - outer) * f, "kind": "cone"})
		var dd := a + t + CONE_BODY_STEP
		var step := POST_STEP if s == 6 else CONE_BODY_STEP
		while dd < e - OUT_TAPER:
			out.append({"d": dd, "x": inner, "kind": "post" if s == 6 else "cone"})
			dd += step
		n = int(OUT_TAPER / CONE_TAPER_STEP)
		for i in n + 1:
			var f2 := float(i) / float(n)
			out.append({"d": e - OUT_TAPER + f2 * OUT_TAPER, "x": inner + (outer - inner) * f2, "kind": "cone"})
	if s == 4 or s == 3:
		out.append({"d": a + t, "x": -WIDTH * 0.5 - 1.0, "kind": "carriageway_closed"})
	return out


# --------------------------------------------------------------------------
# Dodatek agenta lokalnego (etap 2b, 2026-11-14): przejazd aut z naprzeciwka
# przez pas rozdziału na robotach (6). Oba przejazdy wewnątrz pełnego
# przekroju, gdzie nasz lewy pas i tak jest zamknięty: wjazd na naszą
# jezdnię tuż przed końcem pełnego przekroju (auta jadą w stronę malejącego
# d), zjazd z niej tuż za końcem skosu wejścia. W tych miejscach przerwa
# w barierce betonowej (StuntTrack._build_highway).
# --------------------------------------------------------------------------

const CROSS_LEN := 120.0


## Odcinki [d0, d1] przejazdów przez pas rozdziału strefy z: roboty (6),
## 1+1 (4) i 2+1 (3) - wszędzie tam ruch z naprzeciwka jedzie naszą jezdnią.
const ONC_ON_OURS := [6, 4, 3]
static func crossovers(z: Dictionary) -> Array:
	if z.is_empty() or not (int(z["section"]) in ONC_ON_OURS):
		return []
	var b0 := float(z["start"]) + float(z["t_in"])
	var b1 := float(z["end"]) - float(z["t_out"])
	return [[b0, b0 + CROSS_LEN], [b1 - CROSS_LEN, b1]]


## Jak bardzo auto z naprzeciwka w d jest już na naszej jezdni: 0 - na
## swojej, 1 - na naszym lewym pasie (płynnie w przejazdach).
func onc_cross(d: float) -> float:
	var z := zone_at(d)
	var cr := crossovers(z)
	if cr.is_empty():
		return 0.0
	var a: Array = cr[0]
	var b: Array = cr[1]
	if d <= float(a[0]) or d >= float(b[1]):
		return 0.0
	if d < float(a[1]):
		return smoothstep(float(a[0]), float(a[1]), d)
	if d > float(b[0]):
		return 1.0 - smoothstep(float(b[0]), float(b[1]), d)
	return 1.0


## Przerwa w barierce pasa rozdziału w d (przejazd na robotach).
func median_gap(d: float) -> bool:
	for c in crossovers(zone_at(d)):
		if d >= float(c[0]) - 5.0 and d <= float(c[1]) + 5.0:
			return true
	return false


## Żółte linie tymczasowe na naszej jezdni (roboty, cała strefa).
func works_at(d: float) -> bool:
	var z := zone_at(d)
	return not z.is_empty() and int(z["section"]) == 6



# --------------------------------------------------------------------------
# Dodatek agenta lokalnego (etap 2c, 2026-11-14): szerokość w generatorze,
# oś pasów z naprzeciwka na naszej jezdni i znaczniki do shadera.
# --------------------------------------------------------------------------

## Punkty zmiany szerokości stref w [d0, d1): początek i koniec skosu
## wejścia i wyjścia (sekcje ze zmienną szerokością: 4, 3, 2).
func width_marks(d0: float, d1: float) -> Array:
	var out := []
	for z in zones(d0, d1):
		if not (int(z["section"]) in [4, 3, 2]):
			continue
		var a := float(z["start"])
		var e := float(z["end"])
		for m in [a, a + float(z["t_in"]), e - float(z["t_out"]), e]:
			if m >= d0 and m < d1:
				out.append(m)
	out.sort()
	return out


## Oś pasa auta z naprzeciwka (`lane` 0 - ich wolny, czyli nasz skrajny
## lewy) na naszej jezdni w strefie z - z pełnego przekroju (w przejazdach
## oś z najbliższego jego końca). NAN poza strefą z ruchem na naszej jezdni.
func onc_x(d: float, lane: int) -> float:
	var z := zone_at(d)
	var cr := crossovers(z)
	if cr.is_empty():
		return NAN
	var dd := clampf(d, float(cr[0][0]) + 1.0, float(cr[1][1]) - 1.0)
	var onc: Array = lanes_at(dd)["onc"]
	if onc.is_empty():
		onc = lanes_at(clampf(dd, float(cr[0][1]) + 1.0, float(cr[1][0]) - 1.0))["onc"]
	if onc.is_empty():
		return NAN
	# onc od prawej (naszej) strony: ostatni = skrajny lewy = ich wolny pas.
	return float(onc[maxi(onc.size() - 1 - lane, 0)])


## Znaczniki shadera jezdni (COLOR wierzchołka): r - żółte linie robót,
## g - zwykła droga (1 = 1+1, 0,5 = 2+1), b - oś granicy kierunków (x + 8) / 16.
func road_color(d: float) -> Color:
	var z := zone_at(d)
	if z.is_empty():
		return Color(0, 0, 0)
	var s := int(z["section"])
	if s == 6:
		return Color(1, 0, 0)
	if s == 4 or s == 3:
		var la := lanes_at(d)
		# single = od początku skosu (f > 0); 2+1 ma 11,5 m - szerzej niż
		# autostrada, więc bez warunku na szerokość.
		if not bool(la["single"]):
			return Color(0, 0, 0)
		var fwd: Array = la["fwd"]
		var onc: Array = la["onc"]
		var bx := 0.0
		if not onc.is_empty():
			bx = (float(fwd.min()) + float(onc.max())) * 0.5
		return Color(0, 1.0 if s == 4 else 0.5, (bx + 8.0) / 16.0)
	return Color(0, 0, 0)
