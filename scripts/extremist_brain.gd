extends RefCounted
class_name ExtremistBrain

## Ekstremista (użytkownik 2026-11-12): bot, który jedzie z maksymalną
## możliwą prędkością, trąbi na wszystkich i mruga długimi, ale nie zwalnia.
## Nie goni gracza - jego celem jest droga przed nim. Kto nie zjedzie, ten
## dostaje w zderzak przy różnicy prędkości 100 km/h i więcej.
##
## Czysta logika, bez węzłów (jak FeudDirector): BotDriver podaje sytuację
## na pasach przed autem, dostaje pas docelowy, gaz/hamulec i stan klaksonu
## i długich świateł. Sterowanie w poprzek drogi zostaje to samo co u
## innych botów (wygładzony cel toru, skręt ograniczony przyczepnością),
## tylko z ostrzejszymi stałymi LAT_RATE / LAT_GRIP - to brawura kierowcy,
## nie lepsze opony. Opony i bezwładność jak u gracza; oszustwo tylko
## w napędzie (engine_power_kw).
##
## Zachowanie przy łukach (curve_mode), do decyzji użytkownika:
##   "lift"   - nigdy nie hamuje; gdy łuk przed nim wymaga mniejszej
##              prędkości, tylko zdejmuje nogę z gazu (domyślnie);
##   "never"  - pełny gaz zawsze, dosłownie;
##   "curves" - hamuje przed łukami, nigdy przed autami.
## Przed autami nie hamuje w żadnym trybie: trąbi, mruga, omija innym
## pasem, w ostateczności poboczem, a jak się nie da - taranuje.
##
## Integracja: docs/agent/inbox/2026-11-12-bot-ekstremista.md.

const MODE_LIFT := "lift"
const MODE_NEVER := "never"
const MODE_CURVES := "curves"

## Pas ulubiony: lewy (indeks 1 jak w BotDriver.lane / HighwayGenerator).
const PREF_LANE := 1
const SHOULDER := -1                # pas awaryjny - ostateczność
const CAR_LEN := 5.5                # [m] auto obok (gap < tego) = pas zajęty
## Czas do zderzenia [s], poniżej którego szuka innego pasu.
const SWITCH_TTC := 3.5
## Inny pas musi dawać tyle sekund więcej, żeby zmienić (bez szarpania).
const BETTER := 1.0
## Pobocze dopiero, gdy uderzenie za mniej niż tyle sekund.
const SHOULDER_TTC := 1.6
## Najkrótszy czas między decyzjami o pasie [s].
const LANE_HOLD := 0.8
## Trąbi na każde auto przed sobą bliżej niż HORN_DIST (na dowolnym pasie),
## mruga długimi na każde bliżej niż FLASH_DIST - "na wszystkich".
const HORN_DIST := 160.0
const FLASH_DIST := 260.0
## Poniżej tego TTC na jego pasie klakson ciągły zamiast serii.
const LONG_BLAST_TTC := 2.0
## Seria klaksonu: dwa sygnały 0,3 s, pauza (okres 1,4 s).
const HORN_PERIOD := 1.4
const HORN_ON := [[0.0, 0.3], [0.45, 0.75]]
## Długie: dwa mrugnięcia, pauza (okres 1,0 s).
const BEAM_PERIOD := 1.0
const BEAM_ON := [[0.0, 0.15], [0.27, 0.42]]
## Sterowanie w poprzek drogi dla BotDriver (zamiast LAT_RATE / LAT_GRIP).
const LAT_RATE := 3.0               # [m/s] zmiana pasu 3,75 m w ~1,3 s
const LAT_GRIP := 0.7               # ułamek μ·g na zmianę toru
## Łuki: granica, przy której odpuszcza gaz / hamuje (μ·g), i opóźnienie,
## na które liczy przy dojeździe do łuku [m/s²]: samo odpuszczenie gazu
## przy 250 km/h to opór powietrza + toczenia ~2-3 m/s², hamowanie ~7.
const CURVE_G := 0.85
const DECEL_LIFT := 2.5
const DECEL_BRAKE := 7.0
## Oszustwo napędu: moc co najmniej tyle i co najmniej 1,3 x gracz.
const MIN_POWER_KW := 450.0
const PLAYER_POWER_MULT := 1.3

var curve_mode := MODE_LIFT
var lane := PREF_LANE
## Ostatnio policzony czas do zderzenia na jego pasie [s] (do debugowania
## i do decyzji BotDriver, np. o sygnale "na włos").
var threat_ttc := INF
var _hold := 0.0
var _horn_t := 0.0
var _beam_t := 0.0
var _throttle_on := true


## Jeden krok decyzji. ctx:
##   "v": własna prędkość [m/s]
##   "lanes": Array, indeks = pas (0 prawy, 1 lewy): {"gap": odległość [m]
##            do najbliższego auta przed nim na tym pasie (INF = wolny;
##            < CAR_LEN = ktoś obok), "v": jego prędkość [m/s]}
##   "shoulder": jak wpis pasa dla pobocza albo {} (brak pobocza)
##   "v_safe": najwyższa prędkość, przy której zmieści się w łukach przed
##             sobą (v_safe_from_profile); INF = prosta
## Zwraca {"lane", "throttle", "brake", "horn": bool, "beam": 0..1}.
func step(dt: float, ctx: Dictionary) -> Dictionary:
	var v := float(ctx.get("v", 0.0))
	var lanes: Array = ctx.get("lanes", [])
	var shoulder: Dictionary = ctx.get("shoulder", {})
	_choose_lane(dt, v, lanes, shoulder)
	var cur: Dictionary = _entry(lanes, shoulder, lane)
	threat_ttc = ttc(v, cur)

	# Klakson i długie: na każde auto przed nim, na każdym pasie.
	var near_any := INF
	for e in lanes:
		near_any = minf(near_any, _approach_gap(v, e))
	if not shoulder.is_empty():
		near_any = minf(near_any, _approach_gap(v, shoulder))
	var horn := false
	if threat_ttc < LONG_BLAST_TTC:
		horn = true
		_horn_t = 0.0
	elif near_any < HORN_DIST:
		_horn_t = fmod(_horn_t + dt, HORN_PERIOD)
		horn = _in_pattern(_horn_t, HORN_ON)
	else:
		_horn_t = 0.0
	var beam := 0.0
	if near_any < FLASH_DIST:
		_beam_t = fmod(_beam_t + dt, BEAM_PERIOD)
		beam = 1.0 if _in_pattern(_beam_t, BEAM_ON) else 0.0
	else:
		_beam_t = 0.0

	# Gaz i hamulec. Przed autami - nigdy hamulca.
	var v_safe := float(ctx.get("v_safe", INF))
	var throttle := 1.0
	var brake := 0.0
	if curve_mode != MODE_NEVER:
		# Pętla histerezy: odpuszcza nad v_safe, wraca poniżej 98%.
		if v > v_safe:
			_throttle_on = false
		elif v < v_safe * 0.98:
			_throttle_on = true
		throttle = 1.0 if _throttle_on else 0.0
		if curve_mode == MODE_CURVES and v > v_safe:
			brake = clampf((v - v_safe) * 0.25, 0.0, 1.0)
	return {"lane": lane, "throttle": throttle, "brake": brake, "horn": horn, "beam": beam}


## Czas do zderzenia z autem przed nim [s]: 0 = ktoś obok (pas zajęty),
## INF = wolne albo tamten szybszy.
static func ttc(v: float, e: Dictionary) -> float:
	if e.is_empty():
		return INF
	var gap := float(e.get("gap", INF))
	if gap < CAR_LEN:
		return 0.0
	var closing := v - float(e.get("v", 0.0))
	if gap == INF or closing <= 0.1:
		return INF
	return gap / closing


## Prędkość, z którą zmieści się w łukach przed sobą: profil BotDriver._prof
## (krok 4: [dystans, limit², vc² 0,6 g, vc² 0,7 g]) przeskalowany do
## CURVE_G, z drogą wytracania przy opóźnieniu `decel`. Ograniczeń
## prędkości nie zna - ignoruje je.
static func v_safe_from_profile(prof: PackedFloat32Array, dist: float, decel: float) -> float:
	var best := INF
	var i := 0
	while i + 3 < prof.size():
		var k := prof[i] - dist
		var vc2 := prof[i + 3]
		if k >= -2.0 and vc2 < INF:
			var v2 := vc2 * CURVE_G / 0.7 + 2.0 * decel * maxf(k, 0.0)
			best = minf(best, sqrt(v2))
		i += 4
	return best


## Opóźnienie do v_safe_from_profile dla trybu łuków.
static func decel_for(mode: String) -> float:
	return DECEL_BRAKE if mode == MODE_CURVES else DECEL_LIFT


## Moc silnika ekstremisty [kW] (oszustwo napędu, jak przy enrage).
static func engine_kw(player_kw: float) -> float:
	return maxf(MIN_POWER_KW, player_kw * PLAYER_POWER_MULT)


## Punkty za przepuszczenie go bez kontaktu ("ucieczka"), wg najmniejszego
## odstępu boków aut w poprzek [m] przy mijaniu. Kontakt = 0 (tu nie liczone).
static func pass_points(min_gap: float) -> int:
	if min_gap < 1.0:
		return 200
	if min_gap < 2.5:
		return 120
	if min_gap < 4.0:
		return 60
	return 0


## Szansa pojawienia się ekstremisty na kilometr trasy, rosnąca z dystansem
## (trudność rośnie z czasem; wizja). Pierwsze 3 km spokój.
static func spawn_chance_per_km(km: float) -> float:
	if km < 3.0:
		return 0.0
	return minf(0.15 + 0.03 * (km - 3.0), 0.6)


# --- wewnętrzne ---------------------------------------------------------

func _choose_lane(dt: float, v: float, lanes: Array, shoulder: Dictionary) -> void:
	_hold -= dt
	if lanes.is_empty():
		return
	if lane >= lanes.size():
		lane = lanes.size() - 1
	if _hold > 0.0:
		return
	var cur := ttc(v, _entry(lanes, shoulder, lane))
	var best := lane
	var best_t := cur
	if cur >= SWITCH_TTC:
		# Nic przed nim: wraca na lewy pas (albo z pobocza na jezdnię).
		var pref := mini(PREF_LANE, lanes.size() - 1)
		if lane == SHOULDER:
			best = _best_lane(v, lanes)
		elif lane != pref and ttc(v, lanes[pref]) >= SWITCH_TTC * 2.0:
			best = pref
	else:
		# Zagrożony: najlepszy inny pas, jeśli wyraźnie lepszy.
		for i in lanes.size():
			if i == lane:
				continue
			var t := ttc(v, lanes[i])
			if t > best_t + BETTER or (t == INF and best_t < INF):
				best = i
				best_t = t
		if best == lane and cur < SHOULDER_TTC and not shoulder.is_empty():
			var ts := ttc(v, shoulder)
			if ts > cur + BETTER:
				best = SHOULDER
	if best != lane:
		lane = best
		_hold = LANE_HOLD


func _best_lane(v: float, lanes: Array) -> int:
	var best := mini(PREF_LANE, lanes.size() - 1)
	var best_t := ttc(v, lanes[best])
	for i in lanes.size():
		var t := ttc(v, lanes[i])
		if t > best_t:
			best = i
			best_t = t
	return best


static func _entry(lanes: Array, shoulder: Dictionary, i: int) -> Dictionary:
	if i == SHOULDER:
		return shoulder
	if i >= 0 and i < lanes.size():
		return lanes[i]
	return {}


## Odległość do auta, do którego się zbliża (INF, gdy oddala się szybciej).
static func _approach_gap(v: float, e: Dictionary) -> float:
	var gap := float(e.get("gap", INF))
	if gap < CAR_LEN:
		return gap
	if v - float(e.get("v", 0.0)) <= 0.1:
		return INF
	return gap


static func _in_pattern(t: float, on: Array) -> bool:
	for seg in on:
		if t >= float(seg[0]) and t < float(seg[1]):
			return true
	return false
