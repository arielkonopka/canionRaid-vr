@tool
extends Node3D
class_name StuntTrack

## Generator toru kaskaderskiego: wstęga zawieszona na słupach.
##
## Tor to wstęga zawieszona w powietrzu na słupach, opisana listą odcinków.
## Nic tu nie jest modelowane ręcznie - cała geometria powstaje z liczb.
##
## Każdy odcinek to słownik z kluczami (wszystkie opcjonalne poza "len"):
##   len    - długość odcinka w metrach
##   curve  - skręt w stopniach na metr, dodatni w prawo (0 = prosta)
##   pitch  - nachylenie w stopniach, dodatnie pod górę
##   bank   - przechyłka w stopniach, dodatnia = prawa krawędź niżej.
##            Na zakręcie w prawo (curve > 0) dawaj bank > 0, w lewo bank < 0 -
##            odwrotna przechyłka wyrzuca auto z toru.
##   width  - szerokość jezdni w metrach
##   gap    - true: dziura w torze, czyli miejsce do przeskoczenia
##   finish - true: początek tego odcinka to linia mety. Za metą zostaw
##            prostą na wyhamowanie (~100 m) - auto zatrzymuje się po mecie.
##            Bez odcinka z "finish" meta jest 100 m przed końcem toru.
##   surface - nawierzchnia: "dry" (domyślnie), "wet", "ice". Patrz SURFACES.
##            Nie przechodzi na następny odcinek - każdy podaje swoją.
##
## pitch, bank i width są płynnie interpolowane od wartości poprzedniego
## odcinka, więc nie trzeba definiować osobnych odcinków przejściowych.
##
## UWAGA: tor jest otwarty, nie zamyka się w pętlę. Domknięcie obwodu
## wymaga dobrania ostatnich odcinków tak, by wrócić do punktu startu -
## to osobny problem, na później.

## Nawierzchnie. "grip" mnoży współczynnik tarcia opony (StuntCar.tire_mu).
## Wartości względem suchego asfaltu, z typowych pomiarów dla opon drogowych:
## mokry asfalt ~0,7 suchego, lód ~0,12 (czarny lód potrafi mniej).
## Kolizja każdej nawierzchni to osobne StaticBody3D z metadaną "grip",
## którą koło odczytuje z obiektu, w który trafiło.
const SURFACES := {
	"dry": {"label": "sucha", "grip": 1.0},
	"wet": {"label": "mokra", "grip": 0.7},
	"ice": {"label": "lód", "grip": 0.12},
	# Rozbieg i stół wielkiej skoczni: jak sucha, ale w biało-czerwone pasy
	# poprzeczne (road.gdshader layout 3) - widoczna z daleka przy 400 km/h
	# (przegląd renderów 2026-11-10: "wygląda jak zwykła droga").
	"kicker": {"label": "skocznia", "grip": 1.0},
}

const DEFAULT_TRACK: Array[Dictionary] = [
	{"len": 60.0, "width": 9.0},
	{"len": 40.0, "curve": 1.2},
	{"len": 25.0, "pitch": 14.0},                          # rampa w górę
	# Przerwa. Oś toru w przerwie schodzi w dół, więc lądowisko leży niżej
	# niż wybicie - inaczej auto uderza nosem w krawędź po drugiej stronie.
	{"len": 18.0, "gap": true, "pitch": -12.0},
	# Lądowisko musi być długie: w powietrzu nie da się hamować, więc
	# zakręt tuż za skokiem jest nie do przejechania.
	{"len": 50.0, "pitch": -8.0},                          # lądowanie na zjeździe
	# Długi łuk w lewo, przechyłka do środka. Mokry - ~70% przyczepności.
	{"len": 55.0, "curve": -1.5, "bank": -18.0, "surface": "wet"},
	{"len": 35.0, "pitch": -18.0},                         # ostry zjazd
	{"len": 45.0, "curve": 2.2, "bank": 26.0, "width": 7.0},  # ciasny, wąski wiraż
	{"len": 30.0, "pitch": 4.0, "bank": 0.0, "width": 9.0},
	# Oblodzony fragment prostej: gaz i hamulec delikatnie, skręt prawie nic nie daje.
	{"len": 25.0, "pitch": 4.0, "surface": "ice"},
	{"len": 15.0, "pitch": 4.0},
	{"len": 20.0, "pitch": 0.0},
	# Meta, za nią prosta na wyhamowanie.
	{"len": 100.0, "finish": true},
]

## Długość linii startu i mety (szachownica na jezdni) wzdłuż toru [m].
const LINE_DEPTH := 1.5

@export_group("Budowanie")
## Przestaw na true, żeby przebudować tor w edytorze.
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if is_inside_tree():
			build()

## Pusta lista = użyj DEFAULT_TRACK.
@export var segments: Array[Dictionary] = []

@export_group("Parametry")
## Co ile metrów próbkowana jest linia środkowa. Mniej = gładziej, więcej trójkątów.
@export_range(0.25, 5.0, 0.25) var sample_step: float = 1.0
## Grubość płyty jezdni.
@export_range(0.05, 2.0, 0.05) var road_thickness: float = 0.3
## Co ile metrów stawiany jest słup podporowy.
@export_range(4.0, 60.0, 1.0) var pillar_spacing: float = 14.0
@export_range(0.2, 3.0, 0.1) var pillar_size: float = 0.7
## Wysokość punktu startowego nad poziomem zero.
@export var start_height: float = 30.0
@export var generate_collision: bool = true
## Drzewa i głazy wokół toru (Scenery).
@export var scenery: bool = true
## Tryb Autostrada: plan trasy - po _build_highway kawałek dokłada słupki,
## obiekty biomów i zabudowę miast (HighwayScenery), tablice miejscowości.
var hwy_plan: HighwayPlan
## Wąwóz: tor biegnie dnem między ścianami z łupku (z kolizją), bez filarów.
@export var canyon: bool = false
## Odcinek autostrady (TrackGenerator.is_highway): druga jezdnia, bariery,
## nasyp, wiadukty - _build_highway. Numer odcinka mówi kawałkowi wąwozu,
## czy sąsiad jest autostradą (wtedy ściany "otwierają się" przy styku).
var highway := false
var section_index := 0
## Wysokość ścian wąwozu nad jezdnią [m] (średnia; zmienia się z dystansem).
@export var canyon_height: float = 30.0
## Linie startu i mety (pokazowa trasa). Trasa bez końca je wyłącza.
@export var build_lines: bool = true

@export_group("Materiały")
## Materiał suchej jezdni. Mokra i lód dostają własne, wyprowadzone z niego,
## jeśli nie podano ich jawnie.
@export var road_material: Material
@export var wet_material: Material
@export var ice_material: Material
@export var pillar_material: Material

var _samples: Array[Dictionary] = []
## Dystanse próbek (rosnąco) - wyszukiwanie binarne zamiast przeglądania
## wszystkich próbek (na Queście liniowe szukanie botów "po szynie" zjadało
## ~25% procesora).
var _dists := PackedFloat64Array()


func _ready() -> void:
	if get_child_count() == 0:
		build()
	elif _samples.is_empty():
		# Geometria zapisana w scenie z edytora - próbki trzeba odtworzyć,
		# bo API dla samochodu na nich polega.
		_sample_path()


# --------------------------------------------------------------------------
# Budowa
# --------------------------------------------------------------------------

## Punkty profilu ściany (z 13) objęte kolizją - patrz _build_canyon.
const CANYON_COLLIDE_K := 7
## Budowa rozłożona na klatki (odcinki dobudowywane w trakcie jazdy): na
## Queście budowa odcinka w jednym kawałku to ~0,5 s zamrożenia obrazu.
## Próbki i jezdnia z kolizją powstają od razu, reszta (ściany, znaki,
## tunele, zjazdy) w kolejnych klatkach - odcinek powstaje dwa odcinki przed
## autem, więc zdąży.
var slice_build := false
var _built := false


## Przerwa w budowie do następnej klatki. false = kawałek usunięty w trakcie
## budowy (przerwać).
func _slice() -> bool:
	if not slice_build or Engine.is_editor_hint() or not is_inside_tree():
		return true
	await get_tree().process_frame
	return is_inside_tree()


func build() -> void:
	_built = false
	_clear_children()
	_sample_path()
	if _samples.size() < 2:
		push_warning("StuntTrack: za mało próbek, sprawdź definicję toru.")
		return
	# Kawałki dobudowywane w jeździe: próbkowanie, siatka jezdni i kolizja
	# w osobnych klatkach (razem do ~22 ms na PC przy kawałku autostrady
	# ~1,1 km - na Queście szarpnięcie co ~1 km; długi test 2026-11-10).
	if not await _slice():
		return

	# Ściany do kolizji, osobno dla każdej nawierzchni.
	var road_faces := {}
	_road_layout = 1 if hwy_plan else 0
	var mesh := _build_mesh(road_faces)

	var mi := MeshInstance3D.new()
	mi.name = "TrackMesh"
	mi.mesh = mesh
	_adopt(mi)
	if not await _slice():
		return
	_build_road_collision(road_faces)

	# Linie startu i mety; nad metą brama z banerem. Kawałki trasy bez końca
	# mają własne bramy (punkty kontrolne) - wyłączają to przez build_lines.
	if build_lines:
		_build_line("StartLine", START_DISTANCE, false)
		_build_line("FinishLine", finish_distance(), true)
	if not await _slice():
		return
	if canyon:
		_build_canyon()
		if not await _slice():
			return
	if highway:
		_build_highway()
		if not await _slice():
			return
	if hwy_plan:
		var t0 := Time.get_ticks_usec()
		var hrng := RandomNumberGenerator.new()
		hrng.seed = hash([hwy_plan.seed_value, int(float(_samples[0]["dist"]))])
		for n in HighwayScenery.build(_samples, hwy_plan, hrng,
				HighwayScenery.edges_for(float(_samples[0]["width"]))):
			_adopt(n)
		Perf.add("hwy_scenery", t0)
		if not await _slice():
			return
	if scenery and not canyon:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(name) ^ int(float(_samples[0]["dist"]))
		for node in Scenery.scatter(_samples, rng):
			_adopt(node)
	# Bramy punktów kontrolnych i znaki przed skokami (trasa generowana).
	var n_meta := 0
	for smp in _samples:
		var meta: Dictionary = smp["meta"]
		if not meta.is_empty():
			n_meta += 1
			if n_meta % 6 == 0 and not await _slice():
				return
		if meta.has("city_start"):
			_town_sign(float(smp["dist"]) - 40.0, HighwayPlan.city_name(int(meta["city_start"]["name_seed"])).to_upper())
		if meta.has("city_end"):
			_town_sign(float(smp["dist"]) + 10.0, HighwayPlan.city_name(int(meta["city_end"]["name_seed"])).to_upper(), true)
		if meta.has("checkpoint"):
			# Zielony znak "miejscowości" zamiast bramownicy (prośba użytkownika);
			# tuż przed nim koniec poprzedniego odcinka - przekreślony (E-18a).
			# Bez oznaczeń mety i końca odcinka - trasa bez końca (jak River
			# Raid); tylko tablica nowego odcinka.
			var n: int = meta["checkpoint"]
			_town_sign(float(smp["dist"]) + 12.0, "ODCINEK %d" % n)
		if meta.has("tunnel_len"):
			_build_tunnel(float(smp["dist"]), float(meta["tunnel_len"]), meta.get("twin", {}))
		if meta.has("island"):
			var isl: Dictionary = meta["island"]
			_build_island(float(smp["dist"]) + float(isl["start"]), float(isl["len"]), float(isl["w"]))
			_island_front(float(smp["dist"]) + float(isl["start"]))
		# Skocznie i sztuczki: bez tabliczek z napisami - ograniczenie przed
		# (B-33 z pętli niżej) i koniec ograniczenia za (B-34).
		if meta.has("grade"):
			# A-23 stromy podjazd / A-22 niebezpieczny zjazd, z procentem.
			var g: int = meta["grade"]
			_road_sign(float(smp["dist"]) + 6.0, "climb" if g > 0 else "descent", absi(g), "", 0.0)
		if meta.has("curve_len"):
			# U-3: czerwono-białe tablice kierujące co 12 m po zewnętrznej łuku.
			var n_ch := int(float(meta["curve_len"]) / 12.0)
			for k in range(1, n_ch):
				_chevron(float(smp["dist"]) + k * 12.0, int(meta["curve_sign"]))
		if meta.has("curve_sign"):
			# A-1 / A-2 niebezpieczny zakręt - 45 m przed łukiem (jeśli się mieści).
			var cd := float(smp["dist"]) - 45.0
			if cd > float(_samples[0]["dist"]) + 2.0:
				_road_sign(cd, "curve_r" if meta["curve_sign"] > 0 else "curve_l")
		if meta.has("service_ahead"):
			# Znak zjazdu (stacja / warsztat) >= 800 m przed zjazdem.
			_road_sign(float(smp["dist"]) + 20.0, "fuel" if meta["service_ahead"] == "station" else "repair")
		if meta.has("service"):
			_build_service(float(smp["dist"]), meta["service"])
		# Znak drogowy z generatora (autostrada / koniec) - "sign" to już
		# napis z prędkością przed skocznią (inne znaczenie).
		if meta.has("road_sign"):
			_road_sign(float(smp["dist"]) + 8.0, meta["road_sign"], 0, str(meta.get("road_plate", "")))
		if meta.get("overpass", false):
			_build_overpass(float(smp["dist"]) + 50.0)
	# Ograniczenia prędkości: B-33 przy każdym nowym ograniczeniu, B-34
	# "koniec ograniczenia" przy powrocie na otwartą drogę (zamiast "100").
	# A-15 śliska jezdnia przed mokrym fragmentem i lodem.
	var prev_surf := "dry"
	for smp in _samples:
		var sf: String = smp["surface"]
		if sf != "dry" and sf != "kicker" and prev_surf == "dry":
			_road_sign(maxf(float(smp["dist"]) - 30.0, float(_samples[0]["dist"]) + 1.0), "slippery")
		prev_surf = sf
	# Kontynuacja: ograniczenie z końca poprzedniego kawałka (bez zbędnego
	# znaku na każdym łączeniu odcinków).
	var prev_lim: float = start_state.get("limit", -1.0)
	for smp in _samples:
		var lim: float = smp.get("limit", -1.0)
		if lim > 0.0 and not is_equal_approx(lim, prev_lim):
			var open_road := is_equal_approx(lim, TrackGenerator.LIMIT_OPEN)
			if open_road and prev_lim > 0.0 and prev_lim < lim:
				_road_sign(float(smp["dist"]) + 1.0, "limit_end", int(prev_lim))
			elif not open_road or prev_lim < 0.0:
				_road_sign(float(smp["dist"]) + 1.0, "limit", int(lim))
		prev_lim = lim

	_built = true


## Kolizja jezdni (osobne ciało na każdą nawierzchnię) - od razu z siatką,
## przed jakąkolwiek przerwą w budowie.
func _build_road_collision(road_faces: Dictionary) -> void:
	if not generate_collision:
		return
	for surf in road_faces:
		var faces: PackedVector3Array = road_faces[surf]
		if faces.is_empty():
			continue
		var body := StaticBody3D.new()
		# Nazwa "TrackBody" dla suchej zostaje dla zgodności z testami.
		body.name = "TrackBody" if surf == "dry" or surf == "kicker" else "TrackBody_" + surf
		body.set_meta("surface", surf)
		body.set_meta("grip", SURFACES[surf]["grip"])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.name = "TrackShape"
		cs.shape = shape
		_adopt(body)
		body.add_child(cs)
		cs.owner = body.owner


## Stan na początku toru. Domyślnie: początek świata, kierunek -Z.
## EndlessTrack ustawia go tak, żeby kolejne kawałki toru łączyły się
## bez szwu (pozycja, kierunek, nachylenie, przechyłka, szerokość, dystans).
var start_state: Dictionary = {}


## Całkuje opis odcinków wzdłuż toru i zapisuje próbki linii środkowej
## razem z lokalnym układem współrzędnych w każdym punkcie.
func _sample_path() -> void:
	var track: Array = segments if segments.size() > 0 else DEFAULT_TRACK
	var st := start_state.duplicate()
	if not st.has("pos"):
		st["pos"] = Vector3(0.0, start_height, 0.0)
	_samples = sample_segments(track, st, sample_step)
	_dists.resize(_samples.size())
	for i in range(_samples.size()):
		_dists[i] = float(_samples[i]["dist"])


## Liczy próbki dla listy odcinków od stanu początkowego `start`
## ({pos, yaw, pitch, bank, width, dist} - brakujące klucze = zero / 9 m).
## Statyczna: generator tras używa jej do sprawdzania geometrii skoków
## przed zbudowaniem toru.
##
## Kierunek liczony jest z kątów yaw i pitch, a nie z ramy Freneta.
## Rama Freneta degeneruje się na prostych odcinkach (normalna krzywej
## jest wtedy nieokreślona) i tor zaczyna się obracać wokół własnej osi.
##
## Każda próbka ma też "yaw", "pitch", "bank" (rad) - stan, od którego
## można kontynuować tor - i "meta" pierwszej próbki odcinka (klucz "meta"
## odcinka, np. informacja o skoku).
static func sample_segments(track: Array, start: Dictionary, step: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if track.is_empty():
		return out
	var pos: Vector3 = start.get("pos", Vector3.ZERO)
	var yaw: float = start.get("yaw", 0.0)
	var prev_pitch: float = start.get("pitch", 0.0)
	var prev_bank: float = start.get("bank", 0.0)
	var prev_width: float = start.get("width", track[0].get("width", 9.0))
	var dist: float = start.get("dist", 0.0)
	# Ograniczenie prędkości [km/h] - obowiązuje do następnej zmiany.
	var limit: float = start.get("limit", 100.0)

	for seg in track:
		var seg_len: float = seg.get("len", 20.0)
		var curve: float = deg_to_rad(seg.get("curve", 0.0))   # radiany na metr
		var pitch: float = deg_to_rad(seg.get("pitch", 0.0))
		var bank: float = deg_to_rad(seg.get("bank", 0.0))
		var width: float = seg.get("width", prev_width)
		var gap: bool = seg.get("gap", false)
		var surface: String = seg.get("surface", "dry")
		limit = seg.get("limit", limit)
		if not SURFACES.has(surface):
			push_warning("StuntTrack: nieznana nawierzchnia '%s', przyjmuję suchą." % surface)
			surface = "dry"

		var steps := maxi(1, int(ceil(seg_len / step)))
		var ds := seg_len / float(steps)

		for i in range(steps):
			var t := smoothstep(0.0, 1.0, float(i) / float(steps))
			var p := lerpf(prev_pitch, pitch, t)
			var b := lerpf(prev_bank, bank, t)
			var w := lerpf(prev_width, width, t)

			# Kierunek jazdy z yaw i pitch. Przy yaw = 0 jedziemy w -Z.
			var fwd := Vector3(sin(yaw) * cos(p), sin(p), -cos(yaw) * cos(p)).normalized()
			# Poziome "w prawo", potem obie osie przechylane o bank wokół kierunku jazdy.
			var right := fwd.cross(Vector3.UP).normalized()
			var up := right.cross(fwd).normalized()
			right = right.rotated(fwd, b)
			up = up.rotated(fwd, b)

			out.append({
				"pos": pos,
				"fwd": fwd,
				"right": right,
				"up": up,
				"width": w,
				"gap": gap,
				"finish": seg.get("finish", false) and i == 0,
				"surface": surface,
				"rain": int(seg.get("rain", 0)),
				"roof": bool(seg.get("roof", false)),
				"dist": dist,
				"yaw": yaw, "pitch": p, "bank": b,
				"meta": seg.get("meta", {}) if i == 0 else {},
				"limit": limit,
			})

			pos += fwd * ds
			yaw += curve * ds
			dist += ds

		prev_pitch = pitch
		prev_bank = bank
		prev_width = width

	# Próbka końcowa dokładnie w punkcie styku z następnym kawałkiem - bez
	# niej jezdnia i ściany kończyły się ~1 krok wcześniej i na łączeniach
	# odcinków zostawały prześwity.
	if not out.is_empty():
		var last: Dictionary = out[-1]
		var fwd_e := Vector3(sin(yaw) * cos(prev_pitch), sin(prev_pitch), -cos(yaw) * cos(prev_pitch)).normalized()
		var right_e := fwd_e.cross(Vector3.UP).normalized()
		var up_e := right_e.cross(fwd_e).normalized()
		out.append({
			"pos": pos, "fwd": fwd_e,
			"right": right_e.rotated(fwd_e, prev_bank), "up": up_e.rotated(fwd_e, prev_bank),
			"width": prev_width, "gap": last["gap"], "finish": false,
			"surface": last["surface"], "rain": last["rain"], "roof": last["roof"], "dist": dist,
			"yaw": yaw, "pitch": prev_pitch, "bank": prev_bank, "meta": {}, "limit": limit,
		})
	# Stan końcowy jako ostatnia, "wirtualna" informacja - do łączenia kawałków.
	if not out.is_empty():
		out[-1]["end_state"] = {"pos": pos, "yaw": yaw, "pitch": prev_pitch, "limit": limit,
				"bank": prev_bank, "width": prev_width, "dist": dist}
	return out


## Stan na końcu toru - początek następnego kawałka (EndlessTrack).
func end_state() -> Dictionary:
	if _samples.is_empty():
		return {}
	var e: Dictionary = _samples[-1]["end_state"].duplicate()
	# Pozycja w układzie świata (tor może nie stać w zerze).
	e["pos"] = to_global(e["pos"]) if is_inside_tree() else e["pos"]
	return e


func _build_mesh(road_faces: Dictionary) -> ArrayMesh:
	# Wierzch jezdni: jedna powierzchnia na nawierzchnię (shader asfaltu
	# z parametrami mokrej / lodu). Boki i spód płyty: beton.
	var tools := {}
	for surf in SURFACES:
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[surf] = t
		road_faces[surf] = PackedVector3Array()
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_deck := false

	# --- jezdnia ---
	for i in range(_samples.size() - 1):
		var a: Dictionary = _samples[i]
		var b: Dictionary = _samples[i + 1]
		if a["gap"] or b["gap"]:
			continue
		var surf: String = a["surface"]
		var st: SurfaceTool = tools[surf]

		var aw := float(a["width"])
		var bw := float(b["width"])
		var a_half: Vector3 = a["right"] * (aw * 0.5)
		var b_half: Vector3 = b["right"] * (bw * 0.5)
		var a_down: Vector3 = -a["up"] * road_thickness
		var b_down: Vector3 = -b["up"] * road_thickness

		var al: Vector3 = a["pos"] - a_half
		var ar: Vector3 = a["pos"] + a_half
		var bl: Vector3 = b["pos"] - b_half
		var br: Vector3 = b["pos"] + b_half
		var ad := float(a["dist"])
		var bd := float(b["dist"])

		# góra (po niej się jeździ) - UV dla shadera: poprzecznie [m], wzdłuż [m],
		# UV2.x = szerokość (linie pasów zależą od niej).
		_quad_uv(st, [al, bl, br, ar],
				[Vector2(-aw * 0.5, ad), Vector2(-bw * 0.5, bd), Vector2(bw * 0.5, bd), Vector2(aw * 0.5, ad)],
				[aw, bw, bw, aw])
		road_faces[surf].append_array(_quad_faces(al, bl, br, ar))
		# spód i krawędzie boczne - beton (widać je przy spadaniu z toru)
		_quad(deck, al + a_down, ar + a_down, br + b_down, bl + b_down)
		_quad(deck, al, al + a_down, bl + b_down, bl)
		_quad(deck, ar, br, br + b_down, ar + a_down)
		any_deck = true

	var mesh := ArrayMesh.new()
	for surf in SURFACES:
		if road_faces[surf].is_empty():
			continue
		var st: SurfaceTool = tools[surf]
		st.generate_normals()
		st.set_material(_surface_material(surf))
		st.commit(mesh)
	if any_deck:
		deck.generate_normals()
		deck.set_material(_concrete_material())
		deck.commit(mesh)

	# --- filary jak w wiadukcie: stopa, słup, poprzecznica pod płytą ---
	# (w wąwozie jezdnia leży na dnie - bez filarów)
	if canyon:
		return mesh
	var ps := SurfaceTool.new()
	ps.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_pillar := false
	var next_pillar := 0.0
	for smp in _samples:
		if smp["gap"]:
			continue
		if float(smp["dist"]) < next_pillar:
			continue
		next_pillar = float(smp["dist"]) + pillar_spacing
		var pos: Vector3 = smp["pos"]
		var up: Vector3 = smp["up"]
		var right: Vector3 = smp["right"]
		var hw := float(smp["width"]) * 0.5
		# Poprzecznica pozioma, pod najniższym punktem płyty (przechyłka!).
		var y_l: float = (pos - right * hw * 0.75 - up * road_thickness).y
		var y_r: float = (pos + right * hw * 0.75 - up * road_thickness).y
		var cap_top := minf(y_l, y_r) - 0.02
		if cap_top <= 2.0:
			continue
		var fwd_h: Vector3 = smp["fwd"] * Vector3(1, 0, 1)
		if fwd_h.length() < 0.1:
			continue
		fwd_h = fwd_h.normalized()
		var right_h := fwd_h.cross(Vector3.UP).normalized()
		var base := Vector3(pos.x, 0.0, pos.z)
		var cap_h := 0.7
		_obox(ps, Vector3(pos.x, cap_top - cap_h * 0.5, pos.z), right_h, fwd_h,
				Vector3(hw * 1.55, cap_h, 1.3))
		# Słup jak w prawdziwym wiadukcie: ~2,4 x 1,6 m, u góry węższy
		# (dwa człony), na stopie fundamentowej.
		var col_h := cap_top - cap_h - 0.6
		var low_h := col_h * 0.55
		_obox(ps, base + Vector3.UP * (0.6 + low_h * 0.5), right_h, fwd_h,
				Vector3(2.4, low_h, 1.7))
		_obox(ps, base + Vector3.UP * (0.6 + low_h + (col_h - low_h) * 0.5), right_h, fwd_h,
				Vector3(2.0, col_h - low_h, 1.4))
		_obox(ps, base + Vector3.UP * 0.3, right_h, fwd_h, Vector3(4.2, 0.6, 3.2))
		any_pillar = true
	if any_pillar:
		ps.generate_normals()
		ps.set_material(pillar_material if pillar_material is ShaderMaterial else _concrete_material())
		ps.commit(mesh)
	return mesh


## Prostopadłościan o dowolnej orientacji poziomej: oś X = right, Z = fwd,
## Y w górę. size = pełne wymiary.
func _obox(st: SurfaceTool, c: Vector3, right: Vector3, fwd: Vector3, size: Vector3) -> void:
	var x := right * size.x * 0.5
	var y := Vector3.UP * size.y * 0.5
	var z := fwd * size.z * 0.5
	var v := [
		c - x - y - z, c + x - y - z, c + x - y + z, c - x - y + z,
		c - x + y - z, c + x + y - z, c + x + y + z, c - x + y + z,
	]
	# Kolejność jak w _box (tam: -z = fwd ujemny). Tu oś Z = fwd, więc
	# orientacja ścian jest taka sama jak dla prostopadłościanu z osiami świata.
	_quad(st, v[4], v[5], v[6], v[7])
	_quad(st, v[3], v[2], v[1], v[0])
	_quad(st, v[0], v[1], v[5], v[4])
	_quad(st, v[1], v[2], v[6], v[5])
	_quad(st, v[2], v[3], v[7], v[6])
	_quad(st, v[3], v[0], v[4], v[7])


func _quad_uv(st: SurfaceTool, p: Array, uv: Array, w: Array) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[idx])
		st.set_uv2(Vector2(w[idx], 0.0))
		st.add_vertex(p[idx])


## Materiały wspólne dla wszystkich torów (i kawałków trasy bez końca) -
## jeden zestaw shaderów, a nie kopia na każdy kawałek.
static var _shared_mats := {}


## Materiał wierzchu jezdni: shader asfaltu (linie, krawężniki, ziarno),
## mokra i lód jako parametry. Jawnie podane wet_material / ice_material
## mają pierwszeństwo.
## Układ pasów w road.gdshader dla budowanej właśnie siatki jezdni:
## 0 wąwóz, 1 autostrada (nasza jezdnia), 2 autostrada z naprzeciwka.
var _road_layout := 0


func _surface_material(surf: String) -> Material:
	if surf == "wet" and wet_material and _road_layout == 0:
		return wet_material
	if surf == "ice" and ice_material and _road_layout == 0:
		return ice_material
	var key := "road_%s_%d" % [surf, _road_layout]
	if not _shared_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/road.gdshader")
		m.set_shader_parameter("layout", 3 if surf == "kicker" else _road_layout)
		m.set_shader_parameter("wetness", 1.0 if surf == "wet" else 0.0)
		m.set_shader_parameter("ice", 1.0 if surf == "ice" else 0.0)
		# Kolory ustalone z użytkownikiem: sucha #404040, mokra #101010,
		# oblodzona #304070.
		var colors := {"dry": Color("#404040"), "wet": Color("#101010"), "ice": Color("#304070"),
				"kicker": Color("#404040")}
		m.set_shader_parameter("asphalt", colors[surf])
		_shared_mats[key] = m
	return _shared_mats[key]


func _concrete_material() -> Material:
	if not _shared_mats.has("concrete"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/concrete.gdshader")
		_shared_mats["concrete"] = m
	return _shared_mats["concrete"]


func _plain_material(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic_specular = 0.8
	return m


# --------------------------------------------------------------------------
# Pomocnicze
# --------------------------------------------------------------------------

func _cfg(d: Dictionary, key: String, fallback: Variant) -> Variant:
	return d[key] if d.has(key) else fallback


## Czworokąt podany ZGODNIE z ruchem wskazówek zegara, patrząc z przodu.
## Tak Godot definiuje przednią ścianę - zarówno przy renderowaniu
## (tylne ściany są odrzucane), jak i w kolizji ConcavePolygonShape3D
## (tylne ściany są dla fizyki przezroczyste).
func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
	st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)


func _quad_faces(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> PackedVector3Array:
	return PackedVector3Array([p0, p1, p2, p0, p2, p3])


func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var v := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z),   center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z),  center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z),    center + Vector3(-h.x, h.y, h.z),
	]
	_quad(st, v[4], v[5], v[6], v[7])   # góra
	_quad(st, v[3], v[2], v[1], v[0])   # dół
	_quad(st, v[0], v[1], v[5], v[4])
	_quad(st, v[1], v[2], v[6], v[5])
	_quad(st, v[2], v[3], v[7], v[6])
	_quad(st, v[3], v[0], v[4], v[7])


func _clear_children() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()


func _adopt(node: Node) -> void:
	add_child(node)
	if Engine.is_editor_hint():
		var o := owner if owner else self
		node.owner = o


# --------------------------------------------------------------------------
# API dla samochodu (przyda się w etapie 3)
# --------------------------------------------------------------------------

## Odległość startu od początku toru - tu stawiane jest auto.
const START_DISTANCE := 8.0


## Odległość linii mety od początku toru.
func finish_distance() -> float:
	for s in _samples:
		if s["finish"]:
			return float(s["dist"])
	return maxf(total_length() - 100.0, 0.0)


## Szachownica w poprzek jezdni (2 rzędy) i - dla mety - brama z banerem.
func _build_line(node_name: String, dist: float, gate: bool, text := "META") -> void:
	var root := Node3D.new()
	root.name = node_name
	_adopt(root)
	# transform_at_distance zwraca układ globalny; tu potrzebny lokalny toru.
	root.transform = global_transform.affine_inverse() * transform_at_distance(dist)
	var s := _sample_near(dist)
	var width: float = s["width"]
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.05)
	var n := 12
	var sq := width / n
	for row in range(2):
		for col in range(n):
			var b := BoxMesh.new()
			b.size = Vector3(sq, 0.02, LINE_DEPTH * 0.5)
			b.material = white if (row + col) % 2 == 0 else black
			var m := MeshInstance3D.new()
			m.mesh = b
			# Układ linii: X w prawo, Y w górę, -Z do przodu. Lekko nad jezdnią.
			m.position = Vector3(-width * 0.5 + sq * (col + 0.5), 0.012, (row - 0.5) * LINE_DEPTH * 0.5)
			root.add_child(m)
	if not gate:
		return
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.85, 0.15, 0.1)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.3, 5.5, 0.3)
		pb.material = post_mat
		post.mesh = pb
		post.position = Vector3(side * (width * 0.5 + 0.4), 2.75, 0.0)
		root.add_child(post)
	# Baner w szachownicę nad jezdnią, 4,5 m nad nią - auto przejeżdża pod spodem.
	var bn := 16
	var bw := (width + 0.8) / bn
	for row in range(2):
		for col in range(bn):
			var b := BoxMesh.new()
			b.size = Vector3(bw, 0.35, 0.08)
			b.material = white if (row + col) % 2 == 0 else black
			var m := MeshInstance3D.new()
			m.mesh = b
			m.position = Vector3(-(width + 0.8) * 0.5 + bw * (col + 0.5), 4.6 + row * 0.35, 0.0)
			root.add_child(m)
	var label := Label3D.new()
	label.text = text
	label.font_size = 160
	label.pixel_size = 0.01
	label.position = Vector3(0.0, 5.75, 0.05)
	label.modulate = Color(1.0, 0.85, 0.2)
	label.outline_size = 20
	root.add_child(label)


## Ściany wąwozu z łupku. Profil po każdej stronie, od krawędzi jezdni:
## pobocze ze żwiru 1,8 m, pięć stopni (pionowa ściana z lekkim
## odchyleniem na zewnątrz + półka - łupek łupie się na płaskie płyty),
## płaskowyż na górze. Wysokość i półki zmieniają się płynnie z dystansem
## (gładka funkcja dystansu, więc sąsiednie próbki się zgadzają).
## Ściany pionowe względem świata, także przy przechylonej jezdni.
## Kolizja: StaticBody3D z metadanymi nawierzchni "rock" (grip 0,55) -
## uderzenie w ścianę to uszkodzenia auta.
func _build_canyon() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var no_faces := PackedVector3Array()
	# Przekrój co 3 próbki (6 m; było co 4 m) - ściany są gładkie, a budowa
	# ścian to ~60% czasu budowy odcinka (na Queście ~0,5 s szarpnięcia).
	var step := 3
	var prev := {}
	var idxs := range(0, _samples.size(), step)
	if idxs[-1] != _samples.size() - 1:
		idxs.append(_samples.size() - 1)       # do samego styku z następnym kawałkiem
	for i in idxs:
		var smp: Dictionary = _samples[i]
		var prof := {}
		for side in [-1, 1]:
			prof[side] = _canyon_profile(smp, side)
		if not prev.is_empty():
			for side in [-1, 1]:
				var a: Array = prev[side]
				var b: Array = prof[side]
				for k in range(a.size() - 1):
					# Ściana ma patrzeć do środka wąwozu (i w górę na półkach).
					var inward: Vector3 = (smp["right"] * Vector3(1, 0, 1)).normalized() * -side
					# Kolizja tylko dolnej części ściany (do ~3. półki, ~18 m nad
					# jezdnią) - wyżej auto nie doleci, a siatka kolizji całych
					# ścian z płaskowyżem była droga w budowie.
					var f_out := faces if k < CANYON_COLLIDE_K else no_faces
					_quad_facing(st, f_out, a[k], b[k], b[k + 1], a[k + 1], inward + Vector3.UP * 0.3)
					if k >= CANYON_COLLIDE_K:
						no_faces.clear()
		prev = prof
	# Początek trasy: wąwóz zamknięty skalną ścianą za linią startu - inaczej
	# za startem była otwarta przestrzeń i dało się wyjechać na trawę.
	if float(_samples[0]["dist"]) < 0.5:
		var s0: Dictionary = _samples[0]
		var c0: Vector3 = s0["pos"] - (s0["fwd"] as Vector3) * 2.0
		var r0: Vector3 = ((s0["right"] as Vector3) * Vector3(1, 0, 1)).normalized()
		var fwd0: Vector3 = (s0["fwd"] as Vector3) * Vector3(1, 0, 1)
		var w0 := float(s0["width"]) * 0.5 + 40.0
		_quad_facing(st, faces, c0 - r0 * w0 + Vector3.DOWN * 2.0, c0 + r0 * w0 + Vector3.DOWN * 2.0,
				c0 + r0 * w0 + Vector3.UP * 45.0, c0 - r0 * w0 + Vector3.UP * 45.0, fwd0)
	st.generate_normals()
	st.set_material(_rock_material("cavern"))
	_build_sea()
	var mi := MeshInstance3D.new()
	mi.name = "CanyonWalls"
	mi.mesh = st.commit()
	_adopt(mi)
	if generate_collision and not faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "CanyonBody"
		body.set_meta("surface", "rock")
		body.set_meta("grip", 0.55)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_adopt(body)
		body.add_child(cs)
		cs.owner = body.owner


## Widok na morze (prośba użytkownika): mniej więcej raz na SEA_EVERY m
## jedna ściana na ~SEA_LEN m obniża się do skalnego progu, za nim stok do
## morza po horyzont. Położenie i strona z dystansu (hash numeru okna), więc
## kawałki toru zgadzają się na styku bez wymiany danych. W tunelu nie ma
## (tunel ma własną górę).
const SEA_EVERY := 5000.0
const SEA_LEN := 100.0
const SEA_RAMP := 40.0
const SEA_Y := 0.3                     # poziom morza (ziemia z trawą: 0)
const PARAPET_H := 0.5                 # niski próg: widok na morze; przeskoczenie = upadek, strata auta


static func _hash1(k: float, salt: float) -> float:
	return fposmod(sin(k * 127.1 + salt * 311.7) * 43758.5453, 1.0)


## Obniżenie ściany po stronie `side` (-1 lewa, 1 prawa) na dystansie d: 0..1.
static func sea_factor(d: float, side: int) -> float:
	var k := floorf(d / SEA_EVERY)
	var ws := k * SEA_EVERY + 1000.0 + _hash1(k, 1.0) * (SEA_EVERY - 1400.0 - SEA_LEN)
	var sea_side := 1 if _hash1(k, 2.0) > 0.5 else -1
	if sea_side != side:
		return 0.0
	var a := clampf((d - (ws - SEA_RAMP)) / SEA_RAMP, 0.0, 1.0)
	var b := clampf(((ws + SEA_LEN + SEA_RAMP) - d) / SEA_RAMP, 0.0, 1.0)
	var t := minf(a, b)
	return t * t * (3.0 - 2.0 * t)


## Morze za obniżoną ścianą: jedna wielka płaszczyzna na poziomie SEA_Y,
## wysunięta w stronę morza (przykrywa trawę po tej stronie; pod torem jej
## nie widać, bo zasłaniają ją ściany). Tylko w kawałku, który ma okno.
func _build_sea() -> void:
	for side in [-1, 1]:
		var best := {}
		var best_t := 0.5
		for smp in _samples:
			var t := sea_factor(float(smp["dist"]), side)
			if t > best_t and not smp.get("roof", false):
				best_t = t
				best = smp
		if best.is_empty():
			continue
		var out: Vector3 = ((best["right"] as Vector3) * Vector3(1, 0, 1)).normalized() * side
		var size := 9000.0
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size)
		pm.subdivide_width = 0
		pm.subdivide_depth = 0
		pm.material = _ocean_material()
		var mi := MeshInstance3D.new()
		mi.name = "Sea"
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c: Vector3 = best["pos"] + out * (float(best["width"]) * 0.5 + 25.0 + size * 0.5)
		mi.position = Vector3(c.x, SEA_Y, c.z)
		mi.basis = Basis(Vector3.UP, atan2(out.x, out.z))
		_adopt(mi)


func _ocean_material() -> Material:
	if not _shared_mats.has("ocean"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/ocean.gdshader")
		_shared_mats["ocean"] = m
	return _shared_mats["ocean"]


## Punkty profilu ściany wąwozu dla próbki (układ toru).
func _canyon_profile(smp: Dictionary, side: int) -> Array:
	var d := float(smp["dist"])
	var hw := float(smp["width"]) * 0.5
	var right: Vector3 = smp["right"]
	var edge: Vector3 = smp["pos"] + right * hw * side
	var out := (right * Vector3(1, 0, 1)).normalized() * side
	# Gładkie "szumy" z dystansu - różne dla stron.
	var ph := 0.0 if side < 0 else 17.0
	var hscale := 1.0 + 0.25 * sin(d * 0.006 + ph) + 0.12 * sin(d * 0.023 + ph * 2.0)
	var total_h := canyon_height * hscale
	var sea := 0.0 if smp.get("roof", false) else sea_factor(d, side)
	# Wąwóz otwiera się przy styku z autostradą: ściany schodzą do niskiego
	# progu, płaskowyż do terenu (zamiast ucięcia ściany na styku kawałków).
	var openf := _open_factor(d)
	total_h = lerpf(total_h, PARAPET_H, maxf(sea, openf))
	var pts := [edge - Vector3.UP * 0.02]
	var x := 1.8
	var y := 0.1
	pts.append(edge + out * x + Vector3.UP * y)
	for k in range(5):
		var sh := total_h / 5.0 * (0.8 + 0.4 * (0.5 + 0.5 * sin(d * 0.011 + k * 1.7 + ph)))
		x += 0.12 * sh
		y += sh
		pts.append(edge + out * x + Vector3.UP * y)
		x += 0.6 + 1.0 * (0.5 + 0.5 * sin(d * 0.017 + k * 2.3 + ph))
		y += 0.05
		pts.append(edge + out * x + Vector3.UP * y)
	# Płaskowyż - daleko, żeby z dna nie było widać jego końca. Nad morzem
	# zamiast niego stok od progu w dół, pod lustro wody.
	var plateau := edge + out * (x + 300.0) + Vector3.UP * y
	if sea > 0.0 or openf > 0.0:
		var to_y := SEA_Y - 3.0 if sea >= openf else -0.5
		var drop := edge + out * (x + 4.0 + 1.2 * maxf(edge.y + y - to_y, 0.0)) \
				+ Vector3.UP * (to_y - edge.y)
		plateau = plateau.lerp(drop, maxf(sea, openf))
	pts.append(plateau)
	return pts


## 0..1 - jak bardzo wąwóz jest "otwarty" na dystansie d (styk z odcinkiem
## autostrady przed albo za tym kawałkiem; przejście na 150 m).
func _open_factor(d: float) -> float:
	if section_index <= 0 or _dists.is_empty():
		return 0.0
	var f := 0.0
	if TrackGenerator.is_highway(section_index - 1):
		f = maxf(f, 1.0 - smoothstep(0.0, 150.0, d - _dists[0]))
	if TrackGenerator.is_highway(section_index + 1):
		f = maxf(f, 1.0 - smoothstep(0.0, 150.0, _dists[_dists.size() - 1] - d))
	return f


## Czworokąt nawinięty tak, żeby jego przód patrzył w stronę `facing`
## (front w Godocie: zgodnie z ruchem wskazówek zegara). Dokłada też ściany
## do listy kolizji w tej samej kolejności.
func _quad_facing(st: SurfaceTool, faces: PackedVector3Array, p0: Vector3, p1: Vector3,
		p2: Vector3, p3: Vector3, facing: Vector3) -> void:
	var n := (p2 - p0).cross(p1 - p0)
	if n.dot(facing) < 0.0:
		var t := p1
		p1 = p3
		p3 = t
	_quad(st, p0, p1, p2, p3)
	faces.append_array(_quad_faces(p0, p1, p2, p3))


## Skała z tekstur (shaders/rock.gdshader): "cavern" - ściany wąwozu
## i wyspy (cavern walls), "ocean" - góry nad tunelami (ocean rock). Mech
## na zboczach w cieniu w obu (mossy rock, textures/derived).
const ROCK_TEXTURES := {
	"cavern": ["res://textures/cavern-walls-bl/cavern-walls_albedo.png",
			"res://textures/cavern-walls-bl/cavern-walls_normal-ogl.png", 1.0 / 6.0],
	"ocean": ["res://textures/ocean-rock-bl/ocean-rock_albedo.png",
			"res://textures/ocean-rock-bl/ocean-rock_normal-ogl.png", 1.0 / 10.0],
}


const MOSS_TEX := ["res://textures/derived/moss_albedo.png", "res://textures/derived/moss_normal.png"]


func _rock_material(kind := "cavern") -> Material:
	var key := "rock_" + kind
	if not _shared_mats.has(key):
		var t: Array = ROCK_TEXTURES[kind]
		var m := ShaderMaterial.new()
		# Tekstury (freepbr.com) są tylko w lokalnych buildach - nie ma ich
		# w publicznym repo. Bez nich proceduralny łupek (shale.gdshader).
		if not (ResourceLoader.exists(t[0]) and ResourceLoader.exists(MOSS_TEX[0])):
			m.shader = load("res://shaders/shale.gdshader")
			_shared_mats[key] = m
			return m
		m.shader = load("res://shaders/rock.gdshader")
		m.set_shader_parameter("rock_albedo", load(t[0]))
		m.set_shader_parameter("rock_normal", load(t[1]))
		m.set_shader_parameter("rock_scale", t[2])
		m.set_shader_parameter("moss_albedo", load(MOSS_TEX[0]))
		m.set_shader_parameter("moss_normal", load(MOSS_TEX[1]))
		if not Bench.on("rock_simple"):
			# Pomiar A/B: skała bez map normalnych i bez mchu.
			m.set_shader_parameter("normal_dist", 0.0)
			m.set_shader_parameter("moss_amount", 0.0)
		_shared_mats[key] = m
	return _shared_mats[key]


## Znak drogowy wg polskich wzorów, przy prawej krawędzi jezdni:
##   "limit"   - B-33 ograniczenie prędkości (czerwone koło, liczba)
##   "curve_r" / "curve_l" - A-1 / A-2 niebezpieczny zakręt
##   "bump"    - A-11 nierówna droga
##   "danger"  - A-30 inne niebezpieczeństwo (wykrzyknik)
## Ostrzegawcze: trójkąt z czerwonym obrzeżem i żółtym polem. Opcjonalna
## tabliczka z tekstem pod znakiem. `lift` podnosi znak (np. gdy dwa stoją
## w tym samym miejscu).
func _road_sign(dist: float, kind: String, value := 0, plate := "", lift := 0.0) -> void:
	var root := Node3D.new()
	root.name = "RoadSign"
	_adopt(root)
	root.transform = global_transform.affine_inverse() * transform_at_distance(dist)
	# Znak stoi pionowo, także przy przechylonej i pochylonej jezdni:
	# zostaje tylko kierunek w poziomie, a słupek zaczyna się na krawędzi
	# jezdni (na jej wysokości).
	var fwd_h := (-root.basis.z * Vector3(1, 0, 1)).normalized()
	var edge_pt := root.transform * Vector3(float(_sample_near(dist)["width"]) * 0.5, 0, 0)
	root.basis = Basis.looking_at(fwd_h, Vector3.UP)
	root.position = edge_pt - root.basis.x * (float(_sample_near(dist)["width"]) * 0.5)
	var s := _sample_near(dist)
	var x: float = s["width"] * 0.5 + 0.9
	var top := 2.3 + lift
	var mats := _sign_mats()
	_sign_box(root, Vector3(0.07, top, 0.07), Vector3(x, top * 0.5, -0.04), mats["post"])
	var face := Vector3(x, top, 0.0)
	match kind:
		"limit":
			_sign_disc(root, face, 0.38, mats["red"], 0.0)
			_sign_disc(root, face, 0.30, mats["white"], 0.012)
			_sign_text(root, str(value), face + Vector3(0, 0, 0.03), 0.0035, Color.BLACK)
		"limit_end":
			# B-34: biała tarcza, szara liczba, ukośne czarne pasy.
			_sign_disc(root, face, 0.36, mats["white"], 0.0)
			_sign_text(root, str(value), face + Vector3(0, 0, 0.02), 0.0035, Color(0.45, 0.45, 0.45))
			for k in [-0.07, 0.0, 0.07]:
				var bar := _sign_box(root, Vector3(0.66, 0.018, 0.01), face + Vector3(k, k, 0.03), mats["black"])
				bar.rotation = Vector3(0, 0, PI * 0.25)
		"fuel":
			# Znak stacji paliw: niebieska tablica, białe pole, dystrybutor.
			if not _shared_mats.has("sign_blue"):
				var bm := StandardMaterial3D.new()
				bm.albedo_color = Color(0.05, 0.25, 0.65)
				_shared_mats["sign_blue"] = bm
			_sign_box(root, Vector3(0.6, 0.85, 0.02), face, _shared_mats["sign_blue"])
			_sign_box(root, Vector3(0.44, 0.44, 0.02), face + Vector3(0, 0.12, 0.012), mats["white"])
			_sign_box(root, Vector3(0.14, 0.26, 0.01), face + Vector3(-0.03, 0.1, 0.025), mats["black"])
			_sign_box(root, Vector3(0.04, 0.16, 0.01), face + Vector3(0.09, 0.14, 0.025), mats["black"])
			if value == 1:
				_exit_arrow(root, face, mats["white"])
		"highway", "highway_end":
			# Autostrada / koniec autostrady (wzór jak w Polsce): niebieska
			# tablica, biały piktogram - dwie jezdnie pod wiaduktem; koniec -
			# czerwony skos.
			if not _shared_mats.has("sign_blue"):
				var bmh := StandardMaterial3D.new()
				bmh.albedo_color = Color(0.05, 0.25, 0.65)
				_shared_mats["sign_blue"] = bmh
			_sign_box(root, Vector3(0.8, 0.8, 0.02), face, _shared_mats["sign_blue"])
			_sign_box(root, Vector3(0.56, 0.06, 0.01), face + Vector3(0, 0.12, 0.015), mats["white"])
			for sx in [-1.0, 1.0]:
				var lane := _sign_box(root, Vector3(0.07, 0.36, 0.01), face + Vector3(0.11 * sx, -0.08, 0.015), mats["white"])
				lane.rotation = Vector3(0, 0, 0.35 * sx)
			_sign_box(root, Vector3(0.03, 0.28, 0.01), face + Vector3(0, -0.1, 0.015), mats["white"])
			if kind == "highway_end":
				var bar := _sign_box(root, Vector3(0.95, 0.07, 0.01), face + Vector3(0, 0, 0.025), mats["red"])
				bar.rotation = Vector3(0, 0, -0.75)
		"repair":
			# Znak warsztatu: niebieska tablica, białe pole, klucz.
			if not _shared_mats.has("sign_blue"):
				var bm2 := StandardMaterial3D.new()
				bm2.albedo_color = Color(0.05, 0.25, 0.65)
				_shared_mats["sign_blue"] = bm2
			_sign_box(root, Vector3(0.6, 0.85, 0.02), face, _shared_mats["sign_blue"])
			_sign_box(root, Vector3(0.44, 0.44, 0.02), face + Vector3(0, 0.12, 0.012), mats["white"])
			var wr := _sign_box(root, Vector3(0.05, 0.3, 0.01), face + Vector3(0, 0.12, 0.025), mats["black"])
			wr.rotation = Vector3(0, 0, 0.8)
			_sign_box(root, Vector3(0.11, 0.07, 0.01), face + Vector3(0.09, 0.22, 0.025), mats["black"])
			if value == 1:
				_exit_arrow(root, face, mats["white"])
		_:
			# Trójkąt wierzchołkiem do góry: walec o 3 bokach patrzący w +Z.
			_sign_tri(root, face, 0.52, mats["red"], 0.0)
			_sign_tri(root, face, 0.40, mats["yellow"], 0.012)
			var sym: Material = mats["black"]
			match kind:
				"curve_r", "curve_l":
					var sg := 1.0 if kind == "curve_r" else -1.0
					_sign_box(root, Vector3(0.035, 0.18, 0.01), face + Vector3(-0.03 * sg, -0.08, 0.03), sym)
					var arm := _sign_box(root, Vector3(0.035, 0.16, 0.01), face + Vector3(0.025 * sg, 0.06, 0.03), sym)
					arm.rotation = Vector3(0, 0, -0.6 * sg)
				"climb", "descent":
					# Pochylnia z liczbą procent (A-23 / A-22).
					var up_dir := 1.0 if kind == "climb" else -1.0
					var ramp := _sign_box(root, Vector3(0.30, 0.03, 0.01), face + Vector3(0.0, -0.13, 0.03), sym)
					ramp.rotation = Vector3(0, 0, 0.35 * up_dir)
					_sign_text(root, "%d%%" % value, face + Vector3(0, 0.0, 0.03), 0.0022, Color.BLACK)
				"slippery":
					# A-15: auto i dwa ślady poślizgu (S) pod nim.
					_sign_box(root, Vector3(0.14, 0.07, 0.01), face + Vector3(0, -0.02, 0.03), sym)
					for k in [-1.0, 1.0]:
						var tr2 := _sign_box(root, Vector3(0.025, 0.12, 0.01), face + Vector3(0.05 * k, -0.13, 0.03), sym)
						tr2.rotation = Vector3(0, 0, 0.5 * k)
				"fork":
					# Rozwidlenie: pień i dwa ramiona rozchodzące się (jak Y).
					_sign_box(root, Vector3(0.035, 0.13, 0.01), face + Vector3(0, -0.12, 0.03), sym)
					for k in [-1.0, 1.0]:
						var arm2 := _sign_box(root, Vector3(0.035, 0.16, 0.01), face + Vector3(0.05 * k, 0.0, 0.03), sym)
						arm2.rotation = Vector3(0, 0, -0.55 * k)
				"bump":
					for k in [-1.0, 1.0]:
						var b := _sign_box(root, Vector3(0.12, 0.035, 0.01), face + Vector3(0.05 * k, -0.05, 0.03), sym)
						b.rotation = Vector3(0, 0, 0.45 * -k)
				_:
					_sign_text(root, "!", face + Vector3(0, -0.06, 0.03), 0.006, Color.BLACK)
	if plate != "":
		var py := top - 0.62
		_sign_box(root, Vector3(0.7, 0.22, 0.02), Vector3(x, py, 0.0), mats["white"])
		_sign_text(root, plate, Vector3(x, py, 0.015), 0.0016, Color.BLACK)


func _sign_mats() -> Dictionary:
	if not _shared_mats.has("sign_red"):
		var defs := {"sign_red": Color(0.8, 0.08, 0.06), "sign_white": Color(0.95, 0.95, 0.93),
				"sign_yellow": Color(0.98, 0.8, 0.1), "sign_black": Color(0.04, 0.04, 0.04),
				"sign_post": Color(0.55, 0.56, 0.58)}
		for k in defs:
			var m := StandardMaterial3D.new()
			m.albedo_color = defs[k]
			m.roughness = 0.5
			_shared_mats[k] = m
	return {"red": _shared_mats["sign_red"], "white": _shared_mats["sign_white"],
			"yellow": _shared_mats["sign_yellow"], "black": _shared_mats["sign_black"],
			"post": _shared_mats["sign_post"]}


func _sign_box(root: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	mi.mesh = b
	mi.position = pos
	root.add_child(mi)
	return mi


func _sign_disc(root: Node3D, pos: Vector3, r: float, m: Material, dz: float) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.02
	c.radial_segments = 24
	c.rings = 1
	c.material = m
	mi.mesh = c
	mi.position = pos + Vector3(0, 0, dz)
	mi.rotation = Vector3(PI * 0.5, 0, 0)
	root.add_child(mi)


## Trójkąt wierzchołkiem do góry (graniastosłup), przodem do +Z (do kierowcy).
## Z wierzchołków - CylinderMesh o 3 bokach dawał romb.
func _sign_tri(root: Node3D, pos: Vector3, r: float, m: Material, dz: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [Vector2(0, r), Vector2(r * 0.866, -r * 0.5), Vector2(-r * 0.866, -r * 0.5)]
	var zf := 0.01
	var zb := -0.01
	# Przód (+Z) i tył - zgodnie z ruchem wskazówek zegara patrząc z danej strony.
	st.add_vertex(Vector3(p[0].x, p[0].y, zf)); st.add_vertex(Vector3(p[1].x, p[1].y, zf)); st.add_vertex(Vector3(p[2].x, p[2].y, zf))
	st.add_vertex(Vector3(p[0].x, p[0].y, zb)); st.add_vertex(Vector3(p[2].x, p[2].y, zb)); st.add_vertex(Vector3(p[1].x, p[1].y, zb))
	for k in range(3):
		var a2: Vector2 = p[k]
		var b2: Vector2 = p[(k + 1) % 3]
		st.add_vertex(Vector3(a2.x, a2.y, zf)); st.add_vertex(Vector3(a2.x, a2.y, zb)); st.add_vertex(Vector3(b2.x, b2.y, zb))
		st.add_vertex(Vector3(a2.x, a2.y, zf)); st.add_vertex(Vector3(b2.x, b2.y, zb)); st.add_vertex(Vector3(b2.x, b2.y, zf))
	st.generate_normals()
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = pos + Vector3(0, 0, dz)
	root.add_child(mi)


func _sign_text(root: Node3D, t: String, pos: Vector3, px: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = t
	l.font_size = 96
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.position = pos
	root.add_child(l)


## Tunel od `d0` na długości `length`, z kolizją; co 40 m światło punktowe
## bez cieni (Quest). Nad tunelem GÓRA: masyw z łupku, który od wylotu
## wznosi się stokiem do grani ~70-80 m i opada przy drugim wylocie.
## Tunel wiercony (użytkownik: "przekrój koła, jakby wiercony, nie
## wykuwany"): okrągła rura, jezdnia jak pomost poniżej środka koła
## (środek TUNNEL_YC·R nad jezdnią, okrąg przecina poziom jezdni tuż za jej
## krawędziami). Pas jarzeniówek w szczycie. Wyloty: ściana czołowa
## z okrągłym otworem i betonowy pierścień; nad nimi stok góry z łupku.
const TUNNEL_YC := 0.35
const TUNNEL_SEG := 24


func _tunnel_radius(hw: float) -> float:
	return hw / sqrt(1.0 - TUNNEL_YC * TUNNEL_YC)


## Punkty łuku od prawej krawędzi jezdni przez szczyt do lewej (układ toru).
func _tunnel_arc(c: Vector3, r_h: Vector3, rad: float) -> Array:
	var a0 := -asin(TUNNEL_YC)
	var a1 := PI - a0
	var ctr := c + Vector3.UP * (TUNNEL_YC * rad)
	var pts: Array = []
	for k in range(TUNNEL_SEG + 1):
		var a := lerpf(a0, a1, float(k) / TUNNEL_SEG)
		pts.append(ctr + r_h * (cos(a) * rad) + Vector3.UP * (sin(a) * rad))
	return pts


## `twin` (niepusty): dwie nitki - rura nad każdą połową szerokiej jezdni
## (road_w każda, między nimi wyspa island_w); wspólna ściana czołowa
## z dwoma otworami (każda rura domyka ją do osi między nitkami).
func _build_tunnel(d0: float, length: float, twin := {}) -> void:
	const PEAK := 74.0              # grań góry nad jezdnią
	const RISE := 45.0              # stok od wylotu do pełnej wysokości [m]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mount := SurfaceTool.new()
	mount.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lamp := SurfaceTool.new()
	lamp.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var dummy := PackedVector3Array()
	var prev := {}
	var first := {}
	var last := {}
	var light_next := d0 + 10.0
	var hp := 0.0                   # górna krawędź ściany czołowej
	for smp in _samples:
		var d := float(smp["dist"])
		if d < d0 or d > d0 + length:
			continue
		var c: Vector3 = smp["pos"]
		var r_h: Vector3 = (smp["right"] * Vector3(1, 0, 1)).normalized()
		var hw := float(smp["width"]) * 0.5 + 1.2
		# Rury: [środek jezdni pod rurą, półszerokość rury].
		var tubes: Array = [[c, hw]]
		if not twin.is_empty():
			var rw: float = twin["road_w"]
			var off: float = rw * 0.5 + float(twin["island_w"]) * 0.5
			var thw := rw * 0.5 + 1.0
			tubes = [[c - r_h * off, thw], [c + r_h * off, thw]]
		var rad := _tunnel_radius(float(tubes[0][1]))
		var crown := rad * (1.0 + TUNNEL_YC)
		hp = crown + 2.5
		# Wysokość grani: stok od obu wylotów, trochę nierówna.
		var e := minf(d - d0, d0 + length - d)
		var rise := smoothstep(0.0, RISE, e)
		var hc := hp + (PEAK - hp + 8.0 * sin(d * 0.05)) * rise
		var prof: Array = []
		for pt in [[-(hw + 45.0), 0.3], [-(hw + 15.0), 0.75], [0.0, 1.0], [hw + 15.0, 0.8], [hw + 45.0, 0.35]]:
			prof.append(c + r_h * pt[0] + Vector3.UP * (hp + (hc - hp) * pt[1]))
		var arcs: Array = []
		for t in tubes:
			arcs.append(_tunnel_arc(t[0], r_h, rad))
		var p := {"arcs": arcs, "tubes": tubes, "c": c, "r": r_h, "hw": hw,
				"rad": rad, "crown": crown, "prof": prof}
		if first.is_empty():
			first = p
		last = p
		if not prev.is_empty():
			for ti in range(tubes.size()):
				var center: Vector3 = (tubes[ti][0] as Vector3) + Vector3.UP * (TUNNEL_YC * rad)
				var pa: Array = prev["arcs"][ti]
				var ca: Array = p["arcs"][ti]
				for k in range(TUNNEL_SEG):
					# Ściana rury patrzy do środka koła.
					_quad_facing(st, faces, pa[k], ca[k], ca[k + 1], pa[k + 1], center - (ca[k] as Vector3))
			# Stoki góry między przekrojami.
			for k in range(4):
				_quad_facing(mount, dummy, prev["prof"][k], p["prof"][k], p["prof"][k + 1],
						prev["prof"][k + 1], Vector3.UP)
			# Pas jarzeniówek: wąski, świecący, w szczycie każdej rury.
			for ti in range(tubes.size()):
				var la: Vector3 = (prev["tubes"][ti][0] as Vector3) + Vector3.UP * (float(prev["crown"]) - 0.08)
				var lb: Vector3 = (tubes[ti][0] as Vector3) + Vector3.UP * (crown - 0.08)
				var lo: Vector3 = prev["r"] * 0.18
				_quad_facing(lamp, dummy, la - lo, lb - lo, lb + lo, la + lo, Vector3.DOWN)
		if d >= light_next and Bench.on("tunnel_lights"):
			# Co 80 m (było 40): renderer mobilny płaci za każde światło na
			# każdym oświetlanym obiekcie; jarzeniówka i tak świeci.
			light_next = d + 80.0
			for t in tubes:
				var ol := OmniLight3D.new()
				ol.light_color = Color(0.85, 0.95, 1.0)
				ol.light_energy = 2.2
				ol.omni_range = 30.0
				ol.shadow_enabled = false
				ol.position = (t[0] as Vector3) + Vector3.UP * (crown - 0.6)
				_adopt(ol)
		prev = p
	if first.is_empty():
		return
	# Wyloty: ściana czołowa (prostokąt do hp, szeroki na 45 m w bok) z
	# okrągłym otworem - każdy odcinek łuku łączony z punktem na brzegu
	# prostokąta w tym samym kierunku od środka koła; w rogach dokładane
	# trójkąty do narożnika. Na krawędzi otworu betonowy pierścień.
	for end in [first, last]:
		var e: Dictionary = end
		var r: Vector3 = e["r"]
		var fwd_e := Vector3.UP.cross(r)                          # kierunek jazdy
		var out_dir: Vector3 = fwd_e * (1.0 if e == last else -1.0)
		var c: Vector3 = e["c"]
		var rad: float = e["rad"]
		var big: float = float(e["hw"]) + 45.0
		var tubes_e: Array = e["tubes"]
		for ti in range(tubes_e.size()):
			var tc: Vector3 = tubes_e[ti][0]
			var tx := (tc - c).dot(r)                             # środek rury w poprzek
			# Ta rura domyka ścianę od -big do osi (lewa nitka) / od osi do
			# +big (prawa nitka); pojedyncza - całą szerokość.
			var xmin := -big if (tubes_e.size() == 1 or ti == 0) else 0.0
			var xmax := big if (tubes_e.size() == 1 or ti == 1) else 0.0
			_tunnel_facade(st, faces, tc, r, rad, tx, xmin, xmax, hp, (e["arcs"] as Array)[ti], out_dir)
		# Przednia krawędź stoku góry - domyka przekrój od ściany czołowej w górę.
		var lo_l: Vector3 = c - r * big
		var pr: Array = e["prof"]
		for k in range(4):
			_quad_facing(mount, dummy, lo_l + Vector3.UP * hp if k == 0 else pr[k], pr[k + 1],
					pr[k + 1], pr[k], out_dir)
	st.generate_normals()
	st.set_material(_concrete_material())
	mount.generate_normals()
	mount.set_material(_rock_material("ocean"))
	lamp.generate_normals()
	lamp.set_material(_lamp_material())
	var mesh := st.commit()
	mount.commit(mesh)
	lamp.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.name = "Tunnel"
	mi.mesh = mesh
	_adopt(mi)
	_collision_body("TunnelBody", faces, "rock", 0.55)


## Ściana czołowa z okrągłym otworem dla jednej rury: każdy odcinek łuku
## łączony z punktem na brzegu prostokąta [xmin, xmax] × [0, hp] (w układzie
## jezdni pod środkiem tej rury przesuniętym o tx) w tym samym kierunku od
## środka koła; w narożnikach trójkąty. Na krawędzi otworu betonowy
## pierścień wystający 0,6 m.
func _tunnel_facade(st: SurfaceTool, faces: PackedVector3Array, tc: Vector3, r: Vector3,
		rad: float, tx: float, xmin: float, xmax: float, hp: float, arc: Array,
		out_dir: Vector3) -> void:
	var yc := TUNNEL_YC * rad
	var a0 := -asin(TUNNEL_YC)
	# Granice prostokąta względem środka rury.
	var bx0 := xmin - tx
	var bx1 := xmax - tx
	var outer: Array = []
	var edge_id: Array = []
	for k in range(TUNNEL_SEG + 1):
		var a := lerpf(a0, PI - a0, float(k) / TUNNEL_SEG)
		var dx := cos(a)
		var dy := sin(a)
		var t := INF
		var eid := -1
		if dx > 0.001 and bx1 / dx < t:
			t = bx1 / dx
			eid = 0
		if dx < -0.001 and bx0 / dx < t:
			t = bx0 / dx
			eid = 2
		if dy > 0.001 and (hp - yc) / dy < t:
			t = (hp - yc) / dy
			eid = 1
		if dy < -0.001 and yc / -dy < t:
			t = yc / -dy
			eid = 3
		outer.append(tc + r * (dx * t) + Vector3.UP * (yc + dy * t))
		edge_id.append(eid)
	for k in range(TUNNEL_SEG):
		_quad_facing(st, faces, arc[k], arc[k + 1], outer[k + 1], outer[k], out_dir)
		if edge_id[k] != edge_id[k + 1]:
			# Narożnik górny: prawy przy przejściu bok prawy -> góra, lewy przy
			# góra -> bok lewy.
			var cx := bx1 if (edge_id[k] == 0 or edge_id[k + 1] == 0) else bx0
			var corner: Vector3 = tc + r * cx + Vector3.UP * hp
			_tri_facing(st, outer[k], outer[k + 1], corner, out_dir)
	var ctr: Vector3 = tc + Vector3.UP * yc
	var f := out_dir * 0.6
	for k in range(TUNNEL_SEG):
		var p0: Vector3 = arc[k]
		var p1: Vector3 = arc[k + 1]
		var o0: Vector3 = ctr + (p0 - ctr) * ((rad + 1.2) / rad)
		var o1: Vector3 = ctr + (p1 - ctr) * ((rad + 1.2) / rad)
		_quad_facing(st, faces, p0 + f, p1 + f, o1 + f, o0 + f, out_dir)
		_quad_facing(st, faces, p0, p1, p1 + f, p0 + f, ctr - p0)
		_quad_facing(st, faces, o0, o1, o1 + f, o0 + f, o0 - ctr)


## Trójkąt nawinięty przodem w stronę `facing` (front: zgodnie z zegarem).
func _tri_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	if (c - a).cross(b - a).dot(facing) < 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _lamp_material() -> Material:
	if not _shared_mats.has("lamp"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.9, 0.97, 1.0)
		m.emission_enabled = true
		m.emission = Color(0.85, 0.95, 1.0)
		m.emission_energy_multiplier = 3.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_mats["lamp"] = m
	return _shared_mats["lamp"]


## Skalna wyspa rozwidlenia: od `d0` na długości `length`, szerokość `w`,
## zwężona na obu końcach (12 m), wysokość 3,5 m, z kolizją.
## Czoło jest pionową, tępą ścianą pełnej wysokości (ISLAND_NOSE_W szerokości)
## z oznakowaniem (_island_front). Wcześniej dziób zaczynał się od ~1 m
## wysokości i rósł przez 6 m - z auta wyglądał i działał jak rampa
## ("podjazd jak bariera", użytkownik 2026-11-09).
const ISLAND_NOSE_W := 1.4
func _build_island(d0: float, length: float, w: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var prev := {}
	var first := {}
	var first_fwd := Vector3.FORWARD
	var last_fwd := Vector3.FORWARD
	for smp in _samples:
		var d := float(smp["dist"])
		if d < d0 or d > d0 + length:
			continue
		var t := minf(d - d0, d0 + length - d)
		var half := maxf(w * 0.5 * clampf(t / 12.0, 0.0, 1.0), ISLAND_NOSE_W * 0.5)
		var c: Vector3 = smp["pos"]
		var r_h: Vector3 = (smp["right"] * Vector3(1, 0, 1)).normalized()
		var h := 3.5
		var p := {"l0": c - r_h * half, "r0": c + r_h * half,
				"l1": c - r_h * half * 0.8 + Vector3.UP * h, "r1": c + r_h * half * 0.8 + Vector3.UP * h}
		if prev.is_empty():
			first = p
			first_fwd = (smp["fwd"] * Vector3(1, 0, 1)).normalized()
		else:
			_quad_facing(st, faces, prev["l0"], p["l0"], p["l1"], prev["l1"], -r_h)
			_quad_facing(st, faces, prev["r0"], p["r0"], p["r1"], prev["r1"], r_h)
			_quad_facing(st, faces, prev["l1"], p["l1"], p["r1"], prev["r1"], Vector3.UP)
		last_fwd = (smp["fwd"] * Vector3(1, 0, 1)).normalized()
		prev = p
	if faces.is_empty():
		return
	# Czoło i tył: pionowe ściany zamykające bryłę (z kolizją - auto, które
	# nie wybierze strony, uderza w ścianę, nie wjeżdża na skałę).
	_quad_facing(st, faces, first["l0"], first["r0"], first["r1"], first["l1"], -first_fwd)
	_quad_facing(st, faces, prev["l0"], prev["r0"], prev["r1"], prev["l1"], last_fwd)
	st.generate_normals()
	st.set_material(_rock_material("cavern"))
	var mi := MeshInstance3D.new()
	mi.name = "Island"
	mi.mesh = st.commit()
	_adopt(mi)
	_collision_body("IslandBody", faces, "rock", 0.55)


## Oznakowanie czoła wysepki (użytkownik 2026-11-09): żółto-czarna tablica
## przeszkodowa z pasami skośnymi w obie strony (objazd z obu stron)
## i nad nią niebieski znak C-11 "nakaz jazdy z prawej lub lewej strony
## znaku". Trójkąt A-30 120 m wcześniej stawia generator
## (TrackGenerator._island_warning). Tablice odsunięte 5 cm od ściany.
func _island_front(d0: float) -> void:
	var root := Node3D.new()
	root.name = "IslandFront"
	_adopt(root)
	# Pierwsza próbka >= d0 - na niej _build_island stawia ścianę czoła.
	var smp: Dictionary = _samples[mini(_dists.bsearch(d0, true), _samples.size() - 1)]
	root.transform = _sample_transform(smp)
	var fwd_h := (-root.basis.z * Vector3(1, 0, 1)).normalized()
	var origin := root.position
	root.basis = Basis.looking_at(fwd_h, Vector3.UP)
	root.position = origin
	var mats := _sign_mats()
	var z := 0.05
	# Tablica: tył jak słupek, przód - QuadMesh (UV 0..1; BoxMesh dzieli
	# teksturę na 6 ścian i pasy by się rozjechały).
	_sign_box(root, Vector3(1.2, 1.0, 0.03), Vector3(0, 1.0, z), mats["post"])
	var board := MeshInstance3D.new()
	board.name = "HazardBoard"
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.0)
	q.material = _hazard_mat()
	board.mesh = q
	board.position = Vector3(0, 1.0, z + 0.017)
	root.add_child(board)
	# C-11: niebieska tarcza, dwie białe strzałki w dół, w lewo i w prawo.
	if not _shared_mats.has("sign_blue"):
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.05, 0.25, 0.65)
		_shared_mats["sign_blue"] = bm
	var face := Vector3(0, 2.25, z)
	_sign_disc(root, face, 0.42, mats["white"], 0.0)
	_sign_disc(root, face, 0.38, _shared_mats["sign_blue"], 0.012)
	for sx in [-1.0, 1.0]:
		var shaft := _sign_box(root, Vector3(0.06, 0.34, 0.01), face + Vector3(0.1 * sx, -0.02, 0.03), mats["white"])
		shaft.rotation = Vector3(0, 0, 0.75 * sx)
		var head := _sign_box(root, Vector3(0.16, 0.16, 0.01), face + Vector3(0.2 * sx, -0.14, 0.03), mats["white"])
		head.rotation = Vector3(0, 0, PI * 0.25)


## Materiał tablicy przeszkodowej: żółto-czarne pasy pod 45°, opadające od
## środka na obie strony (strzałka w dół = objazd z obu stron). Tekstura
## 64x64 liczona raz.
func _hazard_mat() -> Material:
	if _shared_mats.has("hazard"):
		return _shared_mats["hazard"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var yellow := Color(0.98, 0.8, 0.1)
	for y in 64:
		for x in 64:
			var band := int(floor((absf(float(x) - 31.5) + float(y)) / 12.0))
			img.set_pixel(x, y, yellow if band % 2 == 0 else Color(0.04, 0.04, 0.04))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.5
	_shared_mats["hazard"] = m
	return m


func _collision_body(n: String, faces: PackedVector3Array, surface: String, grip: float) -> void:
	if not generate_collision or faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = n
	body.set_meta("surface", surface)
	body.set_meta("grip", grip)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_adopt(body)
	body.add_child(cs)
	cs.owner = body.owner


## Zielony znak jak przy wjeździe do miejscowości (E-17a): biały napis,
## biała ramka, na dwóch słupkach przy prawej krawędzi.
func _town_sign(dist: float, text: String, crossed := false) -> void:
	var root := Node3D.new()
	root.name = "TownSign"
	_adopt(root)
	root.transform = global_transform.affine_inverse() * transform_at_distance(dist)
	var fwd_h := (-root.basis.z * Vector3(1, 0, 1)).normalized()
	var origin := root.position
	root.basis = Basis.looking_at(fwd_h, Vector3.UP)
	root.position = origin
	# Tablica 1,9 m na poboczu: między krawędzią jezdni (hw) a stopą ściany
	# wąwozu (hw + 1,8, na wysokości tablicy ~hw + 2,1). Wcześniej 2,8 m
	# na środku hw + 1,6 wchodziła w skałę (użytkownik: "znaki toną w ścianie").
	var smp := _sample_near(dist)
	var x: float = float(smp["width"]) * 0.5 + 1.0
	# Podstawa na wysokości krawędzi jezdni (na przechyłce krawędź jest wyżej
	# albo niżej niż środek).
	var y0: float = (smp["right"] as Vector3).y * x
	var mats := _sign_mats()
	if not _shared_mats.has("sign_green"):
		var g := StandardMaterial3D.new()
		g.albedo_color = Color(0.05, 0.42, 0.2)
		g.roughness = 0.5
		_shared_mats["sign_green"] = g
	for px in [-0.55, 0.55]:
		_sign_box(root, Vector3(0.07, 2.6, 0.07), Vector3(x + px, y0 + 1.0, -0.05), mats["post"])
	var cy := y0 + 2.2
	_sign_box(root, Vector3(1.9, 0.6, 0.04), Vector3(x, cy, 0.0), mats["white"])
	_sign_box(root, Vector3(1.8, 0.5, 0.05), Vector3(x, cy, 0.005), _shared_mats["sign_green"])
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.0023
	l.modulate = Color(0.97, 0.97, 0.95)
	l.outline_size = 0
	l.position = Vector3(x, cy, 0.04)
	root.add_child(l)
	if crossed:
		# Koniec odcinka (jak E-18a koniec miejscowości): czerwony ukos.
		var bar := _sign_box(root, Vector3(1.85, 0.06, 0.01), Vector3(x, cy, 0.06), mats["red"])
		bar.rotation = Vector3(0, 0, -0.26)


## U-3 tablica kierująca: czerwona z białą strzałką w stronę zakrętu,
## po zewnętrznej stronie łuku (dir > 0 = zakręt w prawo).
func _chevron(dist: float, dir: int) -> void:
	var root := Node3D.new()
	root.name = "Chevron"
	_adopt(root)
	root.transform = global_transform.affine_inverse() * transform_at_distance(dist)
	var fwd_h := (-root.basis.z * Vector3(1, 0, 1)).normalized()
	var origin := root.position
	root.basis = Basis.looking_at(fwd_h, Vector3.UP)
	root.position = origin
	var x: float = (_sample_near(dist)["width"] * 0.5 + 0.8) * -dir      # zewnętrzna strona
	var mats := _sign_mats()
	_sign_box(root, Vector3(0.06, 1.2, 0.06), Vector3(x, 0.6, -0.04), mats["post"])
	_sign_box(root, Vector3(0.5, 0.6, 0.03), Vector3(x, 1.4, 0.0), mats["red"])
	for k in [-1.0, 1.0]:
		var arm := _sign_box(root, Vector3(0.22, 0.06, 0.01), Vector3(x + 0.03 * dir, 1.4 + 0.07 * k, 0.02), mats["white"])
		arm.rotation = Vector3(0, 0, -0.75 * k * dir)


## Znak drogowy przy prawej krawędzi: tablica na słupku, z tekstem
## (np. prędkość potrzebna do skoku), czytelny z nadjeżdżającego auta.
func _build_sign(dist: float, text: String, board_color := Color(0.95, 0.75, 0.1)) -> void:
	var root := Node3D.new()
	root.name = "Sign"
	_adopt(root)
	root.transform = global_transform.affine_inverse() * transform_at_distance(dist)
	var s := _sample_near(dist)
	var x: float = s["width"] * 0.5 + 0.6
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.6, 0.6, 0.62)
	var post := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.12, 2.6, 0.12)
	pb.material = post_mat
	post.mesh = pb
	post.position = Vector3(x, 1.3, 0.0)
	root.add_child(post)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = board_color
	var board := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(2.6, 0.9, 0.06)
	bb.material = board_mat
	board.mesh = bb
	board.position = Vector3(x, 2.9, 0.0)
	root.add_child(board)
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.position = Vector3(x, 2.9, 0.04)
	root.add_child(label)


## Warsztat przy prawej krawędzi: hala z dachem, otwarte wrota, szyld
## "WARSZTAT" i żółta linia postoju w poprzek jezdni na `stop_dist`.
func _build_workshop(stop_dist: float) -> void:
	var root := Node3D.new()
	root.name = "Workshop"
	_adopt(root)
	root.transform = global_transform.affine_inverse() * transform_at_distance(stop_dist)
	var s := _sample_near(stop_dist)
	var hw: float = s["width"] * 0.5
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.78, 0.74, 0.66)
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.45, 0.18, 0.12)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.8, 0.1)
	# Hala stoi na platformie przy jezdni (na tej samej wysokości).
	var hall_x := hw + 6.0
	var parts := [
		[Vector3(9.0, 0.4, 14.0), Vector3(hall_x, -0.2, 0.0), wall],      # platforma
		[Vector3(0.4, 4.5, 14.0), Vector3(hall_x + 4.3, 2.25, 0.0), wall],  # tylna ściana
		[Vector3(9.0, 4.5, 0.4), Vector3(hall_x, 2.25, -6.8), wall],       # boki
		[Vector3(9.0, 4.5, 0.4), Vector3(hall_x, 2.25, 6.8), wall],
		[Vector3(9.6, 0.3, 14.8), Vector3(hall_x, 4.65, 0.0), roof],       # dach
		[Vector3(0.3, 0.9, 6.0), Vector3(hall_x - 4.5, 5.25, 0.0), yellow], # szyld
		[Vector3(0.1, 3.6, 10.0), Vector3(hall_x + 4.05, 1.9, 0.0), dark],  # ciemne wnętrze
	]
	for part in parts:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		b.material = part[2]
		mi.mesh = b
		mi.position = part[1]
		root.add_child(mi)
	var label := Label3D.new()
	label.text = "WARSZTAT"
	label.font_size = 96
	label.pixel_size = 0.01
	label.modulate = Color(0.1, 0.08, 0.05)
	label.outline_size = 0
	label.position = Vector3(hall_x - 4.67, 5.25, 0.0)
	label.rotation = Vector3(0.0, -PI * 0.5, 0.0)    # przodem do jezdni
	root.add_child(label)
	# Duży napis na ścianie szczytowej - czytelny dla nadjeżdżającego auta
	# (auto jedzie w -Z, więc ta ściana patrzy w +Z, prosto na kierowcę).
	var front := Label3D.new()
	front.text = "WARSZTAT"
	front.font_size = 160
	front.pixel_size = 0.012
	front.modulate = Color(0.95, 0.8, 0.1)
	front.outline_size = 24
	front.outline_modulate = Color(0.1, 0.08, 0.05)
	front.position = Vector3(hall_x, 2.6, 7.02)
	root.add_child(front)
	# Linia postoju.
	var stop := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(hw * 2.0, 0.02, 0.6)
	sb.material = yellow
	stop.mesh = sb
	stop.position = Vector3(0.0, 0.012, 0.0)
	root.add_child(stop)


## Próbki od `dist` na długości `length` (HUD trasy, autopilot).
func samples_from(dist: float, length: float) -> Array:
	var i0 := _dists.bsearch(dist, true)
	var i1 := _dists.bsearch(dist + length, false)
	if i1 <= i0:
		return []
	return _samples.slice(i0, i1)


## Dystans pierwszej i ostatniej próbki (zakres kawałka trasy).
func dist_range() -> Vector2:
	if _dists.is_empty():
		return Vector2(INF, -INF)
	return Vector2(_dists[0], _dists[_dists.size() - 1])


## Zjazd: wysepka (z kolizją) oddzielająca pas zjazdu od głównej drogi,
## po prawej stacja (dystrybutory, ładowarki, zadaszenie) albo warsztat
## (hala z napisem). Tankuje się, jadąc powoli pasem zjazdu; do warsztatu
## trzeba wjechać i stanąć.
## Biała strzałka "zjazd w prawo" w dolnym polu niebieskiego znaku.
func _exit_arrow(root: Node3D, face: Vector3, mat: Material) -> void:
	var shaft := _sign_box(root, Vector3(0.05, 0.2, 0.01), face + Vector3(-0.02, -0.26, 0.025), mat)
	shaft.rotation = Vector3(0, 0, -0.785)
	_sign_box(root, Vector3(0.13, 0.045, 0.01), face + Vector3(0.06, -0.19, 0.025), mat)
	_sign_box(root, Vector3(0.045, 0.13, 0.01), face + Vector3(0.10, -0.23, 0.025), mat)


## Zjazd do warsztatu / na stację. Oprócz znaku na początku odcinka
## (>= 800 m wcześniej) przypomnienia 300 m i 100 m przed zjazdem i znak
## ze strzałką na samym zjeździe (użytkownik nie znalazł zjazdu do warsztatu
## - jedyny znak stał prawie kilometr wcześniej).
func _build_service(d0: float, st: Dictionary) -> void:
	var w0: float = st["road_w"]
	var length: float = st["len"]
	var kind := "fuel" if st["kind"] == "station" else "repair"
	var exit_d := d0 - 40.0              # początek poszerzenia (pas zjazdu)
	for back in [300.0, 100.0]:
		if exit_d - back > float(_samples[0]["dist"]) + 2.0:
			_road_sign(exit_d - back, kind)
	_road_sign(exit_d, kind, 1)
	_build_separator(d0, length, w0 * 0.5 + 0.7)
	if st["kind"] == "station":
		_build_station(d0, st)
	else:
		_build_workshop_bay(d0, st)


## Wysepka między główną drogą a pasem zjazdu: krawężnik z ostrymi końcami.
func _build_separator(d0: float, length: float, x: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var prev := {}
	for smp in _samples:
		var d := float(smp["dist"])
		if d < d0 or d > d0 + length:
			continue
		var t := minf(d - d0, d0 + length - d)
		var half := 0.5 * clampf(t / 8.0, 0.05, 1.0)
		var c: Vector3 = smp["pos"]
		var r_h: Vector3 = (smp["right"] * Vector3(1, 0, 1)).normalized()
		var base: Vector3 = c + (smp["right"] as Vector3) * x
		var p := {"l": base - r_h * half, "r": base + r_h * half,
				"lt": base - r_h * half + Vector3.UP * 0.25, "rt": base + r_h * half + Vector3.UP * 0.25}
		if not prev.is_empty():
			_quad_facing(st, faces, prev["l"], p["l"], p["lt"], prev["lt"], -r_h)
			_quad_facing(st, faces, prev["r"], p["r"], p["rt"], prev["rt"], r_h)
			_quad_facing(st, faces, prev["lt"], p["lt"], p["rt"], prev["rt"], Vector3.UP)
		prev = p
	st.generate_normals()
	st.set_material(_sign_mats()["white"])
	var mi := MeshInstance3D.new()
	mi.name = "Separator"
	mi.mesh = st.commit()
	_adopt(mi)
	_collision_body("SeparatorBody", faces, "rock", 0.55)


## Warsztat w zatoce zjazdu: hala z otwartym frontem i napisem.
func _build_workshop_bay(d0: float, st: Dictionary) -> void:
	var w0: float = st["road_w"]
	var root := Node3D.new()
	root.name = "WorkshopBay"
	_adopt(root)
	var mid := d0 + float(st["len"]) * 0.5
	root.transform = global_transform.affine_inverse() * transform_at_distance(mid)
	var fwd_h := (-root.basis.z * Vector3(1, 0, 1)).normalized()
	var pos0 := root.position
	root.basis = Basis.looking_at(fwd_h, Vector3.UP)
	root.position = pos0
	var mats := _sign_mats()
	var x0 := w0 * 0.5 + 4.6
	_sign_box(root, Vector3(0.4, 5.0, 24.0), Vector3(x0 + 3.0, 2.5, 0.0), mats["white"])
	_sign_box(root, Vector3(3.4, 0.4, 24.0), Vector3(x0 + 1.3, 5.2, 0.0), mats["red"])
	for z in [-12.0, 12.0]:
		_sign_box(root, Vector3(3.4, 5.0, 0.4), Vector3(x0 + 1.3, 2.5, z), mats["white"])
	var l := Label3D.new()
	l.text = "WARSZTAT"
	l.font_size = 96
	l.pixel_size = 0.008
	l.modulate = Color(0.95, 0.8, 0.1)
	l.outline_size = 16
	l.position = Vector3(x0 + 1.3, 6.0, 12.25)
	root.add_child(l)


## Stacja paliw: dystrybutory i ładowarki (kolizja) za pasem zjazdu,
## zadaszenie nad pasem.
func _build_station(d0: float, st: Dictionary) -> void:
	var w0: float = st["road_w"]
	var length: float = st["len"]
	var root := Node3D.new()
	root.name = "Station"
	_adopt(root)
	var mid := d0 + length * 0.5
	root.transform = global_transform.affine_inverse() * transform_at_distance(mid)
	var fwd_h := (-root.basis.z * Vector3(1, 0, 1)).normalized()
	var pos0 := root.position
	root.basis = Basis.looking_at(fwd_h, Vector3.UP)
	root.position = pos0
	var mats := _sign_mats()
	var island_x := w0 * 0.5 + 4.6
	var body := StaticBody3D.new()
	root.add_child(body)
	_sign_box(root, Vector3(1.2, 0.2, 50.0), Vector3(island_x, 0.1, 0.0), mats["white"])
	# (pas zjazdu: od wysepki do dystrybutorów)
	for k in range(5):
		var z := -18.0 + k * 9.0
		var is_charger := k >= 3
		var col: Material = mats["red"] if not is_charger else _station_green()
		_sign_box(root, Vector3(0.6, 1.6, 0.5), Vector3(island_x, 1.0, z), col)
		_sign_box(root, Vector3(0.62, 0.3, 0.52), Vector3(island_x, 1.6, z), mats["white"])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6, 1.8, 0.5)
		cs.shape = bs
		cs.position = Vector3(island_x, 0.9, z)
		body.add_child(cs)
	# Zadaszenie: płyta na czterech słupach, nad wysepką i pasem stacji.
	var roof_x := island_x - 2.2
	_sign_box(root, Vector3(7.0, 0.5, 56.0), Vector3(roof_x, 5.2, 0.0), mats["white"])
	_sign_box(root, Vector3(7.1, 0.25, 56.1), Vector3(roof_x, 4.95, 0.0), mats["red"])
	for cx in [roof_x - 3.0, roof_x + 3.0]:
		for cz in [-25.0, 25.0]:
			_sign_box(root, Vector3(0.3, 5.0, 0.3), Vector3(cx, 2.5, cz), mats["post"])
	var l := Label3D.new()
	l.text = "PALIWO / ŁADOWANIE"
	l.font_size = 96
	l.pixel_size = 0.004
	l.modulate = Color(0.95, 0.1, 0.08)
	l.outline_size = 0
	l.position = Vector3(roof_x, 5.2, 28.06)
	root.add_child(l)


func _station_green() -> Material:
	if not _shared_mats.has("station_green"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.6, 0.3)
		_shared_mats["station_green"] = m
	return _shared_mats["station_green"]


## Zjazdy danego rodzaju: [{"start", "end" - strefa, "lane_x" - od tej
## odległości od osi w prawo to pas zjazdu, "tier" - próg mocy warsztatu}].
func services(kind: String) -> Array:
	var out := []
	for smp in _samples:
		if smp["meta"].has("service") and smp["meta"]["service"]["kind"] == kind:
			var st: Dictionary = smp["meta"]["service"]
			var d := float(smp["dist"])
			out.append({"start": d + 10.0, "end": d + float(st["len"]) - 10.0,
					"lane_x": float(st["road_w"]) * 0.5 + 1.1, "tier": st["tier"],
					"stop": d + float(st["len"]) - 10.0})
	return out


func stations() -> Array:
	return services("station")


## Warsztaty (zjazdy) na tym torze.
func workshops() -> Array:
	return services("workshop")


func _sample_near(dist: float) -> Dictionary:
	var i := _dists.bsearch(dist, true)
	return _samples[mini(i, _samples.size() - 1)]


## Całkowita długość toru w metrach.
func total_length() -> float:
	return 0.0 if _samples.is_empty() else float(_samples[-1]["dist"])


## Koniec ostatniej przerwy, która kończy się nie dalej niż `dist`.
## -INF, jeśli przed `dist` nie ma żadnej przerwy.
func last_gap_end_before(dist: float) -> float:
	var end := -INF
	var in_gap := false
	for s in _samples:
		var d := float(s["dist"])
		if d > dist:
			break
		if s["gap"]:
			in_gap = true
		elif in_gap:
			end = d
			in_gap = false
	return end


## Początek rozbiegu (znak z prędkością) skoku, którego auto jeszcze nie
## przeskoczyło, jeśli `dist` leży na rozbiegu, rampie albo w przerwie.
## -1, jeśli nie. Dźwig stawia tam auto, bo 35 m wstecz to za mało, żeby
## rozpędzić się do prędkości skoku.
func runup_start_before(dist: float) -> float:
	var sign_d := -1.0
	var prev_gap := false
	for smp in _samples:
		if float(smp["dist"]) > dist:
			break
		if smp["meta"].has("sign"):
			sign_d = float(smp["dist"])
		elif prev_gap and not smp["gap"]:
			sign_d = -1.0       # koniec przerwy - ten skok już za nami
		prev_gap = smp["gap"]
	return sign_d


## Czy `dist` leży w przerwie.
func is_gap_at(dist: float) -> bool:
	for s in _samples:
		if float(s["dist"]) >= dist:
			return s["gap"]
	return false


## Globalny układ współrzędnych na osi toru w odległości `dist` od startu.
## Oś -Z wskazuje kierunek jazdy, Y prostopadle do jezdni.
## Przeskakuje przerwy - zwraca najbliższą próbkę z jezdnią przed `dist`.
func transform_at_distance(dist: float) -> Transform3D:
	if _samples.is_empty():
		return global_transform
	# Ostatnia próbka nie dalej niż `dist`, która nie jest przerwą.
	var idx := clampi(_dists.bsearch(dist, false) - 1, 0, _samples.size() - 1)
	while idx > 0 and _samples[idx]["gap"]:
		idx -= 1
	return global_transform * _sample_transform(_samples[idx])


func _sample_transform(s: Dictionary) -> Transform3D:
	var b := Basis(s["right"], s["up"], -s["fwd"])
	return Transform3D(b, s["pos"])


## Zwraca próbkę najbliższą podanej pozycji. Pozwala tanio sprawdzić,
## jak daleko od osi toru jest samochód i czy już z niego spadł.
## Najpierw okolica ostatnio znalezionej próbki (auto przesuwa się między
## zapytaniami o kilka metrów); całość tylko, gdy najlepsza wypadła na
## brzegu okna (auto przeskoczyło dalej, np. odrodzenie).
var _near_hint := 0
const NEAR_WINDOW := 40

func nearest_sample(world_pos: Vector3) -> Dictionary:
	if _samples.is_empty():
		return {}
	var local := to_local(world_pos)
	var lo := maxi(_near_hint - NEAR_WINDOW, 0)
	var hi := mini(_near_hint + NEAR_WINDOW, _samples.size() - 1)
	var bi := _nearest_in(local, lo, hi)
	if (bi == lo and lo > 0) or (bi == hi and hi < _samples.size() - 1):
		bi = _nearest_in(local, 0, _samples.size() - 1)
	_near_hint = bi
	return _samples[bi]


func _nearest_in(local: Vector3, lo: int, hi: int) -> int:
	var bi := lo
	var best_d := INF
	for i in range(lo, hi + 1):
		var d: float = local.distance_squared_to(_samples[i]["pos"])
		if d < best_d:
			best_d = d
			bi = i
	return bi


## Odległość od osi toru w poprzek (dodatnia w prawo) oraz informacja,
## czy pozycja mieści się jeszcze w szerokości jezdni.
func lateral_offset(world_pos: Vector3, s := {}) -> Dictionary:
	if s.is_empty():
		s = nearest_sample(world_pos)
	if s.is_empty():
		return {"offset": 0.0, "on_track": false}
	var delta: Vector3 = to_local(world_pos) - s["pos"]
	var offset: float = delta.dot(s["right"])
	var on_track: bool = not s["gap"] and absf(offset) <= float(s["width"]) * 0.5
	return {"offset": offset, "on_track": on_track, "sample": s}



# --------------------------------------------------------------------------
# Autostrada
# --------------------------------------------------------------------------

## Druga jezdnia (przesunięta w lewo o szerokość jezdni + pas rozdziału),
## betonowa bariera środkowa, trawiasty pas rozdziału, bariery
## energochłonne po zewnętrznych krawędziach, nasyp do terenu (y = 0).
## Wszystko z kolizją oprócz trawy na nasypie.
func _build_highway() -> void:
	var med := TrackGenerator.HIGHWAY_MEDIAN
	# Druga jezdnia: te same próbki przesunięte w lewo - siatka i kolizja
	# jak jezdni głównej (ten sam materiał z liniami).
	var shifted: Array[Dictionary] = []
	for smp in _samples:
		var c: Dictionary = smp.duplicate()
		c["pos"] = (smp["pos"] as Vector3) - (smp["right"] as Vector3) * (float(smp["width"]) + med)
		shifted.append(c)
	var keep := _samples
	_samples = shifted
	var opp_faces := {}
	_road_layout = 2 if hwy_plan else 0
	var opp_mesh := _build_mesh(opp_faces)
	_road_layout = 1 if hwy_plan else 0
	_samples = keep
	var omi := MeshInstance3D.new()
	omi.name = "OppositeRoad"
	omi.mesh = opp_mesh
	_adopt(omi)
	_build_road_collision(opp_faces)

	var concrete := SurfaceTool.new()
	concrete.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal := SurfaceTool.new()
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass := SurfaceTool.new()
	grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var none := PackedVector3Array()
	var prev := {}
	var idxs := range(0, _samples.size(), 2)
	if idxs[-1] != _samples.size() - 1:
		idxs.append(_samples.size() - 1)
	for i in idxs:
		var smp: Dictionary = _samples[i]
		var c: Vector3 = smp["pos"]
		var r: Vector3 = smp["right"]
		var rh := (r * Vector3(1, 0, 1)).normalized()
		var hw := float(smp["width"]) * 0.5
		var mid := c - r * (hw + med * 0.5)               # środek pasa rozdziału
		var out_r := c + r * (hw + 0.6)                     # bariera prawa
		var out_l := c - r * (hw + med + 2.0 * hw + 0.6)    # bariera lewa (druga jezdnia)
		var h_r := maxf(out_r.y, 0.0)
		var h_l := maxf(out_l.y, 0.0)
		var p := {
			# Bariera betonowa (New Jersey): podstawa 0,6 m, góra 0,2 m, 0,85 m.
			"jb_l0": mid - rh * 0.3, "jb_l1": mid - rh * 0.1 + Vector3.UP * 0.85,
			"jb_r0": mid + rh * 0.3, "jb_r1": mid + rh * 0.1 + Vector3.UP * 0.85,
			# Trawa w pasie rozdziału (między krawędziami jezdni).
			"md_r": c - r * hw + Vector3.DOWN * 0.03, "md_l": c - r * (hw + med) + Vector3.DOWN * 0.03,
			# Bariery energochłonne: taśma 0,5-0,85 m.
			"gr0": out_r + Vector3.UP * 0.5, "gr1": out_r + Vector3.UP * 0.85,
			"gl0": out_l + Vector3.UP * 0.5, "gl1": out_l + Vector3.UP * 0.85,
			# Nasyp 1:2 do terenu.
			"er0": out_r + Vector3.DOWN * 0.05, "er1": Vector3(out_r.x, 0.0, out_r.z) + rh * (2.0 * h_r + 2.0),
			"el0": out_l + Vector3.DOWN * 0.05, "el1": Vector3(out_l.x, 0.0, out_l.z) - rh * (2.0 * h_l + 2.0),
			# Pobocze między jezdnią a barierą.
			"sr0": c + r * hw + Vector3.DOWN * 0.03, "sl0": c - r * (hw + med + 2.0 * hw) + Vector3.DOWN * 0.03,
		}
		# W zabudowie miasta (tryb Autostrada) zamiast barier energochłonnych,
		# trawy i nasypu - chodnik z krawężnikiem (HighwayScenery._sidewalks);
		# bariera w pasie rozdziału zostaje (spec. pkt 4).
		var in_city := hwy_plan != null and not hwy_plan.city_at(float(smp["dist"])).is_empty()
		if not prev.is_empty() and in_city:
			var q2 := prev
			_quad_facing(concrete, faces, q2["jb_l0"], p["jb_l0"], p["jb_l1"], q2["jb_l1"], -rh)
			_quad_facing(concrete, faces, q2["jb_r0"], p["jb_r0"], p["jb_r1"], q2["jb_r1"], rh)
			_quad_facing(concrete, faces, q2["jb_l1"], p["jb_l1"], p["jb_r1"], q2["jb_r1"], Vector3.UP)
			_quad_facing(grass, faces, q2["md_r"], p["md_r"], p["md_l"], q2["md_l"], Vector3.UP)
		elif not prev.is_empty():
			var q := prev
			_quad_facing(concrete, faces, q["jb_l0"], p["jb_l0"], p["jb_l1"], q["jb_l1"], -rh)
			_quad_facing(concrete, faces, q["jb_r0"], p["jb_r0"], p["jb_r1"], q["jb_r1"], rh)
			_quad_facing(concrete, faces, q["jb_l1"], p["jb_l1"], p["jb_r1"], q["jb_r1"], Vector3.UP)
			# Pas rozdziału i pobocza z kolizją (przegląd PR #7: bez niej auto
			# zepchnięte ~0,5 m za krawędź spadało pod nasyp); nasyp bez.
			_quad_facing(grass, faces, q["md_r"], p["md_r"], p["md_l"], q["md_l"], Vector3.UP)
			_quad_facing(metal, faces, q["gr0"], p["gr0"], p["gr1"], q["gr1"], -rh)
			_quad_facing(metal, none, q["gr0"], p["gr0"], p["gr1"], q["gr1"], rh)
			_quad_facing(metal, faces, q["gl0"], p["gl0"], p["gl1"], q["gl1"], rh)
			_quad_facing(metal, none, q["gl0"], p["gl0"], p["gl1"], q["gl1"], -rh)
			_quad_facing(grass, faces, q["sr0"], p["sr0"], p["er0"], q["er0"], Vector3.UP)
			_quad_facing(grass, none, q["er0"], p["er0"], p["er1"], q["er1"], Vector3.UP + rh)
			_quad_facing(grass, faces, q["sl0"], p["sl0"], p["el0"], q["el0"], Vector3.UP)
			_quad_facing(grass, none, q["el0"], p["el0"], p["el1"], q["el1"], Vector3.UP - rh)
			none.clear()
		prev = p
	concrete.generate_normals()
	concrete.set_material(_concrete_material())
	metal.generate_normals()
	metal.set_material(_metal_material())
	grass.generate_normals()
	grass.set_material(_grass_material())
	var mesh := concrete.commit()
	metal.commit(mesh)
	grass.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.name = "HighwaySides"
	mi.mesh = mesh
	_adopt(mi)
	_collision_body("HighwayBarriers", faces, "rock", 0.55)


## Wiadukt nad autostradą na dystansie `dist`: poziomy pomost 10 m szeroki,
## 6,5 m nad jezdnią, nad obiema jezdniami i nasypami, filary na poboczu,
## w pasie rozdziału i za drugą jezdnią, przyczółki do terenu. Z kolizją.
func _build_overpass(dist: float) -> void:
	if dist > float(_samples[-1]["dist"]) - 10.0:
		return
	var smp := _sample_near(dist)
	var c: Vector3 = smp["pos"]
	var rh := ((smp["right"] as Vector3) * Vector3(1, 0, 1)).normalized()
	var fh := Vector3(-rh.z, 0.0, rh.x) * -1.0           # kierunek jazdy w poziomie
	var hw := float(smp["width"]) * 0.5
	var med := TrackGenerator.HIGHWAY_MEDIAN
	var deck_y := c.y + 6.5
	var x_r := hw + 14.0
	var x_l := -(hw + med + 2.0 * hw + 14.0)
	var mid_x := (x_r + x_l) * 0.5
	var span := x_r - x_l
	var root := Node3D.new()
	root.name = "Overpass"
	_adopt(root)
	var b := Basis(rh, Vector3.UP, -fh)
	var base := Vector3(c.x, 0.0, c.z)
	var shapes := PackedVector3Array()
	var parts := [
		# [środek (x w poprzek, y), rozmiar (w poprzek, w górę, wzdłuż)]
		[Vector2(mid_x, deck_y + 0.6), Vector3(span, 1.2, 10.0)],
		[Vector2(hw + 3.0, deck_y * 0.5), Vector3(1.2, deck_y, 1.2)],
		[Vector2(-(hw + med * 0.5), deck_y * 0.5), Vector3(1.0, deck_y, 1.0)],
		[Vector2(-(hw + med + 2.0 * hw + 3.0), deck_y * 0.5), Vector3(1.2, deck_y, 1.2)],
		[Vector2(x_r - 1.5, deck_y * 0.5), Vector3(3.0, deck_y, 10.0)],
		[Vector2(x_l + 1.5, deck_y * 0.5), Vector3(3.0, deck_y, 10.0)],
	]
	# Jedna siatka (SurfaceTool) i jedno ciało z kształtami - przegląd PR #7
	# (było 6 MeshInstance3D + 6 StaticBody3D na wiadukt).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "OverpassBody"
	body.set_meta("surface", "concrete")
	body.set_meta("grip", 0.6)
	for pt in parts:
		var size: Vector3 = pt[1]
		var at: Vector2 = pt[0]
		var xf := Transform3D(b, base + rh * at.x + Vector3.UP * at.y)
		var bm := BoxMesh.new()
		bm.size = size
		st.append_from(bm, 0, xf)
		var bs := BoxShape3D.new()
		bs.size = size
		var cs := CollisionShape3D.new()
		cs.shape = bs
		cs.transform = xf
		body.add_child(cs)
	st.set_material(_concrete_material())
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	root.add_child(mi)
	root.add_child(body)


func _metal_material() -> Material:
	if not _shared_mats.has("metal"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.72, 0.74, 0.76)
		m.metallic = 0.7
		m.roughness = 0.35
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shared_mats["metal"] = m
	return _shared_mats["metal"]


func _grass_material() -> Material:
	# Autostrada: paleta biomu kawałka (pustynia - piasek, nie trawa).
	var biome := hwy_plan.biome_at(float(_samples[0]["dist"])) if hwy_plan and not _samples.is_empty() else ""
	var key := "grass_" + biome
	if not _shared_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/ground.gdshader")
		if biome != "":
			var pal: Array = HighwayScenery.BIOME_GROUND.get(biome, HighwayScenery.BIOME_GROUND["meadow"])
			m.set_shader_parameter("grass_a", pal[0])
			m.set_shader_parameter("grass_b", pal[1])
			m.set_shader_parameter("dirt", pal[2])
		_shared_mats[key] = m
	return _shared_mats[key]
