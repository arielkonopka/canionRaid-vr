class_name TrafficAudio
extends Node3D

## Dźwięki innych aut z Dopplerem (użytkownik 2026-11-11: "brakuje też
## dźwięków innych pojazdów i efektów, gdy się je mija, jak dopplera";
## inbox kierownica-decyzje-kolejnosc pkt 4): do MAX_CARS najbliższych aut
## w promieniu RADIUS dostaje dwa odtwarzacze 3D - pętlę silnika i pętlę
## szumu (opony + wiatr, "świst" mijania).
##
## Bez syntezy w GDScript na auto (koszt na Queście): próbki "wypalone" raz
## przy starcie tymi samymi wzorami co CarAudio (bez pobierania czegokolwiek),
## dalej tylko pitch_scale i głośność - miksuje silnik audio w C++.
##
## Doppler liczony tutaj z prędkości (nie wbudowany doppler_tracking: ten
## bierze prędkość z różnicy pozycji, a przesunięcie świata WorldOrigin to
## skok o kilometry = pisk). Prędkość aut też z różnicy pozycji (boty na
## szynie nie mają fizyki), z poprawką shift() przy przesunięciu świata.

const MAX_CARS := 4
const RADIUS := 80.0                   # [m]
const SOUND_C := 343.0                 # [m/s]
const MIX_RATE := 22050
const REF_RPM := 3000.0                # obroty wypalonej próbki silnika
const LOOP_S := 0.5                    # 25 cykli pół-rzędu przy 3000 obr/min - pętla bez szwu
const PICK_EVERY := 0.25               # [s] wybór najbliższych aut
const ENGINE_DB := -6.0
const NOISE_DB := -4.0

static var _engine_wav: AudioStreamWAV
static var _noise_wav: AudioStreamWAV

## Słuchacz: pozycja i prędkość (auto gracza). Ustawia xr_main co klatkę.
var listener_pos := Vector3.ZERO
var listener_vel := Vector3.ZERO
var enabled := true

var _slots: Array = []                 # [{car, eng, noise, prev, vel, have, warm}]
var _pick_t := 0.0


func _ready() -> void:
	name = "TrafficAudio"
	EnvAudio.ensure_bus()
	if _engine_wav == null:
		_engine_wav = bake_engine()
		_noise_wav = bake_noise()
	for i in range(MAX_CARS):
		var eng := _player(_engine_wav)
		var noise := _player(_noise_wav)
		_slots.append({"car": null, "eng": eng, "noise": noise,
				"prev": Vector3.ZERO, "vel": Vector3.ZERO, "have": false, "warm": false})


func _player(wav: AudioStreamWAV) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = wav
	p.bus = EnvAudio.BUS
	p.unit_size = 8.0
	p.max_distance = RADIUS + 10.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p


## Przesunięcie świata: zapamiętane pozycje w starym układzie.
func shift(v: Vector3) -> void:
	for s in _slots:
		s["prev"] -= v


## cars: kandydaci (boty, auta z naprzeciwka; bez auta gracza).
func update(cars: Array, delta: float) -> void:
	if delta <= 0.0:
		return
	_pick_t -= delta
	if _pick_t <= 0.0:
		_pick_t = PICK_EVERY
		_assign(pick_nearest(cars, listener_pos, MAX_CARS, RADIUS) if enabled else [])
	for s in _slots:
		var c: StuntCar = s["car"]
		var eng: AudioStreamPlayer3D = s["eng"]
		var noise: AudioStreamPlayer3D = s["noise"]
		if c == null or not is_instance_valid(c) or not c.visible:
			s["car"] = null
			if eng.playing:
				eng.stop()
				noise.stop()
			continue
		var p := c.global_position
		if s["have"]:
			var v: Vector3 = (p - s["prev"]) / delta
			# Skok (pula, teleport) - bez prędkości z tej klatki.
			# Pierwszy pomiar wprost - bez rozbiegu od zera (umowne biegi
			# "zmieniały się" przy każdym nowym aucie w slocie).
			if v.length() < 150.0:
				s["vel"] = v if not s["warm"] else (s["vel"] as Vector3).lerp(v, clampf(delta * 10.0, 0.0, 1.0))
				s["warm"] = true
		s["prev"] = p
		s["have"] = true
		if not s["warm"]:
			continue                   # pierwsza klatka - jeszcze bez prędkości
		var vel: Vector3 = s["vel"]
		var dop := doppler_ratio(p, vel, listener_pos, listener_vel)
		var spd := vel.length()
		var rpm := c.engine_rpm if (not c.freeze and c.engine_rpm > 500.0 and c.process_mode != Node.PROCESS_MODE_DISABLED) else fake_rpm(spd)
		var load := clampf(c.throttle, 0.0, 1.0) if not c.freeze else 0.5
		eng.global_position = p
		noise.global_position = p
		eng.pitch_scale = clampf(rpm / REF_RPM * dop, 0.15, 4.0)
		eng.volume_db = ENGINE_DB + linear_to_db(0.45 + 0.55 * load)
		# Szum opon i wiatru rośnie z prędkością (~v²): przy mijaniu "świst".
		var nk := clampf(spd / 40.0, 0.0, 1.0)
		noise.pitch_scale = clampf((0.7 + 0.5 * nk) * dop, 0.3, 3.0)
		noise.volume_db = NOISE_DB + linear_to_db(maxf(nk * nk, 0.001))
		if not eng.playing:
			# Losowy punkt startu - kilka aut z jednej próbki nie gra w fazie.
			eng.play(randf() * LOOP_S)
			noise.play(randf() * 1.0)


func _assign(chosen: Array) -> void:
	# Auta już grające zostają w swoich slotach (bez trzasku przy zmianie).
	for s in _slots:
		if s["car"] != null and not chosen.has(s["car"]):
			s["car"] = null
	for c in chosen:
		var has := false
		for s in _slots:
			if s["car"] == c:
				has = true
				break
		if has:
			continue
		for s in _slots:
			if s["car"] == null:
				s["car"] = c
				s["have"] = false
				s["warm"] = false
				s["vel"] = Vector3.ZERO
				break


## Aktywne sloty (do testu i PERF).
func active() -> int:
	var n := 0
	for s in _slots:
		if s["car"] != null:
			n += 1
	return n


# --------------------------------------------------------------------------
# Czysta logika (tests/traffic_audio_test.gd)
# --------------------------------------------------------------------------

## Stosunek częstotliwości (Doppler): f' / f = (c - v_l·u) / (c - v_s·u),
## u - kierunek od źródła do słuchacza. Zbliżanie = wyżej.
static func doppler_ratio(src: Vector3, v_src: Vector3, lis: Vector3, v_lis: Vector3) -> float:
	var d := lis - src
	if d.length_squared() < 1e-4:
		return 1.0
	var u := d.normalized()
	var num := SOUND_C - v_lis.dot(u)
	var den := maxf(SOUND_C - v_src.dot(u), 30.0)
	return clampf(num / den, 0.5, 2.0)


## Umowne obroty z prędkości (bot na szynie bez fizyki): 5 biegów,
## 1800-4800 obr/min w każdym.
static func fake_rpm(speed: float) -> float:
	var gear_span := 13.0               # [m/s] na bieg
	if speed < 1.0:
		return 850.0
	var g := mini(int(speed / gear_span), 4)
	var t := clampf((speed - g * gear_span) / gear_span, 0.0, 1.0) if g < 4 else clampf((speed - 4 * gear_span) / 30.0, 0.0, 1.0)
	return 1800.0 + 3000.0 * t


## Najbliższe auta w promieniu (do n), od najbliższego.
static func pick_nearest(cars: Array, lis: Vector3, n: int, radius: float) -> Array:
	var best: Array = []
	var r2 := radius * radius
	for c in cars:
		if c == null or not is_instance_valid(c) or not (c as Node3D).visible:
			continue
		var d2 := (c as Node3D).global_position.distance_squared_to(lis)
		if d2 > r2:
			continue
		var i := 0
		while i < best.size() and best[i][0] <= d2:
			i += 1
		if i < n:
			best.insert(i, [d2, c])
			if best.size() > n:
				best.pop_back()
	var out: Array = []
	for b in best:
		out.append(b[1])
	return out


## Pętla silnika (benzyna, umiarkowany gaz) przy REF_RPM - wzory z CarAudio.
static func bake_engine() -> AudioStreamWAV:
	var n := int(MIX_RATE * LOOP_S)
	var data := PackedInt32Array()
	data.resize(n)
	var dt := 1.0 / MIX_RATE
	var f_fire := REF_RPM / 30.0
	var load := 0.5
	var bright := 0.25 + 0.6 * load
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var comb_lp := 0.0
	for i in range(n):
		var ph := fmod(i * f_fire * dt, 1.0)
		var ph_half := fmod(i * f_fire * 0.5 * dt, 1.0)
		var a := TAU * ph
		var e := sin(a) + bright * 0.5 * sin(2.0 * a) + bright * 0.3 * sin(3.0 * a) + 0.35 * sin(TAU * ph_half)
		var burst := (1.0 - ph) * (1.0 - ph)
		comb_lp += (rng.randf_range(-1.0, 1.0) - comb_lp) * 0.25
		e += comb_lp * burst * 0.05 * (0.3 + load) * 10.0
		data[i] = int(tanh(e * 0.35) * 26000.0)
	return AudioUtil.wav(data, MIX_RATE, 16, true)


## Pętla szumu: wiatr (dolnoprzepustowy) + szum opon (pasmo ~500 Hz),
## 1 s, końce zszyte przenikaniem (bez stuku na szwie pętli).
static func bake_noise() -> AudioStreamWAV:
	var n := MIX_RATE
	var fade := 2000
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var rng := RandomNumberGenerator.new()
	rng.seed = 54321
	var lp := 0.0
	var bp1 := 0.0
	var bp2 := 0.0
	var g := 2.0 * sin(PI * 500.0 / MIX_RATE)
	for i in range(n + fade):
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.03
		var hp := x - bp2 - 0.3 * bp1
		bp1 += g * hp
		bp2 += g * bp1
		raw[i] = lp * 2.5 + bp1 * 0.25
	var data := PackedInt32Array()
	data.resize(n)
	for i in range(n):
		var s := raw[i]
		if i < fade:
			var w := float(i) / fade
			s = raw[i] * w + raw[n + i] * (1.0 - w)
		data[i] = int(clampf(s, -1.0, 1.0) * 24000.0)
	return AudioUtil.wav(data, MIX_RATE, 16, true)
