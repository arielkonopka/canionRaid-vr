extends Node
class_name BotDriver

## Sterownik bota - pustego, zdalnie sterowanego auta. Dziecko auta-bota.
##
## SPOKÓJ: prawy pas, prędkość = obowiązujące ograniczenie (z wyprzedzeniem
##   zwalnia przed niższym limitem i przed łukami), jak przepisowy kierowca.
## SZAŁ DROGOWY: po zderzeniu z autem gracza. Przyspiesza ponad limit,
##   celuje w auto gracza i taranuje; przednie światła pulsują na czerwono.
##   Uspokaja go wyłącznie przepisowa jazda gracza (prędkość <= limit +
##   5 km/h) - szał opada w ~6 s takiej jazdy, inaczej trwa.
## Zderzenia to zwykła fizyka dwóch brył - nic tu nie jest udawane.

const CALM_TIME := 1024.0                 # s przepisowej jazdy gracza do uspokojenia
## Najkrótszy pościg po zderzeniu - dopiero potem przepisowa jazda gracza
## może bota uspokajać (inaczej gracz jadący przepisowo nie widział pościgu).
const MIN_RAGE_TIME := 500.0
const WINDOW_AHEAD := 180.0

var car: StuntCar
var player: StuntCar
var track
var main                               # scena jazdy (player_compliant(), lane info)
var dist := 0.0                        # dystans bota na trasie
var rage := 0.0                        # 0 = spokój, 1 = pełny szał
var flipped_time := 0.0
var rage_time := 0.0                   # od ostatniego zderzenia [s]
## Wychodzenie z utknięcia (np. obrócony po zderzeniu, przodem w ścianie):
## cofanie z kołami skręconymi przeciwnie, potem znów do przodu.
var _stuck_t := 0.0
var _reverse_t := 0.0
var _reverse_steer := 0.0
var _horn: AudioStreamPlayer3D
var _horn_timer := 0.0

var _window: Array = []
var _window_timer := 0.0


func _physics_process(delta: float) -> void:
	if car == null or track == null:
		return
	_window_timer -= delta
	if _window_timer <= 0.0:
		_window_timer = 0.15
		_window = track.samples_from(dist - 15.0, WINDOW_AHEAD + 15.0)
	if _window.is_empty():
		return
	# Najbliższa próbka w oknie - szukanie lokalne, nie po całej trasie.
	var best: Dictionary = _window[0]
	var best_d := INF
	for s in _window:
		var dd := (s["pos"] as Vector3).distance_squared_to(car.global_position)
		if dd < best_d:
			best_d = dd
			best = s
	dist = float(best["dist"])

	if rage > 0.0:
		rage_time += delta
		if rage_time > MIN_RAGE_TIME and main and main.player_compliant():
			rage = maxf(rage - delta / CALM_TIME, 0.0)

	car.set_rage_lights(rage * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)))

	var right: Vector3 = best["right"]
	var w := float(best["width"])
	var lane_w := (w - 1.0) / 3.0
	var rel := car.global_position - (best["pos"] as Vector3)
	var offset := rel.dot(right)
	var target_off := lane_w                          # prawy pas
	var kmh := car.speed * 3.6
	var target_kmh := _calm_speed(kmh)
	if rage > 0.05 and player:
		# Szał: na auto gracza (jego przesunięcie w poprzek drogi) i szybciej.
		var prel := player.global_position - (best["pos"] as Vector3)
		target_off = clampf(prel.dot(right), -w * 0.5 + 1.0, w * 0.5 - 1.0)
		var ahead := prel.dot(best["fwd"] as Vector3)
		# Goni tak szybko, jak trzeba, żeby dogonić (gracz przed nim) - limitem
		# jest tylko auto i łuki (bot w szale ich nie odpuszcza całkiem).
		var chase := player.speed * 3.6 + (30.0 if ahead > 0.0 else -10.0)
		target_kmh = lerpf(target_kmh, clampf(chase, 30.0, 230.0), rage)

	var fwd := -car.global_basis.z
	var head_err := fwd.signed_angle_to(best["fwd"], car.global_basis.y)
	car.steer = clampf(-(offset - target_off) * 0.22 - head_err * 2.5, -1.0, 1.0) \
			if car.wheels_on_ground > 0 else 0.0
	car.throttle = 1.0 if kmh < target_kmh - 1.0 else (0.3 if kmh < target_kmh + 2.0 else 0.0)
	car.brake = clampf((kmh - target_kmh - 4.0) * 0.12, 0.0, 1.0)

	# Utknięcie: stoi z gazem albo jest odwrócony (> 100° od kierunku drogi).
	var backwards := absf(head_err) > deg_to_rad(100.0)
	if _reverse_t > 0.0:
		_reverse_t -= delta
		# Automat: hamulec na postoju wrzuca wsteczny, potem działa jak gaz.
		car.throttle = 0.0
		car.brake = 0.8
		car.steer = _reverse_steer
		return
	if (absf(kmh) < 3.0 and car.throttle > 0.5) or (backwards and absf(kmh) < 15.0):
		_stuck_t += delta
		if _stuck_t > 1.2:
			_stuck_t = 0.0
			_reverse_t = 1.6
			# Cofając, skręcamy przeciwnie - przód obraca się w stronę drogi.
			_reverse_steer = -signf(car.steer) if absf(car.steer) > 0.1 else 1.0
	else:
		_stuck_t = 0.0
	if car.wheels_on_ground == 0:
		car.throttle = 0.0
		car.brake = 0.0
	flipped_time = flipped_time + delta if car.global_basis.y.y < 0.3 else 0.0


## Prędkość przepisowa: najniższy limit w oknie, z drogą hamowania (5 m/s²),
## i bezpieczna prędkość na łukach (pozioma krzywizna, przyczepność).
func _calm_speed(_kmh: float) -> float:
	var target := 200.0
	for i in range(0, _window.size() - 12, 4):
		var a0: Dictionary = _window[i]
		var k := float(a0["dist"]) - dist
		if k < -2.0:
			continue
		var lim := float(a0["limit"]) / 3.6
		target = minf(target, sqrt(lim * lim + 2.0 * 5.0 * maxf(k, 0.0)) * 3.6)
		var a1: Dictionary = _window[i + 12]
		var f0: Vector3 = (a0["fwd"] as Vector3) * Vector3(1, 0, 1)
		var f1: Vector3 = (a1["fwd"] as Vector3) * Vector3(1, 0, 1)
		var ang := f0.angle_to(f1)
		if ang > 0.01:
			var span := float(a1["dist"]) - float(a0["dist"])
			var grip: float = StuntTrack.SURFACES[a0["surface"]]["grip"]
			var vc := sqrt(0.6 * grip * 9.8 * span / ang)
			target = minf(target, sqrt(vc * vc + 2.0 * 5.0 * maxf(k, 0.0)) * 3.6)
	return target


func _ready() -> void:
	# Zderzenie: sygnał body_entered (contact_monitor jest włączony w aucie) -
	# odpytywanie kontaktów w klatce gubiło krótkie uderzenia.
	car.body_entered.connect(_on_body_entered)
	_horn = AudioStreamPlayer3D.new()
	_horn.stream = _make_horn()
	_horn.unit_size = 8.0
	EnvAudio.ensure_bus()
	_horn.bus = EnvAudio.BUS
	car.add_child(_horn)


## Zderzenie z autem gracza (fizyka już zadziałała) - bot wpada w szał.
func _on_body_entered(b: Node) -> void:
	if b != player:
		return
	var rel_v := (car.linear_velocity - player.linear_velocity).length()
	if rel_v > 1.0:
		if rage < 0.5:
			print("Bot w szale drogowym!")
			# Trąbi raz, przy wybuchu szału.
			if _horn:
				_horn.play()
			# Oszustwo: zdalnie sterowane auto nagle dostaje mocniejszy silnik -
			# co najmniej 350 kW i nie słabszy niż auto gracza (do 700 kW).
			var cheat := maxf(350.0, player.engine_power_kw if player else 0.0)
			if car.engine_power_kw < cheat:
				car.apply_engine("petrol", cheat)
		rage = 1.0
		rage_time = 0.0


## Klakson: dwa tony (~420 i ~500 Hz, jak typowy samochodowy), 0,4 s,
## generowany w kodzie.
static func _make_horn() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.4)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / rate
		var env := clampf(t / 0.02, 0.0, 1.0) * clampf((0.4 - t) / 0.05, 0.0, 1.0)
		var v: float = (signf(sin(TAU * 420.0 * t)) + signf(sin(TAU * 498.0 * t))) * 0.25 * env
		var s16 := int(v * 30000.0)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
