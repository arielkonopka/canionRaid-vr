extends AudioStreamPlayer3D
class_name CarAudio

## Dźwięk auta generowany w kodzie - bez żadnych nagrań.
##
## Jeden strumień AudioStreamGenerator (22 kHz, mono), wypełniany co klatkę
## tyloma próbkami, ile odtwarzacz zużył (~300 na klatkę przy 72 Hz).
## Źródło 3D w komorze silnika - w goglach słychać, że silnik jest z przodu.
##
## Składniki:
##   SILNIK SPALINOWY - częstotliwość zapłonów z obrotów (4 cylindry, 4 suwy:
##     obr/min / 30 Hz) i kilka harmonicznych; "pół-rząd" (połowa częstotliwości
##     zapłonów) daje nierówny, mechaniczny pomruk. Pod obciążeniem (gaz) więcej
##     wyższych harmonicznych i szumu spalania, bez gazu - cichszy, gładszy.
##     Diesel: niżej, więcej szumu i "klekotu" (krótkie impulsy przy zapłonie).
##   ELEKTRYK - ton falownika (proporcjonalny do obrotów silnika) i wycie
##     przekładni; cichy, wysoki.
##   OPONY - pisk: szum przepuszczony przez filtr rezonansowy ~1 kHz, głośność
##     z poślizgu kół (Wheel.slip > 1 = za szczytem przyczepności) i prędkości.
##   WIATR - szum przez filtr dolnoprzepustowy, głośność ~ v².
##   MOKRO - syk wody spod opon: szum górnoprzepustowy, głośność z prędkości
##     i udziału kół na mokrej nawierzchni.
##   UDERZENIA - krótkie, głuche łupnięcie (sygnał landed i wgniecenia).
##
## Koszt: pętla po próbkach w GDScript. Przy 22 kHz to ~300 próbek na klatkę;
## jeśli na Queście okaże się za drogo, ta pętla to jedyne miejsce do
## przeniesienia do GDExtension.

const MIX_RATE := 22050.0
const BUFFER_S := 0.1

@export var volume := 0.8

var car: StuntCar
var _playback: AudioStreamGeneratorPlayback

# Fazy oscylatorów (0..1).
var _ph_fire := 0.0
var _ph_half := 0.0
var _ph_inv := 0.0
var _ph_gear := 0.0
# Stany filtrów.
var _wind_lp := 0.0
var _sq_bp1 := 0.0
var _sq_bp2 := 0.0
var _comb_lp := 0.0
# Wygładzone parametry (zmiana skokowa co klatkę dałaby trzaski).
var _rpm := 800.0
var _load := 0.0
var _slip := 0.0
var _speed := 0.0
var _wet := 0.0                    # udział kół na mokrym, wygładzony
var _hiss_lp := 0.0
# Uderzenie: amplituda i faza zanikającego tonu.
var _thud := 0.0
var _ph_thud := 0.0
var _rng := RandomNumberGenerator.new()
var _prev_dents := 0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_S
	stream = gen
	# Akustyka otoczenia (pogłos wąwozu/tunelu) - patrz EnvAudio.
	EnvAudio.ensure_bus()
	bus = EnvAudio.BUS
	unit_size = 6.0
	max_db = 3.0
	play()
	_playback = get_stream_playback()
	if car:
		car.landed.connect(_on_landed)


func _on_landed(impact_speed: float) -> void:
	thud(clampf((impact_speed - 3.0) / 10.0, 0.0, 1.0))


## Głuche łupnięcie o sile 0..1.
func thud(strength: float) -> void:
	_thud = maxf(_thud, strength)


func _process(delta: float) -> void:
	if not car or not _playback:
		return
	# Wgniecenie karoserii = uderzenie.
	if car.dent_count > _prev_dents:
		thud(0.8)
	_prev_dents = car.dent_count

	# Parametry z auta, wygładzone (stała czasowa ~50 ms).
	var k := clampf(delta * 20.0, 0.0, 1.0)
	_rpm = lerpf(_rpm, car.engine_rpm, k)
	var pedal := car.throttle if not (car.gear < 0 and car.automatic) else car.brake
	_load = lerpf(_load, pedal, k)
	var slip := 0.0
	var wet := 0.0
	for w in car.wheels:
		if w.contact:
			slip = maxf(slip, w.slip)
			if w.surface == "wet":
				wet += 0.25
	_slip = lerpf(_slip, slip, k)
	_speed = lerpf(_speed, car.linear_velocity.length(), k)
	_wet = lerpf(_wet, wet, k * 0.3)

	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	_synth(buf, n)
	_playback.push_buffer(buf)


func _synth(buf: PackedVector2Array, n: int) -> void:
	var dt := 1.0 / MIX_RATE
	var electric := car.electric
	var diesel := car.engine_type == "diesel"

	# --- parametry składników na ten blok ---
	var f_fire := _rpm / 30.0                      # zapłony 4 cyl. [Hz]
	var eng_amp := 0.0 if electric else (0.22 + 0.25 * _load)
	var bright := 0.25 + 0.6 * _load               # udział wyższych harmonicznych
	var comb_amp := (0.10 if diesel else 0.05) * (0.3 + _load)
	var f_inv := _rpm / 60.0 * 8.0                 # falownik (8 x obroty)
	var f_gear := _rpm / 60.0 * 23.0               # zazębienie przekładni
	var ev_amp := 0.0 if not electric else 0.05 + 0.10 * _load
	var wind_amp := clampf(_speed * _speed / 2500.0, 0.0, 1.0) * 0.35
	var sq_amp := clampf((_slip - 1.0) * 0.6, 0.0, 1.0) * clampf(_speed / 8.0, 0.0, 1.0) * 0.30
	# Filtr pisku: rezonans ~1 kHz, trochę wyżej przy większej prędkości.
	var f_sq := 900.0 + _speed * 6.0
	var sq_g := 2.0 * sin(PI * f_sq * dt)
	var sq_q := 0.08
	var wind_k := 0.02
	var thud_decay := exp(-dt * 9.0)
	var hiss_amp := _wet * clampf(_speed / 25.0, 0.0, 1.0) * 0.22

	for i in range(n):
		# Silnik spalinowy.
		var s := 0.0
		if eng_amp > 0.0:
			_ph_fire = fmod(_ph_fire + f_fire * dt, 1.0)
			_ph_half = fmod(_ph_half + f_fire * 0.5 * dt, 1.0)
			var a := TAU * _ph_fire
			var e := sin(a) + bright * 0.5 * sin(2.0 * a) + bright * 0.3 * sin(3.0 * a) \
					+ 0.35 * sin(TAU * _ph_half)
			# Szum spalania - impuls na początku cyklu zapłonu.
			var burst := (1.0 - _ph_fire) * (1.0 - _ph_fire)
			_comb_lp += (_rng.randf_range(-1.0, 1.0) - _comb_lp) * (0.5 if diesel else 0.25)
			e += _comb_lp * burst * comb_amp * 10.0
			s += e * eng_amp * (0.6 if diesel else 0.5)
		# Elektryk.
		if ev_amp > 0.0:
			_ph_inv = fmod(_ph_inv + f_inv * dt, 1.0)
			_ph_gear = fmod(_ph_gear + f_gear * dt, 1.0)
			s += (sin(TAU * _ph_inv) * 0.6 + sin(TAU * _ph_gear) * 0.4) * ev_amp
		# Wiatr.
		var noise := _rng.randf_range(-1.0, 1.0)
		_wind_lp += (noise - _wind_lp) * wind_k
		s += _wind_lp * wind_amp * 3.0
		# Syk wody spod opon: szum bez niskich tonów.
		if hiss_amp > 0.0:
			_hiss_lp += (noise - _hiss_lp) * 0.3
			s += (noise - _hiss_lp) * hiss_amp
		# Pisk opon (filtr pasmowy stanowy).
		if sq_amp > 0.0:
			var hp := noise - _sq_bp2 - sq_q * _sq_bp1
			_sq_bp1 += sq_g * hp
			_sq_bp2 += sq_g * _sq_bp1
			s += _sq_bp1 * sq_amp * 0.5
		# Uderzenie: ton ~55 Hz z szumem, szybko zanika.
		if _thud > 0.001:
			_ph_thud = fmod(_ph_thud + 55.0 * dt, 1.0)
			s += (sin(TAU * _ph_thud) * 0.8 + noise * 0.3) * _thud
			_thud *= thud_decay
		# Miękkie przycięcie - bez trzasków przy sumie głośnych składników.
		s = tanh(s * volume)
		buf[i] = Vector2(s, s)
