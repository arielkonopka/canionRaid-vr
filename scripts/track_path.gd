extends RefCounted
class_name TrackPath

## Jeden ciągły kawałek drogi (bez rozgałęzień) w tablicach Packed* zamiast
## tablicy słowników - plan wydajności, punkt C3 (`docs/PERF_PLAN.md`).
##
## Dziś próbka toru to `Dictionary` z ~16 kluczami tekstowymi i każde
## zapytanie (boty, HUD, dźwig, auta z naprzeciwka) szuka po kluczach albo
## kopiuje wycinek tablicy. Tu te same dane leżą w ciągłych tablicach,
## a zapytania działają po indeksie próbki:
##   var i := path.index_at(d)        # binarnie, O(log n)
##   path.pos[i], path.width[i], path.is_gap(i) ...
## Przerwy są listą przedziałów, więc `is_gap_at` / `last_gap_end_before`
## nie przeglądają wszystkich próbek.
##
## Profil prędkości (punkt C4): bezpieczna prędkość na łukach i przepisowa
## liczona RAZ dla całej ścieżki - BotDriver zamiast przeglądać okno ~195
## próbek co krok fizyki czyta jedną liczbę (`speed_at`).
##
## Moduł jest odizolowany: nic go jeszcze nie używa. `from_samples` buduje
## go z dzisiejszych próbek (`StuntTrack._samples`), więc da się go wpiąć
## stopniowo i porównać wyniki (`tests/track_path_test.gd`). Docelowo to
## element grafu sekcji z rozwidleniami (plan, sekcja 6).
##
## Współrzędne jak w próbkach: w układzie węzła kawałka toru (lokalne).

const FLAG_GAP := 1
const FLAG_ROOF := 2
const FLAG_FINISH := 4

## Kolejność jak w StuntTrack.SURFACES - indeks w `surface`.
const SURFACE_NAMES := ["dry", "wet", "ice"]

var pos := PackedVector3Array()
var fwd := PackedVector3Array()
var right := PackedVector3Array()
var up := PackedVector3Array()
var dist := PackedFloat64Array()
var width := PackedFloat32Array()
var limit := PackedFloat32Array()        # km/h
var grip := PackedFloat32Array()         # mnożnik tarcia nawierzchni
var surface := PackedByteArray()         # indeks w SURFACE_NAMES
var rain := PackedByteArray()
var flags := PackedByteArray()
## Metadane tylko tam, gdzie są (pierwsza próbka odcinka): indeks -> Dictionary.
var meta := {}
## Przerwy: pary [początek, koniec) - dystans pierwszej próbki przerwy
## i pierwszej próbki z jezdnią za nią (koniec = INF, gdy przerwa sięga
## końca ścieżki).
var gaps := PackedFloat64Array()


# --------------------------------------------------------------------------
# Budowa
# --------------------------------------------------------------------------

## Z tablicy próbek StuntTrack.sample_segments (klucze: pos, fwd, right, up,
## width, gap, finish, surface, rain, roof, dist, meta, limit).
static func from_samples(samples: Array) -> TrackPath:
	var p := TrackPath.new()
	var n := samples.size()
	p.pos.resize(n)
	p.fwd.resize(n)
	p.right.resize(n)
	p.up.resize(n)
	p.dist.resize(n)
	p.width.resize(n)
	p.limit.resize(n)
	p.grip.resize(n)
	p.surface.resize(n)
	p.rain.resize(n)
	p.flags.resize(n)
	var gap_start := -1.0
	for i in range(n):
		var s: Dictionary = samples[i]
		p.pos[i] = s["pos"]
		p.fwd[i] = s["fwd"]
		p.right[i] = s["right"]
		p.up[i] = s["up"]
		p.dist[i] = float(s["dist"])
		p.width[i] = float(s["width"])
		p.limit[i] = float(s.get("limit", 100.0))
		var sname: String = s.get("surface", "dry")
		var sid := SURFACE_NAMES.find(sname)
		p.surface[i] = maxi(sid, 0)
		p.grip[i] = float(StuntTrack.SURFACES.get(sname, StuntTrack.SURFACES["dry"])["grip"])
		p.rain[i] = int(s.get("rain", 0))
		var f := 0
		if s.get("gap", false):
			f |= FLAG_GAP
		if s.get("roof", false):
			f |= FLAG_ROOF
		if s.get("finish", false):
			f |= FLAG_FINISH
		p.flags[i] = f
		var m: Dictionary = s.get("meta", {})
		if not m.is_empty():
			p.meta[i] = m
		# Przedziały przerw.
		var g := (f & FLAG_GAP) != 0
		if g and gap_start < 0.0:
			gap_start = p.dist[i]
		elif not g and gap_start >= 0.0:
			p.gaps.append(gap_start)
			p.gaps.append(p.dist[i])
			gap_start = -1.0
	if gap_start >= 0.0:
		p.gaps.append(gap_start)
		p.gaps.append(INF)
	return p


func size() -> int:
	return dist.size()


# --------------------------------------------------------------------------
# Wyszukiwanie
# --------------------------------------------------------------------------

## Indeks ostatniej próbki o dystansie <= d (0, gdy d przed początkiem).
func index_at(d: float) -> int:
	if dist.is_empty():
		return -1
	return clampi(dist.bsearch(d, false) - 1, 0, dist.size() - 1)


## Indeks pierwszej próbki o dystansie >= d (jak StuntTrack._sample_near).
func index_from(d: float) -> int:
	if dist.is_empty():
		return -1
	return mini(dist.bsearch(d, true), dist.size() - 1)


## Najbliższa próbka pozycji `local` (układ kawałka), szukana w oknie
## ±window wokół `hint` (np. indeks z poprzedniego zapytania). Gdy wynik
## wypadnie na brzegu okna - całość, jak StuntTrack.nearest_sample.
func nearest_index(local: Vector3, hint := 0, window := 40) -> int:
	var n := pos.size()
	if n == 0:
		return -1
	var lo := maxi(hint - window, 0)
	var hi := mini(hint + window, n - 1)
	var bi := _nearest_in(local, lo, hi)
	if (bi == lo and lo > 0) or (bi == hi and hi < n - 1):
		bi = _nearest_in(local, 0, n - 1)
	return bi


func _nearest_in(local: Vector3, lo: int, hi: int) -> int:
	var bi := lo
	var best_d := INF
	for i in range(lo, hi + 1):
		var d := local.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			bi = i
	return bi


## Najbliższa próbka, gdy znamy przybliżony indeks i ruch jest powolny
## (bot przesuwa się o < 1 próbkę na krok fizyki): idzie od `hint` w stronę
## malejącej odległości. Dużo taniej niż przeglądanie okna.
func track_index(local: Vector3, hint: int) -> int:
	var n := pos.size()
	if n == 0:
		return -1
	var i := clampi(hint, 0, n - 1)
	var d := local.distance_squared_to(pos[i])
	while i + 1 < n:
		var dn := local.distance_squared_to(pos[i + 1])
		if dn >= d:
			break
		d = dn
		i += 1
	while i > 0:
		var dp := local.distance_squared_to(pos[i - 1])
		if dp >= d:
			break
		d = dp
		i -= 1
	return i


func is_gap(i: int) -> bool:
	return (flags[i] & FLAG_GAP) != 0


func has_roof(i: int) -> bool:
	return (flags[i] & FLAG_ROOF) != 0


func surface_name(i: int) -> String:
	return SURFACE_NAMES[surface[i]]


## Czy `d` leży w przerwie - jak StuntTrack.is_gap_at (pierwsza próbka
## o dystansie >= d; za końcem ścieżki false).
func is_gap_at(d: float) -> bool:
	if dist.is_empty() or d > dist[dist.size() - 1]:
		return false
	return is_gap(dist.bsearch(d, true))


## Koniec ostatniej przerwy, która kończy się nie dalej niż `d` (-INF: brak)
## - jak StuntTrack.last_gap_end_before.
func last_gap_end_before(d: float) -> float:
	var end := -INF
	for k in range(0, gaps.size(), 2):
		var e := gaps[k + 1]
		if e <= d:
			end = e
		else:
			break
	return end


## Układ na osi drogi w `d` (lokalnie): ostatnia próbka nie dalej niż `d`,
## która nie jest przerwą - jak StuntTrack.transform_at_distance (bez
## global_transform węzła).
func transform_at_distance(d: float) -> Transform3D:
	var i := index_at(d)
	if i < 0:
		return Transform3D.IDENTITY
	while i > 0 and is_gap(i):
		i -= 1
	return transform_at(i)


func transform_at(i: int) -> Transform3D:
	return Transform3D(Basis(right[i], up[i], -fwd[i]), pos[i])


## Przesunięcie w poprzek (dodatnie w prawo) pozycji `local` względem próbki i.
func lateral(local: Vector3, i: int) -> float:
	return (local - pos[i]).dot(right[i])


# --------------------------------------------------------------------------
# Profil prędkości
# --------------------------------------------------------------------------

## Bezpieczna prędkość [m/s] w każdej próbce, z wyprzedzeniem: łuki
## (przyczepność `lat_factor`·grip·g) i - opcjonalnie - ograniczenia
## prędkości, a przed nimi droga hamowania z opóźnieniem `brake` [m/s²].
##
## Łuk jak w BotDriver: kąt między poziomymi kierunkami próbek i oraz
## i+span_n, promień ~ długość/kąt, v = sqrt(f·grip·g·długość/kąt).
## Wyprzedzenie: przejście od końca, v[i] = min(v[i], sqrt(v[i+1]² +
## 2·brake·ds)). To dokładnie min po j >= i z sqrt(c_j² + 2·brake·(d_j - d_i)),
## czyli to, co BotDriver liczy pętlą po oknie - tylko raz, nie co krok.
## Różnice: tu każda próbka (BotDriver co 4.) i cała ścieżka (BotDriver
## widzi 180 m) - profil bywa minimalnie ostrożniejszy, nigdy szybszy.
##
## `end_speed` [m/s] - prędkość wymagana na końcu ścieżki (z początku
## następnej; INF = bez ograniczenia). `cap` [m/s] - górna granica.
##
## Dla BotDriver: spokój `speed_profile(0.6, 5.0, true, 200/3.6)`,
## szał (łuki) `speed_profile(0.8, 6.0, false, 400/3.6)`.
func speed_profile(lat_factor: float, brake: float, with_limits: bool, cap: float,
		end_speed := INF, span_n := 12) -> PackedFloat32Array:
	var n := dist.size()
	var v := PackedFloat32Array()
	v.resize(n)
	for i in range(n):
		var c := cap
		if with_limits:
			c = minf(c, limit[i] / 3.6)
		if i + span_n < n:
			var f0 := fwd[i] * Vector3(1, 0, 1)
			var f1 := fwd[i + span_n] * Vector3(1, 0, 1)
			var ang := f0.angle_to(f1)
			if ang > 0.01:
				var span := dist[i + span_n] - dist[i]
				c = minf(c, sqrt(lat_factor * grip[i] * 9.8 * span / ang))
		v[i] = c
	if n > 0:
		v[n - 1] = minf(v[n - 1], end_speed)
	apply_braking(v, brake)
	return v


## Przejście wstecz z drogą hamowania - także po zmianie końca profilu
## (np. dobudowany następny kawałek: `v[n-1] = min(v[n-1], jego v[0])`).
func apply_braking(v: PackedFloat32Array, brake: float) -> void:
	for i in range(v.size() - 2, -1, -1):
		var ds := dist[i + 1] - dist[i]
		v[i] = minf(v[i], sqrt(v[i + 1] * v[i + 1] + 2.0 * brake * ds))


## Prędkość z profilu w dowolnym `d` [m/s]: dokładnie z następnej próbki
## i drogi hamowania do niej (bez schodków co 1 m).
func speed_at(v: PackedFloat32Array, d: float, brake: float) -> float:
	var n := v.size()
	if n == 0:
		return INF
	var i := index_at(d)
	if i + 1 >= n:
		return v[n - 1]
	var ds := maxf(dist[i + 1] - d, 0.0)
	return minf(v[i], sqrt(v[i + 1] * v[i + 1] + 2.0 * brake * ds))
