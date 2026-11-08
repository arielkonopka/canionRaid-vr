extends SceneTree
## Test radia na tablecie: katalog stacji (RadioCatalog) i odtwarzacz
## (CarRadio) bez muzyki - dane syntetyczne, pliki nie istnieją.
##   godot --headless --xr-mode off -s res://tests/radio_test.gd </dev/null
## Sprawdza: filtr licencji (bez NC/ND), odrzucanie złych wpisów, zawijanie
## stacji, tasowanie bez powtórki pod rząd, CREDITS, szynę "Radio" i to,
## że radio bez stacji albo bez plików nie sypie się. Kod wyjścia 1 przy błędzie.

const RC := preload("res://scripts/radio_catalog.gd")
const CR := preload("res://scripts/car_radio.gd")

var fails := 0


func _initialize() -> void:
	_test_licenses()
	_test_load()
	_test_stations()
	_test_shuffle()
	_test_credits()
	_test_player()
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
