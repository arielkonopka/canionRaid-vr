extends RefCounted
class_name SegmentCode

## Kod odcinka trasy: 4 bajty opisują, co gracz zobaczy na kolejnych
## SEG_LEN metrach (użytkownik 2026-11-11: "jak w Pitfall, gdzie całą planszę
## opisywał jeden bajt, tu można losować ze 4 bajty"). Projekt: dokument
## "Urozmaicenia trasy: odcinek z 4 bajtów"; zlecenie:
## docs/agent/inbox/2026-11-13-urozmaicenia-plan-i-kod-odcinka.md.
##
## Czysta logika jak HighwayPlan i WeatherPlan: kod to funkcja ziarna
## i numeru odcinka k, deterministyczna, bez węzłów sceny. Liczony leniwie
## po kolei (gramatyka sąsiedztwa i koszt patrzą na poprzednie odcinki),
## więc kolejność pytań niczego nie zmienia. Odpowiednik w Pythonie:
## tools/segment_code_sim.py (ten sam hash, te same kody).
##
## Kod jest UKRYTY przed graczem (decyzja użytkownika 2026-11-11): tylko
## testy, logi i odtwarzanie z ziarna.
##
## Bajty (bity od najmłodszego):
##   b0 budowla:   structure 0-2, s_len 3-4, s_param 5-7
##   b1 przekrój:  section 0-2, change_at 3-4, variant 5-7
##   b2 pułapka:   trap 0-3, trap_at 4-5, trap_level 6-7
##   b3 zdarzenie: event 0-2, ev_level 3-4, accent 5-7
## code = b0 | b1 << 8 | b2 << 16 | b3 << 24
##
## Filtry nad surowym hashem (kolejność ważna):
##   1. reżyser napięcia: grupy 3-5 odcinków z fazami build/peak/fade/rest
##      (jak reżyser w L4D) - faza wybiera zdarzenie i dopuszcza pułapkę,
##   2. kalendarz: każda wartość ma km pierwszego wystąpienia (trudność
##      rośnie z dystansem, nowości wchodzą pojedynczo),
##   3. pułapka wymusza swoją budowlę/przekrój (albo znika),
##   4. gramatyka: bez powtórki budowli w 4 odcinkach (poza dalszym
##      podjazdem), wąsko najwyżej 2 odcinki z rzędu, pas dla wolnych tylko
##      na podjeździe, "znak kłamie" najwyżej raz na LIE_GAP odcinków,
##   5. koszt na Queście: odcinek + poprzedni <= COST_MAX (ulewa kosztuje).

const SEG_LEN := 1200.0
const FIRST_CALM := 3
const GROUP_MIN := 3
const GROUP_MAX := 5
const COST_MAX := 4
const SAME_STRUCT_GAP := 4
const NARROW_MAX := 3
const LIE_GAP := 33

## Nazwy wartości (do logów i testów; znaczenie - dokument projektu).
const STRUCTURES := ["nasyp", "tunel", "most nad rzeką", "wiadukt kolejowy",
		"podjazd górski", "zjazd z serpentynami", "estakada nad doliną", "przejazd przez miasto"]
const SECTIONS := ["2+2", "2+2 z pasem dla wolnych", "3+3", "2+1", "1+1",
		"rozjazd L/P", "roboty z przejazdem na drugą jezdnię", "zwężenie do jednego pasa"]
const TRAPS := ["zakręt po długiej prostej", "zwężenie za tunelem", "zjazd z lewej",
		"pułapka pasa", "krótki pas włączenia", "odcinek przeplatania",
		"szczyt zasłaniający korek", "niski wiadukt", "przejazd kolejowy", "drzewa przy jezdni",
		"wąski most", "boczny wiatr", "zmiana nawierzchni", "roboty z przejazdem",
		"znak kłamie", "brak"]
const EVENTS := ["nic", "korek", "kierowca pod prąd", "zasadzka z wjazdu",
		"pościg od tyłu", "blokada na zwężeniu", "waśń gangów", "wolna ciężarówka na 1+1"]
const TRAP_NONE := 15
const TRAP_LIE := 14

const BUILD := "build"
const PEAK := "peak"
const FADE := "fade"
const REST := "rest"
const PHASES := {3: ["build", "peak", "rest"], 4: ["build", "build", "peak", "rest"],
		5: ["build", "build", "peak", "fade", "rest"]}
const EVENTS_BY_PHASE := {"build": [0, 1, 7], "peak": [2, 3, 4, 5, 6], "fade": [0, 1, 4], "rest": [0]}

## Kalendarz pierwszych wystąpień [km].
const UNLOCK_STRUCT := {0: 0, 1: 5, 4: 10, 2: 20, 3: 30, 6: 40, 5: 50, 7: 60}
const UNLOCK_SECTION := {0: 0, 7: 8, 4: 15, 6: 25, 3: 35, 5: 45, 1: 10, 2: 60}
const UNLOCK_TRAP := {15: 0, 0: 5, 12: 8, 6: 12, 4: 16, 1: 20, 3: 25, 5: 30, 7: 35,
		10: 40, 9: 45, 11: 50, 13: 55, 2: 60, 8: 70, 14: 120}
const UNLOCK_EVENT := {0: 0, 1: 3, 4: 6, 2: 12, 5: 18, 3: 24, 7: 30, 6: 40}

## Pułapka wymaga budowli albo przekroju.
const TRAP_STRUCT := {1: 1, 7: 3, 10: 2, 11: 6}
const TRAP_SECTION := {8: 4, 13: 6, 9: 4}

const COST_STRUCT := {0: 0, 1: 1, 2: 2, 3: 1, 4: 0, 5: 1, 6: 1, 7: 2}
const COST_EVENT := {0: 0, 1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 2, 7: 0}
const COST_RAIN := 2
## Opad liczony jako ulewa (droższe krople, mgła) - WeatherPlan: 2 ulewa.
const HEAVY_RAIN := 1.5
const NARROW := [4, 7]

var seed_value := 1
## Pogoda (koszt ulewy). Może być null - wtedy bez kosztu deszczu (testy,
## bliźniak w Pythonie).
var weather: WeatherPlan = null

var _groups: Array[int] = [0]
var _codes: Array[Dictionary] = []


func _init(seed_v := 1, p_weather: WeatherPlan = null) -> void:
	seed_value = seed_v
	weather = p_weather


static func _mix(h: int, v: int) -> int:
	h = (h ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFFFFFF


func _h(k: int, salt: int) -> int:
	var x := _mix(0x9E3779B9, seed_value)
	x = _mix(x, k)
	return _mix(x, salt)


## Numer odcinka dla dystansu d [m].
static func index_at(d: float) -> int:
	return int(floor(maxf(d, 0.0) / SEG_LEN))


## Odcinek pod dystansem d.
func at(d: float) -> Dictionary:
	return segment(index_at(d))


## Faza rytmu odcinka k.
func phase(k: int) -> String:
	if k < FIRST_CALM:
		return REST
	while _groups[_groups.size() - 1] <= k:
		var g := _groups.size()
		_groups.append(_groups[g - 1] + GROUP_MIN + _h(g, 100) % (GROUP_MAX - GROUP_MIN + 1))
	var lo := 0
	while _groups[lo + 1] <= k:
		lo += 1
	var start := _groups[lo]
	return String(PHASES[_groups[lo + 1] - start][k - start])


## Odcinek k: słownik z polami (k, phase, structure, s_len, s_param, section,
## change_at, variant, trap, trap_at, trap_level, event, ev_level, accent,
## cost, code). Nie zmieniaj zwróconego słownika.
func segment(k: int) -> Dictionary:
	while _codes.size() <= k:
		_codes.append(_make(_codes.size()))
	return _codes[k]


func _cost(st: int, ev: int, d: float) -> int:
	var c: int = COST_STRUCT[st] + COST_EVENT[ev]
	if weather != null and float(weather.weather(d)["rain"]) >= HEAVY_RAIN:
		c += COST_RAIN
	return c


func _make(k: int) -> Dictionary:
	var km := k * SEG_LEN / 1000.0
	var ph := phase(k)
	var prev: Dictionary = _codes[k - 1] if k > 0 else {}

	# 1. Zdarzenie z fazy.
	var allowed: Array = []
	for e in EVENTS_BY_PHASE[ph]:
		if UNLOCK_EVENT[e] <= km:
			allowed.append(e)
	if allowed.is_empty():
		allowed = [0]
	var event: int = allowed[_h(k, 1) % allowed.size()]
	var ev_level := mini(_h(k, 2) % 4, 1 + int(km / 60.0))

	# 2. Pułapka z fazy.
	var trap := TRAP_NONE
	if ph != REST and k >= FIRST_CALM:
		var raw := _h(k, 3) % 16
		if ph == PEAK and raw == TRAP_NONE:
			raw = _h(k, 4) % 15
		if UNLOCK_TRAP[raw] <= km:
			trap = raw
		if trap == TRAP_LIE:
			for j in range(maxi(0, k - LIE_GAP), k):
				if int(_codes[j]["trap"]) == TRAP_LIE:
					trap = TRAP_NONE
					break
	var lvl_max := 3 if km >= 100.0 else (2 if km >= 30.0 else 1)
	var trap_level := mini(_h(k, 5) % 4, lvl_max)
	if ph == BUILD or ph == FADE:
		trap_level = mini(trap_level, 1)
	var trap_at := _h(k, 6) % 4

	# 3. Budowla i przekrój - surowe, potem dopasowane do pułapki.
	var structure := _h(k, 7) % 8
	if UNLOCK_STRUCT[structure] > km or k < FIRST_CALM:
		structure = 0
	var section := _h(k, 8) % 8
	if UNLOCK_SECTION[section] > km or k < FIRST_CALM:
		section = 0
	if section == 1 and structure != 4:
		section = 0
	if TRAP_STRUCT.has(trap):
		var need: int = TRAP_STRUCT[trap]
		if UNLOCK_STRUCT[need] <= km:
			structure = need
		else:
			trap = TRAP_NONE
	if TRAP_SECTION.has(trap):
		var need2: int = TRAP_SECTION[trap]
		if UNLOCK_SECTION[need2] <= km:
			section = need2
		else:
			trap = TRAP_NONE
	if trap == 1:
		section = 7
		trap_at = 3

	# 4. Gramatyka sąsiedztwa.
	if structure != 0:
		var climb_go_on := structure == 4 and not prev.is_empty() and int(prev["structure"]) == 4
		var repeated := false
		for j in range(maxi(0, k - SAME_STRUCT_GAP + 1), k):
			if int(_codes[j]["structure"]) == structure:
				repeated = true
		if repeated and not climb_go_on:
			if TRAP_STRUCT.has(trap):
				trap = TRAP_NONE
			structure = 0
	var narrow_run := 0
	var j2 := k - 1
	while j2 >= maxi(0, k - NARROW_MAX):
		if int(_codes[j2]["section"]) in NARROW:
			narrow_run += 1
			j2 -= 1
		else:
			break
	if section in NARROW and narrow_run >= NARROW_MAX - 1:
		if TRAP_SECTION.has(trap) or trap == 1:
			trap = TRAP_NONE
		section = 0
	if section == 1 and structure != 4:
		section = 0

	# 5. Koszt na Queście (ten i poprzedni odcinek zbudowane naraz).
	var d_mid := (k + 0.5) * SEG_LEN
	var prev_cost: int = int(prev["cost"]) if not prev.is_empty() else 0
	# Budowla bez kosztu (podjazd) zostaje - jej wycięcie nic nie daje,
	# a zostawiało pas dla wolnych bez podjazdu (ziarno 5 z pogodą).
	if _cost(structure, event, d_mid) + prev_cost > COST_MAX and int(COST_STRUCT[structure]) > 0:
		if TRAP_STRUCT.has(trap):
			trap = TRAP_NONE
		structure = 0
	if _cost(structure, event, d_mid) + prev_cost > COST_MAX:
		event = 0

	if trap == TRAP_NONE:
		trap_level = 0
	if event == 0:
		ev_level = 0
	var s := {"k": k, "phase": ph, "structure": structure, "s_len": _h(k, 9) % 4,
			"s_param": _h(k, 10) % 8, "section": section,
			"change_at": _h(k, 11) % 4 if trap != 1 else 3,
			"variant": _h(k, 12) % 8, "trap": trap, "trap_at": trap_at,
			"trap_level": trap_level, "event": event, "ev_level": ev_level,
			"accent": _h(k, 13) % 8}
	s["cost"] = _cost(structure, event, d_mid)
	s["code"] = pack(s)
	return s


static func pack(s: Dictionary) -> int:
	var b0: int = int(s["structure"]) | (int(s["s_len"]) << 3) | (int(s["s_param"]) << 5)
	var b1: int = int(s["section"]) | (int(s["change_at"]) << 3) | (int(s["variant"]) << 5)
	var b2: int = int(s["trap"]) | (int(s["trap_at"]) << 4) | (int(s["trap_level"]) << 6)
	var b3: int = int(s["event"]) | (int(s["ev_level"]) << 3) | (int(s["accent"]) << 5)
	return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)


## Rozkład kodu na pola (odwrotność pack, do logów i odtwarzania).
static func unpack(code: int) -> Dictionary:
	return {"structure": code & 7, "s_len": (code >> 3) & 3, "s_param": (code >> 5) & 7,
			"section": (code >> 8) & 7, "change_at": (code >> 11) & 3, "variant": (code >> 13) & 7,
			"trap": (code >> 16) & 15, "trap_at": (code >> 20) & 3, "trap_level": (code >> 22) & 3,
			"event": (code >> 24) & 7, "ev_level": (code >> 27) & 3, "accent": (code >> 29) & 7}


## Rondo w mieście (użytkownik 2026-11-13: "dodać do urozmaiceń rondo?
## najlepiej w mieście"). Przejazd przez miasto (structure 7) z s_param 0-3
## ma rondo w połowie odcinka; s_param = indeks promienia ROUNDABOUT_R.
## s_param 4-7: miasto bez ronda. Zlecenie: inbox 2026-11-13-rondo-w-miescie.md.
const ROUNDABOUT_R := [22.0, 28.0, 34.0, 40.0]
const ROUNDABOUT_AT := 0.5


## Promień ronda [m] na środku wyspy do osi pierścienia; 0 = brak ronda.
static func roundabout_r(s: Dictionary) -> float:
	if int(s["structure"]) != 7 or int(s["s_param"]) >= 4:
		return 0.0
	return float(ROUNDABOUT_R[int(s["s_param"])])


## Krótki opis do logu: "k 5 peak 0xCC0FC808 nasyp / 2+2 / brak / pościg od tyłu".
func describe(k: int) -> String:
	var s := segment(k)
	var st: String = STRUCTURES[int(s["structure"])]
	if roundabout_r(s) > 0.0:
		st += " z rondem R%.0f" % roundabout_r(s)
	return "k %d %s 0x%08X %s / %s / %s / %s" % [k, s["phase"], int(s["code"]),
			st, SECTIONS[int(s["section"])], TRAPS[int(s["trap"])], EVENTS[int(s["event"])]]
