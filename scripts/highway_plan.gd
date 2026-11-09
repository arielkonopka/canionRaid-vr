extends RefCounted
class_name HighwayPlan

## Plan trybu "Autostrada" (ustalenia użytkownika 2026-11-09, HANDOVER
## sekcja 2): co się dzieje na którym kilometrze. Czysta logika, bez
## węzłów i bez Godota-sceny - generator jezdni (HighwayGenerator), zabudowa
## (CityBuilder), ruch (TrafficZone) i HUD pytają plan o dystans `d` [m]
## od startu.
##
##   - sceneria (biom) zmienia się co 50 km ± 10 km (losowo), z przejściem
##     BIOME_BLEND metrów;
##   - miasta: co 25 km małe (~1 km zabudowy), co 100 km duże (~5 km),
##     strefa 30 km/h, przed nią stopniowanie 70 / 50;
##   - ruch: 3-5 aut/km do TRAFFIC_RADIUS od krawędzi miasta;
##   - objazdy ze skocznią: rzadko, nigdy w mieście ani przy nim;
##   - słupki: hektometrowe co 100 m, kilometrowe co 1 km.
##
## Wszystko deterministyczne z ziarna i liczone leniwie - plan sięga
## dowolnie daleko (setki km) bez tablic na całą trasę. Dystanse to float
## GDScriptu (64 bity), więc precyzja nie spada z kilometrami (inaczej niż
## Vector3, patrz WorldOrigin).

const BIOMES := ["fields", "meadow", "desert", "mountains", "seaside", "canyon"]
## Pierwszy biom (start gry): łagodny, z punktami odniesienia przy drodze.
const FIRST_BIOME := "meadow"
const BIOME_LEN := 50000.0
const BIOME_JITTER := 10000.0
## Długość przejścia między biomami [m] (mieszanie terenu i obiektów).
const BIOME_BLEND := 2000.0

const SMALL_CITY_EVERY := 25000.0
const SMALL_CITY_LEN := 1000.0
const BIG_CITY_EVERY := 100000.0
const BIG_CITY_LEN := 5000.0
## Strefy przed miastem (od krawędzi zabudowy wstecz): [długość, limit].
## Za miastem od razu koniec ograniczenia (B-34 jak dziś).
const CITY_APPROACH := [[600.0, 70.0], [250.0, 50.0]]
const LIMIT_CITY := 30.0
const LIMIT_HIGHWAY := 140.0

## Ruch wokół miasta: gęstość [aut/km] losowana na miasto z tego przedziału,
## do tylu metrów od krawędzi zabudowy.
const TRAFFIC_MIN := 3.0
const TRAFFIC_MAX := 5.0
const TRAFFIC_RADIUS := 5000.0

## Objazdy ze skocznią: w każdym bloku JUMP_BLOCK metrów najwyżej jeden,
## z szansą JUMP_CHANCE; nie bliżej niż JUMP_CITY_CLEAR od zabudowy.
const JUMP_BLOCK := 10000.0
const JUMP_CHANCE := 0.35
## Długość objazdu: na razie wielka skocznia na jezdni głównej
## (TrackGenerator._big_jump, ~551 m) - pełny objazd z równoległym pasem to
## etap 4 spec. (było 450 m dla samego objazdu).
const JUMP_LEN := 600.0
const JUMP_CITY_CLEAR := 2000.0
## Pierwsze metry trasy bez atrakcji (rozruch, oswojenie z autem).
const JUMP_FIRST := 4000.0

var seed_value := 0
## Granice biomów: _bounds[k] = początek biomu k (k = 0 zaczyna się w 0).
var _bounds := PackedFloat64Array([0.0])
var _kinds := PackedStringArray([FIRST_BIOME])
var _rng := RandomNumberGenerator.new()


func _init(seed_v := 1) -> void:
	seed_value = seed_v


## Liczba losowa [0, 1) zależna tylko od ziarna, klucza i "soli" - ta sama
## przy każdym pytaniu, w dowolnej kolejności.
func _rand(key: int, salt: int) -> float:
	_rng.seed = hash([seed_value, key, salt])
	return _rng.randf()


# --------------------------------------------------------------------------
# Biomy
# --------------------------------------------------------------------------

func _extend_biomes(d: float) -> void:
	while _bounds[_bounds.size() - 1] <= d:
		var k := _bounds.size()
		var len_k := BIOME_LEN + (_rand(k, 1) * 2.0 - 1.0) * BIOME_JITTER
		_bounds.append(_bounds[k - 1] + len_k)
		# Inny niż poprzedni (zmiana scenerii ma być widoczna).
		var prev := _kinds[k - 1]
		var choices := []
		for b in BIOMES:
			if b != prev:
				choices.append(b)
		_kinds.append(choices[int(_rand(k, 2) * choices.size()) % choices.size()])


## Indeks biomu na dystansie d.
func biome_index(d: float) -> int:
	d = maxf(d, 0.0)
	_extend_biomes(d)
	# Wyszukiwanie binarne: ostatnia granica <= d.
	var lo := 0
	var hi := _bounds.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if _bounds[mid] <= d:
			lo = mid
		else:
			hi = mid - 1
	return lo


func biome_at(d: float) -> String:
	return _kinds[biome_index(d)]


## Początek i koniec biomu nr k [m].
func biome_range(k: int) -> Vector2:
	while _bounds.size() <= k + 1:
		_extend_biomes(_bounds[_bounds.size() - 1])
	return Vector2(_bounds[k], _bounds[k + 1])


## Mieszanie na granicy: {"a": biom, "b": następny/poprzedni, "t": 0..1}.
## t = udział "b"; przejście trwa BIOME_BLEND, wyśrodkowane na granicy.
func biome_blend(d: float) -> Dictionary:
	var k := biome_index(d)
	var r := biome_range(k)
	var half := BIOME_BLEND * 0.5
	if k > 0 and d < r.x + half:
		var t := 0.5 - (d - r.x) / BIOME_BLEND
		return {"a": _kinds[k], "b": _kinds[k - 1], "t": clampf(t, 0.0, 0.5)}
	if d > r.y - half:
		var t := 0.5 - (r.y - d) / BIOME_BLEND
		return {"a": _kinds[k], "b": _kinds[k + 1], "t": clampf(t, 0.0, 0.5)}
	return {"a": _kinds[k], "b": _kinds[k], "t": 0.0}


# --------------------------------------------------------------------------
# Miasta
# --------------------------------------------------------------------------

## Miasto nr n (n >= 1): co 25 km, co 4. (co 100 km) duże. Zabudowa zaczyna
## się na n·25 km. {"index", "big", "start", "end", "density", "name_seed"}.
func city(n: int) -> Dictionary:
	if n < 1:
		return {}
	var start := float(n) * SMALL_CITY_EVERY
	var big := is_zero_approx(fmod(start, BIG_CITY_EVERY))
	var length := BIG_CITY_LEN if big else SMALL_CITY_LEN
	return {
		"index": n,
		"big": big,
		"start": start,
		"end": start + length,
		"density": lerpf(TRAFFIC_MIN, TRAFFIC_MAX, _rand(n, 3)),
		"name_seed": hash([seed_value, n, 4]),
	}


## Wymyślona nazwa miejscowości z `name_seed` (sylaby w polskim brzmieniu,
## bez prawdziwych miejscowości - zasada projektu: nic z cudzego świata).
const NAME_A := ["Brze", "Gro", "Wil", "Stru", "Ka", "Mo", "Ja", "Ró", "Sie", "Dą", "Ło", "Pie", "Zbo", "Kru", "Ole"]
const NAME_B := ["ko", "dzi", "la", "ra", "mi", "szy", "ce", "wo", "nie", "ga", "ty", "so"]
const NAME_C := ["wice", "ówek", "nin", "sko", "lin", "wo", "dziec", "ków", "ice", "any", "owo", "ów"]


static func city_name(name_seed: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = name_seed
	var n: String = NAME_A[r.randi() % NAME_A.size()]
	if r.randf() < 0.6:
		n += NAME_B[r.randi() % NAME_B.size()]
	return n + NAME_C[r.randi() % NAME_C.size()]


## Miasto, w którego zabudowie jest d ({} - poza miastem).
func city_at(d: float) -> Dictionary:
	var c := city(int(floor(d / SMALL_CITY_EVERY)))
	if not c.is_empty() and d >= c["start"] and d < c["end"]:
		return c
	return {}


## Najbliższe miasto (po krawędzi zabudowy) i odległość od niej [m]
## (0 w zabudowie). {"city": {...}, "gap": m}.
func nearest_city(d: float) -> Dictionary:
	var n := int(floor(d / SMALL_CITY_EVERY))
	var best := {}
	var best_gap := INF
	for k in [n - 1, n, n + 1]:
		var c := city(k)
		if c.is_empty():
			continue
		var gap := 0.0
		if d < c["start"]:
			gap = c["start"] - d
		elif d > c["end"]:
			gap = d - c["end"]
		if gap < best_gap:
			best_gap = gap
			best = c
	return {"city": best, "gap": best_gap}


## Miasta, których zabudowa nachodzi na [d0, d1).
func cities_between(d0: float, d1: float) -> Array:
	var out := []
	for n in range(maxi(int(floor(d0 / SMALL_CITY_EVERY)) - 1, 1), int(floor(d1 / SMALL_CITY_EVERY)) + 1):
		var c := city(n)
		if c["end"] > d0 and c["start"] < d1:
			out.append(c)
	return out


# --------------------------------------------------------------------------
# Ograniczenia prędkości
# --------------------------------------------------------------------------

## Ograniczenie [km/h] na dystansie d.
func limit_at(d: float) -> float:
	if not city_at(d).is_empty():
		return LIMIT_CITY
	# Stopniowanie przed miastem (tylko przed - za miastem koniec strefy).
	var c := city(int(floor((d + 2000.0) / SMALL_CITY_EVERY)))
	if not c.is_empty() and d < c["start"]:
		var before: float = c["start"] - d
		var edge := 0.0
		for step in CITY_APPROACH:
			edge += float(step[0])
		# CITY_APPROACH: od najdalszego (70) do najbliższego (50).
		var acc := edge
		for step in CITY_APPROACH:
			if before <= acc and before > acc - float(step[0]):
				return float(step[1])
			acc -= float(step[0])
	return LIMIT_HIGHWAY


## Punkty zmiany ograniczenia w [d0, d1): [[dystans, limit], ...] - dla
## generatora (klucz "limit" odcinków) i znaków B-33 / B-34.
func limit_changes(d0: float, d1: float) -> Array:
	var out := []
	for c in cities_between(d0 - 1000.0, d1 + 1000.0):
		var marks := []
		var acc := 0.0
		for step in CITY_APPROACH:
			acc += float(step[0])
		var dd: float = c["start"] - acc
		for step in CITY_APPROACH:
			marks.append([dd, float(step[1])])
			dd += float(step[0])
		marks.append([c["start"], LIMIT_CITY])
		marks.append([c["end"], LIMIT_HIGHWAY])
		for m in marks:
			if m[0] >= d0 and m[0] < d1:
				out.append(m)
	return out


# --------------------------------------------------------------------------
# Ruch
# --------------------------------------------------------------------------

## Gęstość ruchu [aut/km na naszej jezdni] na dystansie d; 0 poza strefami
## miast. Druga jezdnia (z naprzeciwka) - tyle samo, liczy TrafficZone.
func traffic_density(d: float) -> float:
	var nc := nearest_city(d)
	if nc["city"].is_empty() or float(nc["gap"]) > TRAFFIC_RADIUS:
		return 0.0
	return float(nc["city"]["density"])


func in_traffic_zone(d: float) -> bool:
	return traffic_density(d) > 0.0


# --------------------------------------------------------------------------
# Objazdy ze skocznią
# --------------------------------------------------------------------------

## Objazd w bloku nr b ({} - brak): {"start", "end", "side"} - side +1 =
## po prawej (od strony pobocza). Objazd to rampa na równoległym pasie za
## przerwą w barierze; gracz może go ominąć (wjazd dobrowolny).
func jump_in_block(b: int) -> Dictionary:
	if b < 0 or _rand(b, 5) >= JUMP_CHANCE:
		return {}
	var start := float(b) * JUMP_BLOCK + 1000.0 + _rand(b, 6) * (JUMP_BLOCK - 2000.0 - JUMP_LEN)
	var end := start + JUMP_LEN
	if start < JUMP_FIRST:
		return {}
	if not cities_between(start - JUMP_CITY_CLEAR, end + JUMP_CITY_CLEAR).is_empty():
		return {}
	return {"start": start, "end": end, "side": 1}


func jumps_between(d0: float, d1: float) -> Array:
	var out := []
	for b in range(maxi(int(floor(d0 / JUMP_BLOCK)), 0), int(floor(d1 / JUMP_BLOCK)) + 1):
		var j := jump_in_block(b)
		if not j.is_empty() and j["end"] > d0 and j["start"] < d1:
			out.append(j)
	return out


# --------------------------------------------------------------------------
# Stacje paliw
# --------------------------------------------------------------------------

## Stacje co STATION_EVERY (użytkownik 2026-11-09: "stacje rzadziej, co
## ~20 km" - paliwo ma być wyzwaniem; bak ~25 km spokojnej jazdy). Przesunięte
## o STATION_OFFSET, żeby nie wypadały w miastach (co 25 km); stacja
## pomijana, gdy w pobliżu miasto albo skocznia.
const STATION_EVERY := 20000.0
const STATION_OFFSET := 12500.0
const STATION_CLEAR := 1500.0
const STATION_LEN := 190.0          # wjazd 40 + stacja 110 + wyjazd 40


func station(k: int) -> Dictionary:
	if k < 0:
		return {}
	var start := float(k) * STATION_EVERY + STATION_OFFSET
	var end := start + STATION_LEN
	if not cities_between(start - STATION_CLEAR, end + STATION_CLEAR).is_empty():
		return {}
	if not jumps_between(start - STATION_CLEAR, end + STATION_CLEAR).is_empty():
		return {}
	return {"start": start, "end": end}


func stations_between(d0: float, d1: float) -> Array:
	var out := []
	for k in range(maxi(int(floor((d0 - STATION_OFFSET) / STATION_EVERY)), 0),
			int(floor((d1 - STATION_OFFSET) / STATION_EVERY)) + 1):
		var st := station(k)
		if not st.is_empty() and st["end"] > d0 and st["start"] < d1:
			out.append(st)
	return out


## Warsztat w każdym mieście (użytkownik 2026-11-09), WORKSHOP_IN m za
## początkiem zabudowy (strefa 30 km/h), pas zjazdu jak stacja.
const WORKSHOP_IN := 300.0


func workshops_between(d0: float, d1: float) -> Array:
	var out := []
	for c in cities_between(d0 - WORKSHOP_IN - STATION_LEN, d1):
		var start := float(c["start"]) + WORKSHOP_IN
		var end := start + STATION_LEN
		if end > d0 and start < d1:
			out.append({"start": start, "end": end, "city": c})
	return out


# --------------------------------------------------------------------------
# Słupki
# --------------------------------------------------------------------------

## Słupki w [d0, d1): co 100 m hektometrowy, co 1000 m kilometrowy z numerem.
## [{"dist", "km", "hm", "major"}] - km = pełne kilometry, hm = setki metrów.
func posts_between(d0: float, d1: float) -> Array:
	var out := []
	var i := int(ceil(maxf(d0, 100.0) / 100.0))
	while float(i) * 100.0 < d1:
		out.append({"dist": float(i) * 100.0, "km": i / 10, "hm": i % 10, "major": i % 10 == 0})
		i += 1
	return out
