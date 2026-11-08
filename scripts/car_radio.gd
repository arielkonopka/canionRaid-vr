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

signal now_playing(text: String)

# preload zamiast globalnych class_name: działa też w teście headless
# przed pierwszym importem w edytorze (pusta pamięć klas).
const Catalog := preload("res://scripts/radio_catalog.gd")
const Stations := preload("res://scripts/radio_stations.gd")

const BUS := "Radio"
const VOLUME_DB := -8.0            # do odsłuchu: ma nie zagłuszać silnika
const STATIC_DB := -20.0
const GAP_S := 0.35                # szum między utworami
const RATE := 22050

var catalog: Catalog
var station := -1
var is_on := false

var _player: AudioStreamPlayer
var _static: AudioStreamPlayer
var _gap := -1.0                   # >0: odliczanie szumu przed następnym utworem
var _join := false
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


func set_power(on: bool) -> void:
	is_on = on
	if not on:
		_gap = -1.0
		_player.stop()
		_static.stop()
		now_playing.emit("")
		return
	if catalog.station_count() == 0:
		now_playing.emit("Radio: brak stacji")
		return
	if station < 0:
		station = 0
	_burst(true)


func toggle() -> void:
	set_power(not is_on)


func next_station(dir: int = 1) -> void:
	if not is_on:
		set_power(true)
		return
	if catalog.station_count() == 0:
		return
	station = catalog.step_station(station, dir)
	_burst(true)


## Następny utwór tej samej stacji, od początku.
func skip() -> void:
	if is_on and catalog.station_count() > 0:
		_burst(false)


func set_volume_db(db: float) -> void:
	_player.volume_db = db
	_static.volume_db = db + (STATIC_DB - VOLUME_DB)


func _burst(join: bool) -> void:
	_player.stop()
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
