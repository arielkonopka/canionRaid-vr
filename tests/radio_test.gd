extends SceneTree
## Test radia na tablecie: katalog stacji (RadioCatalog) i odtwarzacz
## (CarRadio) bez muzyki - dane syntetyczne, pliki nie istnieją.
##   godot --headless --xr-mode off -s res://tests/radio_test.gd </dev/null
## Sprawdza: filtr licencji (bez NC/ND), odrzucanie złych wpisów, zawijanie
## stacji, tasowanie bez powtórki pod rząd, CREDITS, szynę "Radio" i to,
## że radio bez stacji albo bez plików nie sypie się. Kod wyjścia 1 przy błędzie.

const RC := preload("res://scripts/radio_catalog.gd")
const CR := preload("res://scripts/car_radio.gd")
const RS := preload("res://scripts/radio_stations.gd")
const JS := preload("res://scripts/jamendo_source.gd")

var fails := 0


func _initialize() -> void:
	_test_licenses()
	_test_load()
	_test_stations()
	_test_shuffle()
	_test_credits()
	_test_real_list()
	_test_player()
	_test_jamendo_parse()
	_test_online_station()
	print("radio_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  BŁĄD: ", what)


func _track(file: String, lic: String = "CC-BY-4.0") -> Dictionary:
	return {"file": file, "title": "T " + file, "artist": "A " + file,
		"license": lic, "source": "https://example.org/" + file}


func _data() -> Array:
	return [
		{"id": "a", "name": "Fala 84", "tracks": [_track("a/1.ogg"), _track("a/2.ogg"), _track("a/3.ogg")]},
		{"id": "b", "name": "Nocna", "tracks": [_track("b/1.ogg", "CC0-1.0")]},
		{"id": "c", "name": "Rock", "tracks": [_track("c/1.ogg", "CC-BY-SA-3.0")]},
	]


func _test_licenses() -> void:
	for ok in ["CC0", "CC0-1.0", "cc-by", "CC-BY-4.0", "CC BY-SA 3.0", "CC-BY-SA", "CC_BY_3.0-PL", "PD"]:
		_check(RC.license_ok(ok), "licencja dozwolona: " + ok)
	for bad in ["CC-BY-NC-4.0", "CC-BY-ND", "CC-BY-NC-SA-3.0", "CC-BY-NC-ND", "", "All rights reserved", "CC-BYX", "GPL"]:
		_check(not RC.license_ok(bad), "licencja odrzucona: " + bad)


func _test_load() -> void:
	var d := _data()
	d.append({"id": "nc", "name": "Zła", "tracks": [_track("x.ogg", "CC-BY-NC-4.0")]})
	d.append({"id": "a", "name": "Duplikat", "tracks": [_track("y.ogg")]})
	d.append({"name": "Bez utworów"})
	var t := _track("z.ogg")
	t.erase("artist")
	d[0]["tracks"].append(t)
	var c = RC.new(d, 7)
	_check(c.station_count() == 3, "zostają 3 poprawne stacje (%d)" % c.station_count())
	_check(c.track_count(0) == 3, "utwór bez wykonawcy odrzucony")
	_check(c.errors.size() == 5, "5 opisów błędów (%d): %s" % [c.errors.size(), c.errors])


func _test_stations() -> void:
	var c = RC.new(_data(), 7)
	_check(c.step_station(-1, 1) == 0, "włączenie: pierwsza stacja")
	_check(c.step_station(-1, -1) == 2, "włączenie wstecz: ostatnia stacja")
	_check(c.step_station(2, 1) == 0, "zawijanie w przód")
	_check(c.step_station(0, -1) == 2, "zawijanie w tył")
	var e = RC.new([], 7)
	_check(e.step_station(-1, 1) == -1, "brak stacji: -1")


func _test_shuffle() -> void:
	var c = RC.new(_data(), 12345)
	var prev := ""
	var seen := {}
	for i in 30:
		var f: String = c.next_track(0)["file"]
		_check(f != prev, "bez powtórki pod rząd (krok %d)" % i)
		prev = f
		seen[f] = seen.get(f, 0) + 1
		if i % 3 == 2:
			_check(seen.size() == 3, "każda kolejka zawiera wszystkie utwory")
	_check(seen["a/1.ogg"] == 10 and seen["a/2.ogg"] == 10, "równo po 10 razy")
	var one: String = c.next_track(1)["file"]
	_check(one == "b/1.ogg" and c.next_track(1)["file"] == one, "stacja z jednym utworem gra go dalej")
	for i in 20:
		var f: float = c.join_fraction()
		_check(f >= 0.0 and f <= 0.6, "wejście w środek utworu w zakresie")


func _test_credits() -> void:
	var c = RC.new(_data(), 7)
	var md: String = c.credits_markdown()
	_check(md.contains("### Fala 84") and md.contains("A a/2.ogg") and md.contains("CC0-1.0")
		and md.contains("https://example.org/c/1.ogg"), "CREDITS ma stacje, autorów, licencje i źródła")
	var np := RC.now_playing_text("Nocna", _track("b/1.ogg"))
	_check(np.begins_with("Nocna\n") and np.contains("A b/1.ogg - T b/1.ogg"), "napis na tablet")
	_check(RC.path_of(_track("a/1.ogg")) == "res://audio/radio/a/1.ogg", "ścieżka pliku")


func _test_real_list() -> void:
	var c = RC.new(RS.STATIONS, 7)
	_check(c.errors.is_empty(), "prawdziwa lista stacji bez błędów: %s" % [c.errors])
	_check(c.station_count() == 3, "3 stacje w radio_stations.gd")
	var md: String = c.credits_markdown()
	_check(md.contains("(https://www.facebook.com/BogartVGM/)"), "dodatkowa atrybucja w CREDITS")
	var f := FileAccess.open("res://CREDITS.md", FileAccess.READ)
	_check(f != null and f.get_as_text().contains(md), "CREDITS.md zgodny z radio_stations.gd")


func _test_player() -> void:
	var i := CR.ensure_bus()
	_check(i >= 0 and AudioServer.get_bus_name(i) == "Radio", "szyna Radio")
	_check(CR.ensure_bus() == i, "szyna tworzona raz")
	_check(AudioServer.get_bus_send(i) == &"Master", "Radio idzie na Master, nie na Env")
	var texts: Array = []
	# Bez stacji.
	var r = CR.new()
	r.catalog = RC.new([], 7)
	root.add_child(r)
	r.now_playing.connect(func(t): texts.append(t))
	r.set_power(true)
	_check(texts.back() == "Radio: brak stacji", "bez stacji: komunikat")
	r.next_station(1)
	r.skip()
	r.set_power(false)
	_check(not r.is_on, "wyłączenie")
	r.queue_free()
	# Stacje są, plików nie ma.
	texts.clear()
	var r2 = CR.new()
	r2.catalog = RC.new(_data(), 7)
	root.add_child(r2)
	r2.now_playing.connect(func(t): texts.append(t))
	r2.set_power(true)
	r2._process(1.0)
	_check(r2.station == 0 and texts.back() == "Fala 84\n(brak plików)", "brak plików: komunikat (%s)" % [texts])
	r2.next_station(-1)
	r2._process(1.0)
	_check(r2.station == 2, "zmiana stacji wstecz")
	r2.toggle()
	_check(not r2.is_on and texts.back() == "", "toggle wyłącza")
	r2.queue_free()
	var w := CR._make_static()
	_check(w.data.size() == int(CR.RATE * 0.5) * 2 and CR._make_static() == w, "szum eteru generowany raz")


const JAMENDO_JSON := """{"headers": {"status": "success"}, "results": [
 {"name": "Neon Road", "artist_name": "Ktoś", "audio": "https://prod-1.storage.jamendo.com/?trackid=1&format=mp32",
  "shareurl": "https://www.jamendo.com/track/1", "license_ccurl": "http://creativecommons.org/licenses/by-nc-sa/3.0/"},
 {"name": "Bez dźwięku", "artist_name": "X", "audio": "", "shareurl": "https://www.jamendo.com/track/2"},
 {"name": "Bez licencji", "artist_name": "Y", "audio": "https://a/3", "shareurl": "https://www.jamendo.com/track/3"}
]}"""


func _test_jamendo_parse() -> void:
	_check(JS.license_from_url("http://creativecommons.org/licenses/by-nc-sa/3.0/") == "CC-BY-NC-SA-3.0", "licencja z adresu CC")
	_check(JS.license_from_url("https://creativecommons.org/licenses/by/4.0/") == "CC-BY-4.0", "licencja CC-BY z adresu")
	_check(JS.license_from_url("") == "CC (Jamendo)", "brak adresu licencji")
	var url := JS.build_query_url("abc", ["synthwave", "rock"], 100, 50)
	_check(url.begins_with("https://api.jamendo.com/v3.0/tracks/?") and url.contains("client_id=abc")
		and url.contains("fuzzytags=synthwave+rock") and url.contains("offset=100")
		and url.contains("audioformat=mp32"), "adres zapytania: " + url)
	var t := JS.parse_tracks(JAMENDO_JSON)
	_check(t.size() == 2, "utwór bez adresu MP3 pominięty (%d)" % t.size())
	_check(t[0]["artist"] == "Ktoś" and t[0]["license"] == "CC-BY-NC-SA-3.0"
		and t[0]["source"] == "https://www.jamendo.com/track/1", "pola utworu")
	_check(JS.parse_tracks("to nie json").is_empty() and JS.parse_tracks("[]").is_empty(), "zła odpowiedź = pusta lista")
	var np := JS.now_playing_text(t[0])
	_check(np.begins_with("Jamendo online\n") and np.contains("Ktoś - Neon Road")
		and np.contains("https://www.jamendo.com/track/1"), "napis z linkiem (wymóg API)")


func _test_online_station() -> void:
	var texts: Array = []
	var r = CR.new()
	r.catalog = RC.new(_data(), 7)
	var j = JS.new()
	j.client_id = ""
	r.jamendo = j
	root.add_child(r)
	r.now_playing.connect(func(t): texts.append(t))
	r.set_online(true)
	_check(r.station_total() == 3, "bez klucza brak stacji online")
	j.client_id = "test"
	j._busy = "list"                 # test bez sieci: prefetch nic nie wysyła
	_check(r.station_total() == 4, "z kluczem stacja online na końcu")
	r.set_power(true)
	r._process(1.0)
	r.next_station(-1)
	r._process(1.0)
	_check(r.is_online_station() and r.station_name() == "Jamendo online", "przełączenie na stację online")
	_check(texts.back() == "Jamendo online\nłączenie...", "czekanie na utwór: %s" % [texts.back()])
	var info: Dictionary = JS.parse_tracks(JAMENDO_JSON)[0]
	j._ready_item = {"stream": CR._make_static(), "info": info}
	j.track_ready.emit()
	_check(String(texts.back()).contains("Ktoś - Neon Road"), "gotowy utwór gra: %s" % [texts.back()])
	_check(not j.has_ready(), "utwór zabrany z zapasu")
	r.skip()
	r._process(1.0)
	j.failed.emit("brak sieci")
	_check(r.station == 0 and not r.is_online_station(), "brak sieci: powrót na stację offline")
	r.next_station(-1)
	r._process(1.0)
	_check(r.is_online_station(), "znów online")
	r.set_online(false)
	_check(r.station == 0 and r.station_total() == 3, "wyłączenie opcji: stacja offline, 3 stacje")
	r.set_power(false)
	r.queue_free()
