extends RefCounted
class_name HighwayGenerator

## Generator jezdni trybu "Autostrada": kawałki po ~CHUNK_LEN metrów
## w formacie odcinków StuntTrack (len, curve, pitch, bank, width, limit,
## meta), według planu HighwayPlan (miasta, ograniczenia, objazdy).
##
## Różnice względem TrackGenerator (wąwóz):
##   - 2 pasy w każdą stronę na całej długości (WIDTH = nasza jezdnia, druga
##     jezdnia jak dziś w StuntTrack._build_highway);
##   - płasko (pitch 0) na stałej wysokości ROAD_Y - teren to dziś płaszczyzna
##     y = 0; garby dojdą razem z terenem gór (spec, etap 2);
##   - szerokie łuki (R 900-2500 m, przechyłka 2,5°), w mieście ciaśniej
##     i wolniej;
##   - każda zmiana ograniczenia (miasto, stopniowanie 70/50) wypada DOKŁADNIE
##     na granicy odcinka - StuntTrack stawia znak B-33 / B-34 przy zmianie
##     klucza "limit".
##
## WSPÓŁRZĘDNE LOKALNE: każdy kawałek zaczyna się w (0, ROAD_Y, 0) swojego
## węzła (`localize`), a węzeł stoi w miejscu końca poprzedniego. Dzięki
## temu wierzchołki i próbki kawałka nie przekraczają ~2 km, a precyzja
## float32 (Vector3) nie spada z dystansem - patrz WorldOrigin i spec
## docs/AUTOSTRADA.md. Dystans ("dist") i kurs ("yaw") są w stanie jako
## float GDScriptu (64 bity), więc się nie psują.
##
## Moduł odizolowany: nic go jeszcze nie używa. Test na płasko:
##   godot --headless --xr-mode off -s res://tests/highway_gen_test.gd -- [ziarno] [km] </dev/null

const LANE_W := 3.75
const LANES := 2
const SHOULDER_R := 3.0          # pas awaryjny
const SHOULDER_L := 0.75         # opaska przy pasie rozdziału
const WIDTH := LANES * LANE_W + SHOULDER_R + SHOULDER_L     # 11,25 m
const ROAD_Y := 1.0              # jezdnia nad terenem [m] (niski nasyp)
const CHUNK_LEN := 1000.0
const STEP := 2.0                # krok próbkowania jak w TrackGenerator
## Największe odchylenie kursu od początkowego - trasa nie zawraca (ten sam
## powód co TrackGenerator.MAX_YAW), więc współrzędne rosną liniowo.
const MAX_YAW := deg_to_rad(40.0)
const R_MIN := 900.0
const R_MAX := 2500.0
const R_MIN_CITY := 250.0
const R_MAX_CITY := 600.0
const BANK := 2.5                # przechyłka na łukach autostrady [°]
const BANK_CITY := 0.0
const EASE := 60.0               # wejście / wyjście z przechyłki [m]
## Moduł krótszy niż to przed najbliższym znacznikiem -> prosta do znacznika.
const MIN_MODULE := 120.0

var plan: HighwayPlan
## Przekroje jezdni (etap 2 urozmaiceń): ograniczenie w strefach
## i szerokość w skosach. null - zawsze 2+2 (testy generatora).
var sections: SectionPlan
## Budowle (etap 3): granice stref dzielą odcinki, ograniczenie (tunel 100,
## zjazd 80), meta "structure" na pierwszym odcinku budowli.
var structures: StructurePlan
## Pogoda (WeatherPlan): mokra jezdnia w strefach opadu - odcinki dzielone
## w punktach zmiany nawierzchni (zlecenie warstwa-pogody). null = sucho.
var weather: WeatherPlan
var rng := RandomNumberGenerator.new()
var chunks := 0


func _init(p: HighwayPlan, seed_v := 1) -> void:
	plan = p
	rng.seed = hash([seed_v, "highway_gen"])


## Środek pasu `lane` [m w prawo od osi NASZEJ jezdni]: lane 0 = prawy
## (wolny), 1 = lewy (szybki). `oncoming` = pas jezdni z naprzeciwka (jej
## oś w -(width + median), lustrzanie: jej prawy pas jest dalej od pasa
## rozdziału). Pas awaryjny (SHOULDER_R) zostaje wolny - dzisiejszy wzór
## (w - 1) / 3 z trzech pasów kładłby auta na nim (spec, docs/AUTOSTRADA.md).
static func lane_center(lane: int, oncoming := false, width := WIDTH,
		median := TrackGenerator.HIGHWAY_MEDIAN) -> float:
	var from_left := SHOULDER_L + LANE_W * (float(LANES - 1 - clampi(lane, 0, LANES - 1)) + 0.5)
	var x := -width * 0.5 + from_left            # nasza jezdnia: lewa krawędź + ...
	if oncoming:
		return -(width + median) - x             # lustro względem osi drugiej jezdni
	return x


## Stan startu pierwszego kawałka (w układzie kawałka).
static func first_state() -> Dictionary:
	return {"pos": Vector3(0.0, ROAD_Y, 0.0), "yaw": 0.0, "pitch": 0.0, "bank": 0.0,
			"width": WIDTH, "dist": 0.0, "limit": HighwayPlan.LIMIT_HIGHWAY}


## Rozdziela stan końca poprzedniego kawałka (pozycja w układzie świata,
## StuntTrack.end_state) na stan lokalny nowego kawałka i położenie jego
## węzła: {"state": {...pos = (0, y, 0)}, "origin": Vector3(x, 0, z)}.
static func localize(global_state: Dictionary) -> Dictionary:
	var st := global_state.duplicate()
	var p: Vector3 = st.get("pos", Vector3.ZERO)
	st["pos"] = Vector3(0.0, p.y, 0.0)
	return {"state": st, "origin": Vector3(p.x, 0.0, p.z)}


## Odcinki kolejnego kawałka od stanu `start` (lokalnego). Kawałek kończy się
## na granicy modułu, gdy przekroczy CHUNK_LEN (zwykle 1,0-1,6 km).
func next_chunk(start: Dictionary) -> Array:
	chunks += 1
	var out: Array = []
	var state := start.duplicate()
	var d0: float = state.get("dist", 0.0)
	var first := true
	while float(state["dist"]) - d0 < CHUNK_LEN:
		var meta := {}
		if first:
			var bl := plan.biome_blend(d0)
			meta["autostrada"] = {"chunk": chunks, "biome": bl["a"], "blend": bl}
			first = false
		_module(out, state, meta)
	return out


## Najbliższy znacznik (zmiana ograniczenia, granica miasta, objazd) za `d`.
func _next_mark(d: float) -> Dictionary:
	var best := {"dist": INF}
	for m in plan.limit_changes(d + 0.5, d + 6000.0):
		if float(m[0]) < float(best["dist"]):
			best = {"dist": float(m[0]), "kind": "limit"}
	if sections:
		for m in sections.limit_marks(d + 0.5, d + 6000.0):
			if float(m[0]) < float(best["dist"]):
				best = {"dist": float(m[0]), "kind": "limit"}
		# Punkty zmiany szerokości strefy (2c-2e: skos wejścia i wyjścia) -
		# szerokość odcinka liczona na jego końcu (_seg).
		for m in sections.width_marks(d + 0.5, d + 6000.0):
			if m < float(best["dist"]):
				best = {"dist": m, "kind": "section"}
	if structures:
		for z in structures.zones(d + 0.5, d + 6000.0):
			for m in [float(z["start"]), float(z["end"])]:
				if m > d + 0.5 and m < float(best["dist"]):
					best = {"dist": m, "kind": "structure"}
	for j in plan.jumps_between(d + 0.5, d + 6000.0):
		if float(j["start"]) > d + 0.5 and float(j["start"]) < float(best["dist"]):
			best = {"dist": float(j["start"]), "kind": "detour", "jump": j}
	for st in plan.stations_between(d + 0.5, d + 6000.0) + plan.workshops_between(d + 0.5, d + 6000.0):
		var sign_d := float(st["start"]) - TrackGenerator.SERVICE_SIGN_DIST
		for m in [sign_d, float(st["start"])]:
			if m > d + 0.5 and m < float(best["dist"]):
				best = {"dist": m, "kind": "service"}
	return best


func _module(out: Array, state: Dictionary, meta: Dictionary) -> void:
	var d: float = state["dist"]
	var mark := _next_mark(d)
	var room: float = float(mark["dist"]) - d
	# Objazd zaczyna się tutaj: prosta przez całą jego długość (rampa stoi
	# na równoległym pasie, jezdnia główna zostaje prosta i płaska).
	for j in plan.jumps_between(d, d + 1.0):
		if absf(float(j["start"]) - d) < 0.5:
			# Na razie wielka skocznia (do 400 km/h, użytkownik 2026-11-09) na
			# jezdni głównej; objazd z równoległym pasem - etap 4 spec.
			meta["detour"] = j
			# Skocznia (rozbieg, rampa, stół) zawsze sucha - także w deszczu
			# (pogoda dzieli tylko odcinki z _seg).
			TrackGenerator._big_jump(out, state, meta.duplicate())
			meta.clear()
			_seg(out, state, float(j["end"]) - float(state["dist"]), 0.0, 0.0, meta)
			return
	# Stacja paliw: znak zjazdu SERVICE_SIGN_DIST przed, potem pas zjazdu
	# jak w wąwozie (StuntTrack._build_service, tankowanie w xr_main).
	# Warsztat w każdym mieście (tier 0: xr_main proponuje próg o jeden
	# wyżej niż obecny), ograniczenie z planu (30 w mieście).
	var svcs := []
	for st in plan.stations_between(d - 1.0, d + TrackGenerator.SERVICE_SIGN_DIST + 1.0):
		svcs.append([st, "station", 70.0])
	for ws in plan.workshops_between(d - 1.0, d + TrackGenerator.SERVICE_SIGN_DIST + 1.0):
		svcs.append([ws, "workshop", -1.0])
	for sv in svcs:
		var st: Dictionary = sv[0]
		if absf(float(st["start"]) - TrackGenerator.SERVICE_SIGN_DIST - d) < 0.5:
			meta["service_ahead"] = sv[1]
		elif absf(float(st["start"]) - d) < 0.5:
			var w_ext := WIDTH + TrackGenerator.SERVICE_EXTRA_W
			var lim: float = sv[2]
			_seg(out, state, 40.0, 0.0, 0.0, meta, w_ext, lim)
			_seg(out, state, TrackGenerator.SERVICE_LEN, 0.0, 0.0, {"service": {"kind": sv[1],
					"len": TrackGenerator.SERVICE_LEN, "road_w": WIDTH, "tier": 0}}, w_ext, lim)
			_seg(out, state, 40.0, 0.0, 0.0, {}, WIDTH, lim)
			return
	var city := plan.city_at(d + 0.5)       # +0,5: dist po próbkowaniu bywa o 1e-9 przed znacznikiem
	if not city.is_empty() and absf(float(city["start"]) - d) < 0.5:
		meta["city_start"] = city
	var prev_city := plan.city_at(d - 1.0)
	if not prev_city.is_empty() and absf(float(prev_city["end"]) - d) < 0.5:
		meta["city_end"] = prev_city
	if room < MIN_MODULE * 2.0:
		_seg(out, state, room, 0.0, 0.0, meta)
		return
	var in_city := not city.is_empty()
	var roll := rng.randf()
	if roll < (0.5 if in_city else 0.45):
		_curve(out, state, meta, room, in_city)
	else:
		var length := rng.randf_range(150.0, 400.0) if in_city else rng.randf_range(300.0, 900.0)
		_seg(out, state, minf(length, room), 0.0, 0.0, meta)


## Łuk: wejście w przechyłkę (EASE), łuk, wyjście (EASE), tak żeby kurs nie
## przekroczył MAX_YAW. Nie mieści się przed znacznikiem -> prosta.
func _curve(out: Array, state: Dictionary, meta: Dictionary, room: float, in_city: bool) -> void:
	var yaw: float = state.get("yaw", 0.0)
	var dir := -1.0 if rng.randf() < 0.5 else 1.0
	if absf(yaw) > MAX_YAW * 0.4:
		dir = -signf(yaw)              # zakręt w prawo zwiększa yaw (StuntTrack)
	var r := rng.randf_range(R_MIN_CITY, R_MAX_CITY) if in_city else rng.randf_range(R_MIN, R_MAX)
	var ang := deg_to_rad(rng.randf_range(8.0, 30.0) if in_city else rng.randf_range(5.0, 25.0))
	# Nie dalej niż MAX_YAW od kierunku startu.
	ang = minf(ang, MAX_YAW - dir * yaw)
	var arc := ang * r
	var bank := (BANK_CITY if in_city else BANK) * dir
	var total := arc + 2.0 * EASE
	if ang < deg_to_rad(2.0) or total > room:
		_seg(out, state, minf(rng.randf_range(300.0, 700.0), room), 0.0, 0.0, meta)
		return
	var k := rad_to_deg(1.0 / r) * dir           # stopnie na metr (StuntTrack)
	# Krzywizna stała w odcinku (StuntTrack nie ma klotoid) - połowa
	# krzywizny na wejściu i wyjściu łagodzi skok przyspieszenia bocznego.
	var arc_core := arc - EASE                  # 2 × EASE z połową krzywizny = EASE pełnej
	# Bez "curve_len"/"curve_sign": przy R >= 250 m tablice U-3 co 12 m
	# i znak A-1 byłyby przesadą (StuntTrack stawia je dla wąwozu).
	meta["arc"] = {"r": r, "dir": int(dir)}
	_seg(out, state, EASE, k * 0.5, bank, meta)
	_seg(out, state, arc_core, k, bank, {})
	_seg(out, state, EASE, k * 0.5, 0.0, {})
	_seg(out, state, EASE, 0.0, 0.0, {})


## Dokłada odcinek i przesuwa stan przez prawdziwe próbkowanie (jak
## TrackGenerator._push) - stan zgadza się co do milimetra z torem.
func _seg(out: Array, state: Dictionary, length: float, curve: float, bank: float, meta: Dictionary,
		width := WIDTH, limit := -1.0) -> void:
	if length < 0.5:
		return
	var d: float = state["dist"]
	# Zmiana nawierzchni w środku odcinka: dzielimy (krzywizna i przechył są
	# na metr / stałe, więc geometria się nie zmienia).
	if weather:
		for ch in weather.surface_changes(d + 0.5, d + length - 0.5):
			var cut: float = float(ch["d"]) - d
			if cut > 0.5 and cut < length - 0.5:
				_seg(out, state, cut, curve, bank, meta, width, limit)
				_seg(out, state, length - cut, curve, bank, {}, width, limit)
				return
	var surf := weather.surface(d + 0.25) if weather else "dry"
	# Przekrój (etap 2c-2e): szerokość na końcu odcinka (StuntTrack przechodzi
	# płynnie od poprzedniej), odcinki dzielone w punktach strefy.
	if sections and is_equal_approx(width, WIDTH):
		width = float(sections.lanes_at(d + length - 0.25)["width"])
	var lim := limit if limit > 0.0 else plan.limit_at(d + 0.25)
	if sections and limit <= 0.0:
		lim = minf(lim, sections.limit_at(d + 0.25))
	if structures and limit <= 0.0:
		lim = minf(lim, structures.limit_at(d + 0.25))
	var seg := {"len": length, "curve": curve, "pitch": 0.0, "bank": bank,
			"width": width, "surface": surf, "limit": lim}
	if not meta.is_empty():
		seg["meta"] = meta.duplicate()
		meta.clear()
	out.append(seg)
	var smp := StuntTrack.sample_segments([seg], state, STEP)
	var e: Dictionary = smp[-1]["end_state"]
	for key in e:
		state[key] = e[key]
