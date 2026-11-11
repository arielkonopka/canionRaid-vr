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
## Furia po wyprzedzeniu (użytkownik): bot wyprzedzony blisko (w poprzek
## < 6 m) z tym prawdopodobieństwem wpada w szał bez zderzenia; posiłki
## wzywa dopiero przy pierwszym kontakcie (_reinforced).
var overtake_chance := 0.25
var _reinforced := false
## Punktacja (ScoreKeeper w scenie jazdy): fazy ataku i obrażenia zadane.
## Liczone tylko w szale, ~10 Hz.
var _score_t := 0.0
var _attacking := false
var _atk_hit := false
var _atk_min_gap := INF
var _atk_tactic := ""
var _struct_before := 0.0
var _dmg_check_t := 0.0
var _prev_ahead := 0.0
## Daleko od gracza i bez szału bot jedzie "po szynie": zamrożony,
## przesuwany po torze z prędkością przepisową (bez fizyki - przy 20 autach
## Quest by nie wydolił). Fizyka wraca bliżej niż LOD_NEAR.
const LOD_FAR := 380.0
const LOD_NEAR := 320.0
var on_rail := false
## Waśń z innym botem (FeudDirector, inbox wasnie-na-autostradzie): cel
## pościgu zamiast gracza. null = gracz. Bez punktów i bez podbijania
## silnika - to nie jest pościg gracza.
var foe: StuntCar = null
## Żeton pościgu (xr_main, K = CHASE_TOKENS): fizykę w szale wymusza tylko
## bot z żetonem. Bez żetonu bot w szale może jechać po szynie (tempem
## pościgu) i dostaje żeton, gdy któryś się zwolni. Bez xr_main (testy)
## zawsze true.
var has_token := true
var _rage_on_player := false
## Pas na autostradzie (0 prawy, 1 lewy) - tryb Autostrada (TrafficZone).
var lane := 0
## Poziom szczegółowości z xr_main (BotLod.NEAR/MID/RAIL). -1 = bez BotLod
## (testy) - wtedy jak dawniej: szyna z progów LOD_FAR / LOD_NEAR.
var lod := -1
var _mid_acc := 0.0
var _mid_n := 0
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
## Profil prędkości okna, liczony raz przy odświeżeniu (było: dwie prawie
## identyczne pętle po słownikach co krok - _calm_speed i _curve_speed).
## Co PROF_STEP próbek: [dystans, limit² (m/s)², vc² przy 0,6 g, vc² przy 0,7 g].
var _prof := PackedFloat32Array()
const PROF_STEP := 4
const PROF_SPAN := 12            # próbki do kąta łuku (~12 m)
## Indeks najbliższej próbki z poprzedniego kroku (szukanie lokalne).
var _win_hint := 0
var _lights_on := false
var _window_timer := 0.0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_drive_step(delta)
	Perf.add("bot_ster", t0)


func _drive_step(delta: float) -> void:
	if car == null or track == null:
		return
	if _update_rail(delta):
		return
	if lod == BotLod.MID:
		# Dalej od gracza sterowanie ~30 Hz, wejścia trzymane między krokami.
		_mid_acc += delta
		_mid_n += 1
		if _mid_n % BotLod.MID_STEER_EVERY != 0:
			return
		delta = _mid_acc
	_mid_acc = 0.0
	_window_timer -= delta
	if _window_timer <= 0.0:
		_window_timer = 0.15
		_window = track.samples_from(dist - 15.0, WINDOW_AHEAD + 15.0)
		_build_profile()
		_win_hint = mini(15, _window.size() - 1)
	if _window.is_empty():
		return
	# Najbliższa próbka w oknie: krok od poprzedniej w stronę bliższej (auto
	# przesuwa się o < 1 próbkę na krok; było przeszukanie całego okna).
	var here := car.global_position
	var bi := clampi(_win_hint, 0, _window.size() - 1)
	var bd: float = (_window[bi]["pos"] as Vector3).distance_squared_to(here)
	for dir in [1, -1]:
		while bi + dir >= 0 and bi + dir < _window.size():
			var nd: float = (_window[bi + dir]["pos"] as Vector3).distance_squared_to(here)
			if nd >= bd:
				break
			bi += dir
			bd = nd
	_win_hint = bi
	var best: Dictionary = _window[bi]
	dist = float(best["dist"])

	_check_overtake(best, best["right"])
	_score_step(delta, best)
	if rage > 0.0:
		rage_time += delta
		# Waśń kończy dyrektor (feud_end) - przepisowa jazda gracza jej nie gasi.
		if _foe_valid():
			pass
		elif min_rage_time >= 0.0 and rage_time > min_rage_time and main and main.player_compliant():
			rage = maxf(rage - delta / calm_time, 0.0)
			if rage <= 0.0:
				_reinforced = false
				_rage_on_player = false
				if main and main.has_method("score_chase_close"):
					main.score_chase_close(car, "calmed")

	# Światła szału: zapis materiału tylko w szale albo przy wygaszaniu.
	if rage > 0.0 or _lights_on:
		car.set_rage_lights(rage * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)))
		_lights_on = rage > 0.0

	var right: Vector3 = best["right"]
	var w := float(best["width"])
	var lane_w := (w - 1.0) / 3.0
	var rel := car.global_position - (best["pos"] as Vector3)
	var offset := rel.dot(right)
	var target_off := lane_w                          # prawy pas
	if main and main._endless and main.track.autostrada:
		# Autostrada 2+2: osie pasów z HighwayGenerator (prawy 0,75 m od osi
		# jezdni, lewy -3,0 m) - 3-pasowe lane_w wąwozu jechałoby poboczem.
		target_off = main.hwy_lane_off(lane)
	var kmh := car.speed * 3.6
	var target_kmh := _calm_speed(kmh)
	if rage > 0.05 and _foe():
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
	var target := 200.0 / 3.6
	var i := 0
	while i < _prof.size():
		var k := _prof[i] - dist
		if k >= -2.0:
			var brake := 2.0 * 5.0 * maxf(k, 0.0)
			target = minf(target, sqrt(minf(_prof[i + 1], _prof[i + 2]) + brake))
		i += 4
	return target * 3.6


## Profil prędkości okna (_prof): limit i bezpieczna prędkość na łuku (pozioma
## krzywizna, przyczepność nawierzchni) - wspólne dla jazdy spokojnej (0,6 g)
## i szału (0,7 g).
func _build_profile() -> void:
	_prof.resize(0)
	for i in range(0, _window.size() - PROF_SPAN, PROF_STEP):
		var a0: Dictionary = _window[i]
		var a1: Dictionary = _window[i + PROF_SPAN]
		var lim := float(a0["limit"]) / 3.6
		var f0: Vector3 = (a0["fwd"] as Vector3) * Vector3(1, 0, 1)
		var f1: Vector3 = (a1["fwd"] as Vector3) * Vector3(1, 0, 1)
		var ang := f0.angle_to(f1)
		var vc2_calm := INF
		var vc2_rage := INF
		if ang > 0.01:
			var span := float(a1["dist"]) - float(a0["dist"])
			var grip: float = StuntTrack.SURFACES[a0["surface"]]["grip"]
			vc2_calm = 0.6 * grip * 9.8 * span / ang
			# 0,7 g (było 0,8): z BotDriveModel bot przyspiesza mocniej i przy 0,8 g
			# obracał się w łuku przy pełnym gazie (bot_rage_test 2026-11-09).
			vc2_rage = 0.7 * grip * 9.8 * span / ang
		_prof.append_array([float(a0["dist"]), lim * lim, vc2_calm, vc2_rage])


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
	var tgt := _foe()
	var prel := tgt.global_position - (best["pos"] as Vector3)
	var p_off := clampf(prel.dot(right), -lim, lim)
	var ahead := prel.dot(best["fwd"] as Vector3)     # >0: gracz przed botem
	var pk := tgt.speed * 3.6
	var tactic := _tactic
	if _foe_valid() and (tactic == "pincer" or tactic == "ambush"):
		tactic = "ram"                    # kleszcze i zasadzka - tylko na gracza
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
	var target := 400.0 / 3.6
	var i := 0
	while i < _prof.size():
		var k := _prof[i] - dist
		if k >= -2.0 and _prof[i + 3] < INF:
			target = minf(target, sqrt(_prof[i + 3] + 2.0 * 6.0 * maxf(k, 0.0)))
		i += 4
	return target * 3.6


## Jazda "po szynie" daleko od gracza. Zwraca true, gdy bot jest na
## szynie (fizyka i sterowanie pominięte).
func _update_rail(delta: float) -> bool:
	if main == null:
		return false
	var gap := absf(dist - float(main._last_safe_dist))
	# Z BotLod: szyna, gdy poziom RAIL (dystans albo budżet fizyki); bez
	# BotLod - progi LOD_FAR / LOD_NEAR jak dawniej.
	var want_rail := (lod == BotLod.RAIL) if lod >= 0 else gap >= LOD_FAR
	var want_phys := (lod != BotLod.RAIL) if lod >= 0 else gap < LOD_NEAR
	if not on_rail:
		if (rage > 0.0 and has_token) or not want_rail or car.wheels_on_ground < 4:
			return false
		on_rail = true
		_rail_v = maxf(car.speed, 5.0)
		var smp: Array = track.samples_from(dist, 1.0)
		if smp.is_empty():
			on_rail = false
			return false
		_lane_off = (car.global_position - track.to_global(smp[0]["pos"])).dot(smp[0]["right"])
		car.freeze = true
	elif want_phys or (rage > 0.0 and has_token):
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
	var v_goal := float(smp2[0]["limit"]) / 3.6
	if rage > 0.05 and player and not _foe_valid():
		# Szał bez żetonu: pościg poza wzrokiem - dogania gracza od tyłu.
		v_goal = clampf(player.speed + (12.0 if dist < float(main._last_safe_dist) else -5.0), 10.0, 70.0)
	_rail_v = move_toward(_rail_v, v_goal, 5.0 * delta)
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
		overtake_chance = float(gs.rage_overtake) / 100.0
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
		# Kontakt bot-bot: zgłasza bot o mniejszym instance_id (raz na parę).
		if b is StuntCar and (b as Node).has_node("Driver") and main and main.has_method("feud_contact") \
				and car.get_instance_id() < b.get_instance_id() \
				and (car.linear_velocity - (b as StuntCar).linear_velocity).length() > 1.0:
			main.feud_contact(car, b)
		return
	var rel_v := (car.linear_velocity - player.linear_velocity).length()
	if rel_v > 1.0:
		if main and main.has_method("feud_player_hit"):
			main.feud_player_hit(car)
		if rage < 0.5:
			print("Bot w szale drogowym!")
			# Gracz uderzył spokojnego bota - mandat, pościg bez punktów.
			enrage("player_hit")
		else:
			enrage()
		# Kontakt w pościgu; obrażenia zadane liczone chwilę później (fizyka
		# uszkodzeń dolicza je w kolejnych krokach).
		if main and main.has_method("score_contact"):
			main.score_contact(car)
		if _dmg_check_t <= 0.0:
			_struct_before = float(car.damage["structure"])
		_dmg_check_t = 0.2
		# Kontakt otwiera fazę ataku z trafieniem (sprawdzanie strefy jest
		# 10 Hz - inaczej wejście w strefę po zderzeniu kasowałoby trafienie).
		if not _attacking:
			_attacking = true
			_atk_min_gap = 0.0
			_atk_tactic = _tactic
		_atk_hit = true
		# Posiłki przy pierwszym kontakcie - także gdy szał zaczął się od
		# wyprzedzenia.
		if not _reinforced and reinforce and main:
			_reinforced = true
			main.call_reinforcements(car, 400.0)


## Wyprzedzenie: gracz był za botem, a jest przed nim, blisko w poprzek
## i szybszy. Losowo szał (bez posiłków - patrz _on_body_entered).
func _check_overtake(best: Dictionary, right: Vector3) -> void:
	if player == null or overtake_chance <= 0.0:
		return
	var rel := player.global_position - car.global_position
	var ahead := rel.dot(best["fwd"] as Vector3)
	var side := absf(rel.dot(right))
	if _prev_ahead < -1.0 and ahead >= 0.0 and side < 6.0 and player.speed > car.speed + 2.0 \
			and rage < 0.5 and randf() < overtake_chance:
		print("Bot wyprzedzony - furia drogowa!")
		enrage("overtake")
	_prev_ahead = ahead


## Wejście w szał (zderzenie albo wezwanie posiłków). Trąbi raz, przy
## wybuchu szału. Oszustwo: zdalnie sterowane auto nagle dostaje mocniejszy
## silnik - co najmniej 350 kW i nie słabszy niż auto gracza.
## Cel pościgu: bot z waśni albo gracz.
func _foe() -> StuntCar:
	return foe if _foe_valid() else player


func _foe_valid() -> bool:
	return foe != null and is_instance_valid(foe) and foe.visible


## Potyczka z innym botem (FeudDirector "skirmish"): szał na `other`, bez
## punktów i bez mocniejszego silnika.
func feud_with(other: StuntCar) -> void:
	foe = other
	rage = 1.0
	rage_time = 0.0
	if on_rail:
		_update_rail(0.0)
	if _horn:
		_horn.play()


## Koniec waśni: bot wraca do pościgu gracza, jeśli w nim był, inaczej spokój.
func end_feud() -> void:
	foe = null
	if not _rage_on_player:
		rage = 0.0


func enrage(origin := "self") -> void:
	foe = null
	_rage_on_player = true
	var fresh := rage < 0.5
	if fresh and main and main.has_method("score_chase_open"):
		main.score_chase_open(car, origin)
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
## Klakson: jeden dźwięk na grę (był generowany w GDScript dla każdego
## nowego bota - 8820 próbek przy każdym pojawieniu się).
static var _horn_stream: AudioStreamWAV
static func _make_horn() -> AudioStreamWAV:
	if _horn_stream == null:
		_horn_stream = _gen_horn()
	return _horn_stream


static func _gen_horn() -> AudioStreamWAV:
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



## Zdarzenia punktowane z perspektywy bota (tylko w szale, ~10 Hz):
## koniec fazy ataku (bot w strefie ataku przy graczu i z niej wychodzi -
## unik, gdy bez kontaktu i minął blisko) i obrażenia zadane przez gracza.
func _score_step(delta: float, best: Dictionary) -> void:
	if main == null or not main.has_method("score_end_attack"):
		return
	if _dmg_check_t > 0.0:
		_dmg_check_t -= delta
		if _dmg_check_t <= 0.0:
			var d := float(car.damage["structure"]) - _struct_before
			if d > 0.002:
				main.score_damage(car, d)
	if rage <= 0.05 or player == null:
		_attacking = false
		return
	_score_t -= delta
	if _score_t > 0.0:
		return
	_score_t = 0.1
	var rel := player.global_position - car.global_position
	var ahead := rel.dot(best["fwd"] as Vector3)
	var side := absf(rel.dot(best["right"] as Vector3))
	# Premie szeryfa (pościg za graczem, nie waśń z innym botem).
	if _foe() == player and main.has_method("score_chase_tick"):
		main.score_chase_tick(car, ahead, side, 0.1)
	# Odstęp boków aut w poprzek (szerokość auta ~1,8 m).
	var gap := maxf(side - 1.8, 0.0)
	var in_zone := absf(ahead) < 6.0 and gap < 3.0
	if in_zone and not _attacking:
		_attacking = true
		_atk_hit = false
		_atk_min_gap = INF
		_atk_tactic = _tactic
	if _attacking:
		if absf(ahead) < 4.0:
			_atk_min_gap = minf(_atk_min_gap, gap)
		if not in_zone:
			_attacking = false
			main.score_end_attack(car, _atk_hit, _atk_min_gap, _atk_tactic)
