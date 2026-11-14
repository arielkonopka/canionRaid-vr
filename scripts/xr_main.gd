extends Node3D

## Scena główna: uruchamia OpenXR, czyta wejście i przekazuje je samochodowi.
##
## Dwa tryby:
##   jazda   - kamera w kokpicie (VR) albo za autem / w kokpicie (PC)
##   lot     - swobodne latanie wokół toru, do oglądania geometrii
##
## Gogle - jazda:
##   prawy spust     - gaz
##   lewy spust      - hamulec
##   lewy drążek     - skręt
##   lewy grip       - hamulec ręczny (grip ręki z hamulcem)
##   prawy grip      - wsteczny, trzymany (grip ręki z gazem; wchodzi
##                     dopiero po zatrzymaniu auta - ochrona skrzyni)
##   (strony gazu/hamulca i drążka kierownicy - menu Sterowanie)
##   A / X           - bieg w górę / w dół (skrzynia manualna)
##   B               - postaw auto z powrotem na torze
##   Y krótko        - kontrola trakcji (TCS/ASR) wł./wył.
##   Y przytrzymany  - wycentruj widok (usiądź prosto i przytrzymaj 0,8 s)
##   Menu (lewy)     - powrót do ekranu tytułowego
##   klik prawego drążka - tryb swobodnego lotu (podgląd toru)
## Gogle - lot:
##   prawy drążek ↔  - obrót w poziomie (yaw)
##   prawy drążek ↕  - lot do przodu / do tyłu (tam, gdzie patrzysz)
##   prawy grip + prawy drążek ↕ - pochylenie widoku (pitch)
##   lewy drążek     - ↔ ruch w bok, ↕ góra / dół
##   prawy spust     - przyspieszenie
##
## PC - jazda:
##   W/S lub strzałki góra/dół - gaz / hamulec
##   A/D lub strzałki lewo/prawo - skręt
##   Spacja - ręczny, E / Q - bieg w górę / w dół (manual)
##   T - kontrola trakcji wł./wył.
##   R - reset na tor, C - kokpit / kamera z tyłu, F - tryb lotu, Esc - menu
##   Pad: RT gaz, LT hamulec, lewa gałka skręt, B ręczny, RB/LB biegi,
##        Y reset, Back kontrola trakcji, Start menu
## PC - lot:
##   strzałki - ruch, Q/E - dół/góra, Shift - szybciej,
##   prawy przycisk myszy + ruch - rozglądanie, F - powrót do jazdy

const TITLE_SCENE := "res://scenes/title.tscn"

enum Mode { DRIVE, FLY }
## Przejazd: czeka na ruszenie, jedzie (zegar), po mecie (wyniki).
enum Race { READY, RACING, FINISHED, WORKSHOP, EXPLODING, REPLAY }

@export var fly_speed: float = 14.0
@export var boost_multiplier: float = 4.0
@export var mouse_sensitivity: float = 0.003
## Od której odległości od startu toru stawiany jest samochód (linia startu).
var start_distance: float = StuntTrack.START_DISTANCE
## Ile metrów poniżej jezdni auto uznajemy za spadnięte.
@export var fall_depth: float = 5.0
## Ile metrów przed miejscem upadku auto wraca na tor. Musi wystarczyć
## na rozbieg do przeszkody, na której gracz właśnie poległ.
@export var respawn_back: float = 35.0

@onready var origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var car: StuntCar = $Car
@onready var _demo_track: StuntTrack = $Track
## Tor, po którym jedziemy: StuntTrack (pokazowa) albo EndlessTrack
## (bez końca) - oba mają to samo API, dlatego bez typu.
var track
var _endless := false
## Wąwóz: bez dźwigów - koniec jazdy, gdy auto rozbite.
var _canyon := false
## Pozostałe dźwigi; -1 = bez limitu.
var cranes_left := -1
var _max_dist := 0.0
var _horizon: Node3D

# --- warsztat (trasa bez końca) ---
## GameSettings (autoload; w testach headless może go nie być) - jedno
## wyszukanie zamiast 14 (przegląd chmury D6).
@onready var _gs: Node = get_node_or_null("/root/GameSettings")
var _tier := 0                      # próg mocy (GameSettings.POWER_TIERS)
var _next_ws := {}                  # najbliższy warsztat przed autem
var _ws_xf: Transform3D
var _ws_prev_side := -1.0
var _ws_options: Array = []         # [{type, kw, label}] ostatnia = bez zmian
var _ws_selected := 0
var _ws_stick_ready := true
var _ws_label: Label3D
var _ws_follow: GazeFollow
var _ws_done_stop := -INF           # linia postoju ostatnio obsłużonego warsztatu
var _next_station := {}
var _refueling := false
var _lateral := 0.0                 # przesunięcie auta od osi toru [m], + w prawo
var _track_hud: TrackHud
## Panel HUD (mapka, kolumna postępu, znaki, napisy) - dziecko auta, na prawo
## od kierownicy, obrócony twarzą do oczu kierowcy. Wcześniej stał nad
## kierownicą i zasłaniał zegary (użytkownik 2026-11-09).
var _hud_panel: Node3D
## Środek mapki względem oczu kierowcy (car.seat): w prawo, w dół, przed.
## Mapka 17°..29° w prawo, kolumna postępu do ~37°, wszystko 4°..16° pod
## linią wzroku - nad środkiem deski, z dala od osłony zegarów (do ~17°).
## Liczone od fotela, więc tak samo w sedanie i w concept carze.
const HUD_FROM_EYES := Vector3(0.27, -0.11, -0.62)

# --- boty: puste, zdalnie sterowane auta (trasa bez końca) ---
## Liczba aut na trasie (użytkownik): 4 na start, +1 co 2 odcinki do 20,
## potem +1 co 100 odcinków. Dalekie boty bez szału jadą "po szynie"
## (BotDriver, bez fizyki), więc tylu naraz jest do udźwignięcia.
static func bot_limit(section: int) -> int:
	var n := 4 + maxi(section - 1, 0) / 2
	if n <= 20:
		return n
	var at20 := 33                       # odcinek, na którym limit doszedł do 20
	return 20 + (section - at20) / 100
var _bots: Array[StuntCar] = []
var _bot_timer := 6.0
var _bot_rng := RandomNumberGenerator.new()
## Ograniczenie prędkości w miejscu gracza [km/h].
var current_limit := 100.0

# --- ćwierknięcie przy nowym odcinku ---
var _chirp: AudioStreamPlayer
var _last_section := 1
var _race_label_t := 0.0
var _race_label_state := -1
## Początek bieżącego odcinka (premia za średnią prędkość - ScoreKeeper.
## section_done): czas jazdy i dystans bramy.
var _sec_t0 := 0.0
var _sec_d0 := 0.0

# --- utrata życia: eksplozja i odjazd kamery ---
const CINE_MOVE := 2.2               # odjazd kamery [s]
const CINE_TOTAL := 4.5              # cała scena wybuchu [s]
var _cine_t := 0.0
var _cine_from: Transform3D
var _cine_to: Transform3D
var _cine_reason := ""
var _grace_t := 0.0                  # ochrona po odrodzeniu [s]

# --- lusterko wsteczne ---
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _mirror_frame := 0

# --- nagroda za potrącenie innych aut (kusi, ale bot w szale oszukuje) ---
## Punkty za furię drogową (scripts/score_keeper.gd, logika z wątku
## w chmurze): zastępują dawne "-20 s za potrącenie bota" (decyzja
## użytkownika). Zdarzenia zgłaszają BotDriver i _update_bots.
var score := ScoreKeeper.new()
var _popups: Array[Label3D] = []
var _popup_t: Array[float] = []
var _beep: AudioStreamPlayer
var _beep_fine: AudioStreamPlayer
var _last_hit := {}                  # bot -> czas ostatniej kary (bez kar z jednego zderzenia)

var _xr_ready: bool = false
var _radio: CarRadio
var _radio_label: Label3D
var _pause: PauseMenu
var _mode: Mode = Mode.DRIVE
var _cockpit_on_pc: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _chase_xf: Transform3D

## Ostatnie miejsce na torze, gdzie auto stało wszystkimi kołami na jezdni.
var _last_safe_dist: float = 0.0

var race_state: Race = Race.READY
var race_time := 0.0
var _new_record := false
var _finish_xf: Transform3D        # linia mety w układzie globalnym, -Z = kierunek jazdy
var _prev_finish_side := -1.0
var _race_label: Label3D           # zegar w kokpicie
var _result_label: Label3D         # wyniki po mecie
var _track_check_timer: float = 0.0
var _fallen_time: float = 0.0

## Y w goglach: krótko = TCS, przytrzymany = centrowanie widoku.
const RECENTER_HOLD := 0.8
var _shift_ready := true      # drążek biegów wrócił do środka
var _y_held := -1.0          # czas trzymania Y, -1 = nie wciśnięty


func _ready() -> void:
	# Origin przesuwamy w _process, nie w kroku fizyki - interpolacja fizyki
	# by go tylko szarpała.
	origin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	# GameSettings to autoload; w testach headless może go nie być.
	var gs := _gs
	Bench.load_config()
	if gs:
		if Bench.resolution > 0:
			gs.xr_resolution = Bench.resolution     # pomiar: rozdzielczość z bench.cfg
		gs.apply_to_car(car)
		gs.apply_game_speed()
		_xr_ready = gs.enable_xr(get_viewport())
	if _xr_ready:
		_attach_dummy_hands()
		# Gracz jako cały manekin (użytkownik 2026-11-12) - tułów, nogi na
		# pedałach, ramiona do kontrolerów.
		if PlayerDummy.available():
			_player_dummy = PlayerDummy.new()
			_player_dummy.setup(car, left_hand, right_hand)
	if _xr_ready:
		right_hand.button_pressed.connect(_on_xr_button.bind(true))
		left_hand.button_pressed.connect(_on_xr_button.bind(false))
		left_hand.button_released.connect(_on_left_released)
		print("OpenXR zainicjalizowany - tryb VR.")
	else:
		push_warning("OpenXR niedostępny - tryb podglądu na płasko.")
		# XRCamera3D dziedziczy po Camera3D, więc bez XR działa jak zwykła kamera.
		camera.current = true

	if gs:
		gs.apply_shadows($Sun as DirectionalLight3D)
	elif not Bench.on("shadows"):
		($Sun as DirectionalLight3D).shadow_enabled = false
	car.landed.connect(_on_car_landed)
	car.wrecked.connect(_on_car_wrecked)
	car.body_entered.connect(_on_player_hit)
	_chirp = AudioStreamPlayer.new()
	_chirp.stream = _make_chirp()
	_chirp.volume_db = -16.0
	add_child(_chirp)
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 2026
	_horizon = Scenery.horizon(hrng)
	add_child(_horizon)
	track = _demo_track
	if gs and gs.track_mode in ["endless", "canyon", "autostrada"]:
		# Trasa bez końca zamiast pokazowej: te same materiały, nowy losowy tor.
		var et := EndlessTrack.new()
		et.name = "EndlessTrack"
		if Bench.active():
			et.seed_value = Bench.seed_value       # powtarzalny przejazd pomiarowy
		et.road_material = _demo_track.road_material
		et.pillar_material = _demo_track.pillar_material
		et.canyon = gs.track_mode == "canyon"
		et.autostrada = gs.track_mode == "autostrada"
		_canyon = et.canyon
		if et.autostrada:
			# Setki km: przesuwanie początku świata (float32, docs/AUTOSTRADA.md
			# pkt 3) i bak na ~100 km (użytkownik 2026-11-09: "zasięg 100 km,
			# żeby można było pominąć stację"; stacje co ~20 km).
			_origin = WorldOrigin.new()
			for n in [car, origin]:
				n.add_to_group(WorldOrigin.GROUP)
			car.tank_kwh = StuntCar.TANK_KWH_DEFAULT * 4.0
		_demo_track.queue_free()
		add_child(et)
		track = et
		_endless = true
	if not _endless:
		_finish_xf = track.transform_at_distance(track.finish_distance())
	_build_race_hud()
	restart_race()
	_set_mode(Mode.DRIVE)


# --------------------------------------------------------------------------
# Wejście
# --------------------------------------------------------------------------

## Przyciski w goglach (układ użytkownika, 2026-11-08):
##   A - ABS wł./wył. (po mecie: jeszcze raz; w warsztacie: wybór)
##   B - ESP,  X - TCS,  Y krótko - ograniczenie skrętu (przytrzymany:
##   centrowanie widoku). Klik prawego drążka: nowe auto (strata życia),
##   klik lewego: klakson - wpędza w szał wszystkie auta w promieniu
##   HORN_RADIUS (użytkownik 2026-11-09, zamiast wolnej kamery - ta została
##   pod F na klawiaturze). Biegi: drugi drążek (patrz _physics_process).
func _on_xr_button(button: String, is_right: bool) -> void:
	# Pomiar: kontrolery leżą obok gogli i potrafią wysyłać zdarzenia
	# (powrót do menu przerywał przejazd) - wejście ignorowane.
	if Bench.active():
		return
	if race_state == Race.REPLAY:
		# Spust albo B pomija powtórkę; reszta przycisków nic nie robi.
		if button == "trigger_click" or (is_right and button == "by_button"):
			# Nie w pierwszych chwilach: gracz po uderzeniu puszcza i znów
			# wciska gaz na spuście (przegląd PR #84).
			if _rp_fade > REPLAY_FADE + REPLAY_SKIP_DELAY:
				_rp_skip = true
		return
	if _pause and _pause.is_open():
		# W pauzie: lewe menu wraca do jazdy, A albo spust zatwierdza w menu
		# (jak na ekranie tytułowym - użytkownik 2026-11-09: niespójne).
		if not is_right and button == "menu_button":
			_pause.try_resume()
		elif (is_right and button == "ax_button") or button == "trigger_click":
			_pause.accept()
		elif is_right and button == "by_button":
			_pause.cancel()
		return
	if button == "trigger_click":
		# Spust w warsztacie zatwierdza (w jeździe spust to gaz/hamulec).
		if race_state == Race.WORKSHOP and _ws_arm_t <= 0.0:
			workshop_choose(_ws_selected)
		return
	match [is_right, button]:
		[true, "ax_button"]:          # A
			if race_state == Race.FINISHED:
				restart_race()
			elif race_state == Race.WORKSHOP:
				if _ws_arm_t <= 0.0:
					workshop_choose(_ws_selected)
			else:
				toggle_assist("abs")
		[true, "by_button"]:          # B
			toggle_assist("esp")
		[false, "ax_button"]:         # X
			toggle_assist("tcs")
		[false, "by_button"]:         # Y - akcja dopiero po puszczeniu albo przytrzymaniu
			_y_held = 0.0
		[false, "menu_button"]:
			# Pauza z radiem (wcześniej: od razu ekran tytułowy - wyjście
			# jest teraz w menu pauzy). Po końcu jazdy - ekran tytułowy, jak
			# mówi napis (użytkownik 2026-11-10: pauza na napisie końca gry
			# - napisy nachodziły na siebie).
			if race_state == Race.FINISHED:
				_back_to_title()
			else:
				_set_paused(true)
		[true, "primary_click"]:
			# Nowe auto na kołach = strata życia (na trasie bez końca).
			if _mode != Mode.DRIVE:
				pass
			elif _endless and race_state == Race.RACING:
				lose_life("nowe auto")
			else:
				_use_crane()
		[false, "primary_click"]:
			player_horn()


func _on_left_released(button: String) -> void:
	if button != "by_button" or _y_held < 0.0:
		return
	if _y_held < RECENTER_HOLD:
		toggle_assist("steer")
	_y_held = -1.0


## Przełącza pomoc w trakcie jazdy i zapamiętuje wybór - ekran tytułowy
## pokaże go przy następnej wizycie. Stan widać na kontrolkach w prędkościomierzu
## (świeci = wyłączona, Gauges.set_assist).
func toggle_assist(which: String) -> void:
	var key: String = {"abs": "abs_enabled", "tcs": "tcs_enabled", "esp": "esp_enabled",
			"steer": "steer_assist"}[which]
	car.set(key, not car.get(key))
	var gs := _gs
	if gs:
		if which == "steer":
			# Włączenie wraca do trybu z auta (Wł. albo Wg przyczepności).
			gs.steer_assist = ("grip" if car.steer_grip else true) if car.steer_assist else false
		else:
			gs.set(key, car.get(key))
		gs.save_settings()


## Przełącza kontrolę trakcji w trakcie jazdy i zapamiętuje wybór -
## ekran tytułowy pokaże go przy następnej wizycie.
func toggle_tcs() -> void:
	toggle_assist("tcs")


## Pauza: drzewo sceny stoi (fizyka, boty), działa menu pauzy, radio
## i XROrigin (śledzenie głowy i kontrolerów).
func _set_paused(on: bool) -> void:
	if _pause == null or Bench.active():
		return
	get_tree().paused = on
	if on:
		_pause.open()
	else:
		_pause.close()


func _back_to_title() -> void:
	get_tree().paused = false
	if Bench.active():
		print("BENCH: pominięty powrót do menu")
		return
	get_tree().change_scene_to_file(TITLE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if Bench.active():
		return
	if race_state == Race.WORKSHOP:
		if event.is_action_pressed("ui_up"):
			_ws_move(-1)
		elif event.is_action_pressed("ui_down"):
			_ws_move(1)
		elif event.is_action_pressed("ui_accept"):
			workshop_choose(_ws_selected)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if race_state == Race.FINISHED:
					_back_to_title()
				else:
					_set_paused(true)
				get_viewport().set_input_as_handled()
				return
			KEY_F:
				_set_mode(Mode.FLY if _mode == Mode.DRIVE else Mode.DRIVE)
			KEY_H:
				player_horn()
			KEY_R:
				if race_state == Race.FINISHED:
					restart_race()
				else:
					_use_crane()
			KEY_ENTER:
				if race_state == Race.FINISHED:
					restart_race()
			KEY_C:
				_cockpit_on_pc = not _cockpit_on_pc
			KEY_E:
				if _mode == Mode.DRIVE:
					car.shift_up()
			KEY_Q:
				if _mode == Mode.DRIVE:
					car.shift_down()
			KEY_T:
				toggle_tcs()
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_Y:
				_use_crane()
			JOY_BUTTON_A:
				if race_state == Race.FINISHED:
					restart_race()
			JOY_BUTTON_RIGHT_SHOULDER:
				car.shift_up()
			JOY_BUTTON_LEFT_SHOULDER:
				car.shift_down()
			JOY_BUTTON_START:
				_back_to_title()
			JOY_BUTTON_BACK:
				toggle_tcs()

	if _xr_ready or _mode != Mode.FLY:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed \
				else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.4)
		origin.rotation = Vector3(_pitch, _yaw, 0.0)


## Krzywa drążka kierownicy: martwa strefa, potem |x|^1,6 - mały ruch daje
## mały, precyzyjny skręt, pełne wychylenie nadal pełny. Na koniec czułość
## z ustawień (100% = bez zmian; 50% = najwyżej połowa skrętu).
const STICK_DEADZONE := 0.08
const STICK_EXPO := 1.6

func _stick_curve(x: float) -> float:
	var a := absf(x)
	if a < STICK_DEADZONE:
		return 0.0
	a = (a - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
	var sens := 1.0
	var expo := STICK_EXPO
	var gs := _gs
	if gs:
		sens = gs.stick_sensitivity / 100.0
		expo = gs.stick_expo
	return signf(x) * clampf(pow(a, expo) * sens, 0.0, 1.0)


## Żółte dłonie manekina na kontrolerach (gracz też jest manekinem;
## użytkownik 2026-11-12). Siatki z tools/prepare_dummy_hands.py: -Z od
## nadgarstka do kłykci, +Y kciuk, zero w środku dłoni - jak póza "grip"
## kontrolera. Ułożenie do oceny w goglach (bez cieni, lekkie).
var _player_dummy: PlayerDummy

## Wibracje kontrolerów (Haptics - logika, tu tylko dane auta i wysyłka).
var _haptics := Haptics.new()
func _update_haptics(delta: float) -> void:
	var gs := _gs
	_haptics.strength = float(gs.vibration) if gs else 0.5
	_haptics.road_texture = bool(gs.road_texture) if gs else false
	var gas_right: bool = gs == null or gs.gas_hand == "right"
	var hold := []
	if gs and gs.steer_stick == "wheel":
		hold = [left_hand.get_float("grip") > 0.5, right_hand.get_float("grip") > 0.5]
	var slip := 0.0
	var rough := 0
	var on := 0
	for w in car.wheels:
		if not w.contact:
			continue
		on += 1
		if Haptics.ROUGH.has(w.surface):
			rough += 1
		slip = maxf(slip, w.slip)
	var s := {"speed": car.speed, "hit_j": float(car.last_hit.get("j", 0.0)),
			"hit_ms": int(car.last_hit.get("ms", 0)), "abs": car.abs_active,
			"tcs": car.tcs_active, "slip": slip if car.throttle > 0.3 else 0.0,
			"rough": float(rough) / maxf(on, 1.0),
			"brake_hand": 0 if gas_right else 1, "gas_hand": 1 if gas_right else 0, "holding": hold}
	for p in _haptics.step(delta, s):
		var c: XRController3D = left_hand if int(p[0]) == 0 else right_hand
		c.trigger_haptic_pulse("haptic", 0.0, float(p[1]), float(p[2]), 0.0)



func _attach_dummy_hands() -> void:
	for pair in [[left_hand, "L"], [right_hand, "R"]]:
		var path := "res://models/dummy/dummy_hand_%s.obj" % pair[1]
		if not ResourceLoader.exists(path):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "DummyHand"
		mi.mesh = load(path)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(pair[0] as Node3D).add_child(mi)


## Kierownica w powietrzu (użytkownik 2026-11-12: "dłonie w powietrzu, jako
## alternatywne sterowanie"): AirWheel z pozycji kontrolerów i gripów,
## wieniec w kokpicie obraca się 1:1.
var _air := AirWheel.new()
func _air_wheel_steer(gs: Node) -> float:
	var fr: Array = car.steering_frame()
	if fr.is_empty():
		# Auto bez kierownicy w kokpicie (nie powinno się zdarzyć) - drążek
		# zamiast cichego "nie skręca" (przegląd PR #73).
		car.steering_wheel_deg = NAN
		return _stick_curve(right_hand.get_vector2("primary").x)
	_air.half_range = float(gs.wheel_range)
	var hands := [[left_hand.global_position, left_hand.get_float("grip") > 0.5],
			[right_hand.global_position, right_hand.get_float("grip") > 0.5]]
	var s := _air.update(hands, fr[0], fr[1], fr[2], get_physics_process_delta_time())
	car.steering_wheel_deg = _air.angle
	return s


func _read_drive_input() -> void:
	var thr := 0.0
	var brk := 0.0
	var steer_in := 0.0
	var hb := 0.0
	if _xr_ready:
		# Układ z ustawień: ręka gazu, drążek kierownicy, grip ręcznego.
		var gs := _gs
		var gas_right: bool = gs == null or gs.gas_hand == "right"
		var gas_c := right_hand if gas_right else left_hand
		var brake_c := left_hand if gas_right else right_hand
		var air: bool = gs != null and gs.steer_stick == "wheel"
		var steer_c := left_hand if (gs == null or gs.steer_stick == "left") else right_hand
		thr = gas_c.get_float("trigger")
		brk = brake_c.get_float("trigger")
		if air:
			steer_in = _air_wheel_steer(gs)
		else:
			steer_in = _stick_curve(steer_c.get_vector2("primary").x)
			car.steering_wheel_deg = NAN
		# Drugi drążek: biegi (w górę = wyżej). Jedno wychylenie = jeden bieg,
		# kolejny dopiero po powrocie drążka do środka. Kierownica w powietrzu:
		# biegi prawym drążkiem.
		var shift_c := right_hand if (air or steer_c == left_hand) else left_hand
		var sy: float = shift_c.get_vector2("primary").y
		if absf(sy) < 0.3:
			_shift_ready = true
		elif _shift_ready and absf(sy) > 0.75 and _mode == Mode.DRIVE \
				and race_state != Race.WORKSHOP:
			_shift_ready = false
			if sy > 0.0:
				car.shift_up()
			else:
				car.shift_down()
		if air:
			# Gripy trzymają kierownicę: ręczny - lewy drążek w dół, wsteczny -
			# hamulec na postoju (automat), jak bez gogli.
			hb = clampf(-left_hand.get_vector2("primary").y * 1.25 - 0.25, 0.0, 1.0)
			car.dedicated_reverse = false
			car.reverse_request = false
		else:
			# Ręczny: grip ręki z hamulcem. Wsteczny: grip ręki z gazem
			# (wchodzi dopiero po zatrzymaniu auta - pilnuje tego skrzynia).
			hb = brake_c.get_float("grip")
			car.dedicated_reverse = true
			car.reverse_request = gas_c.get_float("grip") > 0.5
	else:
		if Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_B):
			hb = 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			thr = 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			brk = 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			steer_in -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			steer_in += 1.0
		# Pad, jeśli jest podłączony.
		thr = maxf(thr, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT))
		brk = maxf(brk, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT))
		var stick := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		if absf(stick) > 0.12:
			steer_in += _stick_curve(stick)
	car.throttle = clampf(thr, 0.0, 1.0)
	car.brake = clampf(brk, 0.0, 1.0)
	car.steer = clampf(steer_in, -1.0, 1.0)
	car.handbrake = clampf(hb, 0.0, 1.0)


# --------------------------------------------------------------------------
# Pętla
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Powtórka wypadku: świat stoi (boty wyłączone, bez dobudowy trasy
	# i przesunięć świata), auto i boty z zapisu.
	if race_state == Race.REPLAY:
		_replay_physics(delta)
		return
	_check_origin_shift()
	# Dobudowa trasy pierwsza: błąd skryptu w dalszych funkcjach przerywa
	# resztę kroku i trasa przestawała rosnąć ("trasa się skończyła" także
	# na prostej, 2026-11-11 - hipoteza chmury).
	if _endless:
		_keep_track_ahead(delta)
	if _mode == Mode.DRIVE and not Bench.active():
		_read_drive_input()
	else:
		car.throttle = 0.0
		car.brake = 0.0
		car.steer = 0.0
		car.handbrake = 1.0
	_grace_t = maxf(_grace_t - delta, 0.0)
	if _xr_ready:
		_update_haptics(delta)
	if _player_dummy:
		_player_dummy.update(car.throttle, car.brake, delta, car.clutch_pedal())
	_watch_incident(delta)
	update_race(delta)
	_record_replay()
	_knock_cones()
	_check_river_fall()
	var t0 := Time.get_ticks_usec()
	if race_state != Race.FINISHED:
		_watch_track(delta)
	Perf.add("trasa", t0)
	t0 = Time.get_ticks_usec()
	if _endless:
		_update_bots(delta)
		Perf.add("boty_mgr", t0)
		t0 = Time.get_ticks_usec()
		_update_oncoming(delta)
		Perf.add("naprzeciw", t0)
	else:
		Perf.add("boty_mgr", t0)


## Most nad rzeką (etap 3a): ziemia pod mostem ma dziurę na rzekę - wariant
## shadera z discard tylko w pobliżu mostu (na Queście discard wyłącza
## wczesny test głębi dla całej ziemi). Spadnięcie z mostu = upadek
## (kolizja ziemi to płaszczyzna y = 0 - auto "leżałoby" nad wodą).
const _GROUND_SH := preload("res://shaders/ground.gdshader")
const _GROUND_RIVER_SH := preload("res://shaders/ground_river.gdshader")
var _river := {}                      # {c: Vector2, t: Vector2, hw, road_y} albo pusty
func _update_river() -> void:
	if not (_endless and track.autostrada and track.structures):
		return
	var mat := ($Ground/GroundMesh as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	if mat == null:
		return
	var p := _last_safe_dist
	var found := {}
	for z in track.structures.zones(p - 800.0, p + 1500.0):
		if int(z["structure"]) == 2:
			found = z
			break
	if found.is_empty():
		if mat.shader != _GROUND_SH:
			mat.shader = _GROUND_SH
		_river = {}
		return
	var r0 := float(found["start"]) + StructurePlan.BRIDGE_BANK
	var r1 := r0 + float(found["river"])
	var mid := (r0 + r1) * 0.5
	var xf: Transform3D = track.transform_at_distance(mid)
	var fwd := (-xf.basis.z * Vector3(1, 0, 1)).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var smp: Dictionary = track.sample_at(mid)
	var w := 11.25 if smp.is_empty() else float(smp["width"])
	var c := xf.origin - right * ((w + TrackGenerator.HIGHWAY_MEDIAN) * 0.5)
	if mat.shader != _GROUND_RIVER_SH:
		mat.shader = _GROUND_RIVER_SH
	mat.set_shader_parameter("river_c", Vector2(c.x, c.z))
	mat.set_shader_parameter("river_t", Vector2(fwd.x, fwd.z))
	mat.set_shader_parameter("river_hw", (r1 - r0) * 0.5)
	mat.set_shader_parameter("river_reach", StuntTrack.RIVER_REACH)
	_river = {"c": Vector2(c.x, c.z), "t": Vector2(fwd.x, fwd.z), "hw": (r1 - r0) * 0.5, "road_y": xf.origin.y}


func _check_river_fall() -> void:
	_warm_river_shader()
	if _river.is_empty() or race_state != Race.RACING:
		return
	if _in_river(car.global_position):
		lose_life("upadek")
	# Boty i auta z naprzeciwka z fizyką, które spadły z mostu, "stały" na
	# niewidzialnej płaszczyźnie kolizji nad wodą (przegląd PR #101) - do
	# puli; bot w pościgu liczy się jak rozbity.
	for b in _bots.duplicate():
		var bd: BotDriver = _drv(b)
		if bd and not bd.on_rail and _in_river(b.global_position):
			if bd.rage > 0.05:
				score_chase_close(b, "wreck")
			_bots.erase(b)
			_retire_bot(b, true)
	for o in _oncoming.duplicate():
		if o.loose and is_instance_valid(o.car) and _in_river(o.car.global_position):
			_pool_oncoming(o)


func _in_river(p: Vector3) -> bool:
	var rv := Vector2(p.x, p.z) - (_river["c"] as Vector2)
	var t: Vector2 = _river["t"]
	return absf(rv.dot(t)) < float(_river["hw"]) and absf(rv.dot(Vector2(-t.y, t.x))) < StuntTrack.RIVER_REACH \
			and p.y < float(_river["road_y"]) - 0.4


## Wariant ziemi z dziurą kompiluje się przy pierwszym rysowaniu - na
## Queście zacięcie klatki ~1 km przed pierwszym mostem (przegląd PR #101).
## Maleńka siatka z tym shaderem przed kamerą przez pierwsze klatki jazdy.
var _river_warm: MeshInstance3D
var _river_warm_n := 0
func _warm_river_shader() -> void:
	if _river_warm_n > 5 or not (_endless and track.autostrada):
		return
	_river_warm_n += 1
	if _river_warm == null:
		_river_warm = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.01, 0.01)
		_river_warm.mesh = q
		var m := ShaderMaterial.new()
		m.shader = _GROUND_RIVER_SH
		_river_warm.material_override = m
		_river_warm.position = Vector3(0, 0, -0.5)
		camera.add_child(_river_warm)
	elif _river_warm_n > 5:
		_river_warm.queue_free()


## Tryb Autostrada, etap 2: sceneria z planu (HighwayPlan.biome_blend
## w miejscu auta) - paleta ziemi (ground.gdshader, przejście 2,8 km),
## horyzont biomu (wymieniany przy zmianie biomu, 1,5-2,5 km od auta)
## i morze po lewej w biomie nadmorskim.
## Palety ziemi biomów: HighwayScenery.BIOME_GROUND.
var _biome := ""
var _biome_key := ""
var _sea: MeshInstance3D
func _update_biome() -> void:
	if not _endless or not track.autostrada or track.plan == null:
		return
	var bl: Dictionary = track.plan.biome_blend(_last_safe_dist)
	var a: String = bl["a"]
	var b: String = bl["b"]
	var t: float = bl["t"]
	var key := "%s|%s|%.2f" % [a, b, t]
	if key != _biome_key:
		_biome_key = key
		var mat := ($Ground/GroundMesh as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		if mat:
			var pa: Array = HighwayScenery.BIOME_GROUND.get(a, HighwayScenery.BIOME_GROUND["meadow"])
			var pb: Array = HighwayScenery.BIOME_GROUND.get(b, HighwayScenery.BIOME_GROUND["meadow"])
			mat.set_shader_parameter("grass_a", pa[0])
			mat.set_shader_parameter("grass_b", pa[1])
			mat.set_shader_parameter("dirt", pa[2])
			mat.set_shader_parameter("stripes_a", pa[3])
			mat.set_shader_parameter("b_grass_a", pb[0])
			mat.set_shader_parameter("b_grass_b", pb[1])
			mat.set_shader_parameter("b_dirt", pb[2])
			mat.set_shader_parameter("stripes_b", pb[3])
			mat.set_shader_parameter("biome_t", t)
	# Horyzont: biom dominujący (t < 0,5 -> a).
	if a != _biome:
		_biome = a
		var hrng := RandomNumberGenerator.new()
		hrng.seed = hash([a, int(_last_safe_dist / 1000.0)])
		if _horizon:
			_horizon.queue_free()
		_horizon = Scenery.horizon(hrng, a)
		add_child(_horizon)
		print("BIOM: %s (%.1f km)" % [a, _last_safe_dist / 1000.0])
	# Morze po lewej (za jezdnią z naprzeciwka) przez cały biom nadmorski.
	# W przejściu brzeg powoli przysuwa się z daleka (sea_k: udział morza).
	var sea_k := (1.0 - t) if a == "seaside" else (t if b == "seaside" else 0.0)
	var sea_on := sea_k > 0.02
	if sea_on and _sea == null:
		_sea = MeshInstance3D.new()
		_sea.name = "Sea"
		var pm := PlaneMesh.new()
		pm.size = Vector2(4000.0, 4000.0)
		_sea.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/ocean.gdshader")
		_sea.material_override = m
		_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_sea)
	if _sea:
		_sea.visible = sea_on
		if sea_on:
			var s: Dictionary = track.nearest_sample(car.global_position)
			if not s.is_empty():
				var c: Vector3 = track.to_global(s["pos"])
				var r: Vector3 = ((s["right"] as Vector3) * Vector3(1, 0, 1)).normalized()
				# Brzeg ~90 m za lewą krawędzią jezdni z naprzeciwka.
				var shore := float(s["width"]) * 1.5 + TrackGenerator.HIGHWAY_MEDIAN + 90.0 + (1.0 - sea_k) * 1800.0
				var mid := c - r * (shore + 2000.0)
				_sea.global_transform = Transform3D(Basis(Vector3.UP, atan2(r.x, r.z)), Vector3(mid.x, 0.05, mid.z))


## Tryb Autostrada: przesuwanie początku świata (WorldOrigin), na początku
## kroku fizyki - przed sterowaniem i botami. Węzły w grupie
## WorldOrigin.GROUP (kawałki trasy, auto, boty, auta z naprzeciwka,
## wybuchy, XROrigin, menu w powietrzu, deszcz) jadą o -s; tu poprawki
## zapamiętanych pozycji w świecie. Dystanse (dist, szyna botów) są odporne.
var _origin: WorldOrigin
func _check_origin_shift() -> void:
	if _origin == null:
		return
	var s := _origin.check(car.global_position)
	if s == Vector3.ZERO:
		return
	_origin.apply(s, get_tree().get_nodes_in_group(WorldOrigin.GROUP))
	_ws_xf.origin -= s
	_chase_xf.origin -= s
	_cine_from.origin -= s
	_cine_to.origin -= s
	_rec.shift(s)
	if _traffic_audio:
		_traffic_audio.shift(s)
	if _rain:
		_rain.restart()
	print("ŚWIAT: przesunięty o %s (razem %d, offset %.0f, %.0f m)" % [str(s), _origin.shifts, _origin.offset_x, _origin.offset_z])


## Diagnostyka "dziwnych wypadków" (użytkownik 2026-11-09: auto nagle stanęło
## po puszczeniu gazu, dachowało na prostej przy niedużej prędkości). Przy
## opóźnieniu > 1,5 g albo przechyle > 60° jedna linia INCYDENT do logu:
## stan auta, pedały, miejsce na trasie i najmocniejszy kontakt nadwozia
## (ścieżka obiektu). Najwyżej raz na 3 s.
var _inc_v := Vector3.ZERO
var _inc_cool := 0.0
var _inc_hist: Array[Vector3] = []
func _watch_incident(delta: float) -> void:
	var v: Vector3 = car.linear_velocity
	# Opóźnienie poziome (bez składowej pionowej - inaczej każde lądowanie
	# i wjazd na rampę wyglądały jak "hamowanie 3-100 g"), z okna ~0,1 s
	# (pojedyncze kroki fizyki szumią). Log z jazdy 2026-11-09.
	_inc_hist.append(Vector3(v.x, 0.0, v.z))
	if _inc_hist.size() > 12:
		_inc_hist.pop_front()
	var h0: Vector3 = _inc_hist[0]
	var dec := (h0.length() - Vector3(v.x, 0.0, v.z).length()) / maxf(delta * (_inc_hist.size() - 1), 1e-4) / 9.81
	var v_before := h0.length()
	_inc_v = v
	_inc_cool = maxf(_inc_cool - delta, 0.0)
	var tilt: float = rad_to_deg(acos(clampf(car.global_basis.y.y, -1.0, 1.0)))
	if _inc_cool > 0.0 or (dec < 1.5 and tilt < 60.0) or _mode != Mode.DRIVE:
		return
	_inc_cool = 3.0
	var s: Dictionary = track.nearest_sample(car.global_position) if track else {}
	var hit: Dictionary = car.last_hit
	var hit_txt := "brak"
	if not hit.is_empty() and Time.get_ticks_msec() - int(hit["ms"]) < 1000:
		hit_txt = "%s impuls %.0f N·s w punkcie %s" % [hit["what"], hit["j"], str((hit["at"] as Vector3).snapped(Vector3.ONE * 0.1))]
	var wheels := ""
	for w in car.wheels:
		wheels += "%s(%.0f%%)" % ["K" if w.contact else "-", w.slip * 100.0]
	var near_bot := INF
	for b in _bots:
		near_bot = minf(near_bot, (b as Node3D).global_position.distance_to(car.global_position))
	print("INCYDENT: %s %.1f g, przechył %.0f°, %.0f -> %.0f km/h, gaz %.2f hamulec %.2f ręczny %.2f skręt %.2f, bieg %d, %.0f obr., koła %s, kontakt: %s, odcinek %d, dystans %.0f m, %s, nawierzchnia %s, najbliższy bot %.0f m, ABS %s TCS %s ESP %s" % [
			"HAMOWANIE" if dec >= 1.5 else "PRZECHYŁ", dec, tilt, v_before * 3.6, v.length() * 3.6,
			car.throttle, car.brake, car.handbrake, car.steer, car.gear, car.engine_rpm, wheels, hit_txt,
			_last_section, float(s.get("dist", -1.0)), "autostrada" if s.get("meta", {}).has("highway") else "",
			str(s.get("surface", "?")), near_bot, car.abs_active, car.tcs_active, car.get("esp_active")])


## Gracz jedzie zgodnie z przepisami: prędkość nie większa niż ograniczenie
## + 5 km/h tolerancji. Tylko to uspokaja boty w szale drogowym.
func player_compliant() -> bool:
	return absf(car.speed) * 3.6 <= current_limit + 5.0


## Pula botów: zbudowanie StuntCar (siatka sedana z wgnieceniami) kosztuje
## ~170 ms jednej klatki na Queście (log 2026-11-09, `boty_mgr` maks 171 ms)
## - szarpnięcie przy każdym nowym bocie. Auta budowane raz (BOT_POOL_WARM
## na starcie jazdy, w czasie wczytywania), usuwany bot wraca do puli:
## naprawiony, ukryty, wyłączony z fizyki (PROCESS_MODE_DISABLED zdejmuje
## ciało z przestrzeni fizyki).
## 14 (było 6): na autostradzie bywa 11 botów naraz - bench 2026-11-11
## pokazywał skok ~170 ms co 30-40 s przy każdym nowym aucie ponad pulę.
## Auta z naprzeciwka - osobna pula, rozgrzewana tak samo (ONCOMING_POOL_WARM).
const BOT_POOL_WARM := 14
const ONCOMING_POOL_WARM := 8
var _bot_pool: Array[StuntCar] = []


func _new_bot_car() -> StuntCar:
	var bot := StuntCar.new()
	bot.name = "Bot%d_%d" % [Time.get_ticks_msec(), _bot_pool.size() + _bots.size()]
	bot.is_bot = true
	bot.TIRE_SUBSTEPS = 2
	bot.simple_drive = true            # BotDriveModel (inbox boty-naped-i-poziomy)
	bot.ray_probe = true
	add_child(bot)
	bot.add_to_group(WorldOrigin.GROUP)
	# Zdalnie sterowane auta mają mocny silnik (250 kW) - w szale muszą
	# realnie dogonić gracza (przy 130 kW zostawały w tyle).
	bot.apply_engine("petrol", 250)
	return bot


## Model z epoki dla bota / auta z naprzeciwka: losowany z wag
## CarStyles.STYLES[..]["bot_weight"] ([wąwóz, autostrada]) ziarnem
## _bot_rng (odrodzenie odtwarza ten sam rozkład).
func _pick_style() -> String:
	var col := 1 if track and track.get("autostrada") == true else 0
	var total := 0.0
	for k in CarStyles.STYLES:
		total += float(CarStyles.STYLES[k]["bot_weight"][col])
	var r := _bot_rng.randf() * total
	for k in CarStyles.STYLES:
		r -= float(CarStyles.STYLES[k]["bot_weight"][col])
		if r < 0.0:
			return k
	return "sedan"


## Bot w modelu: fabryczny napęd i zawieszenie modelu, moc botów bez zmian
## (250 kW - chmura sprawdziła symulacją, że każdy model jest sterowny).
func _bot_style(bot: StuntCar, st: String) -> void:
	if bot.style == st:
		return
	var d: Dictionary = CarStyles.STYLES[st]
	bot.drive_layout = d["drive"]
	bot.apply_style(st)
	bot.apply_suspension_preset(d["suspension"])


## Wybuch auta `c` (gracz, bot, auto ze scenki) w kolorze jego lakieru.
func _explode(c: StuntCar) -> void:
	Perf.mark("explosion")
	var boom := Explosion.new()
	boom.paint = c._paint_mat.albedo_color if c._paint_mat else Color(0.8, 0.6, 0.2)
	boom.ignore = [car] + _bots
	add_child(boom)
	boom.add_to_group(WorldOrigin.GROUP)
	boom.global_position = c.global_position


## Kierowca bota (BotDriver) - referencja w aucie zamiast get_node("Driver")
## (~25 miejsc, część w komparatorach sortowania).
static func _drv(b: StuntCar) -> BotDriver:
	return b.driver as BotDriver


func _warm_bot_pool() -> void:
	while _bot_pool.size() + _bots.size() < BOT_POOL_WARM:
		var b := _new_bot_car()
		_park_bot(b)
		_bot_pool.append(b)
	if track and track.get("autostrada") == true:
		while _oncoming_pool.size() + _oncoming.size() < ONCOMING_POOL_WARM:
			var c := _new_oncoming_car()
			c.visible = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
			c.global_position = Vector3(0.0, -500.0, 0.0)
			_oncoming_pool.append(c)


## Auto z naprzeciwka: kinematyczne (jazda po szynie), bez kierowcy.
func _new_oncoming_car() -> StuntCar:
	var c := StuntCar.new()
	c.name = "Oncoming%d_%d" % [Time.get_ticks_msec(), _oncoming_pool.size() + _oncoming.size()]
	c.is_bot = true
	add_child(c)
	c.add_to_group(WorldOrigin.GROUP)
	c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	c.freeze = true
	return c


func _take_bot() -> StuntCar:
	var b: StuntCar = _bot_pool.pop_back() if not _bot_pool.is_empty() else _new_bot_car()
	b.process_mode = Node.PROCESS_MODE_INHERIT
	b.visible = true
	b.freeze = false
	b.repair()
	b.fuel = 1.0
	b.TIRE_SUBSTEPS = 2
	# Auto po ekstremiście (przegląd chmury 2026-11-13): zwykła moc botów
	# i zgaszone długie, także gdy zniknął w trakcie mrugania.
	if b.engine_type != "petrol" or absf(b.engine_power_kw - 250.0) > 0.5:
		b.apply_engine("petrol", 250)
	b.set_high_beam(0.0)
	return b


func _park_bot(b: StuntCar) -> void:
	b.visible = false
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.process_mode = Node.PROCESS_MODE_DISABLED
	b.global_position = Vector3(0.0, -500.0, 0.0)


## Bot znika (za graczem, wybuch, restart odcinka): kierowca usunięty, auto
## do puli.
func _retire_bot(b: StuntCar, dead := false) -> void:
	# Przed oddaniem do puli (ten sam węzeł = ten sam instance_id przy
	# ponownym użyciu - remove_bot musi przyjść przed add_bot).
	_feud_events(feud.remove_bot(b.get_instance_id(), race_time, dead))
	var drv := b.get_node_or_null("Driver")
	b.driver = null
	if drv:
		b.remove_child(drv)
		drv.queue_free()
	_park_bot(b)
	_bot_pool.append(b)


## Waśnie między botami (FeudDirector, inbox wasnie-na-autostradzie,
## użytkownik: "furia drogowa, także między botami"): gangi z kolorem,
## potyczki tylko w zasięgu wzroku gracza i tylko boty z fizyką, najwyżej
## MAX_FEUDS naraz (budżet fizyki Questa). Uderzenie gracza w bota
## w potyczce = sojusz przeciw graczowi.
const GANGS := 3
const MAX_FEUDS := 2
## Żetony pościgu (odpowiedź chmury, outbox 2026-11-10-noc-agent-lokalny
## pkt 4): wspólne dla szału na gracza i waśni. Fizykę w szale wymusza
## tylko bot z żetonem (budżet fizyki Questa); reszta w szale jedzie po
## szynie i czeka na wolny żeton. Gdyby miasto okazało się droższe
## w renderze - zmniejszyć do 3.
const CHASE_TOKENS := 4
## Waśń gaśnie, gdy strona jest poza stożkiem / dalej niż 1,5 x NEAR_R
## dłużej niż tyle sekund.
const FEUD_OOS_MAX := 2.0
var _feud_oos := {}                  # instance_id -> czas poza wzrokiem [s]
var feud := FeudDirector.new()
var _bot_gang := {}                  # instance_id -> gang
var _feud_order := {}                # instance_id -> indeks w kolejności (dist)
var _feud_update_t := 0.0


## Kolor gangu (klucz z GameSettings.PAINTS), stały w całej jeździe
## (na autostradzie "odcinek" zmienia się co ~1 km - kolory skakałyby).
var _gang_seed := 0
func _gang_paint(g: int) -> String:
	var keys: Array = GameSettings.PAINTS.keys()
	return keys[(g * 3 + _gang_seed) % keys.size()]


func _bot_by_id(id: int) -> StuntCar:
	for b in _bots:
		if is_instance_valid(b) and b.get_instance_id() == id:
			return b
	return null


## Żetony pościgu: posiadacze zachowują żeton, dopóki są w szale albo
## waśni; wolne dostają najbliżsi graczowi.
func _assign_tokens() -> void:
	var held := 0
	var want := []
	for b in _bots:
		var drv: BotDriver = _drv(b)
		if not (drv.rage > 0.0 or feud.in_feud(b.get_instance_id())):
			drv.has_token = false
		elif drv.has_token:
			held += 1
		else:
			want.append(b)
	want.sort_custom(func(a, b): return absf(_drv(a).dist - _last_safe_dist) \
			< absf(_drv(b).dist - _last_safe_dist))
	for b in want:
		if held >= CHASE_TOKENS:
			break
		_drv(b).has_token = true
		held += 1


func _free_tokens() -> int:
	var held := 0
	for b in _bots:
		if _drv(b).has_token:
			held += 1
	return CHASE_TOKENS - held


## Czy auto może zniknąć - gracz go nie widzi (głowa, lusterko). Wołane
## przed każdym oddaniem auta do puli poza wybuchem (zlecenie boty-znikanie:
## "nie powinny znikać tak na widoku"); widoczne zostaje i próbujemy
## w następnym kroku.
func _can_vanish(pos: Vector3) -> bool:
	return not TrafficZone.visible(camera.global_position, -camera.global_basis.z,
			-car.global_basis.z, pos)


## Bot w zasięgu potyczki: z fizyką, bliżej niż `r` (domyślnie NEAR_R
## 120 m) i w stożku widzenia gracza.
func _in_sight(b: StuntCar, r := BotLod.NEAR_R) -> bool:
	var drv: BotDriver = _drv(b)
	if drv.lod == BotLod.RAIL or absf(drv.dist - _last_safe_dist) > r:
		return false
	return TrafficZone.visible(camera.global_position, -camera.global_basis.z, -car.global_basis.z, b.global_position)


func _feud_count() -> int:
	var n := 0
	for b in _bots:
		if feud.in_feud(b.get_instance_id()) and feud.target_of(b.get_instance_id()) != FeudDirector.PLAYER:
			n += 1
	return n / 2


## Skan par (4 Hz, z _update_bot_lod): wyprzedzenia sąsiadów w kolejności
## na trasie, wrogowie obok siebie, wygaszanie waśni poza wzrokiem.
func _feud_scan() -> void:
	var t0 := Time.get_ticks_usec()
	var now := race_time
	var phys: Array = []
	for b in _bots:
		var drv: BotDriver = _drv(b)
		var id := b.get_instance_id()
		# Waśń, której strona jest poza wzrokiem (stożek, 1,5 x NEAR_R)
		# dłużej niż FEUD_OOS_MAX, gaśnie; żeton wraca do puli.
		if feud.in_feud(id) and feud.target_of(id) != FeudDirector.PLAYER:
			if _in_sight(b, BotLod.NEAR_R * 1.5):
				_feud_oos.erase(id)
			else:
				_feud_oos[id] = float(_feud_oos.get(id, 0.0)) + 0.25
				if float(_feud_oos[id]) > FEUD_OOS_MAX:
					_feud_oos.erase(id)
					feud.calm(id)
					drv.end_feud()
		else:
			_feud_oos.erase(id)
		if drv.lod != BotLod.RAIL:
			phys.append(b)
	phys.sort_custom(func(a, b): return _drv(a).dist < _drv(b).dist)
	# W odcinku "rest" (reżyser napięcia) nowe waśnie nie startują.
	var room := _feud_count() < MAX_FEUDS and _free_tokens() >= 2 and not seg_calm()
	var order := {}
	for i in range(phys.size()):
		var a: StuntCar = phys[i]
		var ida := a.get_instance_id()
		order[ida] = i
		if not room:
			continue
		var sa := _in_sight(a)
		# Wyprzedzenie: para zamieniła się kolejnością od poprzedniego skanu.
		if i > 0:
			var p: StuntCar = phys[i - 1]
			var idp := p.get_instance_id()
			if _feud_order.has(ida) and _feud_order.has(idp) and int(_feud_order[ida]) < int(_feud_order[idp]):
				_feud_events(feud.on_overtake(ida, idp, now, sa and _in_sight(p)))
		for j in [i + 1, i + 2]:
			if j >= phys.size():
				break
			var c: StuntCar = phys[j]
			var dd := absf(_drv(c).dist - _drv(a).dist)
			if dd < FeudDirector.NEAR_SPARK_R:
				_feud_events(feud.on_near(ida, c.get_instance_id(), 0.25, now, sa and _in_sight(c)))
	_feud_order = order
	_feud_update_t -= 0.25
	if _feud_update_t <= 0.0:
		_feud_update_t = 1.0
		_feud_events(feud.update(now))
	Perf.add("feud", t0)


## Zdarzenia dyrektora -> gra.
func _feud_events(evs: Array) -> void:
	for ev in evs:
		match ev["kind"]:
			"skirmish":
				var a := _bot_by_id(int(ev["a"]))
				var b := _bot_by_id(int(ev["b"]))
				# Potyczka potrzebuje żetonu dla każdej strony bez żetonu.
				var need := 0
				for x in [a, b]:
					if x and not _drv(x).has_token:
						need += 1
				if a and b and need > _free_tokens():
					feud.calm(int(ev["a"]))
					feud.calm(int(ev["b"]))
					continue
				if a and b:
					for x in [a, b]:
						_drv(x).has_token = true
					_drv(a).feud_with(b)
					if feud.target_of(int(ev["b"])) == int(ev["a"]):
						_drv(b).feud_with(a)
					print("Waśń: gang %d na gang %d" % [int(_bot_gang.get(int(ev["a"]), -1)), int(_bot_gang.get(int(ev["b"]), -1))])
				if ev.get("provoked", false) and int(ev.get("points", 0)) > 0:
					_score_pay(score.award_free("feud", int(ev["points"]), race_time, "PROWOKACJA"))
			"alliance":
				# Uczestnicy potyczki mają żetony; nowi członkowie gangu
				# dołączają tylko na wolnych, reszta zostaje spokojna.
				for id in ev["ids"]:
					var bb := _bot_by_id(int(id))
					if bb == null:
						continue
					var bd: BotDriver = _drv(bb)
					if not bd.has_token and _free_tokens() > 0:
						bd.has_token = true
					if bd.has_token:
						bd.enrage("alliance")
					else:
						feud.calm(int(id))
				_show_popup("SOJUSZ!", true)
				print("Waśń: SOJUSZ przeciw graczowi (%d aut)" % (ev["ids"] as Array).size())
			"feud_end":
				var e := _bot_by_id(int(ev["id"]))
				if e:
					_drv(e).end_feud()
			"feud_wreck":
				if ev.get("provoked", false) and int(ev.get("points", 0)) > 0:
					_score_pay(score.award_free("feud_wreck", int(ev["points"]), race_time, "WRAK Z WAŚNI"))


## Kontakt dwóch botów (zgłasza bot o mniejszym instance_id).
func feud_contact(a: StuntCar, b: StuntCar) -> void:
	_feud_events(feud.on_contact(a.get_instance_id(), b.get_instance_id(), race_time,
			_in_sight(a) and _in_sight(b)))


## Gracz uderzył bota (przed jego enrage) - sojusz, jeśli bot był w potyczce.
func feud_player_hit(bot: StuntCar) -> void:
	_feud_events(feud.on_contact(FeudDirector.PLAYER, bot.get_instance_id(), race_time, true))


## Poziomy szczegółowości botów (BotLod, ~4 Hz): NEAR pełne opony
## (2 podkroki) i sterowanie co krok, MID 1 podkrok i sterowanie co 4. krok,
## RAIL szyna. Budżet aut z fizyką BOT_PHYS_BUDGET (NEAR zawsze ma fizykę).
const BOT_PHYS_BUDGET := 8
var _lod_t := 0.0
var _lod_prev := PackedInt32Array()
func _update_bot_lod(delta: float) -> void:
	_lod_t -= delta
	if _lod_t > 0.0 or _bots.is_empty():
		return
	_lod_t = 0.25
	_assign_tokens()
	var dists := PackedFloat32Array()
	var raging := []
	for b in _bots:
		var drv: BotDriver = _drv(b)
		dists.append(absf(drv.dist - _last_safe_dist))
		raging.append(drv.has_token or drv.persona == "extremist")
	if _lod_prev.size() != _bots.size():
		_lod_prev = PackedInt32Array()
	var lv := BotLod.assign(dists, raging, _lod_prev, BOT_PHYS_BUDGET)
	_lod_prev = lv
	for i in range(_bots.size()):
		var b: StuntCar = _bots[i]
		var drv: BotDriver = _drv(b)
		drv.lod = lv[i]
		b.TIRE_SUBSTEPS = 2 if lv[i] == BotLod.NEAR else 1
	_feud_scan()


## Bot "ekstremista" (inbox bot-ekstremista): co km losowanie
## (ExtremistBrain.spawn_chance_per_km), pojawia się 350-500 m za graczem
## poza wzrokiem, lewym pasem ~200 km/h; najwyżej jeden. Punkty: wyprzedził
## bez kontaktu - za odstęp boków; rozbity w 10 s od kontaktu z graczem - 500.
var _extremist: StuntCar
var _x_km := 3
var _x_contact_t := -1e9
var _x_min_gap := INF
var _x_behind := true
var _x_passes := 0
func _update_extremist() -> void:
	if not (_endless and track.autostrada) or race_state != Race.RACING:
		return
	if _extremist and not (is_instance_valid(_extremist) and _bots.has(_extremist)):
		_extremist = null
	if _extremist == null:
		var km := int(_last_safe_dist / 1000.0)
		if km > _x_km:
			_x_km = km
			# Losowanie co km zostaje, ale nie w odcinku "rest" (reżyser napięcia).
			if _bot_rng.randf() < ExtremistBrain.spawn_chance_per_km(float(km)) and not seg_calm():
				_spawn_extremist()
		return
	var drv: BotDriver = _drv(_extremist)
	var s := drv.dist - _last_safe_dist
	# Okno 15 m: przy różnicy ~150 km/h i sterowaniu 30 Hz (LOD MID) bot
	# przeskakiwał wąskie okno i premia przepadała.
	if absf(s) < 15.0:
		var lat := absf((_extremist.global_position - car.global_position).dot(car.global_basis.x)) - 1.8
		_x_min_gap = minf(_x_min_gap, maxf(lat, 0.0))
	if _x_behind and s > 6.0:
		_x_behind = false
		if race_time - _x_contact_t > 10.0 and _x_min_gap < INF:
			var pts := ExtremistBrain.pass_points(_x_min_gap)
			_score_pay(score.award_free("extremist_pass", pts, race_time, "PRZEPUŚCIŁEŚ EKSTREMISTĘ"))
			_x_passes += 1
	if s > 800.0 and _can_vanish(_extremist.global_position):
		_bots.erase(_extremist)
		_retire_bot(_extremist)
		_extremist = null


func _spawn_extremist() -> void:
	var d := _last_safe_dist - _bot_rng.randf_range(350.0, 500.0)
	var xf: Transform3D = track.transform_at_distance(d)
	if not _can_vanish(xf.origin + xf.basis.x * hwy_lane_off(1)):
		return
	var n := _bots.size()
	_spawn_bot(d, 1, 200.0)
	if _bots.size() == n:
		return
	var b: StuntCar = _bots[-1]
	var drv: BotDriver = _drv(b)
	drv.persona = "extremist"
	drv.brain = ExtremistBrain.new()
	feud.remove_bot(b.get_instance_id(), race_time, false)   # nie należy do gangów
	b.apply_engine("petrol", ExtremistBrain.engine_kw(car.engine_power_kw))
	_extremist = b
	_x_contact_t = -1e9
	_x_min_gap = INF
	_x_behind = true
	print("EKSTREMISTA: pojawia się %.0f m za graczem" % (_last_safe_dist - d))


## Kod odcinka i zdarzenia (SegmentCode + SegmentEvents, etap 1 urozmaiceń;
## inbox urozmaicenia-plan-i-kod-odcinka). Kod ukryty przed graczem - log.
var segments: SegmentEvents
func _update_segments(delta: float) -> void:
	if not (_endless and track.autostrada) or race_state != Race.RACING:
		return
	_works_traffic()
	if segments == null:
		segments = SegmentEvents.new(track.segcode, self, track.plan_seed)
	var t0 := Time.get_ticks_usec()
	segments.step(delta)
	Perf.add("odcinki", t0)


## Przejechanie pachołków i słupków przekroju (etap 2): tylko w strefie,
## auto gracza (boty omijają je pasami). Stuknięcie w głośniku auta.
var cones_hit := 0
var x_cones_hit := 0                  # pachołki przewrócone przez ekstremistę (test)
func _knock_cones() -> void:
	if not (_endless and track.autostrada and track.sections) or race_state != Race.RACING:
		return
	var d := _last_safe_dist
	# Gracz tylko w strefie (transform_at_distance + knock_items co krok).
	if not track.sections.zone_at(d).is_empty():
		var xf: Transform3D = track.transform_at_distance(d)
		var x := (car.global_position - xf.origin).dot(xf.basis.x)
		var side := signf(car.linear_velocity.dot(xf.basis.x))
		var n: int = track.knock_items(d, x, 0.95, absf(car.speed), side)
		if n > 0:
			cones_hit += n
			if car.get_node_or_null("Audio"):
				car.get_node("Audio").thud(0.15)
	# Ekstremista i boty w szale jadą po swojemu, także zamkniętym pasem
	# przez pachołki (plan szału goni gracza, nie zna przekrojów) - niech
	# lecą. Tylko auta z fizyką w strefie (kilka naraz, tanio).
	for b in _bots:
		var bd: BotDriver = _drv(b)
		if bd == null or bd.on_rail or not (bd.rage > 0.05 or bd.persona == "extremist"):
			continue
		if track.sections.zone_at(bd.dist).is_empty():
			continue
		var bxf: Transform3D = track.transform_at_distance(bd.dist)
		var nk: int = track.knock_items(bd.dist, (b.global_position - bxf.origin).dot(bxf.basis.x), 0.95, absf(b.speed), 0.0)
		if bd.persona == "extremist":
			x_cones_hit += nk


## Odcinek "rest" (oddech w rytmie reżysera): nic nowego wrogiego.
## seg_rhythm = false - bez rytmu (testy waśni i scenek: pierwsze odcinki
## trasy są zawsze "rest").
var seg_rhythm := true
func seg_calm() -> bool:
	return seg_rhythm and segments != null and segments.calm_at(_last_safe_dist)


## Roboty, 1+1, 2+1 (etap 2b-2d): ruch z naprzeciwka naszą jezdnią - 2-3 auta
## postawione za końcem strefy (poza wzrokiem), gdy gracz jest ~2 km przed
## nią; bez tego przy rzadkim ruchu między miastami strefa bywała pusta.
var _works_done := {}
func _works_traffic() -> void:
	if not track.sections:
		return
	var p := _last_safe_dist
	for z in track.sections.zones(p, p + 2600.0):
		if not (int(z["section"]) in SectionPlan.ONC_ON_OURS) or _works_done.has(int(z["k"])) or p < float(z["start"]) - 2600.0:
			continue
		# Trasa za strefą musi już być (bez szyny auto od razu wraca do puli).
		if track.rail_at(float(z["end"]) + 450.0).is_empty():
			continue
		_works_done[int(z["k"])] = true
		var lim := float(z["limit"])
		var n0 := _oncoming.size()
		for i in range(2 + _bot_rng.randi() % 2):
			var d := float(z["end"]) + 150.0 + i * 140.0
			var xf: Transform3D = _oncoming_xf(d, 0.0)
			if _can_vanish(xf.origin):
				var n := _oncoming.size()
				_spawn_oncoming(d, 0, lim * _bot_rng.randf_range(0.9, 1.05))
				if _oncoming.size() > n:
					(_oncoming[-1] as OncomingCar).works = true
		print("ROBOTY: strefa %.0f-%.0f, auta z naprzeciwka za nią: %d" % [z["start"], z["end"], _oncoming.size() - n0])


func _traffic_ensure() -> void:
	if _traffic == null:
		_traffic = TrafficZone.new(track.plan)
		_traffic.weather = track.weather


func _update_bots(delta: float) -> void:
	_update_bot_lod(delta)
	_update_segments(delta)
	_update_extremist()
	var hwy: bool = _endless and track.autostrada
	if hwy:
		_update_traffic(delta)
	_bot_timer -= delta
	if not hwy and _bot_timer <= 0.0 and race_state == Race.RACING:
		var limit := bot_limit(_last_section) if _endless else 2
		if Bench.scenario == "S4":
			limit = 20                         # pomiar: pełny ruch
		# Im więcej brakuje do limitu, tym szybciej dochodzą nowe auta.
		_bot_timer = _bot_rng.randf_range(2.0, 6.0) if _bots.size() < limit else 3.0
		if _bots.size() < limit:
			_spawn_bot(_last_safe_dist + _bot_rng.randf_range(220.0, 900.0))
	for b in _bots.duplicate():
		var drv: BotDriver = _drv(b)
		# Bot w szale nie znika tak łatwo - ma czas dogonić gracza.
		var behind_max := 700.0 if drv.rage > 0.05 else 250.0
		# Autostrada: spokojny ruch usuwa TrafficZone (poza wzrokiem); bot
		# w szale zgubiony daleko za graczem znika jak w wąwozie ("lost").
		var gone: bool = (not hwy or drv.rage > 0.05) and (drv.dist < _last_safe_dist - behind_max or drv.dist > _last_safe_dist + 2000.0) \
				and _can_vanish(b.global_position)
		# Auto zdarzenia odcinka (spokojne, poza ruchem TrafficZone): daleko
		# za graczem albo bardzo daleko przed nim (gracz stanął).
		if drv.event != "" and drv.rage <= 0.05 and not drv.hold \
				and (drv.dist < _last_safe_dist - 700.0 or drv.dist > _last_safe_dist + 4000.0) \
				and _can_vanish(b.global_position):
			gone = true
		var dead: bool = b.is_wrecked or drv.flipped_time > 3.0 or b.global_position.y < -50.0
		if gone or dead:
			if drv.rage > 0.05:
				# Spadek w otchłań (błąd toru, nie zasługa gracza) - "lost",
				# bez premii za wybuch (przegląd punktacji).
				var fell_out: bool = b.global_position.y < -50.0
				score_chase_close(b, "wreck" if dead and not fell_out else "lost")
			if dead:
				if b == _extremist and race_time - _x_contact_t < 10.0:
					_score_pay(score.award_free("extremist_wreck", 500, race_time, "EKSTREMISTA ROZBITY"))
				_explode(b)
			_bots.erase(b)
			_retire_bot(b, dead)
			Perf.mark("bot_free")


## Klakson gracza (klik lewego drążka, H na klawiaturze): dwa tony jak
## u botów i szał wszystkich botów w promieniu HORN_RADIUS (użytkownik
## 2026-11-09: "klakson, który wpędza w furię wszystkie samochody
## w okolicy"). Auta z naprzeciwka są kinematyczne - nie reagują.
const HORN_RADIUS := 250.0
var _player_horn: AudioStreamPlayer3D
var _horn_cd := 0.0
func player_horn() -> void:
	if _mode != Mode.DRIVE:
		return
	if _player_horn == null:
		_player_horn = BotDriver.horn_on(car)
	_player_horn.play()
	var now := Time.get_ticks_msec() / 1000.0
	if now < _horn_cd:
		return
	_horn_cd = now + 1.0
	var n := 0
	for b in _bots:
		if not is_instance_valid(b):
			continue
		var drv: BotDriver = _drv(b)
		if drv.rage < 0.5 and b.global_position.distance_to(car.global_position) < HORN_RADIUS:
			drv.enrage("horn")
			n += 1
	if n > 0:
		print("Klakson: %d aut w szale" % n)


## Posiłki: boty w promieniu `radius` m od wściekłego bota też wpadają w szał.
func call_reinforcements(from: StuntCar, radius: float) -> void:
	for b in _bots:
		if b == from or not is_instance_valid(b):
			continue
		var drv: BotDriver = _drv(b)
		if drv.rage < 0.5 and b.global_position.distance_to(from.global_position) < radius:
			drv.enrage("reinforce")


## Drugi bot w szale najbliżej gracza (partner do kleszczy) albo null.
func rage_partner(me: StuntCar) -> StuntCar:
	var best: StuntCar = null
	var best_d := 120.0
	for b in _bots:
		if b == me or not is_instance_valid(b):
			continue
		var drv: BotDriver = _drv(b)
		var dd := b.global_position.distance_to(car.global_position)
		if drv.rage > 0.5 and dd < best_d:
			best_d = dd
			best = b
	return best


## Oś pasu naszej jezdni na autostradzie [m od osi jezdni]: 0 prawy, 1 lewy.
func hwy_lane_off(lane: int) -> float:
	return HighwayGenerator.lane_center(lane)


## Oś pasu `lane` w miejscu d z przekrojem (SectionPlan, etap 2): pasy
## naszego kierunku od prawego, indeks przycięty do liczby pasów (zwężenie:
## oba pasy jadą jedynym otwartym). Bez przekrojów - hwy_lane_off.
func hwy_lane_at(lane: int, d: float) -> float:
	if not (_endless and track.autostrada and track.sections):
		return hwy_lane_off(lane)
	var fwd: Array = track.sections.lanes_at(d)["fwd"]
	if fwd.is_empty():
		return hwy_lane_off(lane)
	return float(fwd[clampi(lane, 0, fwd.size() - 1)])


func _spawn_bot(d: float, lane_i := -1, speed_kmh := -1.0) -> void:
	if track.is_gap_at(d) or d > track.total_length() - 20.0:
		return
	var xf: Transform3D = track.transform_at_distance(d)
	var smp: Dictionary = track.sample_at(d)
	if smp.is_empty():
		return
	var lane_w := StuntTrack.lane_width(float(smp["width"]))
	var lim := float(smp["limit"])
	Perf.mark("bot_spawn")
	var bot := _take_bot()
	_bot_style(bot, _pick_style())
	var gs := _gs
	if gs:
		# Gang bota (FeudDirector): kolor gangu, żeby było widać, kto z kim.
		var g := _bot_rng.randi() % GANGS
		_bot_gang[bot.get_instance_id()] = g
		bot.set_paint(gs.PAINTS[_gang_paint(g)])
	# Prawy albo środkowy pas - przy wielu autach nie wszystkie jednym torem.
	var lane := lane_w if _bot_rng.randf() < 0.65 else 0.0
	# Wąwóz: wyspa rozwidlenia w ciągu 200 m - środkiem prosto na jej czoło
	# (horn_control_test, trasa 7: bot postawiony na środku tuż przed wyspą).
	if lane == 0.0 and lane_i < 0:
		var w0 := float(smp["width"])
		if w0 > 18.0:
			lane = lane_w                  # już w rozszerzeniu przed wyspą
		for s2 in track.samples_from(d, 200.0, 10):
			if float(s2["width"]) - w0 > TrackGenerator.ISLAND_W + 3.0:
				lane = lane_w
				break
	if lane_i >= 0:
		lane = hwy_lane_at(lane_i, d)
	bot.place(Transform3D(xf.basis, xf.origin + xf.basis.x * lane + xf.basis.y * 0.9))
	bot._settle_t = 0.0         # place() zjadałby prędkość przepisową startu
	var v := (speed_kmh if speed_kmh > 0.0 else lim) / 3.6
	bot.linear_velocity = -xf.basis.z * v
	for w in bot.wheels:
		w.omega = v / bot.wheel_radius
	bot.gear = mini(3, bot.gear_ratios.size())
	bot._pending_gear = bot.gear
	var drv := BotDriver.new()
	drv.name = "Driver"
	drv.car = bot
	drv.player = car
	drv.track = track
	drv.main = self
	drv.dist = d
	drv.lane = maxi(lane_i, 0)
	drv.has_token = false                 # żetony rozdaje _assign_tokens
	bot.add_child(drv)
	bot.driver = drv
	_bots.append(bot)
	feud.add_bot(bot.get_instance_id(), int(_bot_gang.get(bot.get_instance_id(), 0)))


# --------------------------------------------------------------------------
# Przejazd: start, zegar, meta, wyniki
# --------------------------------------------------------------------------

## Stan przejazdu. Wołane co krok fizyki (też z testów).
func update_race(delta: float) -> void:
	match race_state:
		Race.READY:
			# Zegar rusza razem z autem, nie z wczytaniem sceny.
			if car.linear_velocity.length() > 0.5:
				race_state = Race.RACING
		Race.RACING:
			race_time += delta
			if not _endless:
				_check_finish()
			else:
				_check_workshop()
				_check_fuel(delta)
		Race.WORKSHOP:
			# Postój w warsztacie: zegar stoi, auto hamuje.
			car.throttle = 0.0
			car.brake = 1.0
			car.steer = 0.0
		Race.FINISHED:
			# Po mecie auto samo hamuje do zatrzymania - za metą jest tylko
			# prosta na wyhamowanie, a potem przepaść.
			car.throttle = 0.0
			car.brake = 1.0
			car.steer = 0.0
	# Ograniczenie i "za szybko" - znak obok miniatury ostrzegawczej przy
	# mapce (użytkownik; pole pod wskaźnikiem uszkodzeń usunięte).
	if _track_hud and _race_label:
		_track_hud.show_limit(_hud_panel, _race_label.position + Vector3(0.062, -0.105, 0.0),
				current_limit if _endless else -1.0, not player_compliant())
	# Napis zegara co 0,1 s (wcześniej co krok fizyki z setnymi sekundy -
	# Label3D przebudowywał siatkę tekstu co klatkę).
	_race_label_t -= delta
	if _race_label and (_race_label_t <= 0.0 or race_state != _race_label_state):
		_race_label_t = 0.1
		_race_label_state = race_state
		if race_state == Race.READY:
			_race_label.text = "gotowy\nruszaj!"
		elif race_state == Race.FINISHED:
			_race_label.text = ""
		elif _endless:
			var cr := "" if cranes_left < 0 else "\nauta: %d" % (cranes_left + 1)
			# Paliwo pokazuje wskaźnik na obrotomierzu; tu tylko tankowanie
			# i odległość do stacji.
			var fuel_line := ""
			if _refueling:
				fuel_line = "\nTANKOWANIE"
			elif not _next_station.is_empty():
				fuel_line = "\nstacja %.1f km" % maxf((float(_next_station["start"]) - _last_safe_dist) / 1000.0, 0.0)
			cr += fuel_line
			var pts := "\n%d pkt" % score.points
			if score.combo_active(race_time):
				pts += " x%d" % score.combo
			_race_label.text = "odcinek %d\n%.2f km\n%s%s%s" % [
					_last_section, _max_dist / 1000.0, _fmt_time(race_time, true), pts, cr]
		else:
			_race_label.text = _fmt_time(race_time, true)


## Meta przekroczona, gdy auto przejdzie przez płaszczyznę linii mety
## w kierunku jazdy, w obrębie szerokości toru i niedaleko jezdni.
func _check_finish() -> void:
	var rel := car.global_position - _finish_xf.origin
	var side := signf(rel.dot(-_finish_xf.basis.z))
	var lateral := absf(rel.dot(_finish_xf.basis.x))
	var height := absf(rel.dot(_finish_xf.basis.y))
	if _prev_finish_side < 0.0 and side > 0.0 and lateral < 8.0 and height < 4.0:
		_finish()
	_prev_finish_side = side


func _finish() -> void:
	race_state = Race.FINISHED
	var gs := _gs
	_new_record = false
	var best := 0.0
	if gs:
		if gs.best_time <= 0.0 or race_time < gs.best_time:
			gs.best_time = race_time
			gs.save_settings()
			_new_record = true
		best = gs.best_time
	var lines := PackedStringArray(["META!", "czas  " + _fmt_time(race_time)])
	if _new_record:
		lines.append("NOWY REKORD!")
	elif best > 0.0:
		lines.append("rekord  " + _fmt_time(best))
	lines.append("")
	lines.append("A: jeszcze raz     Menu: ekran tytułowy" if _xr_ready \
			else "R / Enter: jeszcze raz     Esc: ekran tytułowy")
	_result_label.text = "\n".join(lines)
	_result_label.visible = true
	print("Meta: %s%s" % [_fmt_time(race_time), " (rekord)" if _new_record else ""])


## Koniec jazdy na trasie bez końca: skończyły się dźwigi.
func _game_over() -> void:
	race_state = Race.FINISHED
	var gs := _gs
	_new_record = false
	var best := 0.0
	if gs:
		if _max_dist > gs.best_distance:
			gs.best_distance = _max_dist
			gs.save_settings()
			_new_record = true
		best = gs.best_distance
	var lines := PackedStringArray(["AUTO ROZBITE" if car.is_wrecked else "KONIEC JAZDY",
			"odcinek %d   %.2f km" % [track.section_at(_max_dist), _max_dist / 1000.0],
			"czas  " + _fmt_time(race_time)])
	if _new_record:
		lines.append("NOWY REKORD!")
	elif best > 0.0:
		lines.append("rekord  %.2f km" % (best / 1000.0))
	lines.append("")
	lines.append("A: nowa trasa     Menu: ekran tytułowy" if _xr_ready \
			else "R / Enter: nowa trasa     Esc: ekran tytułowy")
	_result_label.text = "\n".join(lines)
	_result_label.visible = true
	print("Koniec jazdy: odcinek %d, %.2f km, %s" % [track.section_at(_max_dist), _max_dist / 1000.0, _fmt_time(race_time)])


## Nowy przejazd od linii startu: zegar od zera, auto naprawione.
## Trasa bez końca: nowa, losowa trasa (scena od nowa).
func restart_race() -> void:
	if _endless and race_state == Race.FINISHED:
		get_tree().reload_current_scene()
		return
	var gs := _gs
	cranes_left = (gs.cranes if gs and gs.cranes > 0 else -1) if _endless else -1
	_max_dist = 0.0
	# Trasa bez końca: start z mocą wybraną w menu (decyzja użytkownika
	# 2026-11-09, inbox moc-z-menu-w-trasie; wcześniej zawsze 90 kW, więc
	# "1000 kW" z menu ledwo wjeżdżało pod górkę). Warsztaty proponują
	# progi powyżej. Silnik ustawił już GameSettings.apply_to_car - tu
	# tylko próg, od którego liczą warsztaty.
	if _endless and gs:
		var kw: int = gs.effective_power(gs.engine_type, gs.motor_layout == "hub", gs.engine_power)
		_tier = maxi(gs.POWER_TIERS.find(kw), 0)
		car.hub_motors = gs.engine_type == "electric" and gs.motor_layout == "hub"
		car.apply_engine(gs.engine_type, kw)
	if _endless:
		_warm_bot_pool()
	_gang_seed = _bot_rng.randi() % 8
	feud.roll_relations(range(GANGS), 1)
	_next_ws = {}
	_ws_done_stop = -INF
	_last_section = 1
	_sec_t0 = 0.0
	_sec_d0 = 0.0
	_next_station = {}
	car.refuel(1.0)
	if _ws_label:
		_ws_label.visible = false
	race_state = Race.READY
	race_time = 0.0
	_prev_finish_side = -1.0
	_last_safe_dist = start_distance
	if _result_label:
		_result_label.visible = false
	car.repair()
	_respawn()


# --------------------------------------------------------------------------
# Warsztat (co 10 odcinków na trasie bez końca)
# --------------------------------------------------------------------------

## Warsztat: auto stoi (< 8 km/h) na pasie zjazdu w strefie warsztatu.
func _check_workshop() -> void:
	if _next_ws.is_empty():
		return
	if _last_safe_dist >= float(_next_ws["start"]) and _last_safe_dist <= float(_next_ws["end"]) \
			and _lateral > float(_next_ws["lane_x"]) and absf(car.speed) * 3.6 < 8.0:
		_enter_workshop(int(_next_ws["tier"]))


var _station_shop_done := -1.0
## Stacja: tankowanie przy powolnym przejeździe (< 35 km/h) pasem zjazdu
## (pełny bak w ~8 s). Pusty bak i auto stoi - utrata życia.
func _check_fuel(delta: float) -> void:
	_refueling = false
	if not _next_station.is_empty():
		if _last_safe_dist >= float(_next_station["start"]) and _last_safe_dist <= float(_next_station["end"]) \
				and _lateral > float(_next_station["lane_x"]) and absf(car.speed) * 3.6 < 35.0:
			car.refuel(delta / 8.0)
			_refueling = true
			# Postój na stacji: sklep z naprawami za punkty (raz na stację).
			if absf(car.speed) * 3.6 < 3.0 and race_state == Race.RACING \
					and float(_next_station["start"]) != _station_shop_done:
				_station_shop_done = float(_next_station["start"])
				_enter_workshop(0, "station")
	if car.fuel <= 0.0 and absf(car.speed) < 0.5 and race_state == Race.RACING:
		lose_life("brak paliwa")


## Warsztat i sklep (użytkownik 2026-11-09: "w menu warsztatu jest mowa
## o dźwigu, a powinny być punkty za każdą rzecz, wymianę silnika,
## naprawę"; "za rzadko można wymienić punkty na naprawę"): każda pozycja
## kosztuje punkty z furii (ScoreKeeper), menu zostaje otwarte do "Wyjazd".
## Naprawy strefami i ulepszenia z WorkshopShop (cennik chmury). Na stacji
## paliw (postój na pasie zjazdu) - ten sam sklep, tylko naprawy.
## Tankowanie w warsztacie bez opłaty (jak na stacji).
## Cena silnika rośnie z progiem mocy.
const ENGINE_COST_PER_TIER := 300
const SHOP_EFFECTS := ["repaired", "repaired_full", "life", "tank"]
var _ws_kind := "workshop"
var _ws_new_tier := 0
var _ws_arm_t := 0.0
var _ws_owned: Array = []


func _enter_workshop(tier: int, kind := "workshop") -> void:
	race_state = Race.WORKSHOP
	_ws_kind = kind
	if kind == "workshop":
		_ws_done_stop = float(_next_ws["stop"])
		_next_ws = {}
		car.refuel(1.0)
	# Próg z trasy, ale nigdy nie słabszy ani równy obecnemu (start z mocą
	# z menu). Ostatni próg osiągnięty - bez wymiany silnika.
	_ws_new_tier = maxi(tier, _tier + 1)
	_ws_selected = 0
	_ws_arm_t = 0.4                     # spust trzymany przy wjeździe nie kupuje
	_ws_build()
	_ws_follow.snap()
	_ws_label.visible = true


## Lista pozycji sklepu (po każdym zakupie od nowa - ceny napraw maleją).
func _ws_build() -> void:
	_ws_options.clear()
	var gs := _gs
	var tiers: Array = gs.POWER_TIERS if gs else [90, 130, 180, 250, 350]
	var spec := WorkshopShop.car_spec(car)
	if _ws_kind == "workshop" and _ws_new_tier < tiers.size():
		# Wymiana silnika - cena z WorkshopShop (za kW, rodzaj napędu, odkup
		# starego silnika pomniejszony o jego uszkodzenie).
		var tier := _ws_new_tier
		var kw: int = tiers[tier]
		var probe := StuntCar.new()
		probe.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM   # poza drzewem (bez _ready)
		var hub_only: bool = gs != null and kw >= gs.HUB_ONLY_KW
		for t in (["electric"] if hub_only else ["petrol", "diesel", "electric"]):
			probe.apply_engine(t, kw)
			var name_pl: String = StuntCar.ENGINE_TYPES[t]["label"]
			var lbl := "Silnik: %s %d kW, %d Nm" % [name_pl, kw, roundi(probe.peak_torque())]
			if hub_only:
				lbl = "Silnik: elektryk 4 x 250 kW w kołach, %d Nm" % roundi(probe.peak_torque())
			var o := WorkshopShop.engine_offer(t, kw, lbl, score.points, spec, car.damage, hub_only)
			_ws_options.append({"kind": "offer", "id": o["id"], "cost": int(o["cost"]), "label": lbl, "tier": tier})
		probe.free()
	for o in WorkshopShop.offers(car.damage, score.points, _ws_owned, spec, _ws_kind):
		var eff := ""
		for u in WorkshopShop.UPGRADES:
			if u["id"] == o["id"]:
				eff = u["effect"]
		# Tylko to, co gra już obsługuje (orurowanie, radio CB - później).
		if eff != "" and not eff in SHOP_EFFECTS:
			continue
		_ws_options.append({"kind": "offer", "id": o["id"], "cost": int(o["cost"]),
				"label": ("Naprawa: " if str(o["id"]).begins_with("repair:") else "") + str(o["label"])})
	_ws_options.append({"kind": "exit", "cost": 0, "label": "Wyjazd"})
	_ws_selected = clampi(_ws_selected, 0, _ws_options.size() - 1)
	_ws_refresh()


func _ws_move(dir: int) -> void:
	_ws_selected = wrapi(_ws_selected + dir, 0, _ws_options.size())
	_ws_refresh()


func _ws_refresh() -> void:
	var title := "WARSZTAT" if _ws_kind == "workshop" else "STACJA - NAPRAWY"
	var lines := PackedStringArray([title, "punkty: %d" % score.points, ""])
	for i in range(_ws_options.size()):
		var o: Dictionary = _ws_options[i]
		var lbl: String = o["label"]
		var cost: int = o["cost"]
		if o["kind"] != "exit":
			lbl += ("   %d pkt" % cost) if cost <= score.points else ("   %d pkt (za mało punktów)" % cost)
		lines.append(("> " + lbl + " <") if i == _ws_selected else lbl)
	lines.append("")
	lines.append("drążek: wybór   spust albo A: zatwierdź" if _xr_ready else "strzałki: wybór   Enter: zatwierdź")
	_ws_label.text = "\n".join(lines)


## Indeks pozycji "Wyjazd" (testy).
func ws_exit_index() -> int:
	for i in range(_ws_options.size()):
		if _ws_options[i]["kind"] == "exit":
			return i
	return _ws_options.size() - 1


## Zatwierdzenie pozycji w warsztacie (też z testów).
func workshop_choose(i: int) -> void:
	if race_state != Race.WORKSHOP:
		return
	var opt: Dictionary = _ws_options[clampi(i, 0, _ws_options.size() - 1)]
	match opt["kind"]:
		"exit":
			_ws_label.visible = false
			race_state = Race.RACING
			print("Warsztat: wyjazd, %d pkt" % score.points)
			return
		"offer":
			var id: String = opt["id"]
			var eff := WorkshopShop.buy(id, car.damage, score, WorkshopShop.car_spec(car), _ws_kind)
			match eff:
				"":
					return                  # za mało punktów
				"engine":
					var e := WorkshopShop.parse_engine(id)
					# Silniki w kołach tylko z ostatniego progu albo gdy elektryk już je
					# miał (inbox menu-a-gra-niespojnosci pkt 5).
					car.hub_motors = bool(e["hub"]) or (e["type"] == "electric" and car.engine_type == "electric" and car.hub_motors)
					car.apply_engine(e["type"], e["kw"])
					_tier = int(opt.get("tier", _tier))
					_ws_new_tier = _tier + 1
				"repaired_full":
					car.repair()
				"repaired":
					if id == "repair:structure":
						car.repair_body()
				"life":
					if cranes_left >= 0:
						cranes_left += 1
				"tank":
					car.tank_kwh *= 1.4
					_ws_owned.append(id)
			print("Warsztat: %s" % opt["label"])
	_ws_build()


var _warn_timer := 0.0
## Opad: cel z próbki trasy pod autem (0 sucho, 1 mżawka, 2 deszcz), auto.rain
## dochodzi do niego płynnie (~3 s), za nim cząstki i szum deszczu.
var _rain_target := 0.0
var _rain_vis := 0.0          # opad widoczny (smugi, szum) - szybko, tunel ucina
var _rain: GPUParticles3D
var _rain_sound: AudioStreamPlayer
var _env: EnvAudio


## Miniatura najbliższego znaku ostrzegawczego (do 250 m przed autem)
## obok mapki, pod kolumną postępu - jak ograniczenie prędkości na desce.
func _update_warning(delta: float) -> void:
	_warn_timer -= delta
	if _warn_timer > 0.0 or _race_label == null:
		return
	_warn_timer = 0.3
	var kind := ""
	var value := 0
	var prev_surf := ""
	# Zjazd do warsztatu albo na stację bliżej niż 400 m: niebieski znak ze
	# strzałką ma pierwszeństwo przed ostrzeżeniami.
	for svc in [[_next_ws, "repair"], [_next_station, "fuel"]]:
		var sd: Dictionary = svc[0]
		if not sd.is_empty() and float(sd["start"]) - 40.0 - _last_safe_dist < 400.0 \
				and float(sd["start"]) > _last_safe_dist:
			kind = svc[1]
	for s in (track.samples_from(_last_safe_dist, 250.0, 4) if kind == "" else []):
		var m: Dictionary = s["meta"]
		if m.has("curve_sign"):
			kind = "curve_r" if m["curve_sign"] > 0 else "curve_l"
		elif m.has("grade"):
			kind = "climb" if m["grade"] > 0 else "descent"
			value = absi(m["grade"])
		elif prev_surf == "dry" and s["surface"] != "dry" and s["surface"] != "kicker":
			kind = "slippery"
		if kind != "":
			break
		prev_surf = s["surface"]
	# Pod kolumną postępu (która stoi przy prawej krawędzi mapki).
	# Niżej niż kolumna tekstu (nie zasłania jej ostatnich linii).
	var pos := _race_label.position + Vector3(0.02, -0.105, 0.0)
	_track_hud.show_warning(_hud_panel, pos, kind, value)


## Lusterko wsteczne u góry przedniej szyby: osobna kamera tuż za tylnym
## zderzakiem patrzy do tyłu i renderuje do małej tekstury (256×80, co
## drugą klatkę - Quest), wyświetlanej na prostokącie jako odbicie lustrzane.
func _build_mirror() -> void:
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(256, 80)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.fov = 28.0
	_mirror_cam.near = 0.1
	_mirror_cam.far = 400.0
	_mirror_cam.current = true
	_mirror_vp.add_child(_mirror_cam)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _mirror_vp.get_texture()
	# Lustro odwraca lewo-prawo.
	m.uv1_scale = Vector3(-1, 1, 1)
	m.uv1_offset = Vector3(1, 0, 0)
	var glass := MeshInstance3D.new()
	glass.name = "MirrorGlass"
	var q := QuadMesh.new()
	q.material = m
	glass.mesh = q
	var face := car.get_node_or_null("MirrorFace") as Node3D
	if face and face.is_visible_in_tree():
		# Sedan: obraz w lusterku z nowego wnętrza (wcześniej działające
		# lusterko wisiało osobno obok atrapy - zgłoszenie użytkownika).
		q.size = Vector2(StuntCar.MIRROR_GLASS_SIZE.x, StuntCar.MIRROR_GLASS_SIZE.y)
		_mirror_vp.size = Vector2i(256, int(256.0 * q.size.y / q.size.x))
		# Model z epoki: kokpit sedana przesunięty o cockpit_offset.
		glass.transform = Transform3D(car.mirror_mount.basis, car.mirror_mount.origin + car.cockpit_offset).translated_local(
				Vector3(0.0, 0.0, StuntCar.MIRROR_GLASS_SIZE.z * 0.5 + 0.001))
		car.add_child(glass)
		return
	# Concept car: własna ramka nad deską.
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.27, 0.09, 0.02)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.05, 0.05)
	fb.material = fm
	frame.mesh = fb
	frame.position = Vector3(0.0, 0.565, -0.13)
	frame.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(12.0), 0.0)
	car.add_child(frame)
	q.size = Vector2(0.25, 0.075)
	glass.position = Vector3(0, 0, 0.011)
	frame.add_child(glass)


func _update_mirror() -> void:
	if _mirror_cam == null:
		return
	var xf := car.get_global_transform_interpolated()
	# Tuż za tylnym zderzakiem, patrzy do tyłu (+Z auta).
	_mirror_cam.global_transform = Transform3D(xf.basis.rotated(xf.basis.y, PI),
			xf * Vector3(0.0, 0.55, 2.5))
	_mirror_frame += 1
	if _mirror_frame % 2 == 0:
		_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Radio (moduł z chmury, CarRadio) i menu pauzy, z którego się nim steruje
## (użytkownik 2026-11-09). Napis "co gra" nad radiem na desce sedana,
## w concept carze pod mapką; przy zmianie utworu krótki napis w HUD.
func _build_radio() -> void:
	origin.process_mode = Node.PROCESS_MODE_ALWAYS
	_radio = CarRadio.new()
	_radio.name = "CarRadio"
	_radio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_radio)
	_radio_label = Label3D.new()
	_radio_label.name = "RadioText"
	_radio_label.font_size = 24
	_radio_label.pixel_size = 0.00035
	_radio_label.outline_size = 4
	_radio_label.modulate = Color(1.0, 0.85, 0.55)
	_radio_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if car.get_node_or_null("MirrorFace") and car.body_model == "sedan":
		_radio_label.position = Vector3(0.10, 0.03, -0.24) + car.cockpit_offset
		car.add_child(_radio_label)
	else:
		_radio_label.position = Vector3(0.0, -TrackHud.SIZE.y * 0.5 - 0.03, 0.0)
		_radio_label.no_depth_test = true
		_hud_panel.add_child(_radio_label)
	_radio.now_playing.connect(_on_radio_text)
	var gs := _gs
	if gs:
		_radio.set_online(gs.radio_online)
		_radio.set_station(gs.radio_station)
		if gs.radio_on:
			_radio.set_power(true)
	_pause = PauseMenu.new()
	_pause.camera = camera
	_pause.hands = [left_hand, right_hand]
	_pause.xr = _xr_ready
	_pause.radio = _radio
	_pause.resumed.connect(_set_paused.bind(false))
	_pause.quit_requested.connect(_back_to_title)
	_pause.restart_requested.connect(_restart_from_pause)
	_pause.setting_changed.connect(_on_setting_changed)
	add_child(_pause)
	_pause.add_to_group(WorldOrigin.GROUP)
	_pause.apply_volume()


## Zmiana ustawienia w menu pauzy, która działa od razu (bez nowej jazdy).
func _on_setting_changed(key: String) -> void:
	var gs := _gs
	if gs == null:
		return
	match key:
		"radio_on":
			_radio.set_power(gs.radio_on)
		"radio_station":
			_radio.set_station(gs.radio_station)
		"radio_volume":
			_pause.apply_volume()
		"radio_online":
			_radio.set_online(gs.radio_online)
		"abs_enabled", "tcs_enabled", "esp_enabled":
			car.set(key, gs.get(key))
		"steer_assist":
			gs.apply_steer(car)
		"paint":
			car.set_paint(gs.PAINTS[gs.paint])
		"xr_resolution", "xr_foveation":
			gs.apply_xr_quality()
		"game_speed":
			gs.apply_game_speed()
		"shadows":
			gs.apply_shadows($Sun as DirectionalLight3D)


## Zmiana auta albo trasy w pauzie, potwierdzona: nowa jazda z nowymi
## ustawieniami (scena od nowa - GameSettings.apply_to_car w _ready).
func _restart_from_pause() -> void:
	_set_paused(false)
	get_tree().reload_current_scene()


func _on_radio_text(text: String) -> void:
	if _radio_label:
		_radio_label.text = text
	if _pause and _pause.is_open():
		_pause.refresh()
	elif text != "":
		_show_popup(text.get_slice("\n", 0) + "  " + text.get_slice("\n", 1), false)


## coarse: dziesiąte części sekundy (zegar na desce odświeżany co 0,1 s);
## wyniki i log - setne.
func _fmt_time(t: float, coarse := false) -> String:
	if coarse:
		return "%d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


## Zegar nad deską i tablica wyników przed kierowcą. Dzieci auta, więc
## jadą z nim; bez testu głębi, żeby prześwitująca kabina ich nie zasłaniała.
func _build_race_hud() -> void:
	# Panel HUD na prawo od kierownicy, twarzą do oczu (odchylenie w bok
	# i pochylenie z kierunku od oczu), żeby tekst nie był ścięty w perspektywie.
	_hud_panel = Node3D.new()
	_hud_panel.name = "HudPanel"
	_hud_panel.position = car.seat.position + HUD_FROM_EYES
	var to_eyes := -HUD_FROM_EYES
	_hud_panel.rotation = Vector3(-atan2(to_eyes.y, Vector2(to_eyes.x, to_eyes.z).length()),
			atan2(to_eyes.x, to_eyes.z), 0.0)
	car.add_child(_hud_panel)

	_race_label = Label3D.new()
	_race_label.name = "RaceClock"
	# Postęp (odcinek, dystans, czas, auta) w kolumnie tuż obok mapki trasy
	# (prawa krawędź HUD), w skali mapki - jeden zwarty panel obok kierownicy.
	_race_label.font_size = 26
	_race_label.pixel_size = 0.00045
	_race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_race_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_race_label.position = Vector3(TrackHud.SIZE.x * 0.5 + 0.008, TrackHud.SIZE.y * 0.5 - 0.004, 0.0)
	_race_label.outline_size = 6
	_race_label.modulate = Color(0.85, 0.95, 1.0)
	_race_label.no_depth_test = true
	_hud_panel.add_child(_race_label)

	_result_label = Label3D.new()
	_result_label.name = "Results"
	_result_label.font_size = 72
	_result_label.pixel_size = 0.0012
	# 1,5 m przed oczami kierowcy, lekko powyżej linii wzroku.
	_result_label.position = car.seat.position + Vector3(0.0, 0.12, -1.5)
	_result_label.modulate = Color(1.0, 0.85, 0.3)
	_result_label.outline_size = 16
	_result_label.no_depth_test = true
	_result_label.visible = false
	car.add_child(_result_label)

	if Bench.on("mirror"):
		_build_mirror()
	_build_rain()
	_build_popups()
	_env = EnvAudio.new()
	_env.name = "EnvAudio"
	add_child(_env)

	# Mapka trasy na 1,5 km: środek panelu HUD (na prawo od kierownicy).
	_track_hud = TrackHud.new()
	_track_hud.name = "TrackHud"
	_hud_panel.add_child(_track_hud)
	_build_radio()
	if Bench.active():
		# Widać od razu, że to przejazd pomiarowy (wejście ignorowane).
		var bl := Label3D.new()
		bl.name = "BenchLabel"
		bl.text = "BENCH " + Bench.scenario
		bl.font_size = 26
		bl.pixel_size = 0.0006
		bl.modulate = Color(1.0, 0.4, 0.3)
		bl.outline_size = 6
		bl.no_depth_test = true
		bl.position = Vector3(0.0, TrackHud.SIZE.y * 0.5 + 0.02, 0.0)
		_hud_panel.add_child(bl)

	_ws_label = _result_label.duplicate()
	_ws_label.name = "Workshop"
	_ws_label.font_size = 60
	_ws_label.modulate = Color(0.9, 0.95, 1.0)
	_ws_label.position = Vector3.ZERO
	# Menu warsztatu podąża za wzrokiem, 1,5 m przed oczami.
	_ws_follow = GazeFollow.new()
	_ws_follow.name = "WorkshopMenu"
	_ws_follow.camera = camera
	_ws_follow.distance = 1.5
	add_child(_ws_follow)
	_ws_follow.add_to_group(WorldOrigin.GROUP)
	_ws_follow.add_child(_ws_label)


func _process(delta: float) -> void:
	_frame_stats(delta)
	_bench_step(delta)
	_update_popups(delta)
	var t0 := Time.get_ticks_usec()
	_update_rain(delta)
	_update_weather_look(delta)
	Perf.add("deszcz", t0)
	_update_traffic_audio(delta)
	_log_perf(delta)
	_ws_arm_t = maxf(_ws_arm_t - delta, 0.0)
	if race_state == Race.WORKSHOP and _xr_ready:
		# Wybór w warsztacie drążkiem (jak w menu: jeden krok na wychylenie).
		var sy := left_hand.get_vector2("primary").y + right_hand.get_vector2("primary").y
		if absf(sy) < 0.3:
			_ws_stick_ready = true
		elif _ws_stick_ready and absf(sy) > 0.7:
			_ws_stick_ready = false
			_ws_move(-1 if sy > 0.0 else 1)
	if _y_held >= 0.0:
		_y_held += delta
		if _y_held >= RECENTER_HOLD:
			XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)
			_y_held = -1.0    # puszczenie po centrowaniu nie przełącza już TCS
	if race_state != Race.REPLAY:
		_update_mirror()
	if race_state == Race.EXPLODING:
		_cinematic(delta)
	elif race_state == Race.REPLAY:
		_replay_camera(delta)
	elif _mode == Mode.DRIVE:
		_follow_car(delta)
	else:
		_fly(delta)
	var th := Time.get_ticks_usec()
	if _track_hud and race_state != Race.REPLAY:
		_track_hud.refresh(delta, car.get_global_transform_interpolated(),
				func(): return track.samples_from(_last_safe_dist - 10.0, TrackHud.RANGE + 20.0, TrackHud.STRIDE),
				_last_safe_dist)
		_update_warning(delta)
	Perf.add("hud", th)
	# Ziemia (siatka 1200 m) jedzie za autem - trasa bez końca wychodzi daleko
	# poza nią. Kolizja ziemi to nieskończona płaszczyzna, więc jej nie ruszamy.
	var gm := $Ground/GroundMesh as Node3D
	var p := car.global_position
	gm.global_position = Vector3(snappedf(p.x, 50.0), 0.0, snappedf(p.z, 50.0))
	# Góry na horyzoncie też (jak tło - nie da się do nich dojechać).
	# Biom (paleta, horyzont, morze) - w _watch_track, 5 razy na sekundę.
	if _horizon:
		_horizon.global_position = Vector3(p.x, 0.0, p.z)


func _follow_car(delta: float) -> void:
	var car_xf := car.get_global_transform_interpolated()
	_update_cockpit_transparency()
	if _xr_ready or _cockpit_on_pc:
		# Sztywno z autem. W goglach to jedyna wygodna opcja - kamera
		# goniąca z opóźnieniem to przepis na chorobę lokomocyjną.
		origin.global_transform = car_xf * car.seat.transform
		return
	# Kamera z tyłu: podąża za autem z opóźnieniem i nie przechyla się.
	var target := car_xf * car.chase_point.transform
	var flat_fwd := -car_xf.basis.z
	flat_fwd.y = 0.0
	if flat_fwd.length_squared() < 0.01:
		flat_fwd = -_chase_xf.basis.z
	var t := 1.0 - exp(-6.0 * delta)
	var pos := _chase_xf.origin.lerp(target.origin, t)
	var look_at_point := car_xf.origin + Vector3.UP * 0.8 + flat_fwd.normalized() * 4.0
	_chase_xf = Transform3D(Basis(), pos).looking_at(look_at_point, Vector3.UP)
	origin.global_transform = _chase_xf


## Przezroczystość kabiny tylko w widoku z kokpitu; z zewnątrz auto pełne.
func _update_cockpit_transparency() -> void:
	var t := 0.0
	var inside := _mode == Mode.DRIVE and (_xr_ready or _cockpit_on_pc)
	# Bryła modelu z epoki niewidoczna z kokpitu (StuntCar.STYLE_BODY_LAYER).
	camera.set_cull_mask_value(10, not inside)
	if inside:
		var gs := _gs
		t = (gs.cockpit_alpha if gs else 40) / 100.0
	car.set_cockpit_transparency(t)


func _fly(delta: float) -> void:
	car.set_cockpit_transparency(0.0)
	var dir := Vector3.ZERO
	var spd := fly_speed
	# W VR kierunek bierzemy z głowy, na płasko z samego origin (kamera stoi w nim).
	var b := camera.global_basis if _xr_ready else origin.global_basis

	if _xr_ready:
		var rs: Vector2 = right_hand.get_vector2("primary")
		var ls: Vector2 = left_hand.get_vector2("primary")
		# Obrót wokół głowy, nie wokół środka pokoju - inaczej świat się zarzuca.
		if absf(rs.x) > 0.15:
			_rotate_origin_around_head(Vector3.UP, -rs.x * FLY_TURN_RATE * delta)
		if right_hand.get_float("grip") > 0.5:
			if absf(rs.y) > 0.15:
				_rotate_origin_around_head(b.x, rs.y * FLY_TURN_RATE * delta)
		else:
			dir += -b.z * rs.y
		dir += b.x * ls.x + Vector3.UP * ls.y
		if right_hand.get_float("trigger") > 0.5:
			spd *= boost_multiplier
	else:
		var fwd := Input.get_axis("ui_down", "ui_up")
		var side := Input.get_axis("ui_left", "ui_right")
		dir += -b.z * fwd + b.x * side
		if Input.is_key_pressed(KEY_Q):
			dir += Vector3.DOWN
		if Input.is_key_pressed(KEY_E):
			dir += Vector3.UP
		if Input.is_key_pressed(KEY_SHIFT):
			spd *= boost_multiplier

	if dir.length_squared() > 0.0001:
		origin.global_position += dir.normalized() * spd * delta


const FLY_TURN_RATE := deg_to_rad(80.0)     # rad/s przy pełnym wychyleniu


## Obraca XROrigin tak, żeby głowa gracza (kamera) została w miejscu.
func _rotate_origin_around_head(axis: Vector3, angle: float) -> void:
	var head := camera.global_position
	var xf := origin.global_transform
	xf.origin -= head
	xf = Transform3D(Basis(axis.normalized(), angle), Vector3.ZERO) * xf
	xf.origin += head
	origin.global_transform = xf


func _set_mode(m: Mode) -> void:
	_mode = m
	if m == Mode.FLY:
		# Startujemy lot z miejsca, w którym była kamera, tylko bez przechyłu.
		var e := origin.global_basis.get_euler()
		_pitch = 0.0
		_yaw = e.y
		origin.global_transform = Transform3D(Basis(Vector3.UP, _yaw), origin.global_position)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_chase_xf = car.global_transform * car.chase_point.transform
		if _xr_ready:
			XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)


# --------------------------------------------------------------------------
# Tor: zapamiętywanie bezpiecznego miejsca i podnoszenie spadniętego auta
# --------------------------------------------------------------------------

var _ahead_t := 0.0
var _ahead_log_t := 0.0
## Siatka bezpieczeństwa dobudowy (EndlessTrack.ensure_ahead) i diagnostyka:
## gdy przed autem zostaje mniej niż 600 m trasy, raz na sekundę stan do logu
## (`./quest.sh log` po zgłoszeniu "trasa się skończyła").
func _keep_track_ahead(delta: float) -> void:
	_ahead_t -= delta
	if _ahead_t > 0.0:
		return
	_ahead_t = 0.25
	var left: float = track.total_length() - _last_safe_dist
	track.ensure_ahead(car.global_position, left)
	_ahead_log_t -= 0.25
	if left < 600.0 and _ahead_log_t <= 0.0:
		_ahead_log_t = 1.0
		print("TRASA KONCZY SIE: zostało %.0f m, _last_safe_dist %.0f, %s" % [
				left, _last_safe_dist, track.debug_state()])


func _watch_track(delta: float) -> void:
	_track_check_timer -= delta
	if _track_check_timer > 0.0:
		return
	# nearest_sample szuka liniowo, więc nie wołamy go co krok fizyki.
	const PERIOD := 0.2
	_track_check_timer = PERIOD

	var info: Dictionary = track.lateral_offset(car.global_position)
	if info.is_empty() or not info.has("sample"):
		return
	var s: Dictionary = info["sample"]
	current_limit = s.get("limit", 100.0)
	_lateral = info.get("offset", 0.0)
	_rain_target = float(s.get("rain", 0))
	# Autostrada: opad z warstwy pogody (WeatherPlan), pod dachem nic.
	if _endless and track.get("weather") != null:
		_weather_now = track.weather.weather(_last_safe_dist)
		_rain_target = 0.0 if bool(s.get("roof", false)) else float(_weather_now["rain"])
	_update_env(s)
	if _endless:
		# Dobudowa trasy przed autem, sprzątanie za nim. Bez cofania: auto
		# w locie nad wcześniejszym kawałkiem cofało `_current` i okno
		# szukania mogło zgubić kawałek z autem (hipoteza chmury 2026-11-11).
		track.update_progress(maxf(float(s["dist"]), _last_safe_dist))
		# Biom: przejście trwa 2,8 km - 5 razy na sekundę wystarczy (było co klatkę).
		_update_biome()
		_update_river()
		var sec: int = track.section_at(_last_safe_dist)
		if sec > _last_section:
			_last_section = sec
			# Premia za odcinek: średnia od bramy do bramy (w czasie gry).
			var d1: float = track.checkpoint_before(_last_safe_dist)
			var dt_s := race_time - _sec_t0
			if race_state == Race.RACING and dt_s > 1.0 and d1 > _sec_d0:
				var avg := (d1 - _sec_d0) / dt_s * 3.6
				print("ODCINEK %d: %.0f m w %.1f s, średnio %.0f km/h" % [sec - 1, d1 - _sec_d0, dt_s, avg])
				_score_pay(score.section_done(avg))
			_sec_t0 = race_time
			_sec_d0 = d1
			feud.roll_relations(range(GANGS), sec)
			_chirp.play()
			score.new_section()
			_reset_bot_pattern(sec)
		if _next_ws.is_empty() or float(_next_ws["stop"]) < _last_safe_dist - 5.0:
			# Nie ten sam warsztat drugi raz: auto staje tuż przy linii postoju.
			_next_ws = track.next_workshop(maxf(_last_safe_dist, _ws_done_stop + 1.0))
		if _next_station.is_empty() or float(_next_station["end"]) < _last_safe_dist:
			_next_station = track.next_station(_last_safe_dist)
			if not _next_ws.is_empty():
				_ws_xf = track.transform_at_distance(_next_ws["stop"])
				_ws_prev_side = -1.0
	var surface: Vector3 = track.to_global(s["pos"])
	var below: float = surface.y - car.global_position.y

	# 3 koła wystarczą: na przechyłce miękkie zawieszenie często unosi jedno.
	# Skok dystansu o ponad 300 m wstecz to nie jazda, tylko auto po locie
	# przypisane do wcześniejszego fragmentu (jazda 2026-11-09: wąwóz, po
	# skoku 2330 -> 1139 m, potem odrodzenie na usuniętym kawałku = "trasa
	# się skończyła") - takiej pozycji nie uznajemy za bezpieczną.
	var jumped_back := _endless and float(s["dist"]) < _last_safe_dist - 300.0
	if info["on_track"] and car.wheels_on_ground >= 3 and below < 2.0 and not jumped_back:
		_last_safe_dist = float(s["dist"])
		_max_dist = maxf(_max_dist, _last_safe_dist)
		_fallen_time = 0.0
	else:
		var resting := car.linear_velocity.length() < 3.0
		# Pod torem na ziemi nie ma czego szukać - po spadnięciu zawsze dźwig.
		var fell := below > fall_depth and (car.wheels_on_ground > 0 or resting)
		var upside_down := car.global_basis.y.y < 0.3 and resting
		# Poza trasą: daleko w bok albo dużo nad/pod jezdnią. W wąwozie jezdnia
		# leży nisko (2-25 m nad ziemią), więc "spadnięcie" się nie włączało
		# i auto wyrzucone z wąwozu zostawało na trawie (zgłoszenie: wirowanie
		# skończyło się "na zielonym placu").
		var hw := float(s["width"]) * 0.5
		# Odległość w poziomie od najbliższego punktu osi, nie tylko w poprzek:
		# auto jadące na wprost od łuku ma mały "offset" (wzdłuż stycznej),
		# choć jest kilometry od drogi (jazda 2026-11-10, "droga się urwała").
		var flat := (car.global_position - surface) * Vector3(1, 0, 1)
		var off_side := absf(float(info.get("offset", 0.0))) > hw + 15.0 or flat.length() > hw + 25.0
		# Lot nad jezdnią (żadne koło nie dotyka, auto nad drogą, nie
		# z boku) to nie upadek - przy 200 km/h ze skoczni auto leci ~12 m
		# nad drogą przez 2-3 s i reguła "> 6 m nad jezdnią" ogłaszała
		# upadek w powietrzu (użytkownik 2026-11-09: "gra uznaje, że
		# samochód gdzieś zawisł i wybucha - dajmy mu chociaż upaść").
		# Limit 10 s na wypadek auta zawieszonego wysoko na czymś.
		var flying := car.wheels_on_ground == 0 and below < 0.0 and not off_side and car.airtime < 10.0
		var off_track := off_side or below > 6.0 or (below < -6.0 and not flying)
		fell = fell or (off_track and _endless)
		# Zawieszone podwoziem na krawędzi jezdni, koła w powietrzu - samo nie zjedzie.
		var beached := car.wheels_on_ground < 3 and car.linear_velocity.length() < 0.5
		if beached:
			_stuck_diag(s, fell, upside_down, below)
		if fell or upside_down or beached or car.global_position.y < -50.0:
			# Chwila na zrozumienie, co się stało, potem dźwig stawia auto na torze.
			# Przy zawieszeniu na krawędzi dłużej - gracz może jeszcze próbować zjechać.
			_fallen_time += PERIOD
			var wait := 3.0 if beached and not (fell or upside_down) else 1.5
			if _fallen_time > wait:
				if _endless and race_state == Race.RACING and (fell or upside_down \
						or car.global_position.y < -50.0):
					# Na dachu (nie da się jechać dalej) albo spadnięte = utrata życia.
					lose_life("auto na dachu" if upside_down else "upadek")
				elif _canyon:
					_right_car()          # zawieszone na krawędzi - tylko na koła
				else:
					_use_crane(true)
		else:
			_fallen_time = 0.0


## Dźwig na żądanie gracza albo po upadku. Na trasie bez końca w trakcie
## jazdy zabiera życie; po ostatnim - koniec jazdy.
var _auto_rights: Array[float] = []
func _use_crane(automatic := false) -> void:
	_rec.reset()                      # przeniesienie auta - nie do powtórki
	if _endless and race_state == Race.RACING:
		# Trasa bez końca: bez dźwigu. Auto na kołach, ale utknięte - stawiamy
		# na koła w miejscu. Auto na dachu - to utrata życia (wybuch), żadnego
		# ratowania przyciskiem.
		if car.global_basis.y.y < 0.3:
			lose_life("auto na dachu")
			return
		# Siatka bezpieczeństwa (użytkownik przez chmurę 2026-11-11): gdy
		# samo stawianie w tym samym miejscu nie pomaga (2 razy w 10 s),
		# trzecie stawia 15 m dalej, czwarte to utrata życia - gracz nie
		# utknie na zawsze. Tylko automatyczne (zawieszenie na krawędzi),
		# nie przycisk gracza.
		var ahead := 0.0
		if automatic:
			# Czas gry (race_time), nie zegar - przy tempie gry < 100% okno
			# 10 s zegara mieściło mniej postawień (przegląd PR #61).
			var now := race_time
			_auto_rights = _auto_rights.filter(func(x: float) -> bool: return now - x < 10.0)
			if _auto_rights.size() >= 3:
				_auto_rights.clear()
				lose_life("utknięcie")
				return
			if _auto_rights.size() == 2:
				ahead = 15.0
			_auto_rights.append(now)
		_right_car(ahead)
		return
	if _canyon:
		_right_car()
		return
	if _endless and race_state == Race.RACING and cranes_left >= 0:
		cranes_left -= 1
		if cranes_left < 0:
			cranes_left = 0
			_game_over()
			return
	_respawn()


## Stawia auto na koła tam, gdzie stoi: na najbliższej próbce toru,
## kierunkiem jazdy. Uszkodzenia zostają.
func _right_car(ahead := 0.0) -> void:
	var info: Dictionary = track.lateral_offset(car.global_position)
	if not info.has("sample"):
		return
	var d := float(info["sample"]["dist"]) + ahead
	var dmg: Dictionary = car.damage.duplicate(true)
	var before := car.global_position
	var xf := _safe_pose(d)
	print("NA KOŁA: d %.1f (+%.0f), z %s na %s" % [d, ahead,
			before.snapped(Vector3.ONE * 0.1), xf.origin.snapped(Vector3.ONE * 0.1)])
	car.place(xf)
	car.damage = dmg
	_fallen_time = 0.0


## Diagnostyka "auto zawisło po locie" (endless_test autostrada, ziarna
## 222 i 3333: 0 km/h, koła bez kontaktu, 9 min bez odrodzenia). Raz na
## sekundę: stan, promienie spod mocowań kół (co jest pod autem), kawałki.
var _stuck_log_t := 0.0
func _stuck_diag(s: Dictionary, fell: bool, upside_down: bool, below: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _stuck_log_t < 1.0:
		return
	_stuck_log_t = now
	var space := get_world_3d().direct_space_state
	var parts := PackedStringArray()
	var up := car.global_basis.y
	for w in car.wheels:
		var m := car.global_transform * w.mount
		var q := PhysicsRayQueryParameters3D.create(m + up * 0.5, m - up * 3.0)
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			parts.append("nic")
		else:
			var o: Object = hit["collider"]
			parts.append("%s %.2f m" % [(o as Node).name if o is Node else "?",
					(m - (hit["position"] as Vector3)).length()])
	print("ZAWIESZONE: stan %d, _fallen_time %.1f, fell %s, dach %s, pod jezdnią %.2f m, koła %d, dist %.1f, up.y %.2f, ostatni kontakt %s | koła: %s | %s" % [
			race_state, _fallen_time, fell, upside_down, below, car.wheels_on_ground,
			float(s["dist"]), up.y, str(car.last_hit.get("what", "-")),
			", ".join(parts), track.debug_state() if _endless else ""])


## Bezpieczne miejsce na postawienie auta od dystansu `d`: prawy pas (na
## osi drogi bywa skalna wyspa rozwidlenia), sprawdzone zapytaniem fizyki,
## że nic tam nie stoi (wyspa, wysepka zjazdu, dystrybutor, bot). Zajęte -
## 8 m dalej, do 8 prób. Auto postawione wewnątrz przeszkody było z niej
## wypychane i wirowało bez końca (zgłoszenie użytkownika).
func _safe_pose(d: float) -> Transform3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.4, 4.8)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.exclude = [car.get_rid()]
	var space := get_world_3d().direct_space_state
	# Zapas, gdy wszystkie 8 prób to przerwa (przegląd chmury R3): było
	# Transform3D() - auto w zerze świata, po przesunięciach WorldOrigin
	# daleko od drogi. transform_at_distance sam cofa się przed przerwę.
	var xf: Transform3D = track.transform_at_distance(d)
	xf.origin += xf.basis.y * 0.9
	for i in range(8):
		var dd := d + 8.0 * i
		if track.is_gap_at(dd):
			continue
		xf = track.transform_at_distance(dd)
		var smp: Dictionary = track.sample_at(dd)
		var w: float = smp["width"] if not smp.is_empty() else 9.0
		var lane := StuntTrack.lane_width(w)
		if _endless and track.autostrada:
			lane = hwy_lane_off(0)          # prawy pas autostrady, nie pas awaryjny
		xf.origin += xf.basis.x * lane + xf.basis.y * 0.9
		# Bryła auta 0,25-1,65 m nad jezdnią - jezdnia sama się nie liczy.
		q.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * 0.25)
		if space.intersect_shape(q, 1).is_empty():
			return xf
	return xf


## Potrącenie innego auta: -20 s od czasu (raz na zderzenie). Kusi - ale
## bot wpada w szał, oszukuje (mocniejszy silnik), goni i taranuje.
func _on_player_hit(body: Node) -> void:
	if body == _extremist:
		_x_contact_t = race_time
	# Najpierw typ: "in" na tablicy typowanej zgłasza błąd dla ściany (StaticBody3D).
	if not (body is StuntCar and body in _bots) or race_state != Race.RACING:
		return
	var now := race_time
	if now - float(_last_hit.get(body, -100.0)) < 2.0:
		return
	_last_hit[body] = now
	# Potrącenie: mandat i punkty liczy ScoreKeeper (BotDriver zgłasza
	# pościg "player_hit" i kontakt) - bez dawnej premii czasowej.


func _on_car_wrecked() -> void:
	if _endless and race_state == Race.RACING:
		lose_life("auto rozbite")


## Ośmiobitowe ćwierknięcie: trzy tony fali prostokątnej (H5, E6, H6) po
## 1/12 s - razem ćwierć sekundy - powtórzone 2 razy co pół sekundy.
## Generowane w kodzie jako 8-bitowy PCM, jak w starych konsolach.
func _make_chirp() -> AudioStreamWAV:
	var rate := 22050
	var smp := PackedInt32Array()
	smp.resize(int(rate * 0.75))
	smp.fill(0)
	var tones := [987.8, 1318.5, 1975.5]
	for rep in range(2):
		var start := int(rep * 0.5 * rate)
		for k in range(3):
			var n0 := start + int(k * rate / 12.0)
			var n1 := start + int((k + 1) * rate / 12.0)
			var period: float = rate / tones[k]
			for n in range(n0, n1):
				# Fala prostokątna, 8 bitów ze znakiem; krótkie wyciszenie na
				# końcu każdego tonu, żeby nie trzaskało.
				var env := clampf((n1 - n) / 80.0, 0.0, 1.0)
				var v := 70 if fmod(n - n0, period) < period * 0.5 else -70
				smp[n] = int(v * env)
	return AudioUtil.wav(smp, rate, 8)


## Utrata życia: auto wybucha, kamera odjeżdża i pokazuje eksplozję,
## potem nowe auto na miejscu wypadku (albo koniec jazdy).
func lose_life(reason: String) -> void:
	if race_state != Race.RACING or _grace_t > 0.0:
		return
	if reason in REPLAY_REASONS and _mode == Mode.DRIVE and _rec.count() > 30 \
			and (_gs == null or bool(_gs.get("crash_replay"))):
		_start_replay(reason)
		return
	_begin_explosion(reason)


## Wybuch i kamera wybuchu. keep_view: po powtórce - wybuch na żywo z tego
## samego miejsca (kamera obserwatora stoi).
func _begin_explosion(reason: String, keep_view := false) -> void:
	race_state = Race.EXPLODING
	_cine_reason = reason
	_cine_t = 0.0
	_explode(car)
	if car.get_node_or_null("Audio"):
		car.get_node("Audio").thud(1.0)
	car.visible = false
	car.freeze = true
	# Kamera: z obecnego miejsca w tył i w górę, przodem do wybuchu.
	# Tylko obrót w poziomie - w goglach obrót w pionie robi głowa gracza.
	_cine_from = origin.global_transform
	var p := car.global_position
	var back := car.global_basis.z * Vector3(1, 0, 1)
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	var cam_pos := p + back * 13.0 + Vector3.UP * 6.0
	var flat_dir := (p - cam_pos) * Vector3(1, 0, 1)
	_cine_to = Transform3D(Basis.looking_at(flat_dir.normalized(), Vector3.UP), cam_pos)
	if not _xr_ready:
		_cine_to = Transform3D(Basis(), cam_pos).looking_at(p, Vector3.UP)
	if keep_view:
		_cine_to = _cine_from
	_result_label.visible = false
	print("Utrata życia: %s" % reason)


func _cinematic(delta: float) -> void:
	_cine_t += delta
	var k := smoothstep(0.0, 1.0, clampf(_cine_t / CINE_MOVE, 0.0, 1.0))
	origin.global_transform = _cine_from.interpolate_with(_cine_to, k)
	if _cine_t >= CINE_TOTAL:
		_after_explosion()


# --------------------------------------------------------------------------
# Powtórka wypadku (inbox 2026-11-12-powtorka-wypadku; użytkownik: "jeśli
# gracz zginął w wypadku, to robimy powtórzone ujęcie ... obserwatorem
# podążającym za samochodem, trochę z góry"). Zapis w ReplayRecorder
# (ostatnie 6 s), odtwarzanie ze zwolnieniem wokół uderzenia, potem wybuch
# na żywo z miejsca kamery. Kamera obserwatora: tylko pozycja i obrót
# w poziomie (horyzont równy - w goglach pion robi głowa), za autem i nad
# nim, sprężyna krytycznie tłumiona - bez szarpnięć.
# --------------------------------------------------------------------------

const REPLAY_REASONS := ["auto rozbite", "auto na dachu", "upadek"]
const REPLAY_FADE := 0.2              # [s] ściemnienie przed i rozjaśnienie po przejściu
const REPLAY_BACK := 8.0              # [m] kamera za autem (wzdłuż trasy)
const REPLAY_UP := 5.5                # [m] nad jezdnią (użytkownik 2026-11-13: "nieco wyżej"; było 4)
const REPLAY_ABOVE_CAR := 3.5         # [m] co najmniej nad autem
const REPLAY_TUNNEL_BACK := 6.0       # [m] za autem pod stropem
const REPLAY_CEIL_GAP := 0.6          # [m] kamera pod stropem
const REPLAY_SPRING := 0.4            # [s] czas reakcji sprężyny kamery
const REPLAY_YAW_T := 0.5             # [s] wygładzenie kierunku trasy
const REPLAY_PITCH := 32.0            # [°] w dół, tylko bez gogli
const REPLAY_OTHERS_R := 120.0        # [m] boty w zapisie
const REPLAY_SKIP_DELAY := 0.8        # [s] po ściemnieniu - wcześniej spust nie pomija
var _rec := ReplayRecorder.new()
var _rec_frame := PackedFloat32Array()
var _rec_ids := PackedInt64Array()
var _rec_poses := PackedFloat32Array()
var _rec_cands: Array[StuntCar] = []  # bez alokacji przy każdej klatce zapisu
var _rp_live := {}                    # instance_id aut żywych w chwili śmierci
var _rp_prev_pos := Vector3.ZERO      # obrót kół w powtórce z drogi auta
var _rec_hit := 0.0                   # najmocniejszy impuls od ostatniej klatki zapisu
var _rp_t := 0.0                      # czas zapisu odtwarzanej klatki
var _rp_key := 0.0
var _rp_end := 0.0
var _rp_fade := 0.0                   # czas od początku powtórki (ściemnienie)
var _rp_skip := false
var _rp_reason := ""
var _rp_car_xf: Transform3D
var _rp_saved: Array = []             # [auto, xf, v, ω, tryb procesu, widoczne]
var _rp_cam := Vector3.ZERO
var _rp_cam_v := Vector3.ZERO
var _rp_goal := Vector3.ZERO
var _rp_goal_v := Vector3.ZERO
var _rp_yaw := 0.0
var _rp_yaw_goal := 0.0
var _rp_road_y := 0.0
var _rp_ceil := INF
var _rp_probe_t := 0.0
var _rp_label: Label3D
var _rp_veil: MeshInstance3D


## Klatka gracza do zapisu - w kroku fizyki, tylko w jeździe.
## Dźwięki innych aut z Dopplerem (TrafficAudio): do 4 najbliższych w 80 m.
## Słuchacz to głowa gracza, prędkość słuchacza - auta (w jeździe).
## Bench: "traffic_audio" w liście wyłączeń.
var _traffic_audio: TrafficAudio
var _ta_cands: Array = []
func _update_traffic_audio(delta: float) -> void:
	if not _endless or not Bench.on("traffic_audio"):
		return
	var t0 := Time.get_ticks_usec()
	if _traffic_audio == null:
		_traffic_audio = TrafficAudio.new()
		add_child(_traffic_audio)
	_traffic_audio.listener_pos = camera.global_position
	_traffic_audio.listener_vel = car.linear_velocity if (_mode == Mode.DRIVE and race_state == Race.RACING) else Vector3.ZERO
	_ta_cands.clear()
	_ta_cands.append_array(_bots)
	for o in _oncoming:
		_ta_cands.append(o.car)
	_traffic_audio.update(_ta_cands, delta)
	Perf.add("auta_dzwiek", t0)


func _record_replay() -> void:
	if race_state != Race.RACING or _mode != Mode.DRIVE:
		return
	if _gs and not bool(_gs.get("crash_replay")):
		return
	var t0 := Time.get_ticks_usec()
	_rec_hit = maxf(_rec_hit, car.hit_j)
	if _rec_frame.size() != ReplayRecorder.P_STRIDE:
		_rec_frame.resize(ReplayRecorder.P_STRIDE)
		_rec_ids.resize(ReplayRecorder.MAX_OTHERS)
		_rec_poses.resize(ReplayRecorder.MAX_OTHERS * ReplayRecorder.O_STRIDE)
	var f := _rec_frame
	var xf := car.global_transform
	_put_xf(f, 0, xf)
	var ground := 0
	for i in range(mini(car.wheels.size(), 4)):
		var w: StuntCar.Wheel = car.wheels[i]
		f[ReplayRecorder.I_WHEELS + i * 3] = w.steer_angle
		f[ReplayRecorder.I_WHEELS + i * 3 + 1] = w.spin
		f[ReplayRecorder.I_WHEELS + i * 3 + 2] = w.spring_len
		if w.contact:
			ground += 1
	f[ReplayRecorder.I_WHEEL_DEG] = car.steering_wheel_deg
	f[ReplayRecorder.I_THROTTLE] = car.throttle
	f[ReplayRecorder.I_BRAKE] = car.brake
	var inv := xf.affine_inverse()
	_put_xf(f, ReplayRecorder.I_CTRL_L, inv * left_hand.global_transform)
	_put_xf(f, ReplayRecorder.I_CTRL_R, inv * right_hand.global_transform)
	f[ReplayRecorder.I_RPM] = car.engine_rpm
	f[ReplayRecorder.I_GAS] = car.throttle
	f[ReplayRecorder.I_HIT] = _rec_hit
	f[ReplayRecorder.I_GROUND] = ground
	if not _rec.push(race_time, f):
		return
	_rec_hit = 0.0
	# Inne auta w promieniu REPLAY_OTHERS_R (pierwsze MAX_OTHERS).
	var n := 0
	var p := xf.origin
	var cands := _rec_cands
	cands.clear()
	cands.append_array(_bots)
	for o in _oncoming:
		cands.append(o.car)
	for b in cands:
		if n >= ReplayRecorder.MAX_OTHERS:
			break
		if not is_instance_valid(b) or not b.visible or b.global_position.distance_squared_to(p) > REPLAY_OTHERS_R * REPLAY_OTHERS_R:
			continue
		_rec_ids[n] = b.get_instance_id()
		var k := n * ReplayRecorder.O_STRIDE
		_put_xf(_rec_poses, k, b.global_transform)
		_rec_poses[k + 7] = b.wheels[0].steer_angle if not b.wheels.is_empty() else 0.0
		n += 1
	for s in range(n, ReplayRecorder.MAX_OTHERS):
		_rec_ids[s] = 0
	_rec.push_others(race_time, _rec_ids, _rec_poses)
	Perf.add("replay_rec", t0)


static func _put_xf(arr: PackedFloat32Array, i: int, xf: Transform3D) -> void:
	var q := xf.basis.get_rotation_quaternion()
	arr[i] = xf.origin.x
	arr[i + 1] = xf.origin.y
	arr[i + 2] = xf.origin.z
	arr[i + 3] = q.x
	arr[i + 4] = q.y
	arr[i + 5] = q.z
	arr[i + 6] = q.w


static func _get_xf(arr: PackedFloat32Array, i: int) -> Transform3D:
	var q := Quaternion(arr[i + 3], arr[i + 4], arr[i + 5], arr[i + 6]).normalized()
	return Transform3D(Basis(q), Vector3(arr[i], arr[i + 1], arr[i + 2]))


func _start_replay(reason: String) -> void:
	race_state = Race.REPLAY
	_rp_reason = reason
	_rp_skip = false
	_rp_fade = 0.0
	_rp_key = _rec.key_time()
	_rp_t = _rec.t_start()
	_rp_end = _rec.t_end()
	_rp_car_xf = car.global_transform
	car.freeze = true
	car.throttle = 0.0
	car.brake = 0.0
	_rp_saved.clear()
	_rp_live.clear()
	var others: Array[StuntCar] = []
	others.assign(_bots)
	for o in _oncoming:
		others.append(o.car)
	for b in others:
		if is_instance_valid(b):
			_rp_saved.append([b, b.global_transform, b.linear_velocity, b.angular_velocity, b.process_mode, b.visible])
			_rp_live[b.get_instance_id()] = true
			b.process_mode = Node.PROCESS_MODE_DISABLED
	_result_label.visible = false
	print("POWTÓRKA: %s, %.1f s, kluczowa chwila %.2f s przed końcem" % [reason, _rp_end - _rp_t, _rp_end - _rp_key])


## Krok fizyki powtórki: auto i boty z zapisu (stałe tempo kroków - płynne
## przy interpolacji fizyki).
func _replay_physics(delta: float) -> void:
	_rp_fade += delta
	if _rp_fade < REPLAY_FADE:
		return                        # ściemnienie - jeszcze chwila wypadku
	if _rp_veil_switch():
		return
	if _rp_skip or _rp_t >= _rp_end:
		_end_replay()
		return
	var rt0 := _rp_t
	_rp_t = minf(ReplayRecorder.advance(_rp_t, delta, _rp_key), _rp_end)
	_apply_replay_frame(_rp_t - rt0)


## Pierwsza klatka po ściemnieniu: przejście do powtórki (kamera od razu
## na miejscu, bez dolatywania).
func _rp_veil_switch() -> bool:
	if _rp_label and _rp_label.visible:
		return false
	_apply_replay_frame()
	car.reset_physics_interpolation()
	if _player_dummy:
		_player_dummy.set_replay(true)
	if _track_hud:
		_track_hud.visible = false
	_replay_probe()
	_rp_yaw = _rp_yaw_goal
	_rp_cam = _replay_cam_goal(car.global_position)
	_rp_goal = _rp_cam
	_rp_goal_v = Vector3.ZERO
	_rp_cam_v = Vector3.ZERO
	_replay_label(true)
	return true


## rec_dt: krok czasu zapisu od poprzedniej klatki (0 = pierwsza klatka).
func _apply_replay_frame(rec_dt := 0.0) -> void:
	var fr := _rec.player_at(_rp_t)
	car.global_transform = _get_xf(fr, 0)
	# Szybko (> ~40 m/s) obrót z zapisu 60 Hz aliasuje (> π na próbkę przy
	# ~62 m/s) - koła kręcone z drogi auta (przegląd PR #84).
	var ds := (car.global_position - _rp_prev_pos).dot(-car.global_basis.z)
	var from_motion := rec_dt > 0.0 and absf(ds) / rec_dt > 40.0
	_rp_prev_pos = car.global_position
	for i in range(mini(car.wheels.size(), 4)):
		var w: StuntCar.Wheel = car.wheels[i]
		w.steer_angle = fr[ReplayRecorder.I_WHEELS + i * 3]
		if from_motion:
			w.spin = wrapf(w.spin + ds / car.wheel_radius, -PI, PI)
		else:
			w.spin = fr[ReplayRecorder.I_WHEELS + i * 3 + 1]
		w.spring_len = fr[ReplayRecorder.I_WHEELS + i * 3 + 2]
		w.omega = 0.0
	car.steering_wheel_deg = fr[ReplayRecorder.I_WHEEL_DEG]
	car.throttle = fr[ReplayRecorder.I_THROTTLE]
	car.brake = fr[ReplayRecorder.I_BRAKE]
	car.engine_rpm = fr[ReplayRecorder.I_RPM]
	if _player_dummy:
		_player_dummy.replay_hands = [_get_xf(fr, ReplayRecorder.I_CTRL_L), _get_xf(fr, ReplayRecorder.I_CTRL_R)]
		_player_dummy.update(car.throttle, car.brake, get_physics_process_delta_time())
	var others := _rec.others_at(_rp_t)
	# Auto nieobecne w tej chwili zapisu (dalej niż 120 m, w puli) - ukryte.
	for sv in _rp_saved:
		var sb: StuntCar = sv[0]
		if is_instance_valid(sb):
			sb.visible = others.has(sb.get_instance_id())
	for id in others:
		# Auto, które przed śmiercią wróciło do puli - zostaje w puli.
		if not _rp_live.has(id):
			continue
		var b := instance_from_id(id) as StuntCar
		if b == null or not is_instance_valid(b):
			continue
		var o: Array = others[id]
		b.global_transform = o[0]
		if b.wheels.size() > 1:
			b.wheels[0].steer_angle = o[1]
			b.wheels[1].steer_angle = o[1]


func _end_replay() -> void:
	car.global_transform = _rp_car_xf
	car.reset_physics_interpolation()
	for sv in _rp_saved:
		var b: StuntCar = sv[0]
		if not is_instance_valid(b):
			continue
		b.global_transform = sv[1]
		b.visible = sv[5]
		b.process_mode = sv[4]
		b.linear_velocity = sv[2]
		b.angular_velocity = sv[3]
		b.reset_physics_interpolation()
	_rp_saved.clear()
	if _player_dummy:
		_player_dummy.set_replay(false)
	if _track_hud:
		_track_hud.visible = true
	car.steering_wheel_deg = NAN
	_replay_label(false)
	print("POWTÓRKA: koniec%s" % (" (pominięta)" if _rp_skip else ""))
	race_state = Race.RACING
	_begin_explosion(_rp_reason, true)
	_rec.reset()


## Kierunek trasy, wysokość jezdni i strop (tunel) przy aucie - 10 razy na
## sekundę (nearest_sample szuka liniowo).
func _replay_probe() -> void:
	var p := car.global_position
	var s: Dictionary = track.nearest_sample(p) if track else {}
	if not s.is_empty():
		var r: Vector3 = (track.global_basis * (s["right"] as Vector3)) * Vector3(1, 0, 1)
		if r.length() > 0.1:
			var fwd := Vector3.UP.cross(r.normalized())
			_rp_yaw_goal = atan2(-fwd.x, -fwd.z)
		_rp_road_y = track.to_global(s["pos"]).y
	else:
		var v := -car.global_basis.z
		_rp_yaw_goal = atan2(-v.x, -v.z)
		_rp_road_y = p.y
	# Strop nad autem (tunel): promień w górę po świecie statycznym.
	_rp_ceil = INF
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.UP * (REPLAY_UP + 3.0))
	q.exclude = [car.get_rid()]
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and not (hit["collider"] is StuntCar):
		_rp_ceil = (hit["position"] as Vector3).y


func _replay_cam_goal(p: Vector3) -> Vector3:
	var back := Vector3(sin(_rp_yaw), 0.0, cos(_rp_yaw))     # +Z obrotu = za autem
	if _rp_ceil < INF:
		var g := p + back * REPLAY_TUNNEL_BACK
		g.y = minf(maxf(_rp_road_y, p.y) + 2.2, _rp_ceil - REPLAY_CEIL_GAP)
		return g
	var g := p + back * REPLAY_BACK
	g.y = maxf(_rp_road_y + REPLAY_UP, p.y + REPLAY_ABOVE_CAR)
	return g


func _replay_camera(delta: float) -> void:
	_update_replay_veil()
	if _rp_label == null or not _rp_label.visible:
		return                        # ściemnienie - kamera jeszcze w aucie
	_rp_probe_t -= delta
	if _rp_probe_t <= 0.0:
		_rp_probe_t = 0.1
		_replay_probe()
	_rp_yaw = lerp_angle(_rp_yaw, _rp_yaw_goal, 1.0 - exp(-delta / REPLAY_YAW_T))
	var p := car.get_global_transform_interpolated().origin
	var goal := _replay_cam_goal(p)
	# Sprężyna krytycznie tłumiona (ω = 1/τ), półjawny Euler, z prędkością
	# celu (bez niej kamera wisiała 2v/ω ~ 22 m dalej przy 100 km/h).
	if delta > 0.0:
		_rp_goal_v = _rp_goal_v.lerp((goal - _rp_goal) / delta, 1.0 - exp(-delta / 0.1))
	_rp_goal = goal
	var w := 1.0 / REPLAY_SPRING
	_rp_cam_v += (w * w * (goal - _rp_cam) + 2.0 * w * (_rp_goal_v - _rp_cam_v)) * delta
	_rp_cam += _rp_cam_v * delta
	var b := Basis(Vector3.UP, _rp_yaw)
	if not _xr_ready:
		b = b * Basis(Vector3.RIGHT, deg_to_rad(-REPLAY_PITCH))
	origin.global_transform = Transform3D(b, _rp_cam)


func _replay_label(on: bool) -> void:
	if _rp_label == null:
		_rp_label = Label3D.new()
		_rp_label.name = "ReplayLabel"
		_rp_label.text = "● POWTÓRKA"
		_rp_label.font_size = 48
		_rp_label.pixel_size = 0.0012
		_rp_label.modulate = Color(1.0, 0.25, 0.2)
		_rp_label.outline_size = 12
		_rp_label.no_depth_test = true
		_rp_label.position = Vector3(-0.32, 0.26, -1.2)
		camera.add_child(_rp_label)
	_rp_label.visible = on


## Ściemnienie przy przejściu do powtórki: czarna zasłona przed kamerą,
## 0-1 przez REPLAY_FADE, potem 1-0.
func _update_replay_veil() -> void:
	if _rp_veil == null:
		_rp_veil = MeshInstance3D.new()
		_rp_veil.name = "ReplayVeil"
		var q := QuadMesh.new()
		q.size = Vector2(4.0, 4.0)
		_rp_veil.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		m.render_priority = 100
		m.albedo_color = Color(0, 0, 0, 0)
		_rp_veil.material_override = m
		_rp_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rp_veil.position = Vector3(0, 0, -0.3)
		camera.add_child(_rp_veil)
	var a := 1.0 - absf(_rp_fade - REPLAY_FADE) / REPLAY_FADE
	a = clampf(a, 0.0, 1.0) if race_state == Race.REPLAY else 0.0
	(_rp_veil.material_override as StandardMaterial3D).albedo_color.a = a
	_rp_veil.visible = a > 0.001


func _after_explosion() -> void:
	_rec.reset()
	# Nowe auto na POCZĄTKU bieżącego odcinka (jak w River Raid przy
	# ostatnim moście; użytkownik: "respawn zawsze na początku aktualnego
	# etapu"), naprawione i zatankowane; przez chwilę bez utraty życia.
	car.freeze = false
	car.visible = true
	car.repair()
	car.refuel(1.0)
	if _endless:
		_restart_section()
	else:
		_right_car(6.0)
	_grace_t = 3.0
	car.damage = {
		"structure": 0.0, "engine": 0.0, "gearbox": 0.0,
		"brakes": [0.0, 0.0, 0.0, 0.0], "suspension": [0.0, 0.0, 0.0, 0.0],
	}
	race_state = Race.RACING
	if cranes_left >= 0:
		cranes_left -= 1
		if cranes_left < 0:
			cranes_left = 0
			_game_over()


## Początek bieżącego odcinka: auto za tablicą "ODCINEK n", boty od nowa
## w tym samym rozkładzie (ziarno z numeru odcinka - każda próba odcinka
## wygląda tak samo, jak w River Raid).
func _restart_section() -> void:
	_rec.reset()
	var cp: float = track.checkpoint_before(_last_safe_dist)
	var d := maxf(cp + 25.0, start_distance)
	_last_safe_dist = d
	car.place(_safe_pose(d))
	_fallen_time = 0.0
	for b in _bots:
		_retire_bot(b)
	_bots.clear()
	# Auta z naprzeciwka do puli (było: niszczone razem z pulą - po każdym
	# odrodzeniu budowane od nowa, ~170 ms na auto na Queście).
	for o in _oncoming.duplicate():
		o.car.repair_body()
		_pool_oncoming(o)
	_osk = null
	_osk_cars = {}
	_osk_next_d = d + OSK_GAP_MIN
	_reset_bot_pattern(track.section_at(d))


## Boty w odcinku: ten sam rozkład przy każdej próbie (ziarno = numer
## odcinka), pierwszy po 6 s.
func _reset_bot_pattern(section: int) -> void:
	_bot_rng.seed = section * 7919 + 17
	_bot_timer = 6.0


func _respawn() -> void:
	# Kawałek wstecz od miejsca upadku, żeby był rozbieg przed przeszkodą.
	var d := maxf(start_distance, _last_safe_dist - respawn_back)
	# Nie cofamy się przez przerwę: auto postawione na rampie przed dziurą,
	# bez rozbiegu, spadałoby w nią w kółko. Jeśli między miejscem upadku
	# a punktem cofnięcia jest przerwa, stawiamy auto tuż za nią.
	var gap_end: float = track.last_gap_end_before(_last_safe_dist)
	if d < gap_end or track.is_gap_at(d):
		d = maxf(gap_end + 2.0, d)
	# Upadek przy skoku: z powrotem na początek rozbiegu (znak z prędkością),
	# bo 35 m to za mało, żeby się rozpędzić do prędkości skoku.
	var runup: float = track.runup_start_before(_last_safe_dist)
	if runup >= 0.0:
		d = maxf(runup, start_distance)
	# Na trasie bez końca nigdy dalej wstecz niż brama bieżącego odcinka.
	if _endless:
		d = maxf(d, track.checkpoint_before(_last_safe_dist) + 3.0)
		# Tylko na kawałku, który jeszcze istnieje (kawałki za autem są
		# usuwane) - inaczej auto stawało w pustce.
		d = maxf(d, track.loaded_start() + 5.0)
	var xf: Transform3D = _safe_pose(d)
	if _endless:
		_last_safe_dist = d
		track.update_progress(d)
	_air.reset()
	car.place(xf)
	_fallen_time = 0.0
	if _mode == Mode.DRIVE and not _xr_ready:
		_chase_xf = xf * car.chase_point.transform


func _on_car_landed(impact_speed: float) -> void:
	_haptics.on_landed(impact_speed)
	# Na razie tylko log. W etapie 4 tu podepniemy licznik uszkodzeń.
	if impact_speed > 6.0:
		print("Twarde lądowanie: %.1f m/s" % impact_speed)


## Deszcz: smugi spadające w świecie (nie przyklejone do auta - auto w nie
## wjeżdża), emiter nad i przed autem, przesunięty o drogę z ~0,5 s jazdy.
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 1000       # było 2400 - na Queście za dużo nakładających się smug
	_rain.lifetime = 1.0
	_rain.local_coords = false
	_rain.amount_ratio = 0.0
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-40, -30, -60), Vector3(80, 50, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9.0, 0.5, 13.0)
	pm.direction = Vector3(0.05, -1.0, 0.0)
	pm.spread = 3.0
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3(0.0, -2.0, 0.0)
	_rain.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.84, 0.9, 0.45)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.7)
	q.material = m
	_rain.draw_pass_1 = q
	add_child(_rain)
	_rain.add_to_group(WorldOrigin.GROUP)
	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.stream = _make_rain_noise()
	_rain_sound.volume_db = -80.0
	add_child(_rain_sound)


## Niebo, słońce, mgła i światło otoczenia z pogody (zlecenie
## warstwa-pogody; użytkownik: "w przypadku deszczu niebo powinno się
## robić ciemnoszare"). Pogoda wygładzona w czasie (stała ~3 s), wygląd
## przepisywany co 1,5 s - zmiana nieba przelicza mapę odbić (Quest), więc
## rzadko i z Sky.PROCESS_MODE_INCREMENTAL. Perf "niebo".
var _weather_now := {}
var _wx_smooth := {"cloud": 0.0, "fog": 0.0}
var _wx_kind := ""
var _wx_t := 0.0
func _update_weather_look(delta: float) -> void:
	if _weather_now.is_empty():
		return
	var k := 1.0 - exp(-delta / 3.0)
	for key in ["cloud", "fog"]:
		_wx_smooth[key] = lerpf(float(_wx_smooth[key]), float(_weather_now.get(key, 0.0)), k)
	_wx_kind = String(_weather_now.get("kind", ""))
	_wx_t -= delta
	if _wx_t > 0.0:
		return
	_wx_t = 1.5
	var t0 := Time.get_ticks_usec()
	var lk := WeatherPlan.look({"cloud": _wx_smooth["cloud"], "fog": _wx_smooth["fog"], "kind": _wx_kind})
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var env := we.environment
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
		if sky_mat:
			if env.sky.process_mode != Sky.PROCESS_MODE_INCREMENTAL:
				env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
			sky_mat.sky_top_color = lk["sky_top"]
			sky_mat.sky_horizon_color = lk["sky_horizon"]
			sky_mat.ground_horizon_color = lk["sky_horizon"]
		env.fog_density = lk["fog_density"]
		env.fog_light_color = lk["fog_color"]
		env.ambient_light_color = lk["ambient"]
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_energy = lk["sun_energy"]
	Perf.add("niebo", t0)


func _update_rain(delta: float) -> void:
	if _rain == null or car == null:
		return
	# Szyba (krople, wycieraczki) mokrnie i schnie powoli; smugi i szum idą
	# za opadem szybko - wjazd do tunelu ucina deszcz (tunel ma rain 0).
	if not Bench.on("rain"):
		_rain_target = 0.0
	elif Bench.scenario == "S3":
		_rain_target = 2.0                     # pomiar: wymuszona ulewa
	car.rain = move_toward(car.rain, _rain_target, delta / 3.0 * 2.0)
	var was := _rain_vis
	_rain_vis = move_toward(_rain_vis, _rain_target, delta * 4.0)
	if _rain_vis <= 0.0:
		if was > 0.0:
			_rain.restart()       # usuwa krople, które jeszcze spadały
		_rain.emitting = false
		if _rain_sound.playing:
			_rain_sound.stop()
		return
	var k := _rain_vis / 2.0
	# Mżawka: rzadkie smugi; deszcz: gęsto.
	_rain.amount_ratio = 0.3 * _rain_vis if _rain_vis <= 1.0 else lerpf(0.3, 1.0, _rain_vis - 1.0)
	_rain.emitting = true
	var v := car.linear_velocity
	_rain.global_position = car.global_position + Vector3(v.x, 0.0, v.z) * 0.5 + Vector3.UP * 8.0
	if not _rain_sound.playing:
		_rain_sound.play()
	_rain_sound.volume_db = linear_to_db(0.08 + 0.25 * k)


## Akustyka: tunel z próbki trasy, ściany zmierzone promieniami w bok
## od auta (lewa/prawa), na wysokości ~1 m nad jezdnią.
func _update_env(s: Dictionary) -> void:
	if _env == null:
		return
	var roof := bool(s.get("roof", false))
	if roof and not _was_roof:
		Perf.mark("tunnel_enter")
	_was_roof = roof
	_env.set_env(roof, _rain_target)
	var space := car.get_world_3d().direct_space_state
	var from := car.global_position + car.global_basis.y * 0.5
	var r := (s["right"] as Vector3) * Vector3(1, 0, 1)
	r = track.global_basis * r.normalized() if r.length() > 0.01 else car.global_basis.x
	var d := []
	for side in [-1.0, 1.0]:
		var q := PhysicsRayQueryParameters3D.create(from, from + r * side * 60.0)
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		d.append(from.distance_to(hit["position"]) if hit else 60.0)
	_env.set_walls(d[0], d[1])


## Wydajność do logu co 5 s (na goglach: ./quest.sh log) - po tym
## dobieramy najwyższą rozdzielczość, przy której gogle trzymają klatki.
var _perf_t := 0.0
var _was_roof := false
## Histogram klatek w oknie 5 s (etap 0 planu wydajności).
var _hist := [0, 0, 0]                    # > 13,9 ms, > 20 ms, > 33 ms
var _frames := 0
var _worst_ms := 0.0
var _worst_events := PackedStringArray()
var _bench_t := 0.0
var _bench_stage := 0
var _bench_driver: BotDriver
var _bench_sum := {"frames": 0, "over": 0, "over33": 0, "worst": 0.0, "gpu": [], "fps": []}
var _perf_measure := false
## Tempo gry: czas fizyki (kroki × 1/120 s) do czasu zegarowego. Poniżej
## 100% gra jedzie w zwolnionym tempie (gogle nie nadążają z krokami
## fizyki), a prędkościomierz tego nie pokazuje - użytkownik 2026-11-09:
## "albo silnik gry działa za wolno, albo przyczepność".
var _tempo_ticks := -1
var _tempo_usec := 0
func _log_perf(delta: float) -> void:
	_perf_t += delta
	if _perf_t < 5.0:
		return
	_perf_t = 0.0
	var ticks := Engine.get_physics_frames()
	var usec := Time.get_ticks_usec()
	if _tempo_ticks >= 0 and usec > _tempo_usec:
		var sim := float(ticks - _tempo_ticks) / float(Engine.physics_ticks_per_second)
		var tempo := sim / (float(usec - _tempo_usec) * 1e-6)
		print("PERF tempo gry: %d%% (fizyka %.2f s na %.2f s zegara), %.0f km/h, %.0f obr., bieg %d, uszk. silnika %d%%" % [
				roundi(tempo * 100.0), sim, float(usec - _tempo_usec) * 1e-6,
				car.linear_velocity.length() * 3.6, car.engine_rpm, car.gear,
				roundi(car.damage["engine"] * 100.0)])
	_tempo_ticks = ticks
	_tempo_usec = usec
	var rail := 0
	for b in _bots:
		if _drv(b).on_rail:
			rail += 1
	var vp := get_viewport().get_viewport_rid()
	if not _perf_measure:
		_perf_measure = true
		RenderingServer.viewport_set_measure_render_time(vp, true)
	print("PERF: %d kl./s, proces %.1f ms, fizyka %.1f ms, GPU %.1f ms, CPU render %.1f ms, boty %d (fizyka %d), odcinek %d" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			RenderingServer.viewport_get_measured_render_time_cpu(vp),
			_bots.size(), _bots.size() - rail, _last_section])
	print("PERF+ ms/s (suma/maks ms): ", Perf.dump(5.0))
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	print("PERF#: klatki %d, >13,9 ms %d, >20 ms %d, >33 ms %d, najdłuższa %.1f ms [%s] | draw %d, obiekty %d, prymitywy %d, VRAM %.0f MB, węzły %d, ciała %d, pary %d" % [
			_frames, _hist[0], _hist[1], _hist[2], _worst_ms, ",".join(_worst_events),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	if Bench.active() and _bench_stage >= 1:
		_bench_sum["gpu"].append(gpu)
		_bench_sum["fps"].append(Engine.get_frames_per_second())
	_hist = [0, 0, 0]
	_frames = 0
	_worst_ms = 0.0
	_worst_events = PackedStringArray()


## Szum deszczu: 2 s szumu przefiltrowanego dolnoprzepustowo, w pętli.
static func _make_rain_noise() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var smp := PackedInt32Array()
	smp.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lp := 0.0
	for i in range(n):
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		# Pojedyncze trzaski kropel na dachu.
		var tick := rng.randf_range(-1.0, 1.0) * 0.6 if rng.randf() < 0.002 else 0.0
		smp[i] = int(clampf(lp * 0.6 + tick, -1.0, 1.0) * 26000.0)
	return AudioUtil.wav(smp, rate, 16, true)



# --------------------------------------------------------------------------
# Ruch z naprzeciwka na autostradzie
# --------------------------------------------------------------------------

## Auta na drugiej jezdni autostrady jadą w przeciwną stronę (użytkownik).
## Bez sterowania i fizyki jazdy: ciała kinematyczne przesuwane po swoim
## pasie (zderzenie po przeskoczeniu bariery działa). Najwyżej
## ONCOMING_MAX naraz, 110-140 km/h, tylko na odcinkach autostrady.
const ONCOMING_MAX := 4
var _oncoming: Array[OncomingCar] = []
var _oncoming_timer := 0.0
var _oncoming_pool: Array[StuntCar] = []


func _update_oncoming(delta: float) -> void:
	_oncoming_timer -= delta
	if _oncoming_timer <= 0.0 and race_state == Race.RACING and not (_endless and track.autostrada):
		_oncoming_timer = _bot_rng.randf_range(1.5, 4.0)
		var d := _last_safe_dist + _bot_rng.randf_range(500.0, 900.0)
		if _oncoming.size() < ONCOMING_MAX and _is_highway_at(d):
			_spawn_oncoming(d)
	if _endless and track.autostrada:
		_update_skirmish(delta)
	for o in _oncoming.duplicate():
		var c: StuntCar = o.car
		if is_instance_valid(c) and not o.loose and c.visible \
				and (c.global_position - car.global_position).length_squared() < LOOSE_R * LOOSE_R \
				and not _onc_beside(o, c):
			_loosen_oncoming(o)
		if o.loose:
			# Swobodne auto (po zbliżeniu gracza): sama fizyka, do puli daleko
			# za graczem albo po LOOSE_TIME.
			o.loose_t = o.loose_t + delta
			if not is_instance_valid(c) or ((o.loose_t > LOOSE_TIME \
					or (c.global_position - car.global_position).length() > 400.0)
					and _can_vanish(c.global_position)):
				if is_instance_valid(c):
					c.repair()
				_pool_oncoming(o)
			continue
		if o.osk != "":
			continue                           # scenka: _update_skirmish
		o.dist = o.dist - o.v * delta
		var d2: float = o.dist
		# Za graczem jedzie do TrafficZone.BEHIND (300 m, było 150) i znika
		# dopiero poza wzrokiem (lusterko, obejrzenie się); bez toru (kawałek
		# zdjęty) stoi ukryty w ostatnim miejscu, aż zniknie z oczu.
		if not is_instance_valid(c):
			_pool_oncoming(o)
			continue
		var past: bool = d2 < _last_safe_dist - TrafficZone.BEHIND
		if past and _can_vanish(c.global_position):
			_pool_oncoming(o)
			continue
		var rail: Array = track.rail_at(d2)
		if rail.is_empty():
			if _can_vanish(c.global_position):
				_pool_oncoming(o)
			else:
				# Bez toru (kawałek zdjęty), a widać: jedzie dalej prosto po
				# ostatniej osi, nie staje na pasie (przegląd 516a1bb).
				c.global_position += -c.global_basis.z * o.v * delta
			continue
		c.global_transform = _wrong_way_pose(rail[0], c.wheel_radius) if o.wrong_way \
				else _oncoming_pose(rail[0], rail[1], o.lane, c.wheel_radius)
		# Roboty (etap 2b): przejazd przez pas rozdziału na nasz lewy pas.
		if not o.wrong_way and track.sections:
			var fx: float = track.sections.onc_cross(d2)
			# onc_x tylko w strefie (zone_at + 2x lanes_at - koszt na Questa).
			var ox: float = track.sections.onc_x(d2, int(o.lane)) if fx > 0.0 else NAN
			if not is_nan(ox):
				o.x_cur = ox if is_nan(o.x_cur) else move_toward(o.x_cur, ox, 3.0 * delta)
				ox = o.x_cur
			else:
				o.x_cur = NAN
			if fx > 0.0 and not is_nan(ox):
				var ours := _wrong_way_pose(rail[0], c.wheel_radius, ox)
				var xf2 := c.global_transform
				# Skos w przejeździe: kurs w stronę ruchu w poprzek (pochodna
				# smoothstep po d, ~ 13 m / 120 m).
				var dx: float = track.sections.onc_cross(d2 - 1.0) - fx
				var lat: float = (ours.origin - xf2.origin).dot(rail[0].basis.x) * dx
				xf2.origin = xf2.origin.lerp(ours.origin, fx)
				# Znak: auto jedzie w stronę malejącego d (przodem +Z toru);
				# obrót o +atan daje ruch w stronę zmiany x (przejście na
				# fizykę przy graczu jechało w drugą stronę - na nasz pas).
				xf2.basis = ours.basis.rotated(ours.basis.y, atan(lat))
				c.global_transform = xf2
		for w in c.wheels:
			# Auto obrócone o PI jedzie swoim przodem - kręcenie do przodu.
			w.omega = o.v / c.wheel_radius


## Potyczki na drugiej jezdni autostrady (OncomingSkirmish, moduł chmury,
## inbox wasnie-na-autostradzie pkt 7): reżyserowana scenka dwóch aut
## z naprzeciwka w kolorach wrogich gangów, klimaks ~180 m przed graczem.
## Najwyżej jedna naraz, następna 1,2-2,5 km jazdy po poprzedniej. Bez
## fizyki i bez punktów (gracz jest za barierą).
var _osk: OncomingSkirmish = null
var _osk_cars := {}                  # "a"/"b" -> OncomingCar z _oncoming
var _osk_started := false
var _osk_v := 0.0                    # prędkość bazowa scenki [m/s]
## Odstęp między scenkami na drugiej jezdni [m] (użytkownik 2026-11-10:
## "mniej walk z przeciwka, więcej w tę samą stronę" - było 1,2-2,5 km).
const OSK_GAP_MIN := 3000.0
const OSK_GAP_MAX := 6000.0
var _osk_next_d := 3000.0            # dystans gracza, od którego wolno zacząć


func _update_skirmish(delta: float) -> void:
	if _osk == null:
		if race_state != Race.RACING or _last_safe_dist < _osk_next_d or seg_calm():
			return
		# Poza wzrokiem (przed autem widać do 2 km; przy 900 m auta scenki
		# pojawiały się na widoku - segment_event_test). Do trigger_gap i tak
		# jadą zwykłym ruchem.
		var d := _last_safe_dist + SegmentEvents.HIDE_DIST
		var dxf: Transform3D = track.transform_at_distance(d)
		if not _can_vanish(dxf.origin):
			_osk_next_d = _last_safe_dist + 200.0
			return
		# Cała scenka na zwykłej jezdni (bez pasa stacji, nie w mieście).
		for k in [0.0, 300.0, 600.0]:
			var smp: Dictionary = track.sample_at(d - k, 1.0)
			if smp.is_empty() or absf(float(smp["width"]) - HighwayGenerator.WIDTH) > 0.1 \
					or not track.plan.city_at(d - k).is_empty():
				_osk_next_d = _last_safe_dist + 200.0
				return
		# Scenka jedzie od startu do gracza - na całej drodze bez strefy
		# przekroju z ruchem z naprzeciwka na naszej jezdni (roboty itp.).
		if track.sections:
			var dd := _last_safe_dist
			while dd < d + 400.0:
				if bool(track.sections.lanes_at(dd)["other_closed"]) or track.sections.onc_cross(dd) > 0.0:
					_osk_next_d = _last_safe_dist + 300.0
					return
				dd += 100.0
		_osk = OncomingSkirmish.random(_bot_rng)
		_osk_started = false
		_osk_v = _bot_rng.randf_range(110.0, 140.0) / 3.6
		var gg := _osk_gangs()
		_osk_cars = {}
		for who in ["b", "a"]:
			var dd := d if who == "b" else d + _osk.gap
			_spawn_oncoming(dd, 0, _osk_v * 3.6)
			var o: OncomingCar = _oncoming[-1]
			o.osk = who
			var c: StuntCar = o.car
			c.set_paint(GameSettings.PAINTS[_gang_paint(gg[0] if who == "a" else gg[1])])
			_osk_cars[who] = o
		print("Scenka na drugiej jezdni: ", _osk.kind)
	var oa: OncomingCar = _osk_cars["a"]
	var ob: OncomingCar = _osk_cars["b"]
	if not (is_instance_valid(oa.car) and is_instance_valid(ob.car)):
		_osk_end()
		return
	if not _osk_started:
		ob.dist = float(ob.dist) - _osk_v * delta
		var closing := maxf(car.speed, 0.0) + _osk_v
		if float(ob.dist) - _last_safe_dist <= _osk.trigger_gap(closing):
			_osk_started = true
	else:
		for ev in _osk.step(delta):
			_osk_event(ev)
		ob.dist = float(ob.dist) - _osk_v * float(_osk.state_b["v"]) * delta
	oa.dist = float(ob.dist) + _osk.gap
	for who in ["a", "b"]:
		var o: OncomingCar = _osk_cars[who]
		var c: StuntCar = o.car
		var stt: Dictionary = _osk.state_a if who == "a" else _osk.state_b
		if bool(stt["hidden"]):
			c.visible = false
			continue
		c.global_transform = _osk_xf(o.dist, stt, c.wheel_radius)
		var v := _osk_v * float(stt["v"])
		for w in c.wheels:
			w.omega = v / c.wheel_radius
	if (_osk.done or float(oa.dist) < _last_safe_dist - TrafficZone.BEHIND) \
			and _can_vanish(oa.car.global_position) and _can_vanish(ob.car.global_position):
		_osk_end()


## Położenie auta scenki: pas L z hwy_from_median, obrót o yaw i przechył.
func _osk_xf(d: float, stt: Dictionary, wheel_r: float) -> Transform3D:
	var xf: Transform3D = track.transform_at_distance(d)
	var w := HighwayGenerator.WIDTH
	# Druga jezdnia: krawędź przy pasie rozdziału w -(w/2 + pas rozdziału),
	# pobocze dalej w -X (lustro hwy_lane_off).
	var x := -(w * 0.5 + TrackGenerator.HIGHWAY_MEDIAN) - OncomingSkirmish.hwy_from_median(float(stt["lane"]), w)
	var b := xf.basis.rotated(xf.basis.y, PI)
	b = b.rotated(b.y, deg_to_rad(float(stt["yaw"])))
	b = b.rotated(b.z, deg_to_rad(float(stt["roll"])))
	return Transform3D(b, xf.origin + xf.basis.x * x + xf.basis.y * (0.41 + wheel_r))


## Dwa wrogie gangi z bieżących relacji; bez wrogów - dwa różne losowe.
func _osk_gangs() -> Array:
	var pairs := []
	for g1 in range(GANGS):
		for g2 in range(g1 + 1, GANGS):
			if feud.gangs_hostile(g1, g2):
				pairs.append([g1, g2])
	if not pairs.is_empty():
		var p: Array = pairs[_bot_rng.randi() % pairs.size()]
		return p if _bot_rng.randf() < 0.5 else [p[1], p[0]]
	var g := _bot_rng.randi() % GANGS
	return [g, (g + 1 + _bot_rng.randi() % (GANGS - 1)) % GANGS]


func _osk_event(ev: Dictionary) -> void:
	var o: OncomingCar = _osk_cars[ev["car"]]
	var c: StuntCar = o.car
	match ev["type"]:
		"horn":
			BotDriver.horn_on(c).play()
		"hit":
			# B dostaje z boku od strony A (A jest bliżej pasa rozdziału).
			c.dent(Vector3(-0.85, 0.55, 0.3), Vector3(1.0, 0.0, 0.0), 0.07)
		"boom":
			_explode(c)
		# "sparks", "smoke" - na razie bez efektu (do zrobienia).


func _osk_end() -> void:
	for who in _osk_cars:
		var o: OncomingCar = _osk_cars[who]
		o.osk = ""
		var c: StuntCar = o.car
		if is_instance_valid(c):
			c.repair_body()                    # wgniecenia scenki nie wracają z puli
		if _oncoming.has(o):
			_pool_oncoming(o)
	_osk_cars = {}
	_osk = null
	_osk_next_d = _last_safe_dist + _bot_rng.randf_range(OSK_GAP_MIN, OSK_GAP_MAX)


## Auto z naprzeciwka tuż przy graczu przechodzi z jazdy po szynie
## (kinematyczne - dla gracza jak ściana) na pełną fizykę z prędkością,
## którą miało. Zasada użytkownika (2026-11-11): boty mogą oszukiwać, ale
## uderzone przez gracza zawsze mają bezwładność i reakcję zgodną z fizyką.
const LOOSE_R := 5.5           # środki aut - kontakt zaczyna się ~4,6 m
const LOOSE_TIME := 30.0
func _loosen_oncoming(o: OncomingCar) -> void:
	var c: StuntCar = o.car
	if o.osk != "":
		# Scenka się kończy; drugie auto jedzie dalej jak zwykły ruch.
		for who in _osk_cars:
			(_osk_cars[who] as OncomingCar).osk = ""
		_osk_cars = {}
		_osk = null
		_osk_next_d = _last_safe_dist + _bot_rng.randf_range(OSK_GAP_MIN, OSK_GAP_MAX)
	o.loose = true
	o.loose_t = 0.0
	c.freeze = false
	c.linear_velocity = -c.global_basis.z * o.v
	c.angular_velocity = Vector3.ZERO
	c.throttle = 0.0
	c.brake = 0.0


## Auto z naprzeciwka do puli (ukryte), zamiast queue_free - bez alokacji.
func _pool_oncoming(o: OncomingCar) -> void:
	var c: StuntCar = o.car
	o.loose = false
	if is_instance_valid(c):
		c.set_high_beam(0.0)                   # pod prąd mógł mrugać
		c.freeze = true                        # z powrotem na szynę (po _loosen_oncoming)
		c.visible = false
		c.global_position.y -= 500.0
		c.process_mode = Node.PROCESS_MODE_DISABLED   # w puli nic nie liczy
		_oncoming_pool.append(c)
	_oncoming.erase(o)


## Ruch trybu Autostrada (etap 3, TrafficZone, co 0,5 s): gęstość z planu
## (miasta 3-5 aut/km do 5 km od zabudowy, między miastami ~0,75/km) na
## obu jezdniach. Auta bez szału znikają tylko poza oknem i poza wzrokiem
## (głowa + lusterka), nowe pojawiają się 700-1500 m przed graczem, też
## poza wzrokiem. Na naszej jezdni boty (spokojne, szał jak w wąwozie),
## z naprzeciwka - auta kinematyczne.
var _traffic: TrafficZone
var _traffic_t := 0.0
func _update_traffic(delta: float) -> void:
	_traffic_t -= delta
	if _traffic_t > 0.0 or race_state != Race.RACING:
		return
	_traffic_t = 0.5
	_traffic_ensure()
	var head := camera.global_position
	var hf := -camera.global_basis.z
	var cf := -car.global_basis.z
	var cars := []
	for b in _bots:
		var drv: BotDriver = _drv(b)
		cars.append({"id": b.get_instance_id(), "dist": drv.dist, "lane": drv.lane, "oncoming": false,
				"raging": drv.rage > 0.05 or drv.persona == "extremist" or drv.event != "",
				"visible": TrafficZone.visible(head, hf, cf, b.global_position)})
	for o in _oncoming:
		var oc: StuntCar = o.car
		cars.append({"id": oc.get_instance_id(), "dist": o.dist, "lane": int(o.lane), "oncoming": true,
				"raging": o.osk != "" or o.wrong_way or o.works, "visible": TrafficZone.visible(head, hf, cf, oc.global_position)})
	var r: Dictionary = _traffic.step(_last_safe_dist, cars, _bot_rng)
	for id in r["despawn"]:
		for b in _bots.duplicate():
			if b.get_instance_id() == id:
				_bots.erase(b)
				_retire_bot(b)
		for o in _oncoming.duplicate():
			if (o.car as Node).get_instance_id() == id:
				_pool_oncoming(o)
	for sp in r["spawn"]:
		var d: float = sp["dist"]
		var lane: int = sp["lane"]
		# Przekrój (etap 2): nasz ruch tylko na otwartych pasach. Ruch
		# z naprzeciwka zostaje - na robotach jedzie naszym lewym pasem
		# (onc_cross w _update_oncoming).
		if track.sections:
			var la: Dictionary = track.sections.lanes_at(d)
			if not sp["oncoming"] and lane >= (la["fwd"] as Array).size():
				lane = 0
		var pos: Vector3
		if sp["oncoming"]:
			pos = _oncoming_xf(d, float(lane)).origin
		else:
			var xf: Transform3D = track.transform_at_distance(d)
			pos = xf.origin + xf.basis.x * hwy_lane_off(lane)
		if TrafficZone.visible(head, hf, cf, pos):
			continue                       # spróbuje przy następnym kroku
		# Fizyczny odstęp od innych aut (TrafficZone sprawdza tylko numer
		# pasa; auto doganiające 250-300 m za graczem pojawiało się na
		# innym albo tuż za nim przy 150 km/h - obroty i wraki,
		# section_drive_test).
		if not sp["oncoming"] and not _spawn_clear(pos, float(sp["speed_kmh"]) / 3.6):
			continue
		if sp["oncoming"]:
			_spawn_oncoming(d, lane, float(sp["speed_kmh"]))
		else:
			var n := _bots.size()
			_spawn_bot(d, lane, float(sp["speed_kmh"]))
			# Korek: wolne auta zostają wolne (bez tego wracały do limitu).
			if _traffic.in_jam(d) and _bots.size() > n:
				var smp: Dictionary = track.sample_at(d)
				if not smp.is_empty():
					_drv(_bots[-1]).speed_k = clampf(float(sp["speed_kmh"]) / float(smp["limit"]), 0.3, 1.0)


## Wolne miejsce na nowe auto w `pos`: nikt bliżej niż 15 m, a przed nim
## nikt wolniejszy w zasięgu hamowania (różnica prędkości²/(2·3 m/s²) + 15 m).
func _spawn_clear(pos: Vector3, v: float) -> bool:
	var others: Array = _bots.duplicate()
	others.append(car)
	for o in others:
		if not is_instance_valid(o):
			continue
		var rel: Vector3 = (o as Node3D).global_position - pos
		if rel.length() < 15.0:
			return false
		var ov: float = (o as RigidBody3D).linear_velocity.length()
		var dv := v - ov
		if dv > 0.0 and absf(rel.dot((o as Node3D).global_basis.x)) < 2.5:
			var ahead: float = -rel.dot((o as Node3D).global_basis.z)   # > 0: tamto auto przed nowym
			if ahead > 0.0 and ahead < 15.0 + dv * dv / 6.0:
				return false
	return true


func _is_highway_at(d: float) -> bool:
	return track.has_method("is_highway_at") and track.is_highway_at(d)


## Auto z naprzeciwka na naszej jezdni (roboty, etap 2b) mija gracza obok
## - bez nachodzenia w poprzek nie przechodzi na fizykę. Inaczej przy
## każdym minięciu (3,75 m obok, LOOSE_R 5,5) jechało dalej bez kierowcy
## prosto przez koniec strefy na nasze pasy.
func _onc_beside(o: OncomingCar, c: StuntCar) -> bool:
	# Na naszej jezdni: strefa (onc_cross) albo kierowca pod prąd (etap 1 -
	# przy minięciu też przechodził na fizykę i bez kierowcy przecinał
	# nasze pasy; "LUŹNE" w section_drive_test, trasa 77, 15 km).
	var ours: bool = o.wrong_way or (track.sections != null and track.sections.onc_cross(o.dist) > 0.0)
	if not ours:
		return false
	return absf((c.global_position - car.global_position).dot(car.global_basis.x)) > 2.4


## Położenie auta z naprzeciwka: druga jezdnia (w lewo o szerokość jezdni
## + pas rozdziału), pas `lane` licząc od pasa rozdziału, przodem do gracza.
func _oncoming_xf(d: float, lane: float, wheel_r := 0.33) -> Transform3D:
	var smp: Dictionary = track.sample_at(d)
	return _oncoming_pose(track.transform_at_distance(d),
			14.8 if smp.is_empty() else float(smp["width"]), lane, wheel_r)


## Kierowca pod prąd: nasza jezdnia, lewy pas, przodem do gracza.
func _wrong_way_pose(xf: Transform3D, wheel_r: float, x := NAN) -> Transform3D:
	var p := _oncoming_pose(xf, 14.8, 0.0, wheel_r)
	var b := xf.basis.rotated(xf.basis.y, PI)
	var o := xf.origin + xf.basis.x * (hwy_lane_off(1) if is_nan(x) else x)
	# Wysokość jak auta z naprzeciwka (koła na jezdni): z ich pozy.
	return Transform3D(b, o + xf.basis.y * (p.origin - xf.origin).dot(xf.basis.y))


## To samo z gotowej osi i szerokości (EndlessTrack.rail_at - co krok).
func _oncoming_pose(xf: Transform3D, w: float, lane: float, wheel_r: float) -> Transform3D:
	var lane_w := StuntTrack.lane_width(w)
	var x := -(w + TrackGenerator.HIGHWAY_MEDIAN) - lane * lane_w
	if _endless and track.autostrada:
		# 2+2: wolny pas jezdni z naprzeciwka (lane 0) przy jej poboczu,
		# szybki (1) przy pasie rozdziału - lustrzanie do hwy_lane_off.
		x = HighwayGenerator.lane_center(int(lane), true, w)
	var b := xf.basis.rotated(xf.basis.y, PI)
	# Kołami na jezdni: środek koła 0,41 m pod mocowaniem + promień koła
	# (przegląd PR #7: przy 0,62 koła wchodziły ~0,16 m w asfalt).
	return Transform3D(b, xf.origin + xf.basis.x * x + xf.basis.y * (0.41 + wheel_r))


func _spawn_oncoming(d: float, lane_i := -1, speed_kmh := -1.0) -> void:
	var c: StuntCar
	if not _oncoming_pool.is_empty():
		c = _oncoming_pool.pop_back()
		c.visible = true
		c.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		c = _new_oncoming_car()
	c.apply_style(_pick_style())
	for w in c.wheels:
		w.spring_len = c.rest_length - 0.04
	var gs := _gs
	if gs:
		var keys: Array = gs.PAINTS.keys()
		c.set_paint(gs.PAINTS[keys[_bot_rng.randi() % keys.size()]])
	var lane := float(_bot_rng.randi_range(-1, 1))     # trzy pasy drugiej jezdni
	if lane_i >= 0:
		lane = float(lane_i)
	var v := (speed_kmh if speed_kmh > 0.0 else _bot_rng.randf_range(110.0, 140.0)) / 3.6
	c.global_transform = _oncoming_xf(d, lane, c.wheel_radius)
	_oncoming.append(OncomingCar.new(c, d, v, lane))



# --------------------------------------------------------------------------
# Punkty za furię drogową (ScoreKeeper)
# --------------------------------------------------------------------------

## Zdarzenia od BotDriver. `now` = czas jazdy, prędkość gracza do mnożnika
## niebezpieczeństwa. Każde zwraca wypłaty -> _score_pay.
func score_chase_open(bot: StuntCar, origin: String) -> void:
	_score_pay(score.open_chase(bot.get_instance_id(), origin, race_time))


func score_chase_tick(bot: StuntCar, behind: float, side: float, dt: float) -> void:
	_score_pay(score.chase_tick(bot.get_instance_id(), behind, side, absf(bot.speed) * 3.6,
			absf(car.speed) * 3.6, dt, race_time))


func score_contact(bot: StuntCar) -> void:
	score.note_contact(bot.get_instance_id(), race_time)


func score_damage(bot: StuntCar, d_structure: float) -> void:
	var t0 := Time.get_ticks_usec()
	_score_pay(score.damage_dealt(bot.get_instance_id(), d_structure, race_time, absf(car.speed) * 3.6))
	Perf.add("punkty", t0)


func score_end_attack(bot: StuntCar, hit: bool, min_gap: float, tactic: String) -> void:
	var t0 := Time.get_ticks_usec()
	_score_pay(score.end_attack(bot.get_instance_id(), hit, min_gap, absf(car.speed) * 3.6,
			race_time, tactic))
	Perf.add("punkty", t0)


func score_chase_close(bot: StuntCar, reason: String) -> void:
	_score_pay(score.close_chase(bot.get_instance_id(), reason, race_time, absf(car.speed) * 3.6))


## Wypłaty: linia do logu (strojenie na Queście), napis z puli i dźwięk.
## Tylko przy zdarzeniu - nic co klatkę (Label3D przebudowuje siatkę przy
## zmianie tekstu).
func _score_pay(pays: Array) -> void:
	for p in pays:
		print(ScoreKeeper.log_line(p))
		_show_popup(p["text"], int(p["points"]) < 0)
		var snd := _beep_fine if int(p["points"]) < 0 else _beep
		if snd:
			snd.play()


## Pula 3 gotowych napisów nad kolumną postępu: najstarszy ustępuje
## nowemu, gasną w 1,6 s (tylko modulate - bez przebudowy siatki).
func _build_popups() -> void:
	for i in range(3):
		var l := Label3D.new()
		l.font_size = 40
		l.pixel_size = 0.00045
		l.outline_size = 10
		l.no_depth_test = true
		l.render_priority = 5
		l.visible = false
		_hud_panel.add_child(l)
		_popups.append(l)
		_popup_t.append(0.0)
	_beep = AudioStreamPlayer.new()
	_beep.stream = _make_beep([880.0, 1320.0])
	_beep.volume_db = -14.0
	add_child(_beep)
	_beep_fine = AudioStreamPlayer.new()
	_beep_fine.stream = _make_beep([440.0, 294.0])
	_beep_fine.volume_db = -14.0
	add_child(_beep_fine)


func _show_popup(text: String, bad: bool) -> void:
	if _popups.is_empty() or _race_label == null:
		return
	# Najstarszy (najmniej czasu zostało) ustępuje.
	var k := 0
	for i in range(_popups.size()):
		if _popup_t[i] < _popup_t[k]:
			k = i
	for i in range(_popups.size()):
		if _popup_t[i] > 0.0:
			_popups[i].position.y += 0.022      # starsze wyżej
	var l := _popups[k]
	l.text = text
	l.modulate = Color(1.0, 0.35, 0.3) if bad else Color(1.0, 0.85, 0.2)
	l.position = _race_label.position + Vector3(0.0, 0.05, 0.0)
	# Jak kolumna przy mapce (w panelu HUD) i wyrównanie do lewej (inaczej
	# napisy wystawały w lewo od kolumny - przegląd punktacji).
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.visible = true
	_popup_t[k] = 1.6


func _update_popups(delta: float) -> void:
	for i in range(_popups.size()):
		if _popup_t[i] <= 0.0:
			continue
		_popup_t[i] -= delta
		var a := clampf(_popup_t[i] / 0.5, 0.0, 1.0)
		_popups[i].modulate.a = a
		_popups[i].outline_modulate.a = a
		if _popup_t[i] <= 0.0:
			_popups[i].visible = false


## Krótki 8-bitowy sygnał (fala prostokątna, kolejne tony po 0,06 s).
func _make_beep(freqs: Array) -> AudioStreamWAV:
	var rate := 22050
	var seg := int(rate * 0.06)
	var smp := PackedInt32Array()
	smp.resize(seg * freqs.size())
	for k in range(freqs.size()):
		var f: float = freqs[k]
		for i in range(seg):
			var t := float(i) / rate
			var v := 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0
			var env := clampf((seg - i) / (seg * 0.3), 0.0, 1.0)
			# 8 bitów ze znakiem (było "128 + x" bez znaku - trzask na końcu).
			smp[k * seg + i] = int(40.0 * v * env)
	return AudioUtil.wav(smp, rate, 8)



# --------------------------------------------------------------------------
# Pomiar (plan wydajności, etap 0): histogram klatek i przejazd porównawczy
# --------------------------------------------------------------------------

## Długość poprzedniej klatki = delta tej; zdarzenia z Perf.mark zebrane
## w poprzedniej klatce - do najdłuższej klatki w oknie.
func _frame_stats(delta: float) -> void:
	var ms := delta * 1000.0
	var ev := Perf.take_events()
	_frames += 1
	if ms > 13.9:
		_hist[0] += 1
	if ms > 20.0:
		_hist[1] += 1
	if ms > 33.0:
		_hist[2] += 1
	if ms > _worst_ms:
		_worst_ms = ms
		_worst_events = ev
	if Bench.active() and _bench_stage >= 1:
		_bench_sum["frames"] += 1
		if ms > 13.9:
			_bench_sum["over"] += 1
		if ms > 33.0:
			_bench_sum["over33"] += 1
		_bench_sum["worst"] = maxf(_bench_sum["worst"], ms)


## Przejazd porównawczy: autem jedzie sterownik bota (jak na ekranie
## tytułowym), stałe ziarno; po ustawieniu scenariusza liczymy statystyki
## przez Bench.duration s, wypisujemy "BENCH END" i kończymy grę.
func _bench_step(delta: float) -> void:
	if not Bench.active() or not _endless:
		return
	_bench_t += delta
	if _bench_stage == 0 and _bench_t > 1.0:
		_bench_stage = 1
		_bench_t = 0.0
		cranes_left = -1
		var d := _bench_start_dist()
		if d > 0.0:
			track.update_progress(d)
			_last_safe_dist = d
			_max_dist = d
			car.place(_safe_pose(d))
		_bench_driver = BotDriver.new()
		_bench_driver.name = "BenchDriver"
		_bench_driver.car = car
		_bench_driver.track = track
		_bench_driver.dist = maxf(d, start_distance)
		car.add_child(_bench_driver)
		race_state = Race.RACING
		print("BENCH START %s na %.0f m" % [Bench.scenario, d])
	if _bench_stage == 1:
		# S5: wybuchy botów w 20., 35. i 50. sekundzie (szarpnięcia C1).
		if Bench.scenario == "S5":
			for at in [20.0, 35.0, 50.0]:
				if _bench_t - delta < at and _bench_t >= at:
					_spawn_bot(_last_safe_dist + 40.0)
					if not _bots.is_empty():
						_bots[-1].is_wrecked = true
		if _bench_t >= Bench.duration:
			_bench_stage = 2
			var g: Array = _bench_sum["gpu"]
			var fps: Array = _bench_sum["fps"]
			var gsum := 0.0
			for v in g:
				gsum += v
			var fsum := 0.0
			for v in fps:
				fsum += v
			print("BENCH END %s wyłączone=[%s] rozdzielczość %d%%: śr. %.0f kl./s, klatek %d, >13,9 ms %.0f%%, >33 ms %d, najdłuższa %.1f ms, GPU śr. %.1f ms" % [
					Bench.scenario, ",".join(Bench.off), int(_gs.xr_resolution) if _gs else 0,
					fsum / maxf(fps.size(), 1), _bench_sum["frames"],
					100.0 * _bench_sum["over"] / maxf(_bench_sum["frames"], 1), _bench_sum["over33"],
					_bench_sum["worst"], gsum / maxf(g.size(), 1)])
			get_tree().quit()


## Dystans startu scenariusza: S2 - przed pierwszym tunelem dwunitkowym
## (albo zwykłym), S4 - przed pierwszą autostradą; reszta od początku.
func _bench_start_dist() -> float:
	if Bench.scenario != "S2" and Bench.scenario != "S4":
		return 0.0
	var p := 0.0
	while p < 30000.0:
		track.update_progress(p)
		for c in track._chunks:
			if Bench.scenario == "S4" and c.highway:
				return c.dist_range().x + 60.0
			if Bench.scenario == "S2":
				for smp in c._samples:
					if smp["meta"].has("tunnel_len"):
						return maxf(float(smp["dist"]) - 150.0, start_distance)
		p += 400.0
	return 0.0
