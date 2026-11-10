extends Node
class_name JamendoSource

## Stacja "Jamendo online" dla CarRadio (prośba użytkownika 2026-11-09:
## "fajnie mieć też prawdziwe radio"). Bandcamp Radio odpada (brak strumieni
## i API, regulamin: tylko osobiste użycie), strumienie radiowe Jamendo
## (/radios/stream) są wg ich dokumentacji zepsute - dlatego "radio" składa
## się z pojedynczych utworów API /tracks.
##
## Warunki API Jamendo (devportal.jamendo.com/api_terms_of_use):
##  - darmowe tylko niekomercyjnie (gra bez sprzedaży i reklam);
##  - przy każdym utworze: wykonawca, Jamendo jako źródło i link do strony
##    utworu (now_playing_text);
##  - zakaz przechowywania do grania offline: utwór żyje tylko w pamięci
##    (bieżący + jeden pobrany na zapas), nic nie trafia na dysk.
##
## Klucz client_id (darmowy, devportal.jamendo.com) NIE trafia do repo
## (decyzja użytkownika 2026-11-09). Plik `radio_secrets.cfg` w katalogu
## projektu, w .gitignore, dołączany do APK przez include_filter eksportu:
##   [jamendo]
##   client_id="..."
## Pierwszeństwo ma user://radio.cfg (ten sam format). Bez klucza stacja
## się nie pokazuje.
##
## Przepływ: refill() -> lista utworów (losowa strona popularnych w gatunkach
## TAGS) -> prefetch() pobiera MP3 jednego utworu -> AudioStreamMP3
## .load_from_buffer (Godot 4.3+) -> sygnał track_ready. CarRadio bierze go przez
## take() i od razu zamawia następny.

signal track_ready                 # jest utwór do take()
signal failed(reason: String)      # brak sieci / błąd API

const API := "https://api.jamendo.com/v3.0/tracks/"
const CFGS := ["user://radio.cfg", "res://radio_secrets.cfg"]
## Gatunki stacji (fuzzytags = LUB). Pasują do gry: noc, szosa, lata 80.
const TAGS := ["synthwave", "retrowave", "rock", "electronic", "funk"]
const PAGE := 50                   # utworów na zapytanie
const MAX_OFFSET := 1000           # losowa strona z tylu najpopularniejszych
const MAX_BYTES := 20 * 1024 * 1024

var client_id := ""
## Ponowne próby przy pustej liście: API raz na jakiś czas odpowiada
## "success" z 0 wynikami dla strony, która chwilę wcześniej miała 50
## (sprawdzone 2026-11-10 z PC i z gogli) - inna losowa strona po chwili.
const EMPTY_RETRIES := 4
const RETRY_S := 1.5
var _empty_tries := 0
## Zwiększany przez drop() - spóźniona ponowna próba po drop() nic nie robi.
var _gen := 0

var _list: Array = []              # utwory do pobrania (słowniki z parse_tracks)
var _ready_item: Dictionary = {}   # {"stream": AudioStreamMP3, "info": {...}}
var _http: HTTPRequest
var _busy := ""                    # "", "list", "audio"
var _pending: Dictionary = {}      # info pobieranego utworu
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	client_id = load_client_id()


static func load_client_id() -> String:
	for path in CFGS:
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK:
			var v := str(cfg.get_value("jamendo", "client_id", "")).strip_edges()
			if v != "":
				return v
	return ""


func configured() -> bool:
	return client_id != ""


func has_ready() -> bool:
	return not _ready_item.is_empty()


## Zabiera gotowy utwór ({"stream", "info"}) i zamawia następny.
func take() -> Dictionary:
	var it := _ready_item
	_ready_item = {}
	prefetch()
	return it


## Zamawia utwór na zapas (jeśli nie ma gotowego i nic się nie pobiera).
func prefetch() -> void:
	if not configured() or _busy != "" or has_ready():
		return
	_ensure_http()
	if _list.is_empty():
		_busy = "list"
		var url := build_query_url(client_id, TAGS, _rng.randi_range(0, MAX_OFFSET / PAGE) * PAGE, PAGE)
		_start(url)
		return
	_pending = _list.pop_back()
	_busy = "audio"
	_start(str(_pending["audio"]))


## Zwolnienie pamięci (radio wyłączone / inna stacja na dłużej).
func drop() -> void:
	_gen += 1
	_empty_tries = 0
	_ready_item = {}
	if _http and _busy != "":
		_http.cancel_request()
	_busy = ""


func _ensure_http() -> void:
	if _http:
		return
	_http = HTTPRequest.new()
	_http.body_size_limit = MAX_BYTES
	_http.timeout = 30.0
	_http.use_threads = true       # pobieranie MP3 nie przycina klatek
	_http.request_completed.connect(_on_done)
	add_child(_http)


func _start(url: String) -> void:
	var err := _http.request(url, ["User-Agent: CanionRaidVR (Godot)"])
	if err != OK:
		_busy = ""
		failed.emit("błąd zapytania (%d)" % err)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var what := _busy
	_busy = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("brak sieci" if result != HTTPRequest.RESULT_SUCCESS else "HTTP %d" % code)
		return
	if what == "list":
		_list = parse_tracks(body.get_string_from_utf8())
		_list.shuffle()
		if _list.is_empty() and _empty_tries < EMPTY_RETRIES:
			_empty_tries += 1
			print("RADIO: Jamendo - pusta strona, próba %d/%d" % [_empty_tries, EMPTY_RETRIES])
			var g := _gen
			get_tree().create_timer(RETRY_S, true, false, true).timeout.connect(func():
				if g == _gen:
					prefetch())
			return
		_empty_tries = 0
		if _list.is_empty():
			# Diagnostyka (gogle: 200, a lista pusta - 2026-11-10): co przyszło.
			var txt := body.get_string_from_utf8()
			print("RADIO: Jamendo - odpowiedź %d B, nagłówki %s, początek: %s" % [body.size(),
					str(_headers).replace(client_id, "***").substr(0, 300),
					txt.substr(0, 300).replace(client_id, "***")])
			failed.emit("pusta lista utworów")
			return
		prefetch()
	elif what == "audio":
		var s := AudioStreamMP3.load_from_buffer(body)
		if s == null or s.get_length() <= 0.0:
			print("RADIO: Jamendo - nie da się odczytać MP3 ", _pending.get("source", "?"))
			prefetch()             # następny z listy
			return
		_ready_item = {"stream": s, "info": _pending}
		_pending = {}
		track_ready.emit()


static func build_query_url(cid: String, tags: Array, offset: int, limit: int) -> String:
	var q := PackedStringArray([
		"client_id=" + cid.uri_encode(),
		"format=json",
		"limit=%d" % limit,
		"offset=%d" % offset,
		"fuzzytags=" + "+".join(PackedStringArray(tags)),
		"audioformat=mp32",
		"order=popularity_total",
		"include=licenses",
	])
	return API + "?" + "&".join(q)


## Odpowiedź /tracks -> słowniki jak w RadioCatalog (title, artist, license,
## source) + "audio" (adres MP3). Utwory bez adresu albo strony pomija.
static func parse_tracks(text: String) -> Array:
	var out: Array = []
	var data = JSON.parse_string(text)
	if not (data is Dictionary) or not (data.get("results") is Array):
		return out
	for r in data["results"]:
		if not (r is Dictionary):
			continue
		var audio := str(r.get("audio", ""))
		var share := str(r.get("shareurl", ""))
		if audio == "" or share == "":
			continue
		out.append({
			"title": str(r.get("name", "?")),
			"artist": str(r.get("artist_name", "?")),
			"license": license_from_url(str(r.get("license_ccurl", ""))),
			"source": share,
			"audio": audio,
		})
	return out


## "http://creativecommons.org/licenses/by-nc-sa/3.0/" -> "CC-BY-NC-SA-3.0".
static func license_from_url(url: String) -> String:
	var m := RegEx.create_from_string("licenses/([a-z\\-]+)/([0-9.]+)").search(url)
	if m == null:
		return "CC (Jamendo)"
	return "CC-%s-%s" % [m.get_string(1).to_upper(), m.get_string(2)]


## Napis na tablet: stacja, wykonawca - tytuł, licencja i link (wymóg API).
static func now_playing_text(info: Dictionary) -> String:
	return "Jamendo online\n%s - %s\n%s  %s" % [info["artist"], info["title"], info["license"], info["source"]]
