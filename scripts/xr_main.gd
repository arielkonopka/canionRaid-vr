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
enum Race { READY, RACING, FINISHED, WORKSHOP, EXPLODING }

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
const HIT_BONUS := 20.0
var _penalty_flash := 0.0
var _last_hit := {}                  # bot -> czas ostatniej kary (bez kar z jednego zderzenia)

var _xr_ready: bool = false
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
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		gs.apply_to_car(car)
		_xr_ready = gs.enable_xr(get_viewport())
	if _xr_ready:
		right_hand.button_pressed.connect(_on_xr_button.bind(true))
		left_hand.button_pressed.connect(_on_xr_button.bind(false))
		left_hand.button_released.connect(_on_left_released)
		print("OpenXR zainicjalizowany - tryb VR.")
	else:
		push_warning("OpenXR niedostępny - tryb podglądu na płasko.")
		# XRCamera3D dziedziczy po Camera3D, więc bez XR działa jak zwykła kamera.
		camera.current = true

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
	if gs and (gs.track_mode == "endless" or gs.track_mode == "canyon"):
		# Trasa bez końca zamiast pokazowej: te same materiały, nowy losowy tor.
		var et := EndlessTrack.new()
		et.name = "EndlessTrack"
		et.road_material = _demo_track.road_material
		et.pillar_material = _demo_track.pillar_material
		et.canyon = gs.track_mode == "canyon"
		_canyon = et.canyon
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
##   klik lewego: wolna kamera. Biegi: drugi drążek (patrz _physics_process).
func _on_xr_button(button: String, is_right: bool) -> void:
	match [is_right, button]:
		[true, "ax_button"]:          # A
			if race_state == Race.FINISHED:
				restart_race()
			elif race_state == Race.WORKSHOP:
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
			_back_to_title()
		[true, "primary_click"]:
			# Nowe auto na kołach = strata życia (na trasie bez końca).
			if _mode != Mode.DRIVE:
				pass
			elif _endless and race_state == Race.RACING:
				lose_life("nowe auto")
			else:
				_use_crane()
		[false, "primary_click"]:
			_set_mode(Mode.FLY if _mode == Mode.DRIVE else Mode.DRIVE)


func _on_left_released(button: String) -> void:
	if button != "by_button" or _y_held < 0.0:
		return
	if _y_held < RECENTER_HOLD:
		toggle_assist("steer")
	_y_held = -1.0


## Przełącza pomoc w trakcie jazdy i zapamiętuje wybór - ekran tytułowy
## pokaże go przy następnej wizycie. Stan widać na desce ("ABS off" itd.).
func toggle_assist(which: String) -> void:
	var key: String = {"abs": "abs_enabled", "tcs": "tcs_enabled", "esp": "esp_enabled",
			"steer": "steer_assist"}[which]
	car.set(key, not car.get(key))
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		gs.set(key, car.get(key))
		gs.save_settings()


## Przełącza kontrolę trakcji w trakcie jazdy i zapamiętuje wybór -
## ekran tytułowy pokaże go przy następnej wizycie.
func toggle_tcs() -> void:
	toggle_assist("tcs")


func _back_to_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
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
			KEY_F:
				_set_mode(Mode.FLY if _mode == Mode.DRIVE else Mode.DRIVE)
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
			KEY_ESCAPE:
				_back_to_title()
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
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		sens = gs.stick_sensitivity / 100.0
		expo = gs.stick_expo
	return signf(x) * clampf(pow(a, expo) * sens, 0.0, 1.0)


func _read_drive_input() -> void:
	var thr := 0.0
	var brk := 0.0
	var steer_in := 0.0
	var hb := 0.0
	if _xr_ready:
		# Układ z ustawień: ręka gazu, drążek kierownicy, grip ręcznego.
		var gs := get_node_or_null("/root/GameSettings")
		var gas_right: bool = gs == null or gs.gas_hand == "right"
		var gas_c := right_hand if gas_right else left_hand
		var brake_c := left_hand if gas_right else right_hand
		var steer_c := left_hand if (gs == null or gs.steer_stick == "left") else right_hand
		thr = gas_c.get_float("trigger")
		brk = brake_c.get_float("trigger")
		steer_in = _stick_curve(steer_c.get_vector2("primary").x)
		# Drugi drążek: biegi (w górę = wyżej). Jedno wychylenie = jeden bieg,
		# kolejny dopiero po powrocie drążka do środka.
		var shift_c := right_hand if steer_c == left_hand else left_hand
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
	if _mode == Mode.DRIVE:
		_read_drive_input()
	else:
		car.throttle = 0.0
		car.brake = 0.0
		car.steer = 0.0
		car.handbrake = 1.0
	_grace_t = maxf(_grace_t - delta, 0.0)
	_penalty_flash = maxf(_penalty_flash - delta, 0.0)
	update_race(delta)
	var t0 := Time.get_ticks_usec()
	if race_state != Race.FINISHED:
		_watch_track(delta)
	Perf.add("trasa", t0)
	t0 = Time.get_ticks_usec()
	if _endless:
		_update_bots(delta)
		_update_oncoming(delta)
	Perf.add("boty_mgr", t0)


## Gracz jedzie zgodnie z przepisami: prędkość nie większa niż ograniczenie
## + 5 km/h tolerancji. Tylko to uspokaja boty w szale drogowym.
func player_compliant() -> bool:
	return absf(car.speed) * 3.6 <= current_limit + 5.0


func _update_bots(delta: float) -> void:
	_bot_timer -= delta
	if _bot_timer <= 0.0 and race_state == Race.RACING:
		var limit := bot_limit(_last_section) if _endless else 2
		# Im więcej brakuje do limitu, tym szybciej dochodzą nowe auta.
		_bot_timer = _bot_rng.randf_range(2.0, 6.0) if _bots.size() < limit else 3.0
		if _bots.size() < limit:
			_spawn_bot(_last_safe_dist + _bot_rng.randf_range(220.0, 900.0))
	for b in _bots.duplicate():
		var drv: BotDriver = b.get_node("Driver")
		# Bot w szale nie znika tak łatwo - ma czas dogonić gracza.
		var behind_max := 700.0 if drv.rage > 0.05 else 250.0
		var gone: bool = drv.dist < _last_safe_dist - behind_max or drv.dist > _last_safe_dist + 2000.0
		var dead: bool = b.is_wrecked or drv.flipped_time > 3.0 or b.global_position.y < -50.0
		if gone or dead:
			if dead:
				var boom := Explosion.new()
				boom.paint = b._paint_mat.albedo_color
				boom.ignore = [car] + _bots
				add_child(boom)
				boom.global_position = b.global_position
			_bots.erase(b)
			b.queue_free()


## Posiłki: boty w promieniu `radius` m od wściekłego bota też wpadają w szał.
func call_reinforcements(from: StuntCar, radius: float) -> void:
	for b in _bots:
		if b == from or not is_instance_valid(b):
			continue
		var drv: BotDriver = b.get_node("Driver")
		if drv.rage < 0.5 and b.global_position.distance_to(from.global_position) < radius:
			drv.enrage()


## Drugi bot w szale najbliżej gracza (partner do kleszczy) albo null.
func rage_partner(me: StuntCar) -> StuntCar:
	var best: StuntCar = null
	var best_d := 120.0
	for b in _bots:
		if b == me or not is_instance_valid(b):
			continue
		var drv: BotDriver = b.get_node("Driver")
		var dd := b.global_position.distance_to(car.global_position)
		if drv.rage > 0.5 and dd < best_d:
			best_d = dd
			best = b
	return best


func _spawn_bot(d: float) -> void:
	if track.is_gap_at(d) or d > track.total_length() - 20.0:
		return
	var xf: Transform3D = track.transform_at_distance(d)
	var smp: Array = track.samples_from(d, 2.0)
	if smp.is_empty():
		return
	var lane_w := (float(smp[0]["width"]) - 1.0) / 3.0
	var lim := float(smp[0]["limit"])
	var bot := StuntCar.new()
	bot.name = "Bot%d" % Time.get_ticks_msec()
	bot.is_bot = true
	bot.TIRE_SUBSTEPS = 2
	bot.ray_probe = true
	add_child(bot)
	# Zdalnie sterowane auta mają mocny silnik (250 kW) - w szale muszą
	# realnie dogonić gracza (przy 130 kW zostawały w tyle).
	bot.apply_engine("petrol", 250)
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		var keys: Array = gs.PAINTS.keys()
		bot.set_paint(gs.PAINTS[keys[_bot_rng.randi() % keys.size()]])
	# Prawy albo środkowy pas - przy wielu autach nie wszystkie jednym torem.
	var lane := lane_w if _bot_rng.randf() < 0.65 else 0.0
	bot.place(Transform3D(xf.basis, xf.origin + xf.basis.x * lane + xf.basis.y * 0.9))
	bot._settle_t = 0.0         # place() zjadałby prędkość przepisową startu
	var v := lim / 3.6
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
	bot.add_child(drv)
	_bots.append(bot)


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
		_track_hud.show_limit(car, _race_label.position + Vector3(0.062, -0.105, 0.0),
				current_limit if _endless else -1.0, not player_compliant())
	if _race_label:
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
			var pen := "\n-20 s!" if _penalty_flash > 0.0 and int(_penalty_flash * 4.0) % 2 == 0 else ""
			_race_label.text = "odcinek %d\n%.2f km\n%s%s%s" % [
					track.section_at(_last_safe_dist), _max_dist / 1000.0, _fmt_time(race_time), cr, pen]
		else:
			_race_label.text = _fmt_time(race_time)


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
	var gs := get_node_or_null("/root/GameSettings")
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
	var gs := get_node_or_null("/root/GameSettings")
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
	var gs := get_node_or_null("/root/GameSettings")
	cranes_left = (gs.cranes if gs and gs.cranes > 0 else -1) if _endless else -1
	_max_dist = 0.0
	# Trasa bez końca: start na najsłabszym silniku wybranego rodzaju.
	if _endless and gs:
		_tier = 0
		car.apply_engine(gs.engine_type, gs.POWER_TIERS[0])
	_next_ws = {}
	_ws_done_stop = -INF
	_last_section = 1
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


## Stacja: tankowanie przy powolnym przejeździe (< 35 km/h) pasem zjazdu
## (pełny bak w ~8 s). Pusty bak i auto stoi - utrata życia.
func _check_fuel(delta: float) -> void:
	_refueling = false
	if not _next_station.is_empty():
		if _last_safe_dist >= float(_next_station["start"]) and _last_safe_dist <= float(_next_station["end"]) \
				and _lateral > float(_next_station["lane_x"]) and absf(car.speed) * 3.6 < 35.0:
			car.refuel(delta / 8.0)
			_refueling = true
	if car.fuel <= 0.0 and absf(car.speed) < 0.5 and race_state == Race.RACING:
		lose_life("brak paliwa")


func _enter_workshop(tier: int) -> void:
	race_state = Race.WORKSHOP
	_ws_done_stop = float(_next_ws["stop"])
	_next_ws = {}
	var gs := get_node_or_null("/root/GameSettings")
	var tiers: Array = gs.POWER_TIERS if gs else [90, 130, 180, 250, 350]
	var kw: int = tiers[mini(tier, tiers.size() - 1)]
	# Opcje: trzy rodzaje napędu na nowym progu mocy + bez zmian.
	# Moment liczony na prawdziwej krzywej silnika (tymczasowe auto).
	_ws_options.clear()
	var probe := StuntCar.new()
	var hub_only: bool = gs != null and kw >= gs.HUB_ONLY_KW
	for t in (["electric"] if hub_only else ["petrol", "diesel", "electric"]):
		probe.apply_engine(t, kw)
		var name_pl: String = StuntCar.ENGINE_TYPES[t]["label"]
		var opt := {"type": t, "kw": kw, "tier": tier,
				"label": "%s %d kW   %d Nm" % [name_pl, kw, roundi(probe.peak_torque())]}
		if hub_only:
			# Ostatni próg: tylko elektryk z silnikiem w każdym kole.
			opt["hub"] = true
			opt["label"] = "Elektryk 4 x 250 kW w kołach   %d Nm" % roundi(probe.peak_torque())
		_ws_options.append(opt)
	probe.free()
	var cur: String = StuntCar.ENGINE_TYPES[car.engine_type]["label"]
	_ws_options.append({"type": "", "label": "bez zmian (%s %d kW)" % [cur, car.engine_power_kw]})
	# Domyślnie podświetlony ten sam rodzaj napędu, mocniejszy.
	_ws_selected = 0
	for i in range(_ws_options.size() - 1):
		if _ws_options[i]["type"] == car.engine_type:
			_ws_selected = i
	_ws_refresh()
	_ws_follow.snap()
	_ws_label.visible = true


func _ws_move(dir: int) -> void:
	_ws_selected = wrapi(_ws_selected + dir, 0, _ws_options.size())
	_ws_refresh()


func _ws_refresh() -> void:
	var lines := PackedStringArray(["WARSZTAT", "wybierz silnik:", ""])
	for i in range(_ws_options.size()):
		var lbl: String = _ws_options[i]["label"]
		lines.append(("> " + lbl + " <") if i == _ws_selected else lbl)
	lines.append("")
	lines.append("+ naprawa karoserii, + 1 dźwig")
	lines.append("drążek: wybór   A: zatwierdź" if _xr_ready else "strzałki: wybór   Enter: zatwierdź")
	_ws_label.text = "\n".join(lines)


## Zatwierdzenie wyboru w warsztacie (też z testów).
func workshop_choose(i: int) -> void:
	if race_state != Race.WORKSHOP:
		return
	var opt: Dictionary = _ws_options[clampi(i, 0, _ws_options.size() - 1)]
	if opt["type"] != "":
		if opt.get("hub", false):
			car.hub_motors = true
		car.apply_engine(opt["type"], opt["kw"])
		_tier = opt["tier"]
	car.repair()
	car.refuel(1.0)
	if cranes_left >= 0:
		cranes_left += 1
	_ws_label.visible = false
	race_state = Race.RACING
	print("Warsztat: %s" % opt["label"])


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
	for s in (track.samples_from(_last_safe_dist, 250.0) if kind == "" else []):
		var m: Dictionary = s["meta"]
		if m.has("curve_sign"):
			kind = "curve_r" if m["curve_sign"] > 0 else "curve_l"
		elif m.has("grade"):
			kind = "climb" if m["grade"] > 0 else "descent"
			value = absi(m["grade"])
		elif prev_surf == "dry" and s["surface"] != "dry":
			kind = "slippery"
		if kind != "":
			break
		prev_surf = s["surface"]
	# Pod kolumną postępu (która stoi przy prawej krawędzi mapki).
	# Niżej niż kolumna tekstu (nie zasłania jej ostatnich linii).
	var pos := _race_label.position + Vector3(0.02, -0.105, 0.0)
	_track_hud.show_warning(car, pos, kind, value)


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
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.075)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _mirror_vp.get_texture()
	# Lustro odwraca lewo-prawo.
	m.uv1_scale = Vector3(-1, 1, 1)
	m.uv1_offset = Vector3(1, 0, 0)
	q.material = m
	glass.mesh = q
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


func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


## Zegar nad deską i tablica wyników przed kierowcą. Dzieci auta, więc
## jadą z nim; bez testu głębi, żeby prześwitująca kabina ich nie zasłaniała.
func _build_race_hud() -> void:
	_race_label = Label3D.new()
	_race_label.name = "RaceClock"
	# Postęp (odcinek, dystans, czas, auta) w kolumnie tuż obok mapki trasy
	# (prawa krawędź HUD), w skali mapki - jeden zwarty panel nad kierownicą.
	_race_label.font_size = 26
	_race_label.pixel_size = 0.00045
	_race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_race_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_race_label.position = Vector3(-0.38 + TrackHud.SIZE.x * 0.5 + 0.008, 0.375 + TrackHud.SIZE.y * 0.5 - 0.004, -0.40) + car.cockpit_offset
	_race_label.rotation = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
	_race_label.outline_size = 6
	_race_label.modulate = Color(0.85, 0.95, 1.0)
	_race_label.no_depth_test = true
	car.add_child(_race_label)

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

	_build_mirror()
	_build_rain()
	_env = EnvAudio.new()
	_env.name = "EnvAudio"
	add_child(_env)

	# Mapka trasy na 1,5 km nad kierownicą, lekko poniżej linii wzroku.
	_track_hud = TrackHud.new()
	_track_hud.name = "TrackHud"
	_track_hud.position = Vector3(-0.38, 0.375, -0.40) + car.cockpit_offset
	_track_hud.rotation = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
	car.add_child(_track_hud)

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
	_ws_follow.add_child(_ws_label)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_update_rain(delta)
	Perf.add("deszcz", t0)
	_log_perf(delta)
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
	_update_mirror()
	if race_state == Race.EXPLODING:
		_cinematic(delta)
	elif _mode == Mode.DRIVE:
		_follow_car(delta)
	else:
		_fly(delta)
	var th := Time.get_ticks_usec()
	if _track_hud:
		_track_hud.refresh(delta, car.get_global_transform_interpolated(),
				func(): return track.samples_from(_last_safe_dist - 10.0, TrackHud.RANGE + 20.0),
				_last_safe_dist)
		_update_warning(delta)
	Perf.add("hud", th)
	# Ziemia (siatka 1200 m) jedzie za autem - trasa bez końca wychodzi daleko
	# poza nią. Kolizja ziemi to nieskończona płaszczyzna, więc jej nie ruszamy.
	var gm := $Ground/GroundMesh as Node3D
	var p := car.global_position
	gm.global_position = Vector3(snappedf(p.x, 50.0), 0.0, snappedf(p.z, 50.0))
	# Góry na horyzoncie też (jak tło - nie da się do nich dojechać).
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
	if _mode == Mode.DRIVE and (_xr_ready or _cockpit_on_pc):
		var gs := get_node_or_null("/root/GameSettings")
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
	_update_env(s)
	if _endless:
		# Dobudowa trasy przed autem, sprzątanie za nim.
		track.update_progress(float(s["dist"]))
		var sec: int = track.section_at(_last_safe_dist)
		if sec > _last_section:
			_last_section = sec
			_chirp.play()
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
	if info["on_track"] and car.wheels_on_ground >= 3 and below < 2.0:
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
		var off_track := absf(float(info.get("offset", 0.0))) > hw + 15.0 or absf(below) > 6.0
		fell = fell or (off_track and _endless)
		# Zawieszone podwoziem na krawędzi jezdni, koła w powietrzu - samo nie zjedzie.
		var beached := car.wheels_on_ground < 3 and car.linear_velocity.length() < 0.5
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
					_use_crane()
		else:
			_fallen_time = 0.0


## Dźwig na żądanie gracza albo po upadku. Na trasie bez końca w trakcie
## jazdy zabiera życie; po ostatnim - koniec jazdy.
func _use_crane() -> void:
	if _endless and race_state == Race.RACING:
		# Trasa bez końca: bez dźwigu. Auto na kołach, ale utknięte - stawiamy
		# na koła w miejscu. Auto na dachu - to utrata życia (wybuch), żadnego
		# ratowania przyciskiem.
		if car.global_basis.y.y < 0.3:
			lose_life("auto na dachu")
		else:
			_right_car()
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
	car.place(_safe_pose(d))
	car.damage = dmg
	_fallen_time = 0.0


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
	var xf := Transform3D()
	for i in range(8):
		var dd := d + 8.0 * i
		if track.is_gap_at(dd):
			continue
		xf = track.transform_at_distance(dd)
		var smp: Array = track.samples_from(dd, 2.0)
		var w: float = smp[0]["width"] if not smp.is_empty() else 9.0
		var lane := (w - 1.0) / 3.0
		xf.origin += xf.basis.x * lane + xf.basis.y * 0.9
		# Bryła auta 0,25-1,65 m nad jezdnią - jezdnia sama się nie liczy.
		q.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * 0.25)
		if space.intersect_shape(q, 1).is_empty():
			return xf
	return xf


## Potrącenie innego auta: -20 s od czasu (raz na zderzenie). Kusi - ale
## bot wpada w szał, oszukuje (mocniejszy silnik), goni i taranuje.
func _on_player_hit(body: Node) -> void:
	# Najpierw typ: "in" na tablicy typowanej zgłasza błąd dla ściany (StaticBody3D).
	if not (body is StuntCar and body in _bots) or race_state != Race.RACING:
		return
	var now := race_time
	if now - float(_last_hit.get(body, -100.0)) < 2.0:
		return
	_last_hit[body] = now
	race_time = maxf(race_time - HIT_BONUS, 0.0)
	_penalty_flash = 2.5
	print("Potrącenie: -%d s" % int(HIT_BONUS))


func _on_car_wrecked() -> void:
	if _endless and race_state == Race.RACING:
		lose_life("auto rozbite")


## Ośmiobitowe ćwierknięcie: trzy tony fali prostokątnej (H5, E6, H6) po
## 1/12 s - razem ćwierć sekundy - powtórzone 2 razy co pół sekundy.
## Generowane w kodzie jako 8-bitowy PCM, jak w starych konsolach.
func _make_chirp() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(rate * 0.75))
	data.fill(0)
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
				data[n] = int(v * env) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


## Utrata życia: auto wybucha, kamera odjeżdża i pokazuje eksplozję,
## potem nowe auto na miejscu wypadku (albo koniec jazdy).
func lose_life(reason: String) -> void:
	if race_state != Race.RACING or _grace_t > 0.0:
		return
	race_state = Race.EXPLODING
	_cine_reason = reason
	_cine_t = 0.0
	var boom := Explosion.new()
	boom.paint = car._paint_mat.albedo_color if car._paint_mat else Color(0.8, 0.6, 0.2)
	boom.ignore = [car] + _bots
	add_child(boom)
	boom.global_position = car.global_position
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
	_result_label.visible = false
	print("Utrata życia: %s" % reason)


func _cinematic(delta: float) -> void:
	_cine_t += delta
	var k := smoothstep(0.0, 1.0, clampf(_cine_t / CINE_MOVE, 0.0, 1.0))
	origin.global_transform = _cine_from.interpolate_with(_cine_to, k)
	if _cine_t >= CINE_TOTAL:
		_after_explosion()


func _after_explosion() -> void:
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
	var cp: float = track.checkpoint_before(_last_safe_dist)
	var d := maxf(cp + 25.0, start_distance)
	_last_safe_dist = d
	car.place(_safe_pose(d))
	_fallen_time = 0.0
	for b in _bots:
		b.queue_free()
	_bots.clear()
	for o in _oncoming:
		(o["car"] as Node).queue_free()
	_oncoming.clear()
	for c in _oncoming_pool:
		c.queue_free()
	_oncoming_pool.clear()
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
	var xf: Transform3D = _safe_pose(d)
	car.place(xf)
	_fallen_time = 0.0
	if _mode == Mode.DRIVE and not _xr_ready:
		_chase_xf = xf * car.chase_point.transform


func _on_car_landed(impact_speed: float) -> void:
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
	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.stream = _make_rain_noise()
	_rain_sound.volume_db = -80.0
	add_child(_rain_sound)


func _update_rain(delta: float) -> void:
	if _rain == null or car == null:
		return
	# Szyba (krople, wycieraczki) mokrnie i schnie powoli; smugi i szum idą
	# za opadem szybko - wjazd do tunelu ucina deszcz (tunel ma rain 0).
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
	_env.set_env(bool(s.get("roof", false)), _rain_target)
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
var _perf_measure := false
func _log_perf(delta: float) -> void:
	_perf_t += delta
	if _perf_t < 5.0:
		return
	_perf_t = 0.0
	var rail := 0
	for b in _bots:
		if b.get_node("Driver").on_rail:
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
	print("PERF+ ms/s: ", Perf.dump(5.0))


## Szum deszczu: 2 s szumu przefiltrowanego dolnoprzepustowo, w pętli.
static func _make_rain_noise() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lp := 0.0
	for i in range(n):
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		# Pojedyncze trzaski kropel na dachu.
		var tick := rng.randf_range(-1.0, 1.0) * 0.6 if rng.randf() < 0.002 else 0.0
		var s16 := int(clampf(lp * 0.6 + tick, -1.0, 1.0) * 26000.0)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav



# --------------------------------------------------------------------------
# Ruch z naprzeciwka na autostradzie
# --------------------------------------------------------------------------

## Auta na drugiej jezdni autostrady jadą w przeciwną stronę (użytkownik).
## Bez sterowania i fizyki jazdy: ciała kinematyczne przesuwane po swoim
## pasie (zderzenie po przeskoczeniu bariery działa). Najwyżej
## ONCOMING_MAX naraz, 110-140 km/h, tylko na odcinkach autostrady.
const ONCOMING_MAX := 4
var _oncoming: Array[Dictionary] = []      # {"car", "dist", "v", "lane"}
var _oncoming_timer := 0.0
var _oncoming_pool: Array[StuntCar] = []


func _update_oncoming(delta: float) -> void:
	_oncoming_timer -= delta
	if _oncoming_timer <= 0.0 and race_state == Race.RACING:
		_oncoming_timer = _bot_rng.randf_range(1.5, 4.0)
		var d := _last_safe_dist + _bot_rng.randf_range(500.0, 900.0)
		if _oncoming.size() < ONCOMING_MAX and _is_highway_at(d):
			_spawn_oncoming(d)
	for o in _oncoming.duplicate():
		var c: StuntCar = o["car"]
		o["dist"] = float(o["dist"]) - float(o["v"]) * delta
		var d2: float = o["dist"]
		if d2 < _last_safe_dist - 150.0 or not _is_highway_at(d2) or not is_instance_valid(c):
			# Do puli (ukryte), zamiast queue_free - bez alokacji w trakcie jazdy.
			if is_instance_valid(c):
				c.visible = false
				c.global_position.y -= 500.0
				c.process_mode = Node.PROCESS_MODE_DISABLED   # w puli nic nie liczy
				_oncoming_pool.append(c)
			_oncoming.erase(o)
			continue
		c.global_transform = _oncoming_xf(d2, float(o["lane"]), c.wheel_radius)
		for w in c.wheels:
			# Auto obrócone o PI jedzie swoim przodem - kręcenie do przodu.
			w.omega = float(o["v"]) / c.wheel_radius


func _is_highway_at(d: float) -> bool:
	return track.has_method("is_highway_at") and track.is_highway_at(d)


## Położenie auta z naprzeciwka: druga jezdnia (w lewo o szerokość jezdni
## + pas rozdziału), pas `lane` licząc od pasa rozdziału, przodem do gracza.
func _oncoming_xf(d: float, lane: float, wheel_r := 0.33) -> Transform3D:
	var xf: Transform3D = track.transform_at_distance(d)
	var smp: Array = track.samples_from(d, 2.0)
	var w := 14.8 if smp.is_empty() else float(smp[0]["width"])
	var lane_w := (w - 1.0) / 3.0
	var x := -(w + TrackGenerator.HIGHWAY_MEDIAN) - lane * lane_w
	var b := xf.basis.rotated(xf.basis.y, PI)
	# Kołami na jezdni: środek koła 0,41 m pod mocowaniem + promień koła
	# (przegląd PR #7: przy 0,62 koła wchodziły ~0,16 m w asfalt).
	return Transform3D(b, xf.origin + xf.basis.x * x + xf.basis.y * (0.41 + wheel_r))


func _spawn_oncoming(d: float) -> void:
	var c: StuntCar
	if not _oncoming_pool.is_empty():
		c = _oncoming_pool.pop_back()
		c.visible = true
		c.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		c = StuntCar.new()
		c.name = "Oncoming%d" % Time.get_ticks_msec()
		c.is_bot = true
		add_child(c)
		c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		c.freeze = true
		for w in c.wheels:
			w.spring_len = 0.41
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		var keys: Array = gs.PAINTS.keys()
		c.set_paint(gs.PAINTS[keys[_bot_rng.randi() % keys.size()]])
	var lane := float(_bot_rng.randi_range(-1, 1))     # trzy pasy drugiej jezdni
	c.global_transform = _oncoming_xf(d, lane, c.wheel_radius)
	_oncoming.append({"car": c, "dist": d, "v": _bot_rng.randf_range(110.0, 140.0) / 3.6, "lane": lane})
