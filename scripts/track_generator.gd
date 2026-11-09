extends RefCounted
class_name TrackGenerator

## Generator odcinków trasy bez końca.
##
## Każde wywołanie generate_section() zwraca listę odcinków toru (format
## StuntTrack) dla jednej sekcji: brama punktu kontrolnego na początku,
## potem kilka modułów (prosta, łuk z przechyłką, skok, garb, szykana,
## podjazd/zjazd), czasem plamy mokrej nawierzchni lub lodu.
##
## TRUDNOŚĆ zależy wyłącznie od dystansu od startu (ustalenie z użytkownikiem),
## nie od auta. Rośnie:
##   - prędkość potrzebna do przeskoczenia przerw,
##   - krótsze rozbiegi przed skokami (trzeba mocniej przyspieszać),
##   - ostrzejsze łuki, węższa jezdnia, częściej mokro i lód.
##
## SKOKI są liczone z balistyki na prawdziwej geometrii toru: generator
## próbkuje rampę i przerwę tą samą funkcją, która buduje tor
## (StuntTrack.sample_segments), mierzy poziomą odległość D i spadek H
## między krawędzią wybicia a krawędzią lądowiska i dobiera długość przerwy
## tak, żeby wymagana prędkość wybicia była równa docelowej:
##   v² = g·D² / (2·cos²θ·(D·tanθ + H))
## z D powiększonym o długość auta (muszą przelecieć też tylne koła).

const G := 9.81
## Ile metrów dalej niż krawędź lądowiska musi dolecieć środek auta, żeby
## wylądowały też tylne koła (rozstaw osi + zapas).
const CAR_CLEARANCE := 3.5
## Wysokość toru nad ziemią utrzymywana w tym przedziale [m].
const MIN_HEIGHT := 18.0
const MAX_HEIGHT := 70.0
## Największe odchylenie kierunku od początkowego - tor nie zawraca
## i nie przecina sam siebie.
const MAX_YAW := deg_to_rad(55.0)
## Warsztat co tyle odcinków; długość prostej z warsztatem i położenie
## linii postoju od jej początku [m].
const WORKSHOP_EVERY := 10
const WORKSHOP_STRAIGHT := 170.0
const WORKSHOP_STOP := 95.0
## Ograniczenie prędkości na otwartej drodze [km/h].
const LIMIT_OPEN := 100.0


## Ograniczenie na łuku: prędkość, przy której przyczepność (z zapasem)
## i przechyłka trzymają auto - v² = g·R·(μ + tanβ)/(1 - μ·tanβ),
## w dół do 10 km/h, 40-100 km/h.
static func curve_limit(r: float, bank_deg: float, grip: float) -> float:
	var mu := 0.7 * grip
	var tb := tan(deg_to_rad(absf(bank_deg)))
	var v := sqrt(G * r * (mu + tb) / maxf(1.0 - mu * tb, 0.2))
	return clampf(floorf(v * 3.6 / 10.0) * 10.0, 40.0, LIMIT_OPEN)


## Parametry trudności dla dystansu `dist` [m] od startu.
static func difficulty(dist: float) -> Dictionary:
	var km := dist / 1000.0
	# Strojone pod warsztat co 10 odcinków (~4,5 km): pierwsze 10 odcinków
	# kończy się na granicy możliwości słabego silnika (~105 km/h na
	# wybiciu), dalej trzeba mocniejszego.
	return {
		"km": km,
		# Prędkość wybicia: 55 km/h na starcie, +11 km/h na kilometr, do 230.
		"v_jump": clampf(15.3 + 3.05 * km, 15.3, 64.0),
		# Rozbieg przed rampą: coraz krótszy - trzeba mocniej przyspieszać.
		"runup": clampf(150.0 - 9.0 * km, 60.0, 150.0),
		"ramp_deg": clampf(10.0 + 0.6 * km, 10.0, 16.0),
		# Promień łuków: coraz ciaśniej.
		"curve_r": clampf(110.0 - 7.0 * km, 35.0, 110.0),
		"bank_deg": clampf(12.0 + 1.6 * km, 12.0, 28.0),
		# Pasy na dwa auta obok siebie (użytkownik): 3 × 4,6 m + pobocza =
		# 14,8 m na starcie, z dystansem węziej - najwyżej do 10 m.
		"width": clampf(14.8 - 0.5 * km, 10.0, 14.8),
		"p_wet": clampf(0.08 + 0.05 * km, 0.0, 0.45),
		"p_ice": clampf(-0.05 + 0.03 * km, 0.0, 0.30),
		"modules": clampi(2 + int(km * 0.35), 2, 5),
		"jumps": 1 if km < 6.0 else 2,
	}


## Prędkość [km/h], jaką auto danego progu mocy osiąga na rozbiegu
## długości runup [m], startując z 60 km/h (wyjście z łuku). Zmierzone
## testem tests/runup_test.gd na prawdziwej fizyce auta; rodzaj napędu
## przy tej samej mocy prawie nic nie zmienia (ogranicza moc).
const RUNUP_CAP := [
	# 60 m, 90 m, 120 m, 150 m
	[83.0, 92.0, 100.0, 104.0],     # 90 kW
	[92.0, 101.0, 109.0, 117.0],    # 130 kW
	[99.0, 111.0, 121.0, 130.0],    # 180 kW
	[107.0, 122.0, 133.0, 141.0],   # 250 kW
	[112.0, 129.0, 142.0, 154.0],   # 350 kW
	# Ponad 350 kW napęd na tył jest ograniczony przyczepnością, nie mocą -
	# na krótkim rozbiegu prawie nic nie zyskuje (pomiar 2026-11-08, opony
	# całoroczne, minimum z napędów). Skoki przestają tu szybko rosnąć.
	[111.0, 128.0, 144.0, 158.0],   # 500 kW
	[112.0, 129.0, 145.0, 159.0],   # 700 kW
	# 1000 kW tylko dla elektryka z silnikami w kołach; w warsztacie można
	# zostać przy starym silniku, więc trudność się już nie podnosi.
	[112.0, 129.0, 145.0, 159.0],   # 1000 kW
]


static func runup_cap(tier: int, runup: float) -> float:
	var row: Array = RUNUP_CAP[clampi(tier, 0, RUNUP_CAP.size() - 1)]
	var x := clampf((runup - 60.0) / 30.0, 0.0, 3.0)
	var i := mini(int(x), 2)
	return lerpf(row[i], row[i + 1], x - i)


## Skoki strojone pod warsztaty: odcinki 10k+1 ... 10k+10 to próg mocy k.
## W obrębie progu wymagana prędkość u podstawy rampy rośnie od granicy
## poprzedniego silnika do 93% możliwości obecnego, a rozbieg skraca się
## ze 150 do 105 m - każdy silnik jest wykorzystany do końca tuż przed
## kolejnym warsztatem. Dalej (po ostatnim progu) prędkość już nie rośnie,
## trudność dają łuki, wąska jezdnia i nawierzchnia.
static func jump_schedule(index: int) -> Dictionary:
	var tier := (index - 1) / WORKSHOP_EVERY
	var i := (index - 1) % WORKSHOP_EVERY
	var t := float(i) / float(WORKSHOP_EVERY - 1)
	var runup := lerpf(150.0, 105.0, t)
	var top: int = RUNUP_CAP.size() - 1
	if tier > top:
		return {"runup": 105.0, "v_bottom_kmh": runup_cap(top, 105.0) * 0.93}
	var lo := 60.0 if tier == 0 else runup_cap(tier - 1, runup) * 0.92
	var hi := runup_cap(tier, runup) * 0.93
	return {"runup": runup, "v_bottom_kmh": lerpf(lo, hi, t)}


## Autostrada zamiast wąwozu (użytkownik): co 5 odcinków (3., 8., 13., ...)
## cały odcinek - nie wypada na stację (5., 10., ...) ani warsztat (11., ...).
const HIGHWAY_EVERY := 5
const HIGHWAY_PHASE := 3
const LIMIT_HIGHWAY := 140.0
const HIGHWAY_HEIGHT := 4.0          # jezdnia nad terenem na autostradzie [m]
## Odstęp jezdni: środek naszej jezdni -> środek przeciwnej (szerokość jezdni
## + pas rozdziału z barierą).
const HIGHWAY_MEDIAN := 3.0


static func is_highway(index: int) -> bool:
	return index >= HIGHWAY_PHASE and index % HIGHWAY_EVERY == HIGHWAY_PHASE


## Sekcja nr `index` (od 1) zaczynająca się w stanie `start` (jak
## StuntTrack.start_state). Zwraca listę odcinków.
static func generate_section(index: int, start: Dictionary, rng: RandomNumberGenerator,
		canyon := false) -> Array:
	if canyon and is_highway(index):
		return _highway_section(index, start, rng)
	var d := difficulty(start.get("dist", 0.0))
	# Wąwóz: bez przerw w jezdni (skocznie ze stołem) i nisko - ściany mają
	# 30 m, a płaskowyż na ich szczycie nie może wisieć nad przepaścią.
	d["canyon"] = canyon
	d["hmin"] = 2.0 if canyon else MIN_HEIGHT
	d["hmax"] = 25.0 if canyon else MAX_HEIGHT
	var js := jump_schedule(index)
	d["runup"] = js["runup"]
	d["v_bottom"] = js["v_bottom_kmh"] / 3.6
	var out: Array = []
	var state := start.duplicate()

	# Brama punktu kontrolnego na płaskiej prostej. Pierwsza sekcja ma
	# dłuższą prostą startową.
	var cp_len := 70.0 if index == 1 else 40.0
	var cp_meta := {"checkpoint": index}
	# Zjazdy (użytkownik): stacja co 5 odcinków, warsztat co 10 (11., 21.,
	# ...). Znak zjazdu na początku odcinka - co najmniej 800 m przed nim.
	var service := ""
	var tier := 0
	if index > 1 and (index - 1) % WORKSHOP_EVERY == 0:
		service = "workshop"
		tier = (index - 1) / WORKSHOP_EVERY
	elif index % STATION_EVERY_SECTIONS == 0:
		service = "station"
	if service != "":
		cp_meta["service_ahead"] = service
	_push(out, state, {"len": cp_len, "pitch": 0.0, "bank": 0.0, "width": d["width"],
			"meta": cp_meta, "limit": LIMIT_OPEN})
	var since_sign := cp_len

	var jumps_left: int = d["jumps"]
	var modules: int = d["modules"]
	for m in range(modules):
		if service != "" and since_sign >= SERVICE_SIGN_DIST:
			_service(out, state, service, tier)
			service = ""
		var before: float = state["dist"]
		_maybe_slippery_zone(state, d, rng)
		_module(out, state, d, rng, canyon, m, modules, jumps_left)
		since_sign += float(state["dist"]) - before
		jumps_left = state.get("_jumps_left", jumps_left)
	# Zjazd jeszcze nie wstawiony - dopełniamy prostą do 820 m i wstawiamy.
	if service != "":
		if since_sign < SERVICE_SIGN_DIST:
			_push(out, state, {"len": SERVICE_SIGN_DIST - since_sign, "pitch": 0.0, "bank": 0.0, "curve": 0.0})
		_service(out, state, service, tier)
	return out


## Jeden moduł trasy (wybór losowy z uwzględnieniem wysokości i skoków).
## Każdy moduł idzie przez _guarded - jezdnia nigdzie nie schodzi poniżej
## d.hmin (patrz niżej).
static func _module(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator,
		canyon: bool, m: int, modules: int, jumps_left: int) -> void:
	var lift := func(o: Array, s: Dictionary, need: float) -> void: _rise(o, s, d, need)
	# Skok co najmniej raz na sekcję, w losowym miejscu (ostatni moduł,
	# jeśli wcześniej nie wypadł).
	var want_jump := jumps_left > 0 and (rng.randf() < 0.45 or modules - m <= jumps_left)
	if want_jump:
		_guarded(out, state, d, rng, func(o: Array, s: Dictionary) -> void: _jump(o, s, d, rng), lift)
		state["_jumps_left"] = jumps_left - 1    # stan wraca do pętli sekcji
		if state["pos"].y < d["hmin"] + 10.0:
			_climb(out, state, d, +1)
		return
	var h: float = state["pos"].y
	var roll := rng.randf()
	var build: Callable
	# Każdy skok obniża tor o ~10 m (przerwa i lądowisko w dół) - podjazd
	# tylko blisko dolnej granicy, inaczej wypierał zakręty.
	if h < d["hmin"] + 4.0:
		build = func(o: Array, s: Dictionary) -> void: _climb(o, s, d, +1)
	elif h > d["hmax"] - 6.0:
		build = func(o: Array, s: Dictionary) -> void: _climb(o, s, d, -1)
	elif canyon and roll < 0.10 + clampf(0.03 * d["km"], 0.0, 0.2):
		# Tunel - częściej na dalszych, trudniejszych odcinkach.
		build = func(o: Array, s: Dictionary) -> void: _tunnel(o, s, d, rng)
	elif canyon and roll > 0.88:
		# Rozwidlenie (jak w River Raid): dwie jezdnie wokół skalnej wyspy.
		build = func(o: Array, s: Dictionary) -> void: _split(o, s, d, rng)
	elif roll < 0.40:
		build = func(o: Array, s: Dictionary) -> void: _curve(o, s, d, rng)
	elif roll < 0.55:
		build = func(o: Array, s: Dictionary) -> void: _chicane(o, s, d, rng)
	elif roll < 0.75:
		build = func(o: Array, s: Dictionary) -> void: _hill(o, s, d, rng)
	else:
		build = func(o: Array, s: Dictionary) -> void: _straight(o, s, d, rng)
	_guarded(out, state, d, rng, build, lift)


# --------------------------------------------------------------------------
# Strażnik wysokości
# --------------------------------------------------------------------------
# Teren to wciąż jedna płaska trawa na y = 0 (z czasów toru na palach),
# a okno na morze kładzie lustro wody na StuntTrack.SEA_Y. Wąwóz nie ma
# własnego dna - jezdnia w nim to ta sama płyta, co na palach. Kiedy
# jezdnia zejdzie niżej niż ~0,3 m, przykrywa ją trawa albo morze
# (błąd zgłoszony przez użytkownika 2026-11-08: "droga pod wodą / pod
# łąką"). Wcześniej wysokość sprawdzano tylko PRZED modułem, a skocznia
# (stół + zeskok -12°) schodzi o 5-10 m w jego trakcie: na autostradzie
# (4 m) prawie zawsze pod trawę, w wąwozie od ~6 m w dół.

## Buduje moduł `build(out, state)` tak, żeby najniższy punkt jezdni
## (z krawędzią na przechyłce) nie zszedł poniżej d.hmin. Najpierw próba
## na kopii stanu przy tym samym stanie losowania; jeśli za nisko, przed
## modułem idzie `lift(out, state, brakujące_metry)` i próba od nowa.
## Geometria modułu nie zależy od wysokości startu, więc po podjeździe
## moduł wychodzi taki sam, tylko wyżej.
static func _guarded(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator,
		build: Callable, lift: Callable) -> void:
	var hmin: float = d["hmin"]
	for _try in range(6):
		var rng_state := rng.state
		var trial: Array = []
		build.call(trial, state.duplicate())
		rng.state = rng_state
		var need := hmin - lowest_edge(trial, state)
		if need <= 0.0:
			break
		lift.call(out, state, need)
	build.call(out, state)


## Najniższa wysokość jezdni [m] odcinków `segs` od stanu `start` - środek
## albo niższa krawędź przy przechyłce.
static func lowest_edge(segs: Array, start: Dictionary) -> float:
	if segs.is_empty():
		return INF
	var low := INF
	for smp in StuntTrack.sample_segments(segs, start, 2.0):
		var hw := float(smp["width"]) * 0.5
		low = minf(low, (smp["pos"] as Vector3).y - absf((smp["right"] as Vector3).y) * hw)
	return low


## Podjazd o co najmniej `need` metrów (kolejne podjazdy 7°).
static func _rise(out: Array, state: Dictionary, d: Dictionary, need: float) -> void:
	var y0: float = state["pos"].y
	for _k in range(8):
		if float(state["pos"].y) - y0 >= need:
			return
		_climb(out, state, d, +1)


# --------------------------------------------------------------------------
# Moduły
# --------------------------------------------------------------------------

## Dokłada odcinek i aktualizuje stan (pozycję, kierunek itd.) - przez
## prawdziwe próbkowanie, więc stan zgadza się co do milimetra z torem.
static func _push(out: Array, state: Dictionary, seg: Dictionary) -> void:
	# Trwająca strefa śliska obejmuje odcinki bez jawnej nawierzchni.
	# Nawierzchnia "" (albo brak) = według strefy; jawna ("dry" na skoczniach,
	# "wet"/"ice" w modułach) zostaje. Opad (rain 1 mżawka / 2 deszcz) idzie
	# za strefą mokrą, także nad wyjątkowo suchymi kawałkami (np. skocznia).
	var slip: float = state.get("_slip_left", 0.0)
	if seg.get("surface", "") == "":
		seg["surface"] = state["_slip_surf"] if slip > 0.0 and not seg.get("gap", false) else "dry"
	if slip > 0.0:
		if state["_slip_surf"] == "wet" and not seg.get("roof", false):
			seg["rain"] = state.get("_slip_rain", 1)
		state["_slip_left"] = slip - float(seg.get("len", 0.0))
	out.append(seg)
	var smp := StuntTrack.sample_segments([seg], state, 2.0)
	var e: Dictionary = smp[-1]["end_state"]
	for k in e:
		state[k] = e[k]


## Nawierzchnia modułu: śliska tylko w trwającej strefie (patrz
## _maybe_slippery_zone) - pojedyncze moduły zostają suche.
static func _surface(_d: Dictionary, _rng: RandomNumberGenerator, _allow_ice: bool) -> String:
	return ""


## Strefa śliskiej nawierzchni (użytkownik: śliskie obszary dłuższe):
## mokro 150-400 m, lód 100-250 m, przez kolejne moduły trasy. _push
## nadaje nawierzchnię odcinkom bez jawnie podanej (skocznie podają suchą).
static func _maybe_slippery_zone(state: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	if state.get("_slip_left", 0.0) > 0.0:
		return
	var r := rng.randf()
	if r < d["p_ice"]:
		state["_slip_surf"] = "ice"
		state["_slip_left"] = rng.randf_range(100.0, 250.0)
	elif r < d["p_ice"] + d["p_wet"]:
		state["_slip_surf"] = "wet"
		state["_slip_left"] = rng.randf_range(150.0, 400.0)
		# Mokro, bo pada: mżawka albo deszcz (deszcz częściej dalej na trasie).
		state["_slip_rain"] = 2 if rng.randf() < clampf(0.3 + 0.02 * float(d["km"]), 0.3, 0.6) else 1


static func _straight(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var length := rng.randf_range(30.0, 70.0)
	_push(out, state, {"len": length, "pitch": 0.0, "bank": 0.0,
			"surface": _surface(d, rng, true)})


## Łuk z przechyłką do środka. Kierunek tak, żeby tor nie odjechał za
## daleko od początkowego kierunku (inaczej mógłby zawrócić na siebie).
static func _curve(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var yaw: float = state.get("yaw", 0.0)
	var dir := -1.0 if rng.randf() < 0.5 else 1.0
	if absf(yaw) > MAX_YAW * 0.5:
		dir = -signf(yaw)      # zakręt w prawo zwiększa yaw - patrz StuntTrack
	var angle := deg_to_rad(rng.randf_range(35.0, 70.0))
	var r: float = d["curve_r"] * rng.randf_range(0.85, 1.2)
	var length := angle * r
	var curve_deg := rad_to_deg(1.0 / r) * dir           # stopnie na metr
	var bank: float = d["bank_deg"] * dir
	# Wejście w przechyłkę jest płynne z interpolacji; na wyjściu krótka prosta.
	# Limit z przyczepności nawierzchni trwającej strefy.
	var surf: String = state["_slip_surf"] if state.get("_slip_left", 0.0) > 0.0 else "dry"
	var lim := curve_limit(r, bank, StuntTrack.SURFACES[surf]["grip"])
	_push(out, state, {"len": length, "curve": curve_deg, "bank": bank, "pitch": 0.0,
			"surface": surf, "limit": lim, "meta": {"curve_sign": dir, "curve_len": length}})
	_push(out, state, {"len": 25.0, "bank": 0.0, "limit": LIMIT_OPEN})


static func _chicane(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: float = d["curve_r"] * 1.1
	var dir := -1.0 if rng.randf() < 0.5 else 1.0
	var angle := deg_to_rad(25.0)
	for k in range(2):
		var sgn := dir if k == 0 else -dir
		var seg := {"len": angle * r, "curve": rad_to_deg(1.0 / r) * sgn,
				"bank": d["bank_deg"] * 0.6 * sgn}
		if k == 0:
			seg["limit"] = curve_limit(r, d["bank_deg"] * 0.6, 1.0)
			seg["meta"] = {"curve_sign": dir}
		_push(out, state, seg)
	_push(out, state, {"len": 20.0, "bank": 0.0, "curve": 0.0, "limit": LIMIT_OPEN})


## Garb: podjazd i zjazd. Przy dużej prędkości auto odrywa się od jezdni
## na szczycie - im dalej, tym krótszy i ostrzejszy garb.
static func _hill(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var p := clampf(6.0 + 1.5 * d["km"], 6.0, 12.0) * rng.randf_range(0.8, 1.1)
	var l := clampf(40.0 - 4.0 * d["km"], 22.0, 40.0)
	# Prędkość, przy której auto oderwie się od jezdni na szczycie: przejście
	# z +p do -p na długości 1,6·l (smoothstep) ma największą krzywiznę
	# κ = 1,5·2p/(1,6·l); auto trzyma się jezdni, dopóki v² < g/κ.
	var kappa := 1.5 * 2.0 * deg_to_rad(p) / (1.6 * l)
	var v_max := sqrt(G / kappa)
	var kmh := floorf(v_max * 3.6 * 0.95 / 5.0) * 5.0
	# Znak ostrzegawczy na krótkiej prostej przed garbem.
	var lim := clampf(floorf(kmh / 10.0) * 10.0, 40.0, LIMIT_OPEN)
	_push(out, state, {"len": 30.0, "pitch": 0.0, "limit": lim,
			"meta": {"warn": "GARB maks. %d km/h" % int(kmh), "v_warn": kmh / 3.6,
					"grade": roundi(tan(deg_to_rad(p)) * 100.0)}})
	_push(out, state, {"len": l, "pitch": p})
	_push(out, state, {"len": l * 1.6, "pitch": -p})
	_push(out, state, {"len": l, "pitch": 0.0, "limit": LIMIT_OPEN})


## Tunel: prosta albo łagodny łuk pod betonowym sklepieniem z pasem
## jarzeniówek. Geometrię buduje StuntTrack._build_tunnel z meta.tunnel_len.
static func _tunnel(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	# Dłuższe tunele (użytkownik): 300-800 m, łagodny łuk albo prosto.
	var length := rng.randf_range(300.0, 800.0)
	var curve := rng.randf_range(-0.06, 0.06) if rng.randf() < 0.5 else 0.0
	if rng.randf() < 0.4:
		# Dwie nitki (użytkownik): jezdnia rozdziela się przed górą (jak
		# rozwidlenie ze skalną wyspą), każda połowa wjeżdża do osobno
		# wierconej rury; za górą nitki znów się łączą.
		var w: float = state.get("width", 9.0)
		_push(out, state, {"len": 45.0, "width": w * 2.0 + ISLAND_W, "bank": 0.0, "pitch": 0.0,
				"meta": {"island": {"start": 45.0, "len": length, "w": ISLAND_W}}})
		_push(out, state, {"len": length, "pitch": 0.0, "bank": 0.0, "curve": curve,
				"surface": "dry", "roof": true,
				"meta": {"tunnel_len": length, "twin": {"road_w": w, "island_w": ISLAND_W}}})
		_push(out, state, {"len": 45.0, "width": w, "curve": 0.0})
		return
	_push(out, state, {"len": 15.0, "pitch": 0.0, "bank": 0.0})
	# Pod sklepieniem sucho i nie pada (strefa mokra trwa dalej za tunelem).
	_push(out, state, {"len": length, "pitch": 0.0, "bank": 0.0, "curve": curve,
			"surface": "dry", "roof": true, "meta": {"tunnel_len": length}})
	_push(out, state, {"len": 15.0, "curve": 0.0})


## Rozwidlenie: jezdnia rozszerza się do dwóch, między nimi skalna wyspa,
## potem znów jedna. Dwie jezdnie to dwie połowy szerokiej drogi - tor
## zostaje jedną ścieżką, a wyspa (z kolizją) rozdziela je fizycznie.
const ISLAND_W := 5.0
static func _split(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var w: float = state.get("width", 9.0)
	var wide := w * 2.0 + ISLAND_W
	var hold := rng.randf_range(100.0, 180.0)
	_push(out, state, {"len": 45.0, "width": wide, "bank": 0.0, "pitch": 0.0,
			"meta": {"island": {"start": 45.0, "len": hold, "w": ISLAND_W}}})
	_push(out, state, {"len": hold, "width": wide})
	_push(out, state, {"len": 45.0, "width": w})


## Zjazd do stacji paliw albo warsztatu (użytkownik: "wymaga zjechania
## tam"): jezdnia poszerza się o pas zjazdu po prawej, oddzielony od głównej
## drogi długą wysepką; stacja - dystrybutory i ładowarki, tankowanie przy
## powolnym przejeździe; warsztat - hala, trzeba wjechać i stanąć.
const STATION_EVERY_SECTIONS := 5
const SERVICE_LEN := 110.0
const SERVICE_EXTRA_W := 8.0
## Znak zjazdu co najmniej tyle przed zjazdem (użytkownik: >= 800 m).
const SERVICE_SIGN_DIST := 820.0
static func _service(out: Array, state: Dictionary, kind: String, tier: int) -> void:
	var w: float = state.get("width", 9.0)
	_push(out, state, {"len": 40.0, "width": w + SERVICE_EXTRA_W, "pitch": 0.0, "bank": 0.0,
			"curve": 0.0, "limit": 70.0})
	_push(out, state, {"len": SERVICE_LEN, "meta": {"service": {"kind": kind,
			"len": SERVICE_LEN, "road_w": w, "tier": tier}}})
	_push(out, state, {"len": 40.0, "width": w, "limit": LIMIT_OPEN})


## Podjazd (+1) albo zjazd (-1) - pilnuje wysokości toru nad ziemią.
static func _climb(out: Array, state: Dictionary, d: Dictionary, dir: int) -> void:
	# Znak A-23 / A-22 z nachyleniem w procentach (tan kąta · 100; 100% = 45°).
	_push(out, state, {"len": 70.0, "pitch": 7.0 * dir,
			"meta": {"grade": roundi(tan(deg_to_rad(7.0)) * 100.0) * dir}})
	_push(out, state, {"len": 25.0, "pitch": 0.0})


## Skok: rozbieg, rampa, przerwa, długie lądowisko z lekkim zjazdem.
## Przed rozbiegiem znak z prędkością potrzebną u podstawy rampy.
static func _jump(out: Array, state: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var theta := deg_to_rad(d["ramp_deg"])
	# Docelowa prędkość u podstawy rampy (z harmonogramu progów mocy) ->
	# prędkość wybicia: na rampie auto traci energię na wysokość
	# (rampa 24 m, wysokość ~ 24·sin(θ)/2).
	var v_bottom: float = d.get("v_bottom", d["v_jump"]) * rng.randf_range(0.95, 1.0)
	var h_est := 24.0 * sin(theta) * 0.5
	var v_target := sqrt(maxf(v_bottom * v_bottom - 2.0 * G * h_est, 25.0))
	var ramp := {"len": 24.0, "pitch": d["ramp_deg"], "bank": 0.0, "curve": 0.0, "surface": "dry"}
	var gap_pitch := -10.0
	var land_pitch := -8.0
	var canyon: bool = d.get("canyon", false)
	if canyon:
		# Skocznia: zamiast przerwy płaski stół, potem stromszy zeskok.
		# Przy prędkości ze znaku auto ląduje na początku zeskoku; wolniej -
		# na stole, szybciej - za zeskokiem na płaskim (twardo).
		gap_pitch = 0.0
		land_pitch = -12.0

	# Stan na początku rampy, gdyby rozbieg był prosty i płaski - geometria
	# skoku nie zależy od położenia, tylko od kształtu.
	var probe := {"pos": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "bank": 0.0,
			"width": state.get("width", 9.0), "dist": 0.0}

	# Bisekcja po długości przerwy: v_req rośnie z długością.
	var lo := 6.0
	var hi := 160.0
	var info := {}
	for it in range(30):
		var mid := (lo + hi) * 0.5
		info = _jump_geometry(probe, ramp, mid, gap_pitch, land_pitch, theta)
		if info["v_req"] < v_target:
			lo = mid
		else:
			hi = mid
	var gap_len := (lo + hi) * 0.5
	info = _jump_geometry(probe, ramp, gap_len, gap_pitch, land_pitch, theta)

	# Prędkość potrzebna u podstawy rampy: na rampie auto traci energię
	# na wysokość. +5% zapasu, w górę do pełnych 5 km/h.
	var v_bottom_real := sqrt(info["v_req"] * info["v_req"] + 2.0 * G * info["ramp_h"])
	var kmh := ceilf(v_bottom_real * 3.6 * 1.05 / 5.0) * 5.0

	var runup: float = d["runup"] * rng.randf_range(0.9, 1.1)
	var label := "SKOCZNIA %d km/h" if canyon else "SKOK %d km/h"
	# Ograniczenie na rozbiegu pozwala na skok: prędkość ze znaku + 10 km/h.
	var jump_lim := ceilf((kmh + 10.0) / 10.0) * 10.0
	_push(out, state, {"len": runup, "pitch": 0.0, "bank": 0.0, "curve": 0.0,
			"surface": "dry", "limit": jump_lim,
			"meta": {"sign": label % int(kmh), "v_sign": kmh / 3.6, "jump_kind": "SKOCZNIA" if canyon else "SKOK"}})
	ramp["meta"] = {"jump": {"v_req": info["v_req"], "v_bottom": v_bottom_real, "gap": gap_len}}
	_push(out, state, ramp)
	_push(out, state, {"len": gap_len, "gap": not canyon, "pitch": gap_pitch, "surface": "dry"})
	_push(out, state, {"len": 55.0, "pitch": land_pitch, "surface": "dry"})
	_push(out, state, {"len": 30.0, "pitch": 0.0, "limit": LIMIT_OPEN})


## Geometria skoku na próbkach toru. Zwraca v_req (prędkość wybicia
## potrzebną, żeby tylne koła doleciały za krawędź lądowiska) i wysokość rampy.
static func _jump_geometry(probe: Dictionary, ramp: Dictionary, gap_len: float,
		gap_pitch: float, land_pitch: float, theta: float) -> Dictionary:
	var smp := StuntTrack.sample_segments(
			[ramp, {"len": gap_len, "gap": true, "pitch": gap_pitch}], probe, 0.5)
	# Krawędź wybicia: pierwsza próbka przerwy (koniec rampy).
	var takeoff: Vector3 = smp[0]["pos"]
	for s in smp:
		if s["gap"]:
			takeoff = s["pos"]
			break
	var landing: Vector3 = smp[-1]["end_state"]["pos"]
	# Tor jedzie w -Z (yaw = 0), więc odległość pozioma to -Δz.
	var dx := -(landing.z - takeoff.z)
	var drop := takeoff.y - landing.y
	# Środek auta musi dolecieć CAR_CLEARANCE dalej - tam jezdnia lądowiska
	# jest już niżej (opada pod kątem przerwy/lądowiska).
	var d_eff := dx + CAR_CLEARANCE
	var h_eff := drop + CAR_CLEARANCE * tan(deg_to_rad(-gap_pitch))
	var denom := 2.0 * cos(theta) * cos(theta) * (d_eff * tan(theta) + h_eff)
	var v_req := sqrt(G * d_eff * d_eff / maxf(denom, 0.01))
	return {"v_req": v_req, "ramp_h": takeoff.y - probe["pos"].y, "dx": dx, "drop": drop}



# --------------------------------------------------------------------------
# Autostrada
# --------------------------------------------------------------------------

## Odcinek autostrady: wjazd (zejście do HIGHWAY_HEIGHT nad terenem, znak
## "autostrada"), długie proste, szerokie łuki, łagodne garby, jedna
## skocznia (stół jak w wąwozie), wiadukty nad drogą; na końcu podjazd
## i znak "koniec autostrady". Geometrię (druga jezdnia, bariery, nasyp,
## wiadukty) buduje StuntTrack._build_highway - po meta "highway" na
## pierwszej próbce. Ruch z naprzeciwka - XrMain (druga jezdnia).
static func _highway_section(index: int, start: Dictionary, rng: RandomNumberGenerator) -> Array:
	var d := difficulty(start.get("dist", 0.0))
	d["canyon"] = true                   # skocznia ze stołem, bez przerw
	d["hmin"] = 2.0
	d["hmax"] = 12.0
	var js := jump_schedule(index)
	d["runup"] = js["runup"]
	d["v_bottom"] = js["v_bottom_kmh"] / 3.6
	var out: Array = []
	var state := start.duplicate()
	var w := 14.8
	_push(out, state, {"len": 40.0, "pitch": 0.0, "bank": 0.0, "width": w, "limit": LIMIT_OPEN,
			"meta": {"checkpoint": index, "highway": true}})
	# Zjazd/podjazd do wysokości autostrady, łagodnie (do 4°).
	_highway_level(out, state, HIGHWAY_HEIGHT)
	_push(out, state, {"len": 30.0, "pitch": 0.0, "limit": LIMIT_HIGHWAY,
			"meta": {"road_sign": "highway"}})
	var jump_at := rng.randi_range(1, 3)
	# Strażnik wysokości (_guarded): skocznia schodzi poniżej poziomu
	# autostrady - podnosimy jezdnię przed nią łagodną rampą.
	var lift := func(o: Array, s: Dictionary, need: float) -> void:
		_highway_level(o, s, float(s["pos"].y) + need + 0.5)
	for m in range(5):
		_maybe_slippery_zone(state, d, rng)
		if m == jump_at:
			# Wielka skocznia (do 400 km/h) zamiast krótkiej z wąwozu.
			_big_jump(out, state)
			_highway_level(out, state, HIGHWAY_HEIGHT)
			_push(out, state, {"len": 20.0, "pitch": 0.0, "limit": LIMIT_HIGHWAY})
			continue
		var roll := rng.randf()
		if roll < 0.45:
			# Szeroki łuk (r 350-600 m) z małą przechyłką.
			var dir := -1.0 if rng.randf() < 0.5 else 1.0
			var yaw: float = state.get("yaw", 0.0)
			if absf(yaw) > MAX_YAW * 0.5:
				dir = -signf(yaw)
			var r := rng.randf_range(350.0, 600.0)
			var ang := deg_to_rad(rng.randf_range(15.0, 35.0))
			_push(out, state, {"len": ang * r, "curve": rad_to_deg(1.0 / r) * dir, "bank": 4.0 * dir,
					"pitch": 0.0, "limit": LIMIT_HIGHWAY, "meta": {"overpass": rng.randf() < 0.4}})
			_push(out, state, {"len": 40.0, "curve": 0.0, "bank": 0.0})
		elif roll < 0.65:
			# Łagodny garb (2-3°), bez ograniczenia prędkości.
			var p := rng.randf_range(2.0, 3.0)
			var hump := func(o: Array, s: Dictionary) -> void:
				_push(o, s, {"len": 80.0, "pitch": p})
				_push(o, s, {"len": 120.0, "pitch": -p})
				_push(o, s, {"len": 60.0, "pitch": 0.0})
			_guarded(out, state, d, rng, hump, lift)
			_highway_level(out, state, HIGHWAY_HEIGHT)
		else:
			_push(out, state, {"len": rng.randf_range(150.0, 300.0), "pitch": 0.0, "curve": 0.0,
					"bank": 0.0, "limit": LIMIT_HIGHWAY, "meta": {"overpass": true}})
	_push(out, state, {"len": 40.0, "pitch": 0.0, "bank": 0.0, "curve": 0.0, "limit": LIMIT_OPEN,
			"meta": {"road_sign": "highway_end"}})
	# Podjazd z powrotem na wysokość wąwozu (jego generator i tak pilnuje).
	_highway_level(out, state, 8.0)
	_push(out, state, {"len": 30.0, "pitch": 0.0})
	return out


## Wielka skocznia autostrady (użytkownik 2026-11-09: "skakać na
## maksymalnych prędkościach, do 400 km/h"; wybór: dwa rodzaje skoczni -
## krótkie w wąwozie, wielkie na autostradzie). Fizyka: przy lądowaniu na
## wysokości progu prędkość uderzenia prostopadle do jezdni = v·sin(kąt
## progu) niezależnie od długości lotu; żeby przy 400 km/h zostać pod
## progiem uszkodzeń (StuntCar.damage_landing_speed 7,5 m/s), próg ma
## BIG_JUMP_DEG 3,5° (111 m/s · sin 3,5° = 6,8 m/s). Za progiem płaski
## stół na wysokości progu, dłuższy niż lot przy 400 km/h
## (R = v²·sin 2θ / g ≈ 153 m) - każda prędkość ląduje na stole.
## Wejście na próg łagodne: dociążenie v²·θ/L ≤ 1 g przy 400 km/h (L ≈ 77 m).
## Wolniej niż ~90 km/h auto przejeżdża przez próg bez lotu.
const BIG_JUMP_DEG := 3.5
const BIG_JUMP_VMAX := 400.0 / 3.6
const BIG_JUMP_TABLE := 170.0


static func _big_jump(out: Array, state: Dictionary, meta := {}) -> void:
	var th := deg_to_rad(BIG_JUMP_DEG)
	var l_in := ceilf(BIG_JUMP_VMAX * BIG_JUMP_VMAX * th / G)
	var base_y: float = (state["pos"] as Vector3).y
	var m := {"sign": "SKOCZNIA DO 400 km/h", "v_sign": 0.0,
			"jump_kind": "WIELKA SKOCZNIA", "big_jump": true}
	m.merge(meta)
	_push(out, state, {"len": 120.0, "pitch": 0.0, "bank": 0.0, "curve": 0.0, "surface": "dry",
			"limit": LIMIT_HIGHWAY, "meta": m})
	_push(out, state, {"len": l_in, "pitch": BIG_JUMP_DEG, "surface": "dry"})
	# Krótki grzbiet: za nim tor lotu odrywa się od jezdni (v² > g·L/θ).
	_push(out, state, {"len": 4.0, "pitch": 0.0, "surface": "dry"})
	_push(out, state, {"len": BIG_JUMP_TABLE, "pitch": 0.0, "surface": "dry"})
	# Łagodny zjazd ze stołu do wysokości sprzed skoczni (bez drugiego
	# wybicia przy 400 km/h): dwa odcinki po 90 m, nachylenie narasta
	# i maleje liniowo, spadek ≈ 90 m · p.
	# Nachylenie dopasowane próbnie (siecznymi), żeby jezdnia wróciła
	# dokładnie na base_y - kawałki autostrady muszą zaczynać się na ROAD_Y.
	var dy: float = (state["pos"] as Vector3).y - base_y
	var p := rad_to_deg(atan(dy / 90.0))
	for _it in range(6):
		var trial := state.duplicate()
		var smp := StuntTrack.sample_segments([{"len": 90.0, "pitch": -p, "surface": "dry"},
				{"len": 90.0, "pitch": 0.0, "surface": "dry"}], trial, 0.5)
		var got: float = (state["pos"] as Vector3).y - (smp[-1]["end_state"]["pos"] as Vector3).y
		if absf(got - dy) < 1e-5 or absf(got) < 1e-9:
			break
		p *= dy / got
	_push(out, state, {"len": 90.0, "pitch": -p, "surface": "dry"})
	_push(out, state, {"len": 90.0, "pitch": 0.0, "surface": "dry"})


## Zmiana wysokości jezdni do `target` [m nad terenem]: rampa do 4°.
static func _highway_level(out: Array, state: Dictionary, target: float) -> void:
	var dy: float = target - float(state["pos"].y)
	if absf(dy) < 0.5:
		return
	var p := clampf(rad_to_deg(atan(dy / 200.0)), -4.0, 4.0)
	var l := absf(dy / tan(deg_to_rad(p)))
	_push(out, state, {"len": 30.0, "pitch": p})
	_push(out, state, {"len": maxf(l - 30.0, 10.0), "pitch": p})
	_push(out, state, {"len": 30.0, "pitch": 0.0})
