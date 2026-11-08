extends Node3D
class_name EndlessTrack

## Trasa bez końca: kolejne sekcje z TrackGenerator, każda jako osobny
## StuntTrack (kawałek), połączone bez szwu przez StuntTrack.start_state.
##
## Kawałki są dobudowywane przed autem i usuwane za nim: zawsze jest
## AHEAD sekcji przed bieżącą i KEEP_BEHIND za nią (dźwig cofa najwyżej
## do punktu kontrolnego bieżącej sekcji, więc dalej wstecz nie trzeba).
##
## API takie samo jak StuntTrack (nearest_sample, lateral_offset,
## transform_at_distance, last_gap_end_before, is_gap_at, finish_distance,
## total_length), więc scena jazdy nie musi wiedzieć, którą trasą jedzie.
## Dystans jest ciągły od startu przez wszystkie kawałki.

const AHEAD := 2
const KEEP_BEHIND := 1

## Ziarno losowania. 0 = losowe przy starcie.
@export var seed_value: int = 0
@export var road_material: Material
@export var pillar_material: Material
@export var start_height: float = 40.0
## Wąwóz z łupku zamiast toru na filarach (bez przerw, ściany z kolizją).
@export var canyon: bool = true

var rng := RandomNumberGenerator.new()
var _chunks: Array[StuntTrack] = []
var _sections := 0                 # ile sekcji wygenerowano
var _current := 0                  # indeks kawałka z autem w _chunks
var _checkpoints: Array[float] = []    # dystans bram punktów kontrolnych


func _ready() -> void:
	rng.seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec())
	for i in range(1 + AHEAD):
		_add_section()


func _add_section() -> void:
	var start := {}
	if _chunks.is_empty():
		var h0 := 6.0 if canyon else start_height
		start = {"pos": Vector3(0.0, h0, 0.0), "yaw": 0.0, "pitch": 0.0,
				"bank": 0.0, "width": 11.0, "dist": 0.0}
	else:
		start = _chunks[-1].end_state()
	_sections += 1
	var chunk := StuntTrack.new()
	chunk.name = "Section%d" % _sections
	chunk.segments.assign(TrackGenerator.generate_section(_sections, start, rng, canyon))
	chunk.canyon = canyon
	chunk.scenery = not canyon
	chunk.start_state = start
	# Trasa bez końca: bez szachownicy startu/mety (użytkownik: "znika
	# oznaczenie mety, jest bez sensu, robimy coś w rodzaju River Raid").
	chunk.build_lines = false
	chunk.road_material = road_material
	chunk.pillar_material = pillar_material
	add_child(chunk)                        # _ready kawałka buduje geometrię
	_chunks.append(chunk)
	_checkpoints.append(float(start["dist"]))


## Wołane przez scenę jazdy z dystansem auta: dobudowuje trasę przed autem
## i sprząta za nim. Budowa kawałka to kilkanaście ms - robimy to, kiedy
## auto dopiero wjeżdża w poprzedni, więc gracz tego nie zauważa.
func update_progress(dist: float) -> void:
	_current = _chunk_index(dist)
	while _chunks.size() - 1 - _current < AHEAD:
		_add_section()
	while _current > KEEP_BEHIND:
		var old: StuntTrack = _chunks.pop_front()
		old.queue_free()
		_current -= 1


func _chunk_index(dist: float) -> int:
	for i in range(_chunks.size()):
		if dist < _chunks[i].total_length():
			return i
	return _chunks.size() - 1


func _chunk_for(dist: float) -> StuntTrack:
	return _chunks[_chunk_index(dist)]


## Numer sekcji (od 1) na dystansie `dist`.
func section_at(dist: float) -> int:
	var n := 0
	for cp in _checkpoints:
		if dist >= cp:
			n += 1
	return maxi(n, 1)


## Dystans bramy punktu kontrolnego sekcji, w której jest `dist`.
func checkpoint_before(dist: float) -> float:
	var best := 0.0
	for cp in _checkpoints:
		if cp <= dist:
			best = cp
	return best


# --------------------------------------------------------------------------
# API jak StuntTrack
# --------------------------------------------------------------------------

func nearest_sample(world_pos: Vector3) -> Dictionary:
	# Bieżący kawałek i sąsiedzi - auto nie przeskakuje dalej niż o jeden.
	var best := {}
	var best_d := INF
	for i in range(maxi(_current - 1, 0), mini(_current + 2, _chunks.size())):
		var s := _chunks[i].nearest_sample(world_pos)
		if s.is_empty():
			continue
		var d: float = (_chunks[i].to_global(s["pos"])).distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = s
	return best


func lateral_offset(world_pos: Vector3) -> Dictionary:
	var s := nearest_sample(world_pos)
	if s.is_empty():
		return {"offset": 0.0, "on_track": false}
	return _chunk_for(float(s["dist"])).lateral_offset(world_pos)


func transform_at_distance(dist: float) -> Transform3D:
	return _chunk_for(dist).transform_at_distance(dist)


func last_gap_end_before(dist: float) -> float:
	var end := -INF
	for c in _chunks:
		var e := c.last_gap_end_before(dist)
		end = maxf(end, e)
	return end


func is_gap_at(dist: float) -> bool:
	return _chunk_for(dist).is_gap_at(dist)


func runup_start_before(dist: float) -> float:
	var best := -1.0
	for c in _chunks:
		best = maxf(best, c.runup_start_before(dist))
	return best


## Najbliższy warsztat, którego linia postoju jest dalej niż `dist`
## (pusty słownik, jeśli w wczytanych kawałkach nie ma).
func next_workshop(dist: float) -> Dictionary:
	for c in _chunks:
		for w in c.workshops():
			if w["stop"] > dist:
				return w
	return {}


## Najbliższa stacja paliw przed `dist` w wczytanych kawałkach ({} - brak).
func next_station(dist: float) -> Dictionary:
	for c in _chunks:
		for s in c.stations():
			if s["end"] > dist:
				return s
	return {}


## Trasa bez końca nie ma mety.
func finish_distance() -> float:
	return INF


func total_length() -> float:
	return _chunks[-1].total_length() if not _chunks.is_empty() else 0.0


## Próbki wszystkich wczytanych kawałków (dla autopilota w testach).
func samples_from(dist: float, length: float) -> Array:
	var out := []
	for c in _chunks:
		for s in c._samples:
			var d: float = s["dist"]
			if d >= dist and d <= dist + length:
				out.append(s)
	return out
