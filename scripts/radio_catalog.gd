extends RefCounted
class_name RadioCatalog

## Katalog stacji radia na tablecie (specyfikacja
## docs/agent/inbox/2026-11-08-radio-na-tablecie.md).
##
## Czysta logika, bez węzłów i dźwięku: lista stacji, filtr licencji,
## kolejność utworów (tasowanie bez powtórki pod rząd), napisy na tablet
## i tekst do CREDITS.md. Testowane bez sceny w tests/radio_test.gd.
##
## Dane stacji są w scripts/radio_stations.gd (GDScript, nie JSON: przy
## export_filter="all_resources" plik .json nie trafia do APK bez
## include_filter, a skrypt trafia zawsze).
##
## Format stacji:
##   {"id": "fala", "name": "Fala 84", "tracks": [
##       {"file": "fala/utwor.ogg", "title": "...", "artist": "...",
##        "license": "CC-BY-4.0", "source": "https://..."}]}
## "file" jest względem ROOT.

const ROOT := "res://audio/radio/"
const FIELDS := ["file", "title", "artist", "license", "source"]

## Stacje po filtrze (tylko z co najmniej jednym poprawnym utworem).
var stations: Array = []
## Opisy odrzuconych utworów i stacji (do logu: "RADIO: ...").
var errors: Array = []

var _rng := RandomNumberGenerator.new()
var _order: Array = []      # per stacja: kolejka indeksów utworów
var _last: Array = []       # per stacja: ostatnio zagrany indeks


func _init(data: Array = [], seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	load_stations(data)


## Licencja pozwala dołączyć utwór do gry na GPL i do sklepu:
## CC0, domena publiczna, CC-BY, CC-BY-SA (dowolna wersja). Bez NC i ND
## (ustalenie w specyfikacji: NC kłóci się z GPL i sprzedażą).
static func license_ok(lic: String) -> bool:
	var l := lic.strip_edges().to_upper().replace("_", "-").replace(" ", "-")
	if l.is_empty() or l.contains("NC") or l.contains("ND"):
		return false
	if l.begins_with("CC0") or l == "PD" or l.begins_with("PUBLIC-DOMAIN"):
		return true
	if not l.begins_with("CC-BY"):
		return false
	var rest := l.substr(5)          # po "CC-BY"
	if rest.begins_with("-SA"):
		rest = rest.substr(3)
	# Zostaje pusto albo numer wersji, np. "-4.0", "-3.0-PL".
	return rest.is_empty() or (rest.begins_with("-") and rest.length() > 1 and rest[1].is_valid_int())


func load_stations(data: Array) -> void:
	stations.clear()
	errors.clear()
	_order.clear()
	_last.clear()
	var ids := {}
	for s in data:
		if not (s is Dictionary) or not s.has("name") or not s.has("tracks"):
			errors.append("stacja bez nazwy albo listy utworów")
			continue
		var sid := str(s.get("id", s["name"]))
		if ids.has(sid):
			errors.append("powtórzone id stacji '%s'" % sid)
			continue
		var good: Array = []
		for t in s["tracks"]:
			var why := _track_problem(t)
			if why.is_empty():
				good.append(t)
			else:
				errors.append("%s: %s" % [sid, why])
		if good.is_empty():
			errors.append("stacja '%s' bez poprawnych utworów - pominięta" % sid)
			continue
		ids[sid] = true
		stations.append({"id": sid, "name": str(s["name"]), "tracks": good})
		_order.append([])
		_last.append(-1)


func _track_problem(t) -> String:
	if not (t is Dictionary):
		return "utwór nie jest słownikiem"
	for f in FIELDS:
		if str(t.get(f, "")).strip_edges().is_empty():
			return "brak pola '%s' (%s)" % [f, t.get("file", "?")]
	if not license_ok(str(t["license"])):
		return "licencja '%s' niedozwolona (%s)" % [t["license"], t["file"]]
	return ""


func station_count() -> int:
	return stations.size()


func track_count(station: int) -> int:
	return stations[station]["tracks"].size()


## Następna stacja z zawinięciem; dir = +1 / -1. Zwraca indeks albo -1.
func step_station(current: int, dir: int) -> int:
	var n := stations.size()
	if n == 0:
		return -1
	if current < 0:
		return 0 if dir >= 0 else n - 1
	return posmod(current + dir, n)


## Następny utwór stacji: każdy raz w tasowanej kolejce, bez powtórki pod
## rząd także na styku dwóch kolejek. Zwraca słownik utworu.
func next_track(station: int) -> Dictionary:
	var tracks: Array = stations[station]["tracks"]
	var q: Array = _order[station]
	if q.is_empty():
		for i in tracks.size():
			q.append(i)
		# Fisher-Yates na własnym RNG (powtarzalny w teście).
		for i in range(q.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp = q[i]
			q[i] = q[j]
			q[j] = tmp
		if q.size() > 1 and q[0] == _last[station]:
			var tmp2 = q[0]
			q[0] = q[q.size() - 1]
			q[q.size() - 1] = tmp2
	var idx: int = q.pop_front()
	_last[station] = idx
	return tracks[idx]


## Losowy ułamek długości utworu przy wejściu na stację - jak w prawdziwym
## radiu trafia się w środek piosenki. Nie dalej niż `max_frac`.
func join_fraction(max_frac: float = 0.6) -> float:
	return _rng.randf_range(0.0, max_frac)


static func path_of(track: Dictionary) -> String:
	return ROOT + str(track["file"])


## Napis na tablet: "Wykonawca - Tytuł" i druga linia z licencją.
static func now_playing_text(station_name: String, track: Dictionary) -> String:
	return "%s\n%s - %s\n%s" % [station_name, track["artist"], track["title"], track["license"]]


## Sekcja do CREDITS.md (wymóg CC-BY: autor, tytuł, licencja, źródło).
func credits_markdown() -> String:
	var out := "## Muzyka w radiu\n"
	for s in stations:
		out += "\n### %s\n\n" % s["name"]
		for t in s["tracks"]:
			out += "- \"%s\" - %s, %s, %s\n" % [t["title"], t["artist"], t["license"], t["source"]]
	return out
