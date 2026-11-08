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

## Parametry szału z menu "Szał drogowy botów" (GameSettings, czytane
## w _ready): ile sekund przepisowej jazdy gracza gasi szał, najkrótszy
## pościg po zderzeniu (dopiero potem przepisowa jazda uspokaja; <0 = szał
## nie mija nigdy), o ile km/h bot może przekroczyć ograniczenie (0 = bez
## limitu) i strategia.
var calm_time := 6.0
var min_rage_time := 10.0
var overspeed := 50.0
var strategy := "mixed"
## Strategie:
##   "block" - wyprzedza gracza innym pasem, zajeżdża mu drogę i gwałtownie
##             hamuje przed nim (impulsami co kilka sekund);
##   "ram"   - gwałtownie dojeżdża od tyłu i stuka w zderzak; gdy jest przed
##             graczem, zwalnia i zjeżdża z jego linii, żeby być za nim;
##   "pit"   - podjeżdża równolegle i uderza w tylny bok (manewr PIT);
##   "zigzag" - jedzie przed graczem od krawędzi do krawędzi, nie da się
##             go wyprzedzić;
##   "ambush" - wyprzedza, staje na poboczu i wyjeżdża graczowi przed maskę;
##   "pincer" - dwa boty w szale biorą gracza w kleszcze z obu boków
##             (bez partnera - jak "pit");
##   "mixed" - co 8-14 s losuje jedną z powyższych (domyślnie).
## Posiłki (rage_reinforce): gdy bot wpada w szał, boty w promieniu 400 m
## też wpadają.
const TACTICS := ["block", "ram", "pit", "zigzag", "ambush", "pincer"]
var reinforce := true
## Daleko od gracza i bez szału bot jedzie "po szynie": zamrożony,
## przesuwany po torze z prędkością przepisową (bez fizyki - przy 20 autach
## Quest by nie wydolił). Fizyka wraca bliżej niż LOD_NEAR.
const LOD_FAR := 380.0
const LOD_NEAR := 320.0
var on_rail := false
var _rail_v := 0.0
var _rail_acc := 0.0                   # szyna liczona 30 razy na sekundę, nie 240
var _lane_off := 0.0
var _side := 1.0                       # strona dla kleszczy/PIT (-1 lewa, 1 prawa)
var _tactic := "ram"
var _tactic_t := 0.0
var _brake_pulse := 0.0                # >0: trwa hamowanie przed graczem
var _brake_cd := 0.0
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
	if _update_rail(delta):
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
		if min_rage_time >= 0.0 and rage_time > min_rage_time and main and main.player_compliant():
			rage = maxf(rage - delta / calm_time, 0.0)

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
		var plan := _rage_plan(delta, best, right, w, lane_w, offset)
		target_off = plan.x
		# Limit szału: ograniczenie + przekroczenie z menu; łuki hamują zawsze.
		var cap := 400.0 if overspeed <= 0.0 else float(best["limit"]) + overspeed
		target_kmh = lerpf(target_kmh, clampf(plan.y, 0.0, minf(cap, _curve_speed())), rage)

	var fwd := -car.global_basis.z
	var head_err := fwd.signed_angle_to(best["fwd"], car.global_basis.y)
	car.steer = clampf(-(offset - target_off) * 0.22 - head_err * 2.5, -1.0, 1.0) \
			if car.wheels_on_ground > 0 else 0.0
	car.throttle = 1.0 if kmh < target_kmh - 1.0 else (0.3 if kmh < target_kmh + 2.0 else 0.0)
	car.brake = clampf((kmh - target_kmh - 4.0) * 0.12, 0.0, 1.0)
	if _brake_pulse > 0.0 and rage > 0.5:
		# Hamowanie przed graczem: ostro, jak przy "nauczce".
		car.throttle = 0.0
		car.brake = 0.9

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


## Plan szału na ten krok: x = docelowe przesunięcie w poprzek drogi,
## y = docelowa prędkość [km/h] (przed limitem z menu).
func _rage_plan(delta: float, best: Dictionary, right: Vector3, w: float,
		lane_w: float, offset: float) -> Vector2:
	_tactic_t -= delta
	if strategy == "mixed":
		if _tactic_t <= 0.0:
			var nxt: String = TACTICS[randi() % TACTICS.size()]
			while nxt == _tactic:
				nxt = TACTICS[randi() % TACTICS.size()]
			_tactic = nxt
			_tactic_t = randf_range(8.0, 14.0)
	else:
		_tactic = strategy
	_brake_pulse = maxf(_brake_pulse - delta, 0.0)
	_brake_cd = maxf(_brake_cd - delta, 0.0)
	var lim := w * 0.5 - 1.0
	var prel := player.global_position - (best["pos"] as Vector3)
	var p_off := clampf(prel.dot(right), -lim, lim)
	var ahead := prel.dot(best["fwd"] as Vector3)     # >0: gracz przed botem
	var pk := player.speed * 3.6
	var tactic := _tactic
	if tactic == "pincer" and (main == null or main.rage_partner(car) == null):
		tactic = "pit"                    # kleszcze wymagają drugiego bota
	if tactic == "pit" or tactic == "pincer":
		_brake_pulse = 0.0
		# Pas obok gracza (strona stała dla bota); przy kleszczach drugi bot
		# bierze przeciwną.
		var sd := _side
		if tactic == "pincer":
			var partner: StuntCar = main.rage_partner(car)
			sd = -1.0 if car.get_instance_id() < partner.get_instance_id() else 1.0
		var beside := clampf(p_off + sd * lane_w * 0.9, -lim, lim)
		if ahead > 4.0:
			return Vector2(beside, pk + 25.0)           # dogania bokiem
		if ahead > -1.0:
			# Przód bota przy tylnym kole gracza: skręt w bok auta.
			var squeeze := 1.9 if tactic == "pincer" else 1.2
			return Vector2(clampf(p_off + sd * squeeze, -lim, lim), pk + 6.0)
		return Vector2(beside, pk - 15.0)               # wyprzedził - zwalnia
	if tactic == "zigzag":
		_brake_pulse = 0.0
		if ahead > -6.0:
			var side_z := 1.0 if p_off < 0.0 else -1.0
			return Vector2(clampf(p_off + side_z * lane_w * 1.2, -lim, lim), pk + 30.0)
		# Przed graczem: zygzak przez całą szerokość, tempo gracza.
		var zz := sin(Time.get_ticks_msec() * 0.0013 + float(car.get_instance_id() % 7)) * lim * 0.85
		return Vector2(zz, pk + (2.0 if -ahead > 10.0 else -4.0))
	if tactic == "ambush":
		_brake_pulse = 0.0
		if ahead > -60.0 and not (ahead < 0.0 and car.speed < 3.0):
			# Wyprzedza z dużym zapasem.
			var side_a := 1.0 if p_off < 0.0 else -1.0
			return Vector2(clampf(p_off + side_a * lane_w * 1.2, -lim, lim), pk + 45.0)
		if -ahead > 28.0:
			# Czeka na poboczu.
			return Vector2(_side * lim, 0.0)
		# Gracz blisko: wyjeżdża mu przed maskę.
		return Vector2(p_off, maxf(pk * 0.4, 25.0))
	if tactic == "ram":
		_brake_pulse = 0.0
		if ahead > -3.0:
			# Za graczem: gwałtowny dojazd i stuknięcie (szybciej niż gracz).
			return Vector2(p_off, pk + (35.0 if ahead > 12.0 else 18.0))
		# Przed graczem: zwalnia i zjeżdża z jego linii, żeby być za nim.
		return Vector2(clampf(p_off + (lane_w if p_off < 0.0 else -lane_w), -lim, lim), pk - 25.0)
	# "block": wyprzedzanie sąsiednim pasem, zajechanie drogi, hamowanie.
	if ahead > -6.0:
		var side := 1.0 if p_off < 0.0 else -1.0
		return Vector2(clampf(p_off + side * lane_w * 1.2, -lim, lim), pk + 30.0)
	# Przed graczem: wjeżdża na jego tor, trzyma się tuż przed nim i co
	# kilka sekund gwałtownie hamuje.
	var gap := -ahead
	if gap < 18.0 and absf(offset - p_off) < 1.2 and _brake_cd <= 0.0:
		_brake_pulse = 1.2
		_brake_cd = randf_range(3.0, 5.0)
	return Vector2(p_off, pk + (5.0 if gap > 12.0 else -3.0))


## Prędkość bezpieczna na łukach w oknie (bez znaków ograniczenia).
func _curve_speed() -> float:
	var target := 400.0
	for i in range(0, _window.size() - 12, 4):
		var a0: Dictionary = _window[i]
		var k := float(a0["dist"]) - dist
		if k < -2.0:
			continue
		var a1: Dictionary = _window[i + 12]
		var f0: Vector3 = (a0["fwd"] as Vector3) * Vector3(1, 0, 1)
		var f1: Vector3 = (a1["fwd"] as Vector3) * Vector3(1, 0, 1)
		var ang := f0.angle_to(f1)
		if ang > 0.01:
			var span := float(a1["dist"]) - float(a0["dist"])
			var grip: float = StuntTrack.SURFACES[a0["surface"]]["grip"]
			var vc := sqrt(0.8 * grip * 9.8 * span / ang)
			target = minf(target, sqrt(vc * vc + 2.0 * 6.0 * maxf(k, 0.0)) * 3.6)
	return target


## Jazda "po szynie" daleko od gracza. Zwraca true, gdy bot jest na
## szynie (fizyka i sterowanie pominięte).
func _update_rail(delta: float) -> bool:
	if main == null:
		return false
	var gap := absf(dist - float(main._last_safe_dist))
	if not on_rail:
		if rage > 0.0 or gap < LOD_FAR or car.wheels_on_ground < 4:
			return false
		on_rail = true
		_rail_v = maxf(car.speed, 5.0)
		var smp: Array = track.samples_from(dist, 1.0)
		if smp.is_empty():
			on_rail = false
			return false
		_lane_off = (car.global_position - track.to_global(smp[0]["pos"])).dot(smp[0]["right"])
		car.freeze = true
	elif gap < LOD_NEAR or rage > 0.0:
		# Z powrotem fizyka, z prędkością, jaką miał na szynie.
		on_rail = false
		car.freeze = false
		var fwd := -car.global_basis.z
		car.linear_velocity = fwd * _rail_v
		car.angular_velocity = Vector3.ZERO
		for w in car.wheels:
			w.omega = _rail_v / car.wheel_radius
		return false
	# Daleko od gracza 30 Hz wystarcza (szukanie na trasie jest drogie).
	_rail_acc += delta
	if _rail_acc < 1.0 / 30.0:
		return true
	delta = _rail_acc
	_rail_acc = 0.0
	# Prędkość przepisowa w tym miejscu, płynnie.
	var smp2: Array = track.samples_from(dist, 1.0)
	if smp2.is_empty():
		return true
	_rail_v = move_toward(_rail_v, float(smp2[0]["limit"]) / 3.6, 3.0 * delta)
	dist += _rail_v * delta
	var xf: Transform3D = track.transform_at_distance(dist)
	var lane := clampf(_lane_off, -float(smp2[0]["width"]) * 0.5 + 1.0, float(smp2[0]["width"]) * 0.5 - 1.0)
	car.global_transform = Transform3D(xf.basis, xf.origin + xf.basis.x * lane + xf.basis.y * 0.62)
	return true


func _ready() -> void:
	_side = -1.0 if get_instance_id() % 2 == 0 else 1.0
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		calm_time = float(gs.rage_calm)
		min_rage_time = float(gs.rage_time)
		overspeed = float(gs.rage_overspeed)
		strategy = gs.rage_strategy
		reinforce = gs.rage_reinforce
	_tactic = TACTICS[randi() % TACTICS.size()] if strategy == "mixed" else strategy
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
		var fresh := rage < 0.5
		enrage()
		if fresh:
			print("Bot w szale drogowym!")
			if reinforce and main:
				main.call_reinforcements(car, 400.0)


## Wejście w szał (zderzenie albo wezwanie posiłków). Trąbi raz, przy
## wybuchu szału. Oszustwo: zdalnie sterowane auto nagle dostaje mocniejszy
## silnik - co najmniej 350 kW i nie słabszy niż auto gracza.
func enrage() -> void:
	var fresh := rage < 0.5
	rage = 1.0
	rage_time = 0.0
	if on_rail:
		_update_rail(0.0)                 # rage > 0 - zejście z szyny
	if fresh:
		if _horn:
			_horn.play()
		var cheat := maxf(350.0, player.engine_power_kw if player else 0.0)
		if car.engine_power_kw < cheat:
			car.apply_engine("petrol", cheat)


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
