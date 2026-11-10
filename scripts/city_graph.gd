extends RefCounted
class_name CityGraph

## Miasto jako leniwy, niejawny graf ulic (pomysł użytkownika 2026-11-09:
## "skrzyżowania, w które można skręcić, i one wtedy wiodą prosto i też mają
## skrzyżowania, gdzie droga tworzona jest tam, gdzie gracz jedzie").
## Specyfikacja: docs/agent/inbox/2026-11-09-pozostalosci-estakad.md
## (dopisek, pkt 2) i docs/agent/inbox/2026-11-10-miasta-leniwy-graf.md.
##
## Czysta logika, bez węzłów sceny i bez fizyki. Współrzędne 2D w układzie
## miasta (x, y) = (x, z) świata; obrót, położenie i wysokość (ground_y)
## nakłada ten, kto buduje geometrię.
##
## GRAF NIEJAWNY - nic nie jest zapisywane. Ulice to funkcja ziarna
## i komórki siatki:
##   - węzeł (i, j) leży w punkcie siatki CELL z przesunięciem z hasha
##     węzła (JITTER) - miasto nie wygląda jak kratka z linijki;
##   - "aleje" co AVENUE kolumn i wierszy (oraz obwodnica na brzegu
##     `bounds`) są ciągłe - to szkielet, który łączy całe miasto;
##   - ulice między alejami istnieją albo nie CAŁYM odcinkiem od alei do
##     alei (hash odcinka) - dzięki temu nie ma ślepych zaułków: każdy
##     węzeł ma co najmniej 2 wyloty;
##   - kształt krawędzi (łuk) z hasha PARY węzłów posortowanej, więc ulica
##     wygląda tak samo z obu stron i przy każdym powrocie.
##
## LENIWA BUDOWA (stan tylko tutaj, w obiekcie): gracz jedzie krawędzią
## `current` od węzła A do B. Zbudowane są: bieżąca krawędź w całości,
## KEEP_BEHIND poprzednich w całości, a przy węzłach A i B wszystkie inne
## wyloty jako krótkie zalążki (STUB_LEN m - widać, że można skręcić).
## Gdy auto wjedzie w zalążek, ten staje się bieżącą krawędzią i buduje się
## w całości, a przy jego końcu pojawiają się nowe zalążki. To, co wypadło
## z zestawu, idzie do usunięcia. update() zwraca różnicę (co dobudować,
## co usunąć) - geometrię robi wywołujący.

const CELL := 80.0               # odstęp węzłów siatki [m]
const JITTER := 9.0              # przesunięcie węzła z hasha [m] (±)
const BEND := 5.0                # wygięcie środka krawędzi w bok [m] (±)
const AVENUE := 4                # aleja co tyle kolumn / wierszy
const P_STREET := 0.55           # szansa, że odcinek ulicy między alejami istnieje
const W_AVENUE := 14.0           # szerokość jezdni alei [m]
const W_STREET := 9.0            # szerokość jezdni ulicy [m]
const STUB_LEN := 25.0           # długość zalążka wylotu [m]
const KEEP_BEHIND := 2           # ile przejechanych krawędzi zostaje za autem
const STEP := 4.0                # krok próbkowania krawędzi [m]

var seed_value := 0
## Obszar miasta w komórkach (węzły od position do end włącznie). Brzeg to
## obwodnica (zawsze aleja). Rozmiar 0 = miasto bez końca, bez obwodnicy.
var bounds := Rect2i()

## Stan leniwej budowy.
var current_a := Vector2i.ZERO
var current_b := Vector2i.ZERO
var odometer := 0.0                       # przejechana droga [m]
var _history: Array[Vector2i] = []        # pary (a, b) poprzednich krawędzi, płasko
var _built := {}                          # klucz -> {a, b, len (pełna = -1)}
var _last_pos := Vector2.INF
var _cur_s := 0.0                         # dystans wzdłuż bieżącej krawędzi (od a)
var _back := 0.0                          # ile metrów z rzędu auto jedzie wstecz
## Ile metrów jazdy wstecz po tej samej krawędzi oznacza zawrócenie.
const TURN_BACK := 3.0


func _init(p_seed := 0, p_bounds := Rect2i()) -> void:
	seed_value = p_seed
	bounds = p_bounds


# --------------------------------------------------------------------------
# Hash (całkowity, 32 bity, ten sam w tools/city_graph_sim.py)
# --------------------------------------------------------------------------

static func _mix(h: int, v: int) -> int:
	h = (h ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFFFFFF


## Liczba 0..1 z ziarna i kilku liczb całkowitych.
func _h01(vals: Array) -> float:
	var h := _mix(0x9E3779B9, seed_value)
	for v in vals:
		h = _mix(h, int(v))
	return float(h) / 4294967296.0


# --------------------------------------------------------------------------
# Graf
# --------------------------------------------------------------------------

func _bounded() -> bool:
	return bounds.size.x > 0 and bounds.size.y > 0


## Węzeł w obszarze miasta (brzeg włącznie).
func in_bounds(c: Vector2i) -> bool:
	if not _bounded():
		return true
	return c.x >= bounds.position.x and c.x <= bounds.end.x \
			and c.y >= bounds.position.y and c.y <= bounds.end.y


## Kolumna `i` to aleja (pionowa): co AVENUE albo brzeg (obwodnica).
func is_avenue_col(i: int) -> bool:
	if posmod(i, AVENUE) == 0:
		return true
	return _bounded() and (i == bounds.position.x or i == bounds.end.x)


func is_avenue_row(j: int) -> bool:
	if posmod(j, AVENUE) == 0:
		return true
	return _bounded() and (j == bounds.position.y or j == bounds.end.y)


## Czy jest krawędź między sąsiednimi (4-sąsiedztwo) węzłami a i b.
func has_edge(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if absi(d.x) + absi(d.y) != 1:
		return false
	if not (in_bounds(a) and in_bounds(b)):
		return false
	if d.y == 0:
		# Pozioma, w wierszu a.y, między kolumnami min(a.x, b.x) i +1.
		var j := a.y
		if is_avenue_row(j):
			return true
		var i := mini(a.x, b.x)
		# Odcinek od alei do alei: początek = najbliższa aleja <= i (stały
		# klucz hasha dla całego odcinka).
		return _h01([1, j, i - posmod(i, AVENUE)]) < P_STREET
	var col := a.x
	if is_avenue_col(col):
		return true
	var jj := mini(a.y, b.y)
	return _h01([2, col, jj - posmod(jj, AVENUE)]) < P_STREET


const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


## Sąsiedzi połączeni ulicą (kolejność stała: +x, +y, -x, -y).
func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		if has_edge(c, c + d):
			out.append(c + d)
	return out


## Węzeł istnieje, jeśli wychodzi z niego jakakolwiek ulica.
func is_node(c: Vector2i) -> bool:
	return not neighbors(c).is_empty()


## Położenie węzła w układzie miasta [m].
func node_pos(c: Vector2i) -> Vector2:
	var jx := (_h01([3, c.x, c.y]) * 2.0 - 1.0) * JITTER
	var jy := (_h01([4, c.x, c.y]) * 2.0 - 1.0) * JITTER
	return Vector2(c.x * CELL + jx, c.y * CELL + jy)


## Krawędź jest aleją, gdy leży na linii alei.
func is_avenue(a: Vector2i, b: Vector2i) -> bool:
	return is_avenue_row(a.y) if a.y == b.y else is_avenue_col(a.x)


func edge_width(a: Vector2i, b: Vector2i) -> float:
	return W_AVENUE if is_avenue(a, b) else W_STREET


## Klucz krawędzi niezależny od kierunku.
static func edge_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a
	var hi := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		lo = b
		hi = a
	return "%d,%d|%d,%d" % [lo.x, lo.y, hi.x, hi.y]


## Punkty osi krawędzi od a do b co ~STEP m (krzywa Béziera 2. stopnia:
## środek wygięty w bok o hash PARY węzłów - ten sam łuk z obu stron).
## `max_len` > 0 - tylko pierwsze max_len metrów (zalążek).
func edge_points(a: Vector2i, b: Vector2i, max_len := -1.0) -> PackedVector2Array:
	var lo := a
	var hi := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		lo = b
		hi = a
	var p0 := node_pos(lo)
	var p2 := node_pos(hi)
	var side := (p2 - p0).orthogonal().normalized()
	var bend := (_h01([5, lo.x, lo.y, hi.x, hi.y]) * 2.0 - 1.0) * BEND
	var p1 := (p0 + p2) * 0.5 + side * bend
	var n := maxi(2, int(ceil(p0.distance_to(p2) / STEP)))
	var pts := PackedVector2Array()
	for k in range(n + 1):
		var t := float(k) / float(n)
		pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	if lo != a:
		pts.reverse()
	if max_len > 0.0:
		pts = _cut(pts, max_len)
	return pts


static func _cut(pts: PackedVector2Array, max_len: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var acc := 0.0
	for k in range(1, pts.size()):
		var seg := pts[k - 1].distance_to(pts[k])
		if acc + seg >= max_len:
			out.append(pts[k - 1].lerp(pts[k], (max_len - acc) / maxf(seg, 0.0001)))
			return out
		acc += seg
		out.append(pts[k])
	return out


static func polyline_length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for k in range(1, pts.size()):
		l += pts[k - 1].distance_to(pts[k])
	return l


## Odległość punktu od łamanej i dystans wzdłuż niej do rzutu: Vector2(d, s).
static func project(pts: PackedVector2Array, p: Vector2) -> Vector2:
	var best := INF
	var best_s := 0.0
	var acc := 0.0
	for k in range(1, pts.size()):
		var a := pts[k - 1]
		var ab := pts[k] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-9 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			best_s = acc + sqrt(l2) * t
		acc += sqrt(l2)
	return Vector2(best, best_s)


# --------------------------------------------------------------------------
# Leniwa budowa
# --------------------------------------------------------------------------

## Start na krawędzi a -> b (np. wjazd do miasta). Zwraca różnicę jak update.
func start(a: Vector2i, b: Vector2i) -> Dictionary:
	assert(has_edge(a, b), "CityGraph.start: brak ulicy %s-%s" % [a, b])
	current_a = a
	current_b = b
	_history.clear()
	_last_pos = Vector2.INF
	_cur_s = 0.0
	_back = 0.0
	return _sync()


## Zestaw krawędzi, które powinny być zbudowane: klucz -> {a, b, len}.
## len = -1 - cała krawędź, > 0 - zalążek od a.
func wanted() -> Dictionary:
	var w := {}
	for k in range(0, _history.size(), 2):
		w[edge_key(_history[k], _history[k + 1])] = {"a": _history[k], "b": _history[k + 1], "len": -1.0}
	w[edge_key(current_a, current_b)] = {"a": current_a, "b": current_b, "len": -1.0}
	for end in [current_b, current_a]:
		for n in neighbors(end):
			var key := edge_key(end, n)
			if not w.has(key):
				w[key] = {"a": end, "b": n, "len": STUB_LEN}
	return w


## Wołane z położeniem auta w układzie miasta (np. 5-10 razy na sekundę).
## Zwraca {"add": [{key, a, b, len}], "remove": [key], "switched": bool}
## (switched: skręt w inną ulicę albo zawrócenie na tej samej).
## Zalążek, który staje się pełną krawędzią, jest w "remove" i w "add".
func update(pos: Vector2) -> Dictionary:
	if _last_pos != Vector2.INF:
		odometer += _last_pos.distance_to(pos)
	_last_pos = pos
	# Najbliższa zbudowana krawędź; przy remisie zostaje bieżąca.
	var cur_key := edge_key(current_a, current_b)
	var best_key := cur_key
	var cur_pts := edge_points(current_a, current_b)
	var cur_proj := project(cur_pts, pos)
	var best_d := cur_proj.x
	for key in _built:
		if key == cur_key:
			continue
		var e: Dictionary = _built[key]
		var d := project(edge_points(e["a"], e["b"], e["len"]), pos).x
		# Zapas 0,5 m: na skrzyżowaniu obie krawędzie są równie blisko.
		if d < best_d - 0.5:
			best_d = d
			best_key = key
	var switched := false
	if best_key != cur_key:
		var e: Dictionary = _built[best_key]
		var ea: Vector2i = e["a"]
		var eb: Vector2i = e["b"]
		# Nowa bieżąca krawędź wychodzi ze wspólnego węzła z poprzednią
		# (skręt na skrzyżowaniu przed autem albo zawrócenie za nim).
		var from := ea
		if eb == current_a or eb == current_b:
			from = eb
		var to := eb if from == ea else ea
		_history.append(current_a)
		_history.append(current_b)
		while _history.size() > KEEP_BEHIND * 2:
			_history.remove_at(0)
			_history.remove_at(0)
		# Krawędź, na którą wracamy, nie jest już "za autem".
		for k in range(_history.size() - 2, -1, -2):
			if edge_key(_history[k], _history[k + 1]) == best_key:
				_history.remove_at(k)
				_history.remove_at(k)
		current_a = from
		current_b = to
		switched = true
		_cur_s = project(edge_points(current_a, current_b), pos).y
		_back = 0.0
	else:
		# Zawrócenie na tej samej ulicy (zgłoszenie agenta lokalnego
		# 2026-11-10): auto jedzie wstecz dłużej niż TURN_BACK - kierunek
		# bieżącej krawędzi się odwraca (current_a = węzeł, od którego teraz
		# odjeżdża).
		var ds := cur_proj.y - _cur_s
		_back = _back - ds if ds < 0.0 else 0.0
		_cur_s = cur_proj.y
		if _back > TURN_BACK:
			var t := current_a
			current_a = current_b
			current_b = t
			_cur_s = polyline_length(cur_pts) - _cur_s
			_back = 0.0
			switched = true
	var diff := _sync()
	diff["switched"] = switched
	return diff


func _sync() -> Dictionary:
	var w := wanted()
	var add := []
	var remove := []
	for key in _built:
		if not w.has(key) or not is_equal_approx(float(w[key]["len"]), float(_built[key]["len"])):
			remove.append(key)
	for key in remove:
		_built.erase(key)
	for key in w:
		if not _built.has(key):
			var e: Dictionary = w[key]
			_built[key] = e
			add.append({"key": key, "a": e["a"], "b": e["b"], "len": e["len"]})
	return {"add": add, "remove": remove, "switched": false}


## Zbudowane krawędzie (klucz -> {a, b, len}) - do testów i mapki.
func built() -> Dictionary:
	return _built
