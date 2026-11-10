extends Node
class_name CarRadio

## Radio na tablecie w kabinie (specyfikacja
## docs/agent/inbox/2026-11-08-radio-na-tablecie.md).
##
## Gra muzykę z dołączonych stacji (RadioCatalog + RadioStations) na
## osobnej szynie "Radio": obcięty dół i góra jak głośniki w drzwiach auta,
## lekki pogłos kabiny. Celowo NIE przez szynę "Env" (EnvAudio), żeby tunel
## i wąwóz nie dodawały echa do muzyki.
##
## Przy zmianie stacji: krótki szum eteru i wejście w środek utworu (jak
## w prawdziwym radiu). Po końcu utworu: krótki szum i następny utwór
## (tasowanie bez powtórki pod rząd).
##
## Bez stacji (pusta lista) radio milczy i podaje "brak stacji" - nic się
## nie sypie, więc można je wpiąć przed wyborem muzyki.
##
## Integracja (po stronie gry, plik gorący - agent lokalny):
##   var radio := CarRadio.new(); add_child(radio)
##   radio.now_playing.connect(tablet.show_text)
##   przycisk: radio.toggle() / radio.next_station(+1) / radio.skip()
##
## Stacja "Jamendo online" (JamendoSource, prośba użytkownika 2026-11-09):
## dodatkowa, ostatnia na liście, tylko gdy set_online(true) i jest klucz
## client_id. Domyślnie wyłączona (jawna opcja w menu). Brak sieci = komunikat
## i powrót na pierwszą stację offline.

signal now_playing(text: String)

# preload zamiast globalnych class_name: działa też w teście headless
# przed pierwszym importem w edytorze (pusta pamięć klas).
const Catalog := preload("res://scripts/radio_catalog.gd")
const Stations := preload("res://scripts/radio_stations.gd")
const Jamendo := preload("res://scripts/jamendo_source.gd")

const BUS := "Radio"
const VOLUME_DB := -8.0            # do odsłuchu: ma nie zagłuszać silnika
const STATIC_DB := -20.0
const GAP_S := 0.35                # szum między utworami
const RATE := 22050

var catalog: Catalog
var station := -1
var is_on := false
var online_enabled := false
var jamendo: Jamendo

var _player: AudioStreamPlayer
var _static: AudioStreamPlayer
var _gap := -1.0                   # >0: odliczanie szumu przed następnym utworem
var _join := false
var _waiting_online := false
static var _noise: AudioStreamWAV


## Szyna "Radio" (raz na całą grę - AudioServer jest globalny).
static func ensure_bus() -> int:
	var i := AudioServer.get_bus_index(BUS)
	if i >= 0:
		return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Master")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 140.0
	AudioServer.add_bus_effect(i, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 8000.0
	AudioServer.add_bus_effect(i, lp)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.12
	rev.damping = 0.7
	rev.predelay_msec = 5.0
	rev.wet = 0.05
	rev.dry = 1.0
	AudioServer.add_bus_effect(i, rev)
	return i


func _ready() -> void:
	_setup()


## Szyna, katalog i odtwarzacze - przy pierwszym użyciu, nie tylko w _ready
## (węzeł dodany w _initialize testu albo przed wejściem sceny do drzewa
## dostaje wywołania wcześniej niż _ready).
func _setup() -> void:
	if _player:
		return
	ensure_bus()
	if catalog == null:
		catalog = Catalog.new(Stations.STATIONS)
	for e in catalog.errors:
		print("RADIO: ", e)
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.volume_db = VOLUME_DB
	_player.finished.connect(_on_finished)
	add_child(_player)
	_static = AudioStreamPlayer.new()
	_static.bus = BUS
	_static.volume_db = STATIC_DB
	_static.stream = _make_static()
	add_child(_static)
	if jamendo == null:
		jamendo = Jamendo.new()
	jamendo.name = "Jamendo"
	jamendo.track_ready.connect(_on_online_ready)
	jamendo.failed.connect(_on_online_failed)
	add_child(jamendo)


## Liczba stacji razem ze stacją online (jeśli włączona i skonfigurowana).
func station_total() -> int:
	_setup()
	return catalog.station_count() + (1 if has_online() else 0)


func has_online() -> bool:
	return online_enabled and jamendo != null and jamendo.configured()


func is_online_station() -> bool:
	return has_online() and station == catalog.station_count()


## Nazwa bieżącej stacji (dla menu i tabletu).
func station_name() -> String:
	_setup()
	if station_total() == 0:
		return "-"
	if is_online_station():
		return "Jamendo online"
	return catalog.stations[clampi(station, 0, catalog.station_count() - 1)]["name"]


## Jawna opcja: stacja online wł./wył. Wyłączenie na tej stacji przełącza
## na pierwszą stację offline.
func set_online(on: bool) -> void:
	_setup()
	var was_online := is_online_station()
	online_enabled = on
	if on and has_online():
		jamendo.prefetch()
	elif was_online:
		jamendo.drop()
		_waiting_online = false
		station = 0 if catalog.station_count() > 0 else -1
		if is_on:
			if station >= 0:
				_burst(true)
			else:
				set_power(true)


func set_power(on: bool) -> void:
	_setup()
	is_on = on
	if not on:
		_gap = -1.0
		_waiting_online = false
		_player.stop()
		_static.stop()
		now_playing.emit("")
		return
	if station_total() == 0:
		now_playing.emit("Radio: brak stacji")
		return
	if station < 0 or station >= station_total():
		station = 0
	_burst(true)


func toggle() -> void:
	set_power(not is_on)


func next_station(dir: int = 1) -> void:
	if not is_on:
		set_power(true)
		return
	var n := station_total()
	if n == 0:
		return
	station = 0 if station < 0 else posmod(station + dir, n)
	_burst(true)


## Wybór stacji (ustawienie "Stacja" z menu). Ujemny (GameSettings.
## STATION_ONLINE) = stacja online, gdy włączona; inaczej pierwsza z gry.
func set_station(i: int) -> void:
	_setup()
	if i < 0 and has_online():
		station = catalog.station_count()
	elif catalog.station_count() == 0:
		return
	elif i < 0 or i >= catalog.station_count():
		station = 0
	else:
		station = i
	if is_on:
		_burst(true)


## Następny utwór tej samej stacji, od początku.
func skip() -> void:
	if is_on and station_total() > 0:
		_burst(false)


func set_volume_db(db: float) -> void:
	_setup()
	_player.volume_db = db
	_static.volume_db = db + (STATIC_DB - VOLUME_DB)


func _burst(join: bool) -> void:
	_player.stop()
	if _static.is_inside_tree():
		_static.play()
	_join = join
	_gap = GAP_S


func _process(delta: float) -> void:
	if _gap <= 0.0:
		return
	_gap -= delta
	if _gap <= 0.0:
		_static.stop()
		_tune(_join)


func _on_finished() -> void:
	if is_on:
		_burst(false)


## Ładuje następny utwór stacji. Brakujący plik pomija (log), najwyżej
## tyle razy, ile stacja ma utworów, żeby nie kręcić się w kółko.
func _tune(join: bool) -> void:
	if not is_on or station < 0:
		return
	if is_online_station():
		_tune_online()
		return
	if station >= catalog.station_count():
		return
	var name_s: String = catalog.stations[station]["name"]
	for _i in catalog.track_count(station):
		var t := catalog.next_track(station)
		var path := Catalog.path_of(t)
		var s: AudioStream = null
		if ResourceLoader.exists(path):
			s = load(path) as AudioStream
		if s == null:
			print("RADIO: brak pliku ", path)
			continue
		_player.stream = s
		var from := 0.0
		if join:
			from = catalog.join_fraction() * s.get_length()
		_player.play(from)
		now_playing.emit(Catalog.now_playing_text(name_s, t))
		return
	now_playing.emit("%s\n(brak plików)" % name_s)


## Stacja online: gotowy utwór gra od początku (pobieranie całości tylko
## po to, żeby wejść w środek, byłoby marnotrawstwem). Gdy nic nie czeka -
## szum eteru ("strojenie") aż JamendoSource zgłosi track_ready.
func _tune_online() -> void:
	if jamendo.has_ready():
		_waiting_online = false
		_static.stop()
		var it := jamendo.take()
		_player.stream = it["stream"]
		_player.play()
		now_playing.emit(Jamendo.now_playing_text(it["info"]))
		return
	_waiting_online = true
	now_playing.emit("Jamendo online\nłączenie...")
	if _static.is_inside_tree():
		_static.play()
	jamendo.prefetch()


func _on_online_ready() -> void:
	if _waiting_online and is_on and is_online_station():
		_tune_online()


func _on_online_failed(reason: String) -> void:
	print("RADIO: Jamendo - ", reason)
	if not (_waiting_online and is_on and is_online_station()):
		return
	_waiting_online = false
	_static.stop()
	now_playing.emit("Jamendo online\n%s" % reason)
	if catalog.station_count() > 0:
		station = 0
		_burst(true)


## Szum eteru: szum przefiltrowany dolnoprzepustowo z trzaskami,
## generowany raz (jak deszcz w xr_main.gd - bez plików).
static func _make_static() -> AudioStreamWAV:
	if _noise != null:
		return _noise
	var n := int(RATE * 0.5)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1984
	var lp := 0.0
	for i in n:
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		var v := lp * 0.6
		if rng.randf() < 0.004:
			v += rng.randf_range(-0.9, 0.9)       # trzask
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	wav.data = data
	_noise = wav
	return wav
