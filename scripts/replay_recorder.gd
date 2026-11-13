class_name ReplayRecorder
extends RefCounted

## Zapis ostatnich sekund jazdy do powtórki wypadku (użytkownik 2026-11-12:
## "jeśli gracz zginął w wypadku, to robimy powtórzone ujęcie ... gracz jest
## obserwatorem podążającym za samochodem, trochę z góry"; specyfikacja
## inbox powtorka-wypadku). Czysta logika, bez sceny: bufory kołowe
## przydzielone raz (bez alokacji w trakcie jazdy), interpolacja, przesunięcie
## świata, kluczowa chwila i mapa tempa (zwolnienie wokół uderzenia).
## Test: tests/replay_recorder_test.gd.

const WINDOW := 6.0                    # [s] długość powtórki
const RATE := 60.0                     # [Hz] auto gracza
const OTHER_RATE := 30.0               # [Hz] boty i auta z naprzeciwka
const MAX_OTHERS := 8
## Klatka gracza: pozycja 3, kwaternion 4, koła 4x3 (skręt, obrót, sprężyna),
## kierownica [°] 1, gaz 1, hamulec 1, kontrolery L i P w układzie auta
## 2x7 (pozycja 3 + kwaternion 4), obroty 1, gaz silnika 1, impuls uderzenia
## 1, koła na ziemi 1.
const P_STRIDE := 40
const I_WHEELS := 7
const I_WHEEL_DEG := 19
const I_THROTTLE := 20
const I_BRAKE := 21
const I_CTRL_L := 22
const I_CTRL_R := 29
const I_RPM := 36
const I_GAS := 37
const I_HIT := 38
const I_GROUND := 39
const O_STRIDE := 8                    # inne auto: pozycja 3, kwaternion 4, skręt 1
## Tempo odtwarzania wokół kluczowej chwili.
const SLOW := 0.35
const SLOW_BEFORE := 0.5
const SLOW_AFTER := 1.0
const RAMP := 0.2
const HIT_MIN := 2000.0                # [N·s] uderzenie, które jest "kluczowe"

var _pcap := int(WINDOW * RATE) + 2
var _ocap := int(WINDOW * OTHER_RATE) + 2
var _p := PackedFloat32Array()
var _pt := PackedFloat64Array()
var _pn := 0                           # ile próbek gracza (<= _pcap)
var _pi := 0                           # następny indeks zapisu
var _o := PackedFloat32Array()
var _oid := PackedInt64Array()
var _ot := PackedFloat64Array()
var _on := 0
var _oi := 0


func _init() -> void:
	_p.resize(_pcap * P_STRIDE)
	_pt.resize(_pcap)
	_o.resize(_ocap * MAX_OTHERS * O_STRIDE)
	_oid.resize(_ocap * MAX_OTHERS)
	_ot.resize(_ocap)
	reset()


func reset() -> void:
	_pn = 0
	_pi = 0
	_on = 0
	_oi = 0


func count() -> int:
	return _pn


## Zapis klatki gracza; co 1/RATE s (częstsze wywołania pomijane - wtedy
## false; impuls uderzenia z pominiętych kroków trzeba zebrać po stronie
## wołającego, bo pojedynczy krok z uderzeniem by przepadł).
func push(t: float, frame: PackedFloat32Array) -> bool:
	if _pn > 0 and t - _pt[_last(_pi, _pcap)] < 1.0 / RATE - 1e-4:
		return false
	var base := _pi * P_STRIDE
	for k in range(P_STRIDE):
		_p[base + k] = frame[k] if k < frame.size() else 0.0
	_pt[_pi] = t
	_pi = (_pi + 1) % _pcap
	_pn = mini(_pn + 1, _pcap)
	return true


## Zapis innych aut: ids (do MAX_OTHERS), poses po O_STRIDE liczb.
func push_others(t: float, ids: PackedInt64Array, poses: PackedFloat32Array) -> void:
	if _on > 0 and t - _ot[_last(_oi, _ocap)] < 1.0 / OTHER_RATE - 1e-4:
		return
	var n := mini(ids.size(), MAX_OTHERS)
	for s in range(MAX_OTHERS):
		_oid[_oi * MAX_OTHERS + s] = ids[s] if s < n else 0
		var b := (_oi * MAX_OTHERS + s) * O_STRIDE
		for k in range(O_STRIDE):
			_o[b + k] = poses[s * O_STRIDE + k] if s < n else 0.0
	_ot[_oi] = t
	_oi = (_oi + 1) % _ocap
	_on = mini(_on + 1, _ocap)


## Przesunięcie świata (WorldOrigin.apply): pozycje zapisane w starym układzie.
func shift(v: Vector3) -> void:
	for i in range(_pcap):
		var b := i * P_STRIDE
		_p[b] -= v.x
		_p[b + 1] -= v.y
		_p[b + 2] -= v.z
	for i in range(_ocap * MAX_OTHERS):
		var b := i * O_STRIDE
		_o[b] -= v.x
		_o[b + 1] -= v.y
		_o[b + 2] -= v.z


func t_start() -> float:
	return _pt[_first(_pi, _pn, _pcap)] if _pn > 0 else 0.0


func t_end() -> float:
	return _pt[_last(_pi, _pcap)] if _pn > 0 else 0.0


## Klatka gracza w chwili t (interpolacja; kwaterniony slerp).
func player_at(t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(P_STRIDE)
	if _pn == 0:
		return out
	var ab := _bracket(_pt, _pi, _pn, _pcap, t)
	var a: int = ab[0]
	var b: int = ab[1]
	var w: float = ab[2]
	for k in range(P_STRIDE):
		out[k] = lerpf(_p[a * P_STRIDE + k], _p[b * P_STRIDE + k], w)
	# Obrót kół zawinięty do [-π, π] - lerpf przez ±π cofałby koło o prawie
	# pełny obrót (przegląd PR #84).
	for i in range(4):
		var k := I_WHEELS + i * 3 + 1
		out[k] = lerp_angle(_p[a * P_STRIDE + k], _p[b * P_STRIDE + k], w)
	for qi in [3, I_CTRL_L + 3, I_CTRL_R + 3]:
		var q := _quat(_p, a * P_STRIDE + qi).slerp(_quat(_p, b * P_STRIDE + qi), w)
		out[qi] = q.x
		out[qi + 1] = q.y
		out[qi + 2] = q.z
		out[qi + 3] = q.w
	# Impuls i koła na ziemi - bez mieszania (zdarzenia).
	out[I_HIT] = _p[(a if w < 0.5 else b) * P_STRIDE + I_HIT]
	out[I_GROUND] = _p[(a if w < 0.5 else b) * P_STRIDE + I_GROUND]
	return out


## Inne auta w chwili t: id -> [Transform3D, skręt]. Auto obecne tylko
## w jednej z dwóch próbek - z tej najbliższej.
func others_at(t: float) -> Dictionary:
	var out := {}
	if _on == 0:
		return out
	var ab := _bracket(_ot, _oi, _on, _ocap, t)
	var a: int = ab[0]
	var b: int = ab[1]
	var w: float = ab[2]
	var in_b := {}
	for s in range(MAX_OTHERS):
		var id := _oid[b * MAX_OTHERS + s]
		if id != 0:
			in_b[id] = s
	for s in range(MAX_OTHERS):
		var id := _oid[a * MAX_OTHERS + s]
		if id == 0:
			continue
		var ba := (a * MAX_OTHERS + s) * O_STRIDE
		if in_b.has(id):
			var bb := (b * MAX_OTHERS + int(in_b[id])) * O_STRIDE
			var p := Vector3(_o[ba], _o[ba + 1], _o[ba + 2]).lerp(Vector3(_o[bb], _o[bb + 1], _o[bb + 2]), w)
			var q := _quat(_o, ba + 3).slerp(_quat(_o, bb + 3), w)
			out[id] = [Transform3D(Basis(q), p), lerpf(_o[ba + 7], _o[bb + 7], w)]
		elif w < 0.5:
			out[id] = [Transform3D(Basis(_quat(_o, ba + 3)), Vector3(_o[ba], _o[ba + 1], _o[ba + 2])), _o[ba + 7]]
	return out


## Kluczowa chwila: najmocniejsze uderzenie (> HIT_MIN), a bez niego ostatnie
## oderwanie wszystkich kół; bez obu - sekunda przed końcem.
func key_time() -> float:
	if _pn == 0:
		return 0.0
	var best_j := HIT_MIN
	var best_t := -1.0
	var lift_t := -1.0
	var prev_ground := -1.0
	for n in range(_pn):
		var i := (_first(_pi, _pn, _pcap) + n) % _pcap
		var j := _p[i * P_STRIDE + I_HIT]
		if j > best_j:
			best_j = j
			best_t = _pt[i]
		var g := _p[i * P_STRIDE + I_GROUND]
		if prev_ground > 0.0 and g <= 0.0:
			lift_t = _pt[i]
		prev_ground = g
	if best_t >= 0.0:
		return best_t
	if lift_t >= 0.0:
		return lift_t
	return maxf(t_end() - 1.0, t_start())


## Prędkość odtwarzania w chwili zapisu `rt` (1 / SLOW wokół kluczowej,
## płynne przejścia RAMP).
static func speed_at(rt: float, key: float) -> float:
	var a := key - SLOW_BEFORE
	var b := key + SLOW_AFTER
	if rt < a - RAMP or rt > b + RAMP:
		return 1.0
	if rt < a:
		return lerpf(1.0, SLOW, (rt - (a - RAMP)) / RAMP)
	if rt > b:
		return lerpf(SLOW, 1.0, (rt - b) / RAMP)
	return SLOW


## Krok czasu zapisu dla kroku czasu powtórki dt (mapa tempa: ciągła,
## monotoniczna).
static func advance(rt: float, dt: float, key: float) -> float:
	return rt + dt * speed_at(rt, key)


# --------------------------------------------------------------------------

static func _last(next_i: int, cap: int) -> int:
	return (next_i - 1 + cap) % cap


static func _first(next_i: int, n: int, cap: int) -> int:
	return (next_i - n + cap) % cap


static func _quat(arr: PackedFloat32Array, i: int) -> Quaternion:
	return Quaternion(arr[i], arr[i + 1], arr[i + 2], arr[i + 3]).normalized()


## Dwie sąsiednie próbki wokół t (indeksy w buforze) i waga.
static func _bracket(times: PackedFloat64Array, next_i: int, n: int, cap: int, t: float) -> Array:
	var f := _first(next_i, n, cap)
	if n == 1 or t <= times[f]:
		return [f, f, 0.0]
	var l := _last(next_i, cap)
	if t >= times[l]:
		return [l, l, 0.0]
	# Wyszukiwanie binarne po kolejności zapisu.
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if times[(f + mid) % cap] <= t:
			lo = mid
		else:
			hi = mid
	var a := (f + lo) % cap
	var b := (f + hi) % cap
	var span := times[b] - times[a]
	return [a, b, 0.0 if span <= 0.0 else (t - times[a]) / span]
