extends RigidBody3D
class_name StuntCar

## Samochód z realistycznym modelem fizyki.
##
## Nadwozie to RigidBody3D z jawnie podaną masą, środkiem masy i tensorem
## bezwładności. Reszta jest liczona tutaj, na czterech kołach:
##
## ZAWIESZENIE
##   Kontakt koła z jezdnią to sfera o promieniu koła rzucana w dół z punktu
##   mocowania (cast_motion). Sfera, nie promień - koło płynnie wjeżdża na
##   krawędź lądowiska, zamiast zahaczać o nią jednym punktem.
##   F = k·ugięcie + c·prędkość_ugięcia, z osobnym tłumieniem na dobiciu
##   i odbiciu, odbojem na końcu skoku i stabilizatorami na obu osiach.
##   Gotowe zestawy nastaw: SUSPENSION_PRESETS, wybierane na ekranie tytułowym.
##
## OPONY
##   Magic Formula Pacejki w wersji znormalizowanej: poślizg wzdłużny κ
##   i boczny tan α dzielone przez wartości szczytowe i składane w jeden
##   poślizg ρ. Siła = μ·Fz·MF(ρ), rozkładana na kierunki proporcjonalnie
##   do składowych. Daje to poprawne zachowanie przy łączonym poślizgu:
##   hamowanie w zakręcie odbiera przyczepność boczną.
##   μ maleje z obciążeniem (load sensitivity), jak w prawdziwej oponie.
##   Poślizgi nie są liczone wprost z prędkości, tylko przez relaxation
##   length: opona potrzebuje kawałka drogi, żeby zbudować siłę. To usuwa
##   osobliwość przy zerowej prędkości (dzielenie przez v) i pozwala autu
##   stać na pochyłości bez pełzania.
##
## NAPĘD
##   Krzywa momentu, hamowanie silnikiem, ogranicznik obrotów, 6-biegowa
##   skrzynia (automat albo ręczna), sprzęgło przy ruszaniu, dyferencjał
##   o ograniczonym poślizgu, napęd na tył. Bezwładność silnika przeliczona
##   przez przełożenie dochodzi do bezwładności tylnych kół - dlatego na
##   jedynce koła rozkręcają się wolniej niż na luzie. Każde koło ma własną
##   prędkość obrotową, więc może buksować i się blokować.
##
## HAMULCE
##   Moment hamujący z rozdziałem przód/tył, ręczny na tył.
##
## SYSTEMY WSPOMAGANIA (każdy wyłączalny z ekranu tytułowego)
##   Działają jak w prawdziwym aucie: na podstawie tego, co auto może
##   zmierzyć (prędkości kół, żyroskop), a nie "wiedzy" symulacji.
##   ABS - gdy koło wpada w poślizg za szczytem krzywej, puszcza hamulec.
##   TCS - porównuje prędkość obwodową tylnych (napędzanych) kół z przednimi
##         (swobodnymi); gdy tył buksuje, odcina moment silnika.
##   ESP - porównuje zmierzoną prędkość obrotu wokół osi pionowej z oczekiwaną
##         z modelu rowerowego (kąt skrętu, prędkość, rozstaw osi). Przy
##         nadsterowności hamuje zewnętrzne przednie koło i odcina gaz,
##         przy podsterowności hamuje wewnętrzne tylne.
##
## SIŁY NA NADWOZIE
##   Siła boczna opony działa w punkcie styku, wzdłużna na piaście, a moment
##   reakcji napędu i hamulców na nadwozie. Dzięki temu auto przysiada przy
##   ruszaniu i nurkuje przy hamowaniu z właściwych powodów. W powietrzu gaz
##   rozkręca koła i podnosi nos, hamulec je zatrzymuje i nos opada -
##   bez żadnej sztucznej "kontroli w powietrzu".
##
## Sterowanie (throttle, brake, steer, handbrake, shift_up/down) ustawia
## scena główna. Przód auta to -Z. Obrót koła do przodu = dodatnie omega.

signal landed(impact_speed: float)
## Auto rozbite: ogólne uszkodzenie doszło do 100%.
signal wrecked

const RPM_PER_RAD_S := 60.0 / TAU
## Podkroki opon na krok fizyki. Boty mają 2 (taniej na Queście).
var TIRE_SUBSTEPS := 6

## Zestawy nastaw zawieszenia. Zmieniają się razem: sztywniejsza sprężyna
## wymaga mocniejszego tłumika, inaczej auto podskakuje jak piłka.
## Częstotliwość własna przy ~290 kg na róg: miękkie ~1,4 Hz, sportowe
## ~1,8 Hz, twarde ~2,4 Hz.
const SUSPENSION_PRESETS := {
	"soft": {
		"label": "Miękkie",
		"spring_k": 22000.0, "damper_bump": 1500.0, "damper_rebound": 2800.0,
		"anti_roll_front": 11000.0, "anti_roll_rear": 6000.0,
	},
	"sport": {
		"label": "Sportowe",
		"spring_k": 36000.0, "damper_bump": 1900.0, "damper_rebound": 3600.0,
		"anti_roll_front": 19000.0, "anti_roll_rear": 11000.0,
	},
	"stiff": {
		"label": "Twarde",
		"spring_k": 65000.0, "damper_bump": 2600.0, "damper_rebound": 4900.0,
		"anti_roll_front": 32000.0, "anti_roll_rear": 20000.0,
	},
}

## Rodzaje napędu. "shape" to kształt krzywej momentu (obroty, moment
## względny); apply_engine() skaluje go tak, żeby szczyt mocy wypadł na
## wybranej wartości. Elektryk nie ma kształtu - jego krzywa wynika
## z fizyki silnika: stały moment do obrotów bazowych, potem stała moc.
const ENGINE_TYPES := {
	"petrol": {
		"label": "Benzyna",
		"shape": [[800, 0.50], [1500, 0.68], [2500, 0.83], [3500, 0.95],
				[4500, 1.0], [5500, 0.97], [6500, 0.87], [7200, 0.75]],
		"idle": 850.0, "redline": 7200.0, "inertia": 0.18,
		"brake_a": 18.0, "brake_b": 0.006,
		"gears": [3.30, 2.10, 1.55, 1.20, 0.97, 0.80], "final": 3.9, "reverse": 3.25,
		"up": 6700.0, "down": 2600.0, "clutch": 1300.0, "launch": 3800.0,
		"extra_mass": 0.0, "com_y": 0.0,
	},
	# Turbodiesel: płaski szczyt momentu nisko, wcześnie kończy się na obrotach,
	# cięższy wał i wysoki stopień sprężania - mocniej hamuje silnikiem.
	"diesel": {
		"label": "Diesel",
		"shape": [[800, 0.45], [1250, 0.70], [1750, 1.0], [2750, 1.0],
				[3500, 0.86], [4200, 0.70], [4700, 0.52]],
		"idle": 800.0, "redline": 4700.0, "inertia": 0.28,
		"brake_a": 28.0, "brake_b": 0.012,
		"gears": [3.55, 2.05, 1.35, 1.00, 0.80, 0.66], "final": 3.45, "reverse": 3.4,
		"up": 4200.0, "down": 1500.0, "clutch": 1050.0, "launch": 2000.0,
		"extra_mass": 50.0, "com_y": 0.0,
	},
	# Silnik elektryczny: pełny moment od zera, jeden bieg, bez sprzęgła.
	# Puszczony gaz = rekuperacja. Bateria w podłodze - cięższy, ale niżej.
	"electric": {
		"label": "Elektryk",
		"electric": true, "base_rpm": 4800.0,
		"idle": 0.0, "redline": 16000.0, "inertia": 0.06,
		"regen": 0.15,
		"gears": [9.0], "final": 1.0, "reverse": 9.0,
		"up": 1.0e9, "down": 0.0, "clutch": 0.0, "launch": 0.0,
		"extra_mass": 200.0, "com_y": -0.05,
	},
}

@export_group("Nadwozie")
@export var car_mass: float = 1150.0
## Środek masy względem punktu odniesienia nadwozia (na wysokości mocowań kół).
@export var com_offset: Vector3 = Vector3(0.0, -0.12, -0.03)
## Główne momenty bezwładności [kg·m²]: X = pochylenie, Y = odchylenie, Z = przechył.
@export var body_inertia: Vector3 = Vector3(1750.0, 1950.0, 480.0)
## Opór powietrza 0,5·ρ·Cd·A [kg/m]. 0,46 ≈ Cd 0,36 przy 2,1 m² czoła.
@export var aero_drag: float = 0.46
## Masa nadwozia bez napędu [kg] - opcja menu "Masa" (950-2500 kg).
## Bezwładność i zawieszenie skalują się proporcjonalnie do masy auta.
@export var body_mass: float = 1150.0
## Spojler (opcja menu): docisk F = ½·ρ·Cl·A·v² nad tylną osią, kosztem
## oporu ½·ρ·Cd·A·v². Docisk = więcej przyczepności przy dużej prędkości.
const SPOILERS := {
	"none": {"cla": 0.0, "cda": 0.0},
	"small": {"cla": 0.45, "cda": 0.03},
	"large": {"cla": 1.1, "cda": 0.08},
}
const AIR_RHO := 1.225
@export var spoiler: String = "none"
var _spoiler_nodes := {}
var _extra_mass := 0.0
var _suspension_preset := "sport"

@export_group("Zawieszenie")
## Długość sprężyny w spoczynku, od mocowania do osi koła.
@export var rest_length: float = 0.45
@export var wheel_radius: float = 0.33
## Sztywność [N/m] na koło. Nadpisywana przez apply_suspension_preset().
@export var spring_k: float = 36000.0
## Tłumienie przy ściskaniu i przy odbiciu [N·s/m]. Odbicie zwykle ~2x mocniejsze.
@export var damper_bump: float = 1900.0
@export var damper_rebound: float = 3600.0
## Odbój: ostatnie centymetry skoku to bardzo twarda sprężyna.
@export var bump_stop_travel: float = 0.06
@export var bump_stop_k: float = 260000.0
## Stabilizatory [N/m różnicy ugięć]. Mocniejszy z przodu = podsterowność.
@export var anti_roll_front: float = 19000.0
@export var anti_roll_rear: float = 11000.0

@export_group("Opony")
## Szczytowy współczynnik tarcia przy obciążeniu nominalnym. 1,1 = sportowa opona drogowa.
@export var tire_mu: float = 1.1
## Mieszanka opon: mnożnik przyczepności nawierzchni (SURFACES.grip).
## Użytkownik: "opony raczej całoroczne niż letnie". Całoroczne: na suchym
## trochę słabiej od letnich, w chłodzie na mokrym i na lodzie wyraźnie lepiej.
const TIRE_COMPOUNDS := {
	"summer": {"dry": 1.0, "wet": 1.0, "ice": 1.0},
	"all_season": {"dry": 0.94, "wet": 1.08, "ice": 1.6},
	"winter": {"dry": 0.86, "wet": 1.05, "ice": 2.3},
}
@export var tires: String = "all_season"
## Spadek μ z obciążeniem: μ = μ0·(1 − s·(Fz/Fz0 − 1)).
@export var load_sensitivity: float = 0.1
## Poślizg wzdłużny, przy którym opona daje maksimum siły.
@export var peak_slip_ratio: float = 0.11
## Kąt znoszenia, przy którym opona daje maksimum siły bocznej.
@export var peak_slip_angle_deg: float = 7.5
## Kształt krzywej MF. C=1,4 → po zerwaniu przyczepności zostaje ~80% siły.
@export var mf_shape_c: float = 1.4
## Relaxation length: droga potrzebna oponie do zbudowania siły [m].
@export var relax_lateral: float = 0.45
@export var relax_longitudinal: float = 0.25
@export var rolling_resistance_coef: float = 0.013
@export var wheel_inertia: float = 1.2

@export_group("Silnik i skrzynia")
## Krzywa momentu: pary (obroty, Nm). Między punktami interpolacja liniowa.
@export var torque_curve: PackedVector2Array = PackedVector2Array([
	Vector2(800, 150), Vector2(1500, 205), Vector2(2500, 250), Vector2(3500, 285),
	Vector2(4500, 300), Vector2(5500, 290), Vector2(6500, 260), Vector2(7200, 225),
])
@export var idle_rpm: float = 850.0
@export var redline_rpm: float = 7200.0
@export var engine_inertia: float = 0.18
## Hamowanie silnikiem: T = a + b·rpm [Nm], gdy gaz puszczony.
@export var engine_brake_a: float = 18.0
@export var engine_brake_b: float = 0.006
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([3.30, 2.10, 1.55, 1.20, 0.97, 0.80])
@export var reverse_ratio: float = 3.25
@export var final_drive: float = 3.9
@export var drivetrain_efficiency: float = 0.88
@export var shift_time: float = 0.18
## true = automat, false = ręczna. Ustawiane z ekranu tytułowego.
@export var automatic: bool = true
## Silnik elektryczny: bez sprzęgła, moment od zera, rekuperacja zamiast
## hamowania silnikiem. Ustawiane przez apply_engine().
@export var electric: bool = false
@export var launch_rpm: float = 3800.0
@export var upshift_rpm: float = 6700.0
@export var downshift_rpm: float = 2600.0
## Poniżej tych obrotów (liczonych z kół) sprzęgło się ślizga, inaczej silnik by zgasł.
@export var clutch_engage_rpm: float = 1300.0
## Dyferencjał LSD: moment blokady [Nm na rad/s różnicy] i jego limit.
@export var lsd_stiffness: float = 25.0
@export var lsd_max_torque: float = 500.0
## Układ napędu: "rwd" (tył) albo "awd" (4x4). W 4x4 centralny dyferencjał
## planetarny dzieli moment AWD_FRONT_SHARE na przód, reszta na tył,
## sprzęgło wiskotyczne między osiami (moment z różnicy ich prędkości)
## i LSD na obu osiach.
@export var drive_layout: String = "rwd"
## Elektryk: silnik w każdym kole (4 × 1/4 mocy, bez dyferencjałów, koła
## kręcą się niezależnie, kontrola trakcji osobno na każde koło). Zawsze 4x4.
@export var hub_motors: bool = false
const AWD_FRONT_SHARE := 0.4
@export var center_coupling: float = 40.0
@export var center_coupling_max: float = 900.0

@export_group("Hamulce")
## Maksymalny moment hamujący na koło [Nm].
@export var brake_torque_front: float = 1900.0
@export var brake_torque_rear: float = 1050.0
@export var handbrake_torque: float = 2600.0

@export_group("Systemy wspomagania")
@export var abs_enabled: bool = true
@export var tcs_enabled: bool = true
@export var esp_enabled: bool = true
## TCS: poślizg tylnych kół (względem przednich), który system dopuszcza.
## Nieco poniżej szczytu krzywej opony - tam jest najwięcej przyczepności.
@export var tcs_target_slip: float = 0.09
## Jak szybko TCS odcina i oddaje moment [1/s].
@export var tcs_response: float = 25.0
## ESP: prędkość charakterystyczna podsterowności [m/s] w modelu rowerowym.
## Powyżej niej auto z założenia skręca coraz mniej na ten sam kąt kół.
@export var esp_char_speed: float = 28.0
## Martwa strefa błędu prędkości obrotu [rad/s] - poniżej ESP nic nie robi.
@export var esp_deadband: float = 0.06
## Moment hamujący ESP na rad/s błędu i jego limit [Nm].
@export var esp_gain: float = 5000.0
@export var esp_max_brake: float = 1600.0

@export_group("Kierowanie")
@export var max_steer_deg: float = 34.0
## Pomoc dla gracza: zmniejsza zakres skrętu z prędkością. Prawdziwe auto
## tego nie robi, ale gałka czy klawisz to nie kierownica z 900° obrotu.
@export var steer_assist: bool = true
@export var high_speed_steer_deg: float = 6.0
@export var steer_assist_speed: float = 45.0
## Jak szybko koła nadążają za wejściem [pełne wychylenia na sekundę].
@export var steer_rate: float = 2.5

# --- wejście, ustawiane z zewnątrz ---
var throttle: float = 0.0    # 0..1
var brake: float = 0.0       # 0..1; w automacie na postoju włącza wsteczny
var steer: float = 0.0       # -1..1, dodatnie w prawo
var handbrake: float = 0.0   # 0..1
## Osobny przycisk wstecznego (gogle: grip ręki z gazem). Gdy włączony:
## wsteczny tylko na żądanie i tylko po zatrzymaniu auta (ochrona skrzyni),
## bez automatycznego "hamulec na postoju = wsteczny" i bez zamiany pedałów.
var dedicated_reverse := false
var reverse_request := false

# --- stan do odczytu ---
var speed: float = 0.0           # prędkość wzdłuż nadwozia [m/s], dodatnia do przodu
var engine_rpm: float = 850.0
var gear: int = 1                # -1 = wsteczny, 0 = luz, 1..6
var wheels_on_ground: int = 0
var airtime: float = 0.0
## Czy dany system ingerował w ostatnim kroku fizyki - do kontrolek na desce.
var abs_active := false
var tcs_active := false
var esp_active := false
var esp_oversteer := false     # rodzaj ostatniej ingerencji ESP, do diagnostyki

## Stan jednego koła.
class Wheel:
	var mount: Vector3            # punkt mocowania w układzie nadwozia
	var front: bool
	var left: bool
	var node: Node3D              # wizualizacja
	var steer_angle := 0.0
	var omega := 0.0              # prędkość obrotowa [rad/s], dodatnia do przodu
	var spin := 0.0               # kąt obrotu do wizualizacji
	var kappa := 0.0              # poślizg wzdłużny (stan relaksacji)
	var tan_alpha := 0.0          # tangens kąta znoszenia (stan relaksacji)
	var contact := false
	var contact_point := Vector3.ZERO
	var normal := Vector3.UP
	var spring_len := 0.0
	var compression := 0.0
	var prev_compression := 0.0
	var load := 0.0               # docisk Fz [N]
	var slip := 0.0               # poślizg znormalizowany ρ, do dźwięku i śladów
	var grip := 1.0               # mnożnik tarcia nawierzchni pod kołem
	var surface := ""             # nazwa nawierzchni pod kołem (pusta = brak kontaktu)

var wheels: Array[Wheel] = []
var engine_type := "petrol"
var engine_power_kw := 0.0
var _base_mass := 1150.0
var _base_com := Vector3.ZERO
var _base_inertia := Vector3.ONE

var _steer_input_smoothed := 0.0
var _shift_timer := 0.0
var _pending_gear := 1
var _reverse_hold := 0.0
var _shift_cooldown := 0.0
var _clutch_engaged := false
var _max_fall_speed := 0.0
var _sphere: SphereShape3D
var _cast: PhysicsShapeQueryParameters3D
var _wheelbase := 2.57
var _track_width := 1.64
var _tcs_factor := 1.0                          # mnożnik momentu silnika od TCS
var _hub_tcs: Array[float] = [1.0, 1.0, 1.0, 1.0]
## Badanie podłoża promieniem zamiast sfery (tańsze; boty).
var ray_probe := true
var _ray: PhysicsRayQueryParameters3D  # TCS na koło (silniki w kołach)
var _esp_factor := 1.0                          # mnożnik momentu silnika od ESP
var _esp_brake: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _abs_hit := false
## Modulacja ciśnienia ABS na koło: 1 = pełne ciśnienie z pedału.
var _abs_mod: Array[float] = [1.0, 1.0, 1.0, 1.0]

## Punkt oczu kierowcy, kamera z tyłu i deska rozdzielcza.
var seat: Marker3D
var chase_point: Marker3D
var dash_label: Label3D
var gauges: Gauges
var _steering_wheel: Node3D
var _tail_mat: StandardMaterial3D
var _paint_mat: StandardMaterial3D
## Materiały kabiny i karoserii, które prześwitują w widoku z kokpitu.
var _cockpit_mats: Array[BaseMaterial3D] = []
var _cockpit_alpha := -1.0
var _vinyl_mat: StandardMaterial3D
var _roof_mats: Array = []

## Opad nad autem: 0 = sucho, 1 = mżawka, 2 = deszcz (ustawia scena jazdy,
## płynnie). Wycieraczki włączają się same: przy mżawce przerywany tryb,
## przy deszczu ciągły - jak czujnik deszczu, bez wpływu na jazdę.
var rain := 0.0
const WIPE_DUR := 1.1                 # s na cykl w górę i w dół
const WIPE_SWEEP := 1.75              # rad
const WIPE_PAUSE := 2.5               # s przerwy przy mżawce
var _wipers: Array[Node3D] = []
var _drops_mat: ShaderMaterial
var _wipe_t := 0.0                    # zegar wycieraczek [s]
var _wipe_start := -1e6
var _wipe_prev := -1e6
var _wipe_active := false


func _ready() -> void:
	_base_mass = car_mass
	_base_com = com_offset
	_base_inertia = body_inertia
	mass = car_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset
	inertia = body_inertia
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	continuous_cd = true
	can_sleep = false
	# Kontakty nadwozia potrzebne do wgnieceń (_integrate_forces).
	contact_monitor = true
	max_contacts_reported = 8

	var mat := PhysicsMaterial.new()
	mat.friction = 0.5       # nadwozie trące o jezdnię, np. po dachowaniu
	mat.bounce = 0.05
	physics_material_override = mat

	var mounts := [
		Vector3(-0.82, 0.0, -1.32), Vector3(0.82, 0.0, -1.32),
		Vector3(-0.82, 0.0, 1.25), Vector3(0.82, 0.0, 1.25),
	]
	for i in range(4):
		var w := Wheel.new()
		w.mount = mounts[i]
		w.front = i < 2
		w.left = i % 2 == 0
		w.spring_len = rest_length
		wheels.append(w)
	_wheelbase = absf(mounts[0].z - mounts[2].z)
	_track_width = absf(mounts[1].x - mounts[0].x)

	_sphere = SphereShape3D.new()
	_sphere.radius = wheel_radius
	_cast = PhysicsShapeQueryParameters3D.new()
	_cast.shape = _sphere
	_cast.exclude = [get_rid()]

	engine_rpm = idle_rpm
	_build_body()

	# Bot (puste, zdalnie sterowane auto): bez zegarów i bez dźwięku -
	# każdy bot to pełna fizyka auta, oszczędzamy, gdzie się da.
	if is_bot:
		return
	# Dźwięk generowany w kodzie (CarAudio) - źródło w komorze silnika.
	var audio := CarAudio.new()
	audio.name = "Audio"
	audio.car = self
	audio.position = Vector3(0.0, 0.0, -1.6)
	add_child(audio)


## Puste, zdalnie sterowane auto (bot): bez zegarów, dźwięku i kokpitu.
@export var is_bot := false


## Światła w szale drogowym: przednie lampy pulsują na czerwono (0 = normalnie).
func set_rage_lights(t: float) -> void:
	var g: Dictionary = _dent_groups.get("head", {})
	if g.is_empty():
		return
	var m: StandardMaterial3D = g["mat"]
	m.emission = Color(1.0, 0.92, 0.75).lerp(Color(1.0, 0.1, 0.05), t)
	m.emission_energy_multiplier = 0.6 + 3.0 * t


## Ustawia rodzaj napędu i moc maksymalną [kW]. Krzywa momentu jest
## przeskalowana tak, żeby jej szczyt mocy P = T·ω wynosił dokładnie power_kw.
func apply_engine(type_name: String, power_kw: float) -> void:
	if not ENGINE_TYPES.has(type_name):
		push_warning("StuntCar: nieznany napęd '%s'." % type_name)
		return
	var e: Dictionary = ENGINE_TYPES[type_name]
	engine_type = type_name
	engine_power_kw = power_kw
	var p_w := power_kw * 1000.0
	electric = e.get("electric", false)
	idle_rpm = e["idle"]
	redline_rpm = e["redline"]
	engine_inertia = e["inertia"]
	gear_ratios = PackedFloat32Array(e["gears"])
	final_drive = e["final"]
	reverse_ratio = e["reverse"]
	upshift_rpm = e["up"]
	downshift_rpm = e["down"]
	clutch_engage_rpm = e["clutch"]
	launch_rpm = e["launch"]
	# Bardzo mocne silniki (powyżej 350 kW, elektryk powyżej 250 kW) mają
	# dłuższe przełożenie - inaczej 700 kW kończyłoby się w ogranicznika
	# przy ~290 km/h (benzyna) albo ~234 km/h (elektryk).
	if electric and power_kw > 250.0:
		gear_ratios = PackedFloat32Array([e["gears"][0] * sqrt(250.0 / power_kw)])
		reverse_ratio = gear_ratios[0]
	elif not electric and power_kw > 350.0:
		final_drive *= sqrt(350.0 / power_kw)
	# Większe koła (concept car) = dłuższe przełożenie efektywne; korekta
	# tak, żeby te same obroty dawały tę samą prędkość co w sedanie.
	var rk := wheel_radius / BASE_WHEEL_RADIUS
	if not is_equal_approx(rk, 1.0):
		final_drive *= rk

	var curve := PackedVector2Array()
	if electric:
		# Stały moment do obrotów bazowych, potem stała moc: T = P/ω.
		var base_w: float = e["base_rpm"] / RPM_PER_RAD_S
		var t_max := p_w / base_w
		curve.append(Vector2(0.0, t_max))
		var rpm: float = e["base_rpm"]
		while rpm <= redline_rpm:
			curve.append(Vector2(rpm, p_w / (rpm / RPM_PER_RAD_S)))
			rpm += 1000.0
		# Rekuperacja jako "hamowanie silnikiem": stały moment, część maksymalnego.
		engine_brake_a = t_max * e["regen"]
		engine_brake_b = 0.0
	else:
		# Skala z najwyższej mocy na kształcie (próbkowanym co 50 obr.).
		var shape: Array = e["shape"]
		var tmp := PackedVector2Array()
		for pt in shape:
			tmp.append(Vector2(pt[0], pt[1]))
		torque_curve = tmp
		var peak := 0.0
		var r := tmp[0].x
		while r <= tmp[tmp.size() - 1].x:
			peak = maxf(peak, _curve_torque(r) * r / RPM_PER_RAD_S)
			r += 50.0
		var t_scale := p_w / peak
		for pt in tmp:
			curve.append(Vector2(pt.x, pt.y * t_scale))
		engine_brake_a = e["brake_a"]
		engine_brake_b = e["brake_b"]
	torque_curve = curve

	# Masa i środek masy zależą od napędu (bateria, cięższy silnik).
	_extra_mass = e["extra_mass"]
	_apply_mass()
	com_offset = _base_com + Vector3(0.0, e["com_y"], 0.0) + _model_com
	center_of_mass = com_offset
	engine_rpm = idle_rpm
	gear = 1
	_pending_gear = 1
	if gauges:
		gauges.set_rpm_range(redline_rpm + 800.0, redline_rpm)


## Maksymalny moment silnika z bieżącej krzywej [Nm] - do opisu w menu.
func peak_torque() -> float:
	var m := 0.0
	for pt in torque_curve:
		m = maxf(m, pt.y)
	return m


## Przezroczystość kabiny i karoserii (0 = pełne, 0,8 = prawie niewidoczne).
## Ustawiana przez scenę jazdy tylko w widoku z kokpitu: na torze nad
## przepaścią trzeba widzieć jezdnię przed autem i pod nim, a maska i deska
## ją zasłaniają. Szyby i światła bez zmian.
## Tryb "alpha z depth pre-pass": nakładające się ściany jednej siatki nie
## migają, a prześwituje tylko to, co leży za kabiną (jezdnia, koła).
func set_cockpit_transparency(t: float) -> void:
	t = clampf(t, 0.0, 0.95)
	if is_equal_approx(t, _cockpit_alpha):
		return
	_cockpit_alpha = t
	for m in _cockpit_mats:
		# Słupki (winyl) prześwitują mocniej niż reszta - to one dają ciemną
		# "ramkę" wokół widoku (użytkownik: mniej winietowania). Dach odwrotnie:
		# wyraźnie widoczny (użytkownik chce dach), połowa przezroczystości.
		var tm := t
		if m == _vinyl_mat:
			tm = minf(t * 1.5, 0.9)
		elif m in _roof_mats:
			tm = t * 0.5
		if tm <= 0.001:
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color.a = 1.0
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.albedo_color.a = 1.0 - tm


## Kolor lakieru. Jeden materiał na całą karoserię, więc zmiana jest natychmiastowa.
func set_paint(c: Color) -> void:
	_paint_color = c
	if _paint_mat:
		# Kanał alfa należy do przezroczystości kokpitu - nie nadpisujemy go.
		_paint_mat.albedo_color = Color(c, _paint_mat.albedo_color.a)
	for m in _concept_paint_mats:
		m.albedo_color = Color(c, m.albedo_color.a)


## Ustawia sprężyny, tłumiki i stabilizatory z zestawu SUSPENSION_PRESETS.
func apply_suspension_preset(preset_name: String) -> void:
	if not SUSPENSION_PRESETS.has(preset_name):
		push_warning("StuntCar: nieznany zestaw zawieszenia '%s'." % preset_name)
		return
	_suspension_preset = preset_name
	var p: Dictionary = SUSPENSION_PRESETS[preset_name]
	# Zestawy strojone dla 1150 kg - przy innej masie ta sama częstotliwość
	# drgań: sprężyny, tłumiki i stabilizatory proporcjonalnie do masy.
	var k := car_mass / (_base_mass + _extra_mass) if _base_mass > 0.0 else 1.0
	spring_k = p["spring_k"] * k
	damper_bump = p["damper_bump"] * k
	damper_rebound = p["damper_rebound"] * k
	anti_roll_front = p["anti_roll_front"] * k
	anti_roll_rear = p["anti_roll_rear"] * k


## Masa nadwozia [kg]: przelicza masę, bezwładność i zawieszenie.
func set_body_mass(kg: float) -> void:
	body_mass = kg
	_apply_mass()
	apply_suspension_preset(_suspension_preset)


func _apply_mass() -> void:
	car_mass = body_mass + _extra_mass
	mass = car_mass
	# _base_mass to masa odniesienia (1150 kg z _ready), dla niej body_inertia.
	inertia = _base_inertia * (car_mass / maxf(_base_mass, 1.0))


func set_spoiler(kind: String) -> void:
	if not SPOILERS.has(kind):
		return
	spoiler = kind
	for k in _spoiler_nodes:
		(_spoiler_nodes[k] as Node3D).visible = k == kind


# --------------------------------------------------------------------------
# Krok fizyki
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_physics_step(delta)
	Perf.add("bot_fiz" if is_bot else "auto_fiz", t0)


func _physics_step(delta: float) -> void:
	# Zamrożone auto (wybuch, ekran tytułowy) nie liczy fizyki - siły
	# przykładane do zamrożonej bryły mogły się kumulować i po odmrożeniu
	# rozkręcać auto (wirowanie po odrodzeniu).
	if freeze:
		return
	# Stabilizacja tuż po postawieniu: bez obrotu, wytłumiona prędkość.
	if _settle_t > 0.0:
		_settle_t -= delta
		angular_velocity = Vector3.ZERO
		linear_velocity *= 0.5
	for d in _dent_queue:
		dent(d[0], d[1], d[2])
	_dent_queue.clear()
	for imp in _impact_queue:
		_damage_impact(imp[0], imp[1])
	_impact_queue.clear()
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var right := xf.basis.x
	speed = linear_velocity.dot(fwd)

	_update_steering(delta)
	_update_gearbox(delta)

	# --- 1. kontakt i ugięcie ---
	var space := get_world_3d().direct_space_state
	var grounded := 0
	for w in wheels:
		_probe_wheel(space, xf, w)
		if w.contact:
			grounded += 1

	# --- 2. siły zawieszenia, ze stabilizatorami ---
	for w in wheels:
		if not w.contact:
			w.load = 0.0
			continue
		var comp_vel := (w.compression - w.prev_compression) / delta
		var damper := damper_bump if comp_vel > 0.0 else damper_rebound
		var f := spring_k * w.compression + damper * comp_vel
		if w.spring_len < bump_stop_travel:
			f += bump_stop_k * (bump_stop_travel - w.spring_len)
		w.load = f
	_anti_roll(wheels[0], wheels[1], anti_roll_front)
	_anti_roll(wheels[2], wheels[3], anti_roll_rear)
	for w in wheels:
		if w.contact:
			w.load = maxf(w.load, 0.0)    # opona tylko pcha
			apply_force(up * w.load, w.contact_point - xf.origin)

	# --- 3. systemy wspomagania, napęd ---
	_update_tcs(delta)
	_update_esp(delta, grounded)
	var g_ratio := _total_ratio(gear)
	var axle_torque := 0.0
	if _clutch_engaged or _clutch_slipping():
		var t_engine := _engine_torque_at_clutch()
		if t_engine > 0.0:
			# Systemy odcinają tylko moment napędowy, hamowania silnikiem nie ruszają.
			t_engine *= minf(_tcs_factor, _esp_factor)
			# Uszkodzony silnik: do -75% mocy. Rozbite auto nie jedzie,
			# bez paliwa (prądu) też nie.
			t_engine *= (1.0 - 0.75 * damage["engine"]) * (0.0 if (is_wrecked or fuel <= 0.0) else 1.0)
		axle_torque = t_engine * g_ratio * drivetrain_efficiency
		_burn_fuel(maxf(t_engine, 0.0) * engine_rpm / RPM_PER_RAD_S, delta)
	elif not electric:
		_burn_fuel(0.0, delta)
	# Bezwładność silnika przez przełożenie, rozdzielona na napędzane koła.
	var n_driven := 2.0 if _is_rwd() else 4.0
	var reflected := engine_inertia * g_ratio * g_ratio / n_driven if _clutch_engaged else 0.0

	# --- 4. opony i koła, w podkrokach ---
	# Kierunki i prędkości w punktach styku są stałe w obrębie kroku.
	var dirs: Array = []
	for w in wheels:
		var n := w.normal if w.contact else up
		var wf := fwd.rotated(up, -w.steer_angle)
		wf = (wf - n * wf.dot(n)).normalized()
		var wr := wf.cross(n).normalized()
		var v := Vector3.ZERO
		if w.contact:
			v = linear_velocity + angular_velocity.cross(w.contact_point - xf.origin)
		dirs.append([wf, wr, v.dot(wf), v.dot(wr)])

	var h := delta / float(TIRE_SUBSTEPS)
	_abs_hit = false
	var body_reaction := 0.0
	var fx_sum: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var fy_sum: Array[float] = [0.0, 0.0, 0.0, 0.0]

	for _s in range(TIRE_SUBSTEPS):
		# Blokada dyferencjału zależy od różnicy prędkości kół osi.
		var lsd := clampf((wheels[2].omega - wheels[3].omega) * lsd_stiffness,
				-lsd_max_torque, lsd_max_torque)
		var lsd_f := clampf((wheels[0].omega - wheels[1].omega) * lsd_stiffness,
				-lsd_max_torque, lsd_max_torque)
		# 4x4: podział 40/60 i wiskoza między osiami (przenosi moment z osi
		# szybszej na wolniejszą).
		var t_front := 0.0
		var t_rear := axle_torque
		if not _is_rwd() and not _hub():
			var visc := clampf(((wheels[0].omega + wheels[1].omega) - (wheels[2].omega + wheels[3].omega))
					* 0.5 * center_coupling, -center_coupling_max, center_coupling_max)
			t_front = axle_torque * AWD_FRONT_SHARE - visc
			t_rear = axle_torque * (1.0 - AWD_FRONT_SHARE) + visc
		for i in range(4):
			var w := wheels[i]
			var d: Array = dirs[i]

			var fx := 0.0
			var fy := 0.0
			if w.contact and w.load > 1.0:
				var f := _tire_forces(w, d[2], d[3], h)
				fx = f.x
				fy = f.y
			else:
				w.slip = 0.0

			# Momenty na kole: napęd, opona, opór toczenia, hamulec.
			var t_drive := 0.0
			var inertia_w := wheel_inertia
			if _hub():
				# Własny silnik w kole: ćwierć momentu, własna kontrola trakcji.
				t_drive = axle_torque * 0.25 * (_hub_tcs[i] if axle_torque > 0.0 else 1.0)
				inertia_w += reflected
			elif not w.front:
				t_drive = t_rear * 0.5 + (-lsd if w.left else lsd)
				inertia_w += reflected
			elif not _is_rwd():
				t_drive = t_front * 0.5 + (-lsd_f if w.left else lsd_f)
				inertia_w += reflected
			var t_roll := -rolling_resistance_coef * w.load * wheel_radius * clampf(w.omega * 2.0, -1.0, 1.0)
			var t_free := t_drive - fx * wheel_radius + t_roll

			var t_brake := _brake_torque_for(w, i, h)
			var omega_free := w.omega + t_free / inertia_w * h
			var brake_dw := t_brake / inertia_w * h
			var applied_brake := 0.0
			if absf(omega_free) <= brake_dw:
				# Hamulec zatrzymuje koło - blokada.
				applied_brake = -omega_free * inertia_w / h
				w.omega = 0.0
			else:
				applied_brake = -signf(omega_free) * t_brake
				w.omega = omega_free + applied_brake / inertia_w * h

			# Napęd i hamulec działają na koło, nadwozie dostaje przeciwny moment.
			body_reaction += (t_drive + applied_brake) / float(TIRE_SUBSTEPS)
			fx_sum[i] += fx / float(TIRE_SUBSTEPS)
			fy_sum[i] += fy / float(TIRE_SUBSTEPS)

	# --- 5. siły opon na nadwozie ---
	for i in range(4):
		var w := wheels[i]
		if not w.contact:
			continue
		var d: Array = dirs[i]
		var hub := xf * (w.mount - Vector3.UP * w.spring_len)
		# Wzdłużna na piaście, boczna w punkcie styku.
		apply_force(d[0] * fx_sum[i], hub - xf.origin)
		apply_force(d[1] * fy_sum[i], w.contact_point - xf.origin)

	# Moment "do przodu" na kole to wektor wzdłuż -X nadwozia, więc reakcja jest wzdłuż +X.
	apply_torque(right * body_reaction)

	# --- 6. opór powietrza ---
	var v2 := linear_velocity.length_squared()
	if v2 > 0.01:
		var sp: Dictionary = SPOILERS[spoiler]
		apply_central_force(-linear_velocity.normalized() * v2 * (aero_drag + 0.5 * AIR_RHO * sp["cda"]))
		if sp["cla"] > 0.0:
			# Docisk z prędkości wzdłuż auta, nad tylną osią (spojler na klapie).
			var vf := linear_velocity.dot(fwd)
			var rear_axle := (wheels[2].mount + wheels[3].mount) * 0.5
			apply_force(-up * 0.5 * AIR_RHO * sp["cla"] * vf * vf, xf.basis * rear_axle)

	_update_engine_rpm(delta)
	abs_active = _abs_hit

	# --- lot i lądowanie ---
	if grounded == 0:
		airtime += delta
		_max_fall_speed = maxf(_max_fall_speed, -linear_velocity.y)
	else:
		if wheels_on_ground == 0 and airtime > 0.25:
			landed.emit(_max_fall_speed)
			_damage_landing(_max_fall_speed)
		airtime = 0.0
		_max_fall_speed = 0.0
	wheels_on_ground = grounded


## Sfera koła rzucana w dół z mocowania. Ustawia kontakt, normalną i ugięcie.
func _probe_wheel(space: PhysicsDirectSpaceState3D, xf: Transform3D, w: Wheel) -> void:
	var up := xf.basis.y
	var mount_w := xf * w.mount
	if ray_probe:
		_probe_wheel_ray(space, xf, w, up, mount_w)
		return
	_cast.transform = Transform3D(xf.basis, mount_w)
	_cast.motion = -up * rest_length
	var res := space.cast_motion(_cast)
	w.prev_compression = w.compression
	if res.is_empty() or res[1] >= 1.0:
		w.contact = false
		w.surface = ""
		w.spring_len = rest_length
		w.compression = 0.0
		return

	var safe: float = res[0]
	var unsafe: float = res[1]
	w.contact = true
	w.spring_len = rest_length * safe

	_cast.transform = Transform3D(xf.basis, mount_w - up * rest_length * unsafe)
	_cast.motion = Vector3.ZERO
	var info := space.get_rest_info(_cast)
	if info.is_empty():
		w.normal = up
		w.contact_point = mount_w - up * (w.spring_len + wheel_radius)
	else:
		w.normal = info["normal"]
		w.contact_point = info["point"]
		# Nawierzchnia: metadane "grip" i "surface" ciała, w które trafiło koło
		# (tor ustawia je osobno dla suchej, mokrej i lodu). Brak = sucha.
		var obj := instance_from_id(info["collider_id"])
		w.grip = 1.0
		w.surface = "dry"
		if obj:
			w.grip = obj.get_meta("grip", 1.0)
			w.surface = obj.get_meta("surface", "dry")
		w.grip *= TIRE_COMPOUNDS[tires].get(w.surface, 1.0)
		# Ułamek z cast_motion ma ograniczoną dokładność (rzędu centymetra),
		# a tłumik różniczkuje ugięcie przy 240 Hz: 1 cm szumu = kilka kN
		# fałszywej siły i koło co kilka kroków traci docisk. Dlatego ugięcie
		# liczymy dokładnie: środek koła leży na osi zawieszenia w odległości
		# promienia od płaszczyzny styku.
		#   (mount − up·s − p)·n = r  →  s = ((mount − p)·n − r) / (up·n)
		var un := up.dot(w.normal)
		if un > 0.2:
			var s := ((mount_w - w.contact_point).dot(w.normal) - wheel_radius) / un
			w.spring_len = clampf(s, 0.0, rest_length)
	w.compression = rest_length - w.spring_len


## Tańsze badanie podłoża (boty): jeden promień od mocowania w dół zamiast
## rzutu sfery i zapytania o kontakt (dwa drogie zapytania na koło - przy
## 240 Hz to było ~60% kosztu fizyki auta). Ugięcie liczone tak samo,
## z płaszczyzny styku. Różnica tylko na ostrych krawędziach (krawężnik
## łapie dopiero pod środkiem koła).
func _probe_wheel_ray(space: PhysicsDirectSpaceState3D, xf: Transform3D, w: Wheel,
		up: Vector3, mount_w: Vector3) -> void:
	w.prev_compression = w.compression
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.exclude = [get_rid()]
	_ray.from = mount_w
	_ray.to = mount_w - up * (rest_length + wheel_radius)
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		w.contact = false
		w.surface = ""
		w.spring_len = rest_length
		w.compression = 0.0
		return
	w.contact = true
	w.normal = hit["normal"]
	w.contact_point = hit["position"]
	var obj: Object = hit["collider"]
	w.grip = obj.get_meta("grip", 1.0) if obj else 1.0
	w.surface = obj.get_meta("surface", "dry") if obj else "dry"
	w.grip *= TIRE_COMPOUNDS[tires].get(w.surface, 1.0)
	var un := up.dot(w.normal)
	var s := rest_length
	if un > 0.2:
		s = ((mount_w - w.contact_point).dot(w.normal) - wheel_radius) / un
	else:
		s = (mount_w - w.contact_point).length() - wheel_radius
	w.spring_len = clampf(s, 0.0, rest_length)
	w.compression = rest_length - w.spring_len


func _anti_roll(l: Wheel, r: Wheel, k: float) -> void:
	if not (l.contact or r.contact):
		return
	var f := (l.compression - r.compression) * k
	if l.contact:
		l.load += f
	if r.contact:
		r.load -= f


## Siły opony z modelu Magic Formula ze stanem relaksacji. Zwraca (Fx, Fy)
## w kierunkach koła: Fx do przodu, Fy w prawo.
func _tire_forces(w: Wheel, v_long: float, v_lat: float, h: float) -> Vector2:
	var vx_abs := absf(v_long)
	var slip_vel := w.omega * wheel_radius - v_long   # >0 = koło szybsze niż jezdnia

	# Relaksacja: dκ/dt = (v_poślizgu − |vx|·κ)/σ. Całkowane dokładnie
	# (wykładniczo), więc stabilne przy każdej prędkości.
	w.kappa = clampf(_relax(w.kappa, slip_vel, vx_abs, relax_longitudinal, h), -2.0, 2.0)
	w.tan_alpha = clampf(_relax(w.tan_alpha, v_lat, vx_abs, relax_lateral, h), -2.0, 2.0)

	var sx := w.kappa / peak_slip_ratio
	var sy := w.tan_alpha / tan(deg_to_rad(peak_slip_angle_deg))
	var rho := sqrt(sx * sx + sy * sy)
	w.slip = rho

	var fz0 := car_mass * 9.81 * 0.25
	var mu := tire_mu * clampf(1.0 - load_sensitivity * (w.load / fz0 - 1.0), 0.5, 1.3)
	var f_max := mu * w.grip * w.load

	var fx := 0.0
	var fy := 0.0
	if rho > 1e-6:
		var f := f_max * _magic_formula(rho)
		fx = f * sx / rho
		fy = -f * sy / rho

	# Przy niskiej prędkości relaksacja działa jak sprężyna bez tłumienia -
	# dodajemy tłumienie, które zanika powyżej kilku m/s.
	var low := clampf(1.0 - vx_abs / 4.0, 0.0, 1.0)
	if low > 0.0:
		var c := 2.0 * w.load
		fx += c * slip_vel * low
		fy -= c * v_lat * low
		var total := Vector2(fx, fy)
		if total.length() > f_max:
			total = total.normalized() * f_max
		fx = total.x
		fy = total.y
	return Vector2(fx, fy)


func _relax(state: float, input_vel: float, vx_abs: float, sigma: float, h: float) -> float:
	var a := vx_abs / sigma
	if a < 1e-3:
		return state + input_vel / sigma * h
	var target := input_vel / vx_abs
	return target + (state - target) * exp(-a * h)


## Znormalizowana Magic Formula: maksimum 1 przy ρ = 1.
func _magic_formula(rho: float) -> float:
	var b := tan(PI / (2.0 * mf_shape_c))
	return sin(mf_shape_c * atan(b * rho))


func _brake_torque_for(w: Wheel, i: int, h: float) -> float:
	var pedal := throttle if (gear < 0 and automatic and not dedicated_reverse) else brake
	var t := pedal * (brake_torque_front if w.front else brake_torque_rear)
	# Uszkodzony hamulec (przewody, zacisk): do -80% siły.
	t *= 1.0 - 0.8 * damage["brakes"][i]
	# ESP dokłada hamowanie pojedynczego koła, niezależnie od pedału.
	t += _esp_brake[i]
	if abs_enabled and t > 0.0 and w.contact and absf(speed) > 2.0:
		# ABS moduluje ciśnienie w cyklu, jak prawdziwy zawór: szybko spuszcza,
		# dopóki koło jest w poślizgu za szczytem krzywej, potem powoli dokłada.
		# Stały procent ciśnienia nie wystarcza - na lodzie nawet 15% pedału
		# blokuje koło, bo lód przenosi ~110 Nm, a hamulec daje ~1900.
		# Działa też na hamowanie z ESP - tak jest w prawdziwych układach.
		var dir := signf(speed)
		if w.kappa * dir < -peak_slip_ratio * 1.15:
			_abs_mod[i] = maxf(_abs_mod[i] - 25.0 * h, 0.0)
		else:
			_abs_mod[i] = minf(_abs_mod[i] + 20.0 * h, 1.0)
		t *= _abs_mod[i]
		if _abs_mod[i] < 0.98:
			_abs_hit = true
	else:
		_abs_mod[i] = 1.0
	# Ręczny celowo omija ABS - po to jest, żeby blokować tył.
	if not w.front:
		t += handbrake * handbrake_torque
	return t


## Kontrola trakcji. Prędkość odniesienia z przednich kół, bo nie są
## napędzane - dokładnie tak liczy to prawdziwy TCS z czujników ABS.
func _update_tcs(delta: float) -> void:
	var target := 1.0
	tcs_active = false
	var dir := -1.0 if gear < 0 else 1.0
	if _hub():
		# Każde koło osobno: poślizg względem prędkości auta.
		var v_ref := maxf(absf(speed), 3.0)
		for i in range(4):
			var t_w := 1.0
			if tcs_enabled and _drive_pedal() > 0.05 and wheels[i].contact:
				var slip := (wheels[i].omega * dir * wheel_radius - absf(speed)) / v_ref
				if slip > tcs_target_slip:
					t_w = clampf(1.0 - (slip - tcs_target_slip) * 6.0, 0.05, 1.0)
					tcs_active = true
			_hub_tcs[i] = move_toward(_hub_tcs[i], t_w, tcs_response * delta)
		_tcs_factor = 1.0
		return
	if tcs_enabled and _drive_pedal() > 0.05 and not _is_rwd():
		# 4x4: odniesieniem jest prędkość auta (nie ma kół nienapędzanych).
		if wheels[0].contact or wheels[2].contact or wheels[1].contact or wheels[3].contact:
			var v_max := 0.0
			for w in wheels:
				v_max = maxf(v_max, w.omega * dir * wheel_radius)
			var slip := (v_max - absf(speed)) / maxf(absf(speed), 3.0)
			if slip > tcs_target_slip:
				target = clampf(1.0 - (slip - tcs_target_slip) * 6.0, 0.05, 1.0)
				tcs_active = true
		_tcs_factor = move_toward(_tcs_factor, target, tcs_response * delta)
		return
	if tcs_enabled and _drive_pedal() > 0.05:
		var front_contact := wheels[0].contact or wheels[1].contact
		var rear_contact := wheels[2].contact or wheels[3].contact
		if front_contact and rear_contact:
			var v_ref := (wheels[0].omega + wheels[1].omega) * 0.5 * wheel_radius
			var v_rear := maxf(wheels[2].omega * dir, wheels[3].omega * dir) * wheel_radius
			var slip := (v_rear - absf(v_ref)) / maxf(absf(v_ref), 3.0)
			if slip > tcs_target_slip:
				# Im większy poślizg ponad cel, tym mocniej odcina.
				target = clampf(1.0 - (slip - tcs_target_slip) * 6.0, 0.05, 1.0)
				tcs_active = true
	_tcs_factor = move_toward(_tcs_factor, target, tcs_response * delta)


## ESP. Oczekiwana prędkość obrotu z modelu rowerowego:
##   r_ref = v·tan(δ) / (L·(1 + (v/v_ch)²)),
## ograniczona przez to, na co pozwala przyczepność: |r| ≤ μ·g/v.
## Znak: dodatni = obrót w prawo, zgodnie z kierunkiem skrętu.
func _update_esp(delta: float, grounded: int) -> void:
	for i in range(4):
		_esp_brake[i] = 0.0
	esp_active = false
	var target_factor := 1.0
	if esp_enabled and speed > 5.0 and grounded >= 3:
		var delta_avg := (wheels[0].steer_angle + wheels[1].steer_angle) * 0.5
		var v := speed
		var r_ref := v * tan(delta_avg) / (_wheelbase * (1.0 + (v / esp_char_speed) ** 2))
		# Szacunek tarcia nawierzchni - prawdziwe ESP też go wyznacza; bez
		# tego na lodzie żądałby obrotu, na który przyczepność nie pozwala.
		var grip_sum := 0.0
		var grip_n := 0
		for w in wheels:
			if w.contact:
				grip_sum += w.grip
				grip_n += 1
		var grip_est := grip_sum / maxf(grip_n, 1.0)
		var r_max := 0.85 * tire_mu * grip_est * 9.81 / v
		r_ref = clampf(r_ref, -r_max, r_max)
		var r := -angular_velocity.dot(global_basis.y)    # dodatni = w prawo
		var err := r - r_ref
		# Nadsterowność: auto kręci się mocniej niż chce kierowca (albo
		# w przeciwną stronę). Podsterowność: kręci się słabiej.
		var oversteer := absf(r) > absf(r_ref) or signf(r) != signf(r_ref)
		# Sam błąd obrotu to za mało: na przechylonym łuku auto skręca mocniej,
		# niż wynika z kąta kół, i ESP brałby to za nadsterowność. Prawdziwe
		# układy szacują też, czy oś faktycznie traci przyczepność - tu:
		# kąt znoszenia opon tej osi blisko szczytu krzywej.
		var tan_peak := tan(deg_to_rad(peak_slip_angle_deg))
		var axle_slip := 0.0
		if oversteer:
			axle_slip = maxf(absf(wheels[2].tan_alpha), absf(wheels[3].tan_alpha))
		else:
			axle_slip = maxf(absf(wheels[0].tan_alpha), absf(wheels[1].tan_alpha))
		var sliding := axle_slip > tan_peak * (0.75 if oversteer else 1.0)
		if absf(err) > esp_deadband and sliding:
			esp_active = true
			esp_oversteer = oversteer
			var t := clampf((absf(err) - esp_deadband) * esp_gain, 0.0, esp_max_brake)
			# Potrzebny moment: err > 0 = za dużo w prawo, trzeba w lewo.
			# Hamowanie koła po lewej stronie skręca auto w lewo.
			var brake_left := err > 0.0
			var idx: int
			if oversteer:
				idx = 0 if brake_left else 1     # przednie - zewnętrzne w zakręcie
				target_factor = clampf(1.0 - (absf(err) - esp_deadband) * 2.0, 0.2, 1.0)
			else:
				idx = 2 if brake_left else 3     # tylne - wewnętrzne w zakręcie
			_esp_brake[idx] = t
	_esp_factor = move_toward(_esp_factor, target_factor, tcs_response * delta)


# --------------------------------------------------------------------------
# Kierowanie
# --------------------------------------------------------------------------

func _update_steering(delta: float) -> void:
	# Krzywa geometria po uderzeniu: przednie koła "ciągną" w stronę
	# bardziej uszkodzonego zawieszenia, tylne lekko skręcają tył.
	var pull: float = (damage["suspension"][1] - damage["suspension"][0]) * 0.18 \
			+ (damage["suspension"][3] - damage["suspension"][2]) * 0.08
	_steer_input_smoothed = move_toward(_steer_input_smoothed, clampf(steer + pull, -1.0, 1.0), steer_rate * delta)
	var max_angle := deg_to_rad(max_steer_deg)
	if steer_assist:
		var t := clampf(absf(speed) / steer_assist_speed, 0.0, 1.0)
		max_angle = deg_to_rad(lerpf(max_steer_deg, high_speed_steer_deg, t))
	var delta_ang := _steer_input_smoothed * max_angle
	# Geometria Ackermanna: koło wewnętrzne skręca mocniej.
	if absf(delta_ang) < 1e-4:
		wheels[0].steer_angle = 0.0
		wheels[1].steer_angle = 0.0
		return
	var r := _wheelbase / tan(delta_ang)        # dodatni = zakręt w prawo
	wheels[0].steer_angle = atan(_wheelbase / (r + _track_width * 0.5))
	wheels[1].steer_angle = atan(_wheelbase / (r - _track_width * 0.5))


# --------------------------------------------------------------------------
# Silnik i skrzynia
# --------------------------------------------------------------------------

func _total_ratio(g: int) -> float:
	if g == 0:
		return 0.0
	if g < 0:
		return -reverse_ratio * final_drive
	return gear_ratios[g - 1] * final_drive


## Obroty, jakie miałby silnik, gdyby sprzęgło było zamknięte.
func _wheel_rpm() -> float:
	return _driven_omega() * _total_ratio(gear) * RPM_PER_RAD_S


## Silniki w kołach działają tylko w elektryku (warsztat może zmienić napęd).
func _hub() -> bool:
	return hub_motors and electric


func _is_rwd() -> bool:
	return drive_layout != "awd" and not _hub()


## Prędkość kątowa "wału" z kół napędzanych: tył - średnia tylnych; 4x4 -
## dyferencjał planetarny 40/60 (wał = 0,4·przód + 0,6·tył); silniki
## w kołach - średnia czterech (obrotomierz pokazuje średnie obroty).
func _driven_omega() -> float:
	var rear := (wheels[2].omega + wheels[3].omega) * 0.5
	if _is_rwd():
		return rear
	var front := (wheels[0].omega + wheels[1].omega) * 0.5
	var share := 0.5 if _hub() else AWD_FRONT_SHARE
	return front * share + rear * (1.0 - share)


## Gaz w aktualnym kierunku jazdy. W automacie na wstecznym pedał hamulca
## jest gazem, a pedał gazu hamulcem - tak, jak gracz tego oczekuje.
## W manualu wsteczny to zwykły bieg: gaz to gaz.
func _drive_pedal() -> float:
	return brake if (gear < 0 and automatic and not dedicated_reverse) else throttle


func _clutch_slipping() -> bool:
	return gear != 0 and _shift_timer <= 0.0 and not _clutch_engaged and _drive_pedal() > 0.02


func _engine_torque_at_clutch() -> float:
	if gear == 0 or _shift_timer > 0.0:
		return 0.0
	var pedal := _drive_pedal()
	if engine_rpm >= redline_rpm:
		pedal = 0.0    # ogranicznik obrotów
	var t := pedal * _curve_torque(engine_rpm)
	if _clutch_engaged:
		# Hamowanie silnikiem (w elektryku rekuperacja) zanika przy zerowych
		# obrotach - inaczej elektryk na postoju toczyłby się do tyłu.
		var fade := clampf(engine_rpm / 400.0, 0.0, 1.0)
		t -= (1.0 - pedal) * (engine_brake_a + engine_brake_b * engine_rpm) * fade
	return t


func _curve_torque(rpm: float) -> float:
	var c := torque_curve
	if rpm <= c[0].x:
		return c[0].y
	for i in range(1, c.size()):
		if rpm <= c[i].x:
			var t := (rpm - c[i - 1].x) / (c[i].x - c[i - 1].x)
			return lerpf(c[i - 1].y, c[i].y, t)
	return c[c.size() - 1].y


func _update_gearbox(delta: float) -> void:
	_shift_cooldown = maxf(_shift_cooldown - delta, 0.0)
	if _shift_timer > 0.0:
		_shift_timer -= delta
		if _shift_timer <= 0.0:
			gear = _pending_gear
			_shift_cooldown = 0.6
		_clutch_engaged = false
		return

	var wheel_rpm := _wheel_rpm()
	# Elektryk nie ma sprzęgła: silnik jest zawsze sprzężony z kołami.
	_clutch_engaged = gear != 0 and (electric or wheel_rpm >= clutch_engage_rpm)

	if dedicated_reverse:
		# Wsteczny tylko w miejscu - w ruchu skrzynia by się rozsypała.
		var stopped := absf(speed) < 0.5
		if reverse_request and gear >= 0 and stopped:
			_shift_to(-1)
			return
		if not reverse_request and gear < 0 and stopped:
			_shift_to(1)
			return

	if not automatic:
		return

	# Wsteczny w automacie: przytrzymany hamulec na postoju (klawiatura/pad).
	if dedicated_reverse:
		pass
	elif gear > 0 and absf(speed) < 0.5 and brake > 0.5 and throttle < 0.05:
		_reverse_hold += delta
		if _reverse_hold > 0.35:
			_shift_to(-1)
	elif gear < 0 and absf(speed) < 0.5 and throttle > 0.5 and brake < 0.05:
		_reverse_hold += delta
		if _reverse_hold > 0.15:
			_shift_to(1)
	else:
		_reverse_hold = 0.0

	# Decyzje z obrotów kół, nie silnika: przy ślizgającym się sprzęgle silnik
	# kręci się wyżej niż koła i automat nigdy by nie zredukował.
	# Tylko z kontaktem tylnych kół - w powietrzu koła kręcą się bez oporu
	# i automat wrzuciłby szóstkę przed lądowaniem.
	var rear_grounded := wheels[2].contact or wheels[3].contact
	if gear >= 1 and rear_grounded and _shift_cooldown <= 0.0:
		if wheel_rpm > upshift_rpm and gear < gear_ratios.size() and throttle > 0.1:
			_shift_to(gear + 1)
		elif wheel_rpm < downshift_rpm and gear > 1:
			_shift_to(gear - 1)


func _shift_to(g: int) -> void:
	g = clampi(g, -1, gear_ratios.size())
	if g == gear and _shift_timer <= 0.0:
		return
	# Blokada wstecznego: jak w prawdziwej skrzyni, R nie wejdzie w ruchu
	# do przodu (i odwrotnie). Chroni przed przeklikaniem przez N na R.
	if g < 0 and speed > 2.0:
		return
	if g > 0 and gear < 0 and speed < -2.0:
		return
	_pending_gear = g
	# Uszkodzona skrzynia: biegi wchodzą do 4 razy wolniej.
	_shift_timer = shift_time * (1.0 + 3.0 * damage["gearbox"])
	_reverse_hold = 0.0


func is_shifting() -> bool:
	return _shift_timer > 0.0


## Ręczna zmiana biegów. Kolejność: R - N - 1 - 2 ... 6.
## W trakcie zmiany kolejne wciśnięcie liczy się od biegu docelowego.
func shift_up() -> void:
	_shift_to((_pending_gear if _shift_timer > 0.0 else gear) + 1)


func shift_down() -> void:
	_shift_to((_pending_gear if _shift_timer > 0.0 else gear) - 1)


func _update_engine_rpm(delta: float) -> void:
	if _clutch_engaged:
		engine_rpm = maxf(_wheel_rpm(), idle_rpm)
		return
	# Sprzęgło otwarte lub się ślizga: silnik kręci się sam do celu.
	var pedal := _drive_pedal()
	var target := idle_rpm + pedal * (redline_rpm - idle_rpm)
	if _shift_timer > 0.0 and _pending_gear != 0:
		# W trakcie zmiany biegu obroty schodzą do obrotów nowego biegu.
		var w_avg := _driven_omega()
		target = clampf(absf(w_avg * _total_ratio(_pending_gear) * RPM_PER_RAD_S), idle_rpm, redline_rpm)
	elif _clutch_slipping():
		# Ruszanie: obroty trzymane w okolicy maksimum momentu.
		target = lerpf(idle_rpm, launch_rpm, pedal)
	engine_rpm = move_toward(engine_rpm, target, 9000.0 * delta)


# --------------------------------------------------------------------------
# Wizualizacja
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_visual_step(delta)
	Perf.add("bot_wyg" if is_bot else "auto_wyg", t0)


func _visual_step(delta: float) -> void:
	_update_wipers(delta)
	# Przebudowa wgniecionych siatek - najwyżej raz na klatkę obrazu.
	for k in _dent_groups:
		var g: Dictionary = _dent_groups[k]
		if g.get("dirty", false) and g.has("mi"):
			_recompute_normals(g)
			_dent_rebuild(g)
	for w in wheels:
		w.spin = wrapf(w.spin + w.omega * delta, -PI, PI)
		w.node.position = w.mount - Vector3.UP * w.spring_len
		# Obrót do przodu to obrót wokół -X.
		w.node.basis = Basis(Vector3.UP, -w.steer_angle) * Basis(Vector3.RIGHT, -w.spin)
	if _steering_wheel:
		# Przełożenie kierownicy ~14:1, jak w aucie bez wspomagania z epoki.
		var wheel_angle := (wheels[0].steer_angle + wheels[1].steer_angle) * 0.5 * 14.0
		_steering_wheel.rotation = Vector3(0.0, -wheel_angle, 0.0)
	if _concept_steer:
		var wa := (wheels[0].steer_angle + wheels[1].steer_angle) * 0.5 * 14.0
		_concept_steer.basis = Basis(_concept_steer_axis, wa)
	if _tail_mat:
		# Światła pozycyjne słabo, stop mocno.
		var stop := maxf(brake if not (gear < 0 and automatic) else throttle, handbrake)
		_tail_mat.emission_energy_multiplier = 0.4 + 2.6 * stop
	if dash_label:
		var shown := _pending_gear if _shift_timer > 0.0 else gear
		var g := "R" if shown < 0 else ("N" if shown == 0 else str(shown))
		var mode := "A" if automatic else "M"
		# Kontrolki systemów: świecą, gdy system ingeruje; "off", gdy wyłączony.
		var lights := PackedStringArray()
		for sys in [["ABS", abs_enabled, abs_active], ["TCS", tcs_enabled, tcs_active], ["ESP", esp_enabled, esp_active]]:
			if not sys[1]:
				lights.append(sys[0] + " off")
			elif sys[2]:
				lights.append("[" + sys[0] + "]")
		if not steer_assist:
			lights.append("SKRĘT off")
		# Kontrolki uszkodzeń: tylko układy powyżej 10%.
		var dmg := PackedStringArray()
		if damage["engine"] > 0.1:
			dmg.append("silnik %d%%" % roundi(damage["engine"] * 100.0))
		var b_max: float = damage["brakes"].max()
		if b_max > 0.1:
			dmg.append("hamulce %d%%" % roundi(b_max * 100.0))
		var s_max: float = damage["suspension"].max()
		if s_max > 0.1:
			dmg.append("zawieszenie %d%%" % roundi(s_max * 100.0))
		if damage["gearbox"] > 0.1:
			dmg.append("skrzynia %d%%" % roundi(damage["gearbox"] * 100.0))
		var dmg_line := ""
		if damage["structure"] > 0.02:
			dmg_line = "\nstan auta %d%%  %s" % [roundi((1.0 - damage["structure"]) * 100.0), "  ".join(dmg)]
		# Prędkość i obroty pokazują tarcze, uszkodzenia - obrys auta.
		dash_label.text = "%s%s   %s" % [mode, g, "  ".join(lights)]
	if gauges:
		gauges.update_values(absf(speed) * 3.6, engine_rpm, damage)
		gauges.set_fuel(fuel)


## Ustawia samochód w podanym miejscu i zeruje cały stan dynamiczny.
func place(xf: Transform3D) -> void:
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for w in wheels:
		w.omega = 0.0
		w.kappa = 0.0
		w.tan_alpha = 0.0
		w.compression = 0.0
		w.prev_compression = 0.0
		w.steer_angle = 0.0
	_steer_input_smoothed = 0.0
	gear = 1
	_pending_gear = 1
	_shift_timer = 0.0
	_shift_cooldown = 0.0
	engine_rpm = idle_rpm
	airtime = 0.0
	_max_fall_speed = 0.0
	_tcs_factor = 1.0
	_hub_tcs = [1.0, 1.0, 1.0, 1.0]
	_esp_factor = 1.0
	_settle_t = 0.5
	_dent_queue.clear()
	_impact_queue.clear()
	constant_force = Vector3.ZERO
	constant_torque = Vector3.ZERO
	reset_physics_interpolation()


# --------------------------------------------------------------------------
# Geometria - wszystko z prymitywów, bez zewnętrznych modeli
# --------------------------------------------------------------------------

## Sedan w stylu lat 70.: długa maska i bagażnik, kanciasta kabina,
## chromowane zderzaki i listwy, cztery okrągłe reflektory, winylowy dach,
## kanapa w środku. Ogólny styl epoki, nie konkretny model.
##
## Wymiary względem jezdni (przy statycznym ugięciu jezdnia jest ~0,70 m
## pod punktem odniesienia auta): dach 1,39 m, linia okien 0,82 m,
## oczy kierowcy 1,15 m, prześwit 0,25 m, długość 4,56 m, szerokość 1,78 m.
## Rozstaw osi 2,57 m wynika z mocowań kół - zwisy 0,95 m z przodu i 1,05 m
## z tyłu, typowe dla sedanów z epoki.
##
## Kabina jest pusta w środku (boki to cienkie panele), żeby z fotela
## kierowcy było widać podłogę, kanapy i deskę, a nie wnętrze bryły.
func _build_body() -> void:
	var paint := _mat(Color(0.80, 0.60, 0.18), 0.35)        # "harvest gold"
	paint.metallic = 0.1
	_paint_mat = paint
	var vinyl := _mat(Color(0.05, 0.05, 0.05), 0.75)        # winylowy dach
	var chrome := _mat(Color(0.85, 0.86, 0.88), 0.12)
	chrome.metallic = 1.0
	var dark := _mat(Color(0.06, 0.06, 0.07), 0.9)
	var trim := _mat(Color(0.35, 0.22, 0.13), 0.8)          # brązowy winyl wnętrza
	var carpet := _mat(Color(0.20, 0.13, 0.08), 1.0)
	# Dach osobno od słupków (użytkownik: "auto gracza powinno mieć dach") -
	# z zewnątrz czarny winyl, od środka jasna podsufitka.
	var roof := _mat(Color(0.05, 0.05, 0.05), 0.75)
	var headliner := _mat(Color(0.62, 0.57, 0.48), 1.0)
	_cockpit_mats = [paint, vinyl, chrome, dark, trim, carpet, roof, headliner]
	_vinyl_mat = vinyl
	_roof_mats = [roof, headliner]
	var glass := _mat(Color(0.30, 0.40, 0.45), 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.22
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

	# --- kolizja: dół nadwozia i osobno kabina (ważne przy dachowaniu) ---
	_collision_box("BodyShape", Vector3(1.76, 0.57, 4.50), Vector3(0.0, -0.12, 0.01))
	_collision_box("CabinShape", Vector3(1.40, 0.52, 1.75), Vector3(0.0, 0.42, 0.55))

	# --- karoseria: wszystkie części zewnętrzne trafiają do siatek
	# wgniatalnych (patrz "Wgniecenia" niżej), po jednej na materiał ---
	var plate := _mat(Color(0.92, 0.92, 0.88), 0.6)
	_dent_begin({"paint": paint, "vinyl": vinyl, "roof": roof, "chrome": chrome,
			"dark": dark, "glass": glass, "tail": _make_tail_mat(), "head": _make_head_mat(),
			"plate": plate})
	# przód (komora silnika) z wycięciem na nadkole
	_dbox("paint", Vector3(1.78, 0.14, 1.72), Vector3(0.0, 0.05, -1.41))
	_dbox("paint", Vector3(1.78, 0.43, 0.55), Vector3(0.0, -0.235, -1.995))
	_dbox("paint", Vector3(1.78, 0.43, 0.37), Vector3(0.0, -0.235, -0.735))
	# kabina: cienkie boki, wycięcie na tylne nadkole
	for sx in [-0.86, 0.86]:
		_dbox("paint", Vector3(0.06, 0.14, 2.10), Vector3(sx, 0.05, 0.50))
		_dbox("paint", Vector3(0.06, 0.43, 1.40), Vector3(sx, -0.235, 0.15))
	# tył (bagażnik)
	_dbox("paint", Vector3(1.78, 0.14, 0.74), Vector3(0.0, 0.05, 1.92))
	_build_spoilers(dark)
	_dbox("paint", Vector3(1.78, 0.43, 0.64), Vector3(0.0, -0.235, 1.97))

	# kabina: szyby, słupki, winylowy dach
	_dbox("roof", Vector3(1.40, 0.05, 1.14), Vector3(0.0, 0.665, 0.55))
	_dslab("glass", Vector3(0.0, 0.12, -0.55), Vector3(0.0, 0.64, -0.02), 1.40, 0.015)
	_dslab("glass", Vector3(0.0, 0.64, 1.12), Vector3(0.0, 0.12, 1.55), 1.40, 0.015)
	for sx in [-0.70, 0.70]:
		_dslab("vinyl", Vector3(sx, 0.12, -0.55), Vector3(sx, 0.64, -0.02), 0.06, 0.06)
		# Szeroki słupek C - znak rozpoznawczy sedanów z tamtych lat.
		_dslab("vinyl", Vector3(sx, 0.64, 1.12), Vector3(sx, 0.12, 1.55), 0.14, 0.06)
		_dbox("vinyl", Vector3(0.07, 0.52, 0.09), Vector3(sx * 1.014, 0.38, 0.45))
		_dbox("glass", Vector3(0.012, 0.50, 1.12), Vector3(sx * 1.03, 0.38, 0.55))

	# chrom i światła
	_dbox("chrome", Vector3(1.86, 0.13, 0.14), Vector3(0.0, -0.22, -2.31))
	_dbox("chrome", Vector3(1.86, 0.13, 0.14), Vector3(0.0, -0.22, 2.33))
	_dbox("dark", Vector3(1.24, 0.22, 0.03), Vector3(0.0, -0.07, -2.285))
	for gy in [-0.13, -0.07, -0.01]:
		_dbox("chrome", Vector3(1.24, 0.02, 0.02), Vector3(0.0, gy, -2.30))
	for sx in [-0.895, 0.895]:
		_dbox("chrome", Vector3(0.01, 0.025, 4.40), Vector3(sx, -0.08, 0.01))
	for hx in [-0.74, -0.56, 0.56, 0.74]:
		var c := CylinderMesh.new()
		c.top_radius = 0.07
		c.bottom_radius = 0.07
		c.height = 0.04
		c.radial_segments = 12
		c.rings = 1
		_dent_add("head", c, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(hx, -0.06, -2.285)))
	for sx in [-0.58, 0.58]:
		_dbox("tail", Vector3(0.50, 0.11, 0.03), Vector3(sx, -0.05, 2.30))
		# Obwódki lamp i kły zderzaka - drobny chrom, który łapie światło.
		_dbox("chrome", Vector3(0.53, 0.015, 0.035), Vector3(sx, 0.012, 2.30))
		_dbox("chrome", Vector3(0.53, 0.015, 0.035), Vector3(sx, -0.112, 2.30))
		_dbox("chrome", Vector3(0.07, 0.20, 0.08), Vector3(sx * 0.62, -0.20, -2.36))
		_dbox("chrome", Vector3(0.07, 0.20, 0.08), Vector3(sx * 0.62, -0.20, 2.38))
	# Linie drzwi (szczeliny) - ciemne paski na boku: przednie i tylne drzwi.
	for sx in [-0.892, 0.892]:
		for z in [-0.52, 0.45, 1.36]:
			_dbox("dark", Vector3(0.006, 0.52, 0.012), Vector3(sx, -0.14, z))
		_dbox("dark", Vector3(0.006, 0.012, 1.88), Vector3(sx, -0.40, 0.42))
		# Klamki.
		_dbox("chrome", Vector3(0.02, 0.025, 0.14), Vector3(sx * 1.003, 0.02, -0.38 if sx < 0 else -0.38))
		_dbox("chrome", Vector3(0.02, 0.025, 0.14), Vector3(sx * 1.003, 0.02, 0.62))
	# Lusterka boczne na drzwiach kierowcy i pasażera.
	for sx in [-0.95, 0.95]:
		_dbox("chrome", Vector3(0.10, 0.02, 0.03), Vector3(sx * 0.96, 0.17, -0.46))
		_dbox("chrome", Vector3(0.05, 0.09, 0.14), Vector3(sx, 0.22, -0.46))
	# Tablice rejestracyjne (bez napisów - jasne pola z ramką).
	_dbox("plate", Vector3(0.52, 0.12, 0.012), Vector3(0.0, -0.22, -2.385))
	_dbox("plate", Vector3(0.52, 0.12, 0.012), Vector3(0.0, -0.08, 2.32))
	# Rura wydechowa z lewej z tyłu.
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.035
	pipe.bottom_radius = 0.035
	pipe.height = 0.25
	pipe.radial_segments = 10
	pipe.rings = 1
	_dent_add("chrome", pipe, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.55, -0.40, 2.30)))
	_dent_finish()
	_build_wipers(dark)

	# --- wnętrze (sekcja "Wnętrze sedana" niżej) ---
	_build_interior(trim, carpet, headliner, dark, chrome)

	# --- koła: opona z zaokrąglonymi ściankami, kołpak z żebrami ---
	var tire_mat := _mat(Color(0.06, 0.06, 0.065), 0.92)
	var wheel_mesh := _wheel_mesh(tire_mat, chrome, dark)
	for i in range(4):
		var w := wheels[i]
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % i
		pivot.position = w.mount - Vector3.UP * rest_length
		add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = wheel_mesh
		# Kołpak (strona +X siatki) zawsze na zewnątrz auta.
		if w.left:
			mi.rotation = Vector3(0.0, PI, 0.0)
		pivot.add_child(mi)
		w.node = pivot
	# Nadkola: ciemne wnęki nad kołami, żeby nie świeciło pustym wycięciem.
	for z in [-1.32, 1.25]:
		_box_mesh("WheelWell", Vector3(1.62, 0.06, 0.82), Vector3(0.0, -0.01, z), dark)

	# Oczy kierowcy: 1,15 m nad jezdnią, lewy fotel, za kierownicą.
	seat = Marker3D.new()
	seat.name = "Seat"
	seat.position = Vector3(-0.38, 0.45, 0.30)
	add_child(seat)

	chase_point = Marker3D.new()
	chase_point.name = "ChasePoint"
	chase_point.position = Vector3(0.0, 2.2, 7.5)
	chase_point.rotation = Vector3(deg_to_rad(-12.0), 0.0, 0.0)
	add_child(chase_point)

	if is_bot:
		return
	# Zegary: tarcze za kierownicą, wskaźnik uszkodzeń na środku deski.
	gauges = Gauges.new()
	gauges.name = "Gauges"
	add_child(gauges)
	gauges.build(SEDAN_CLUSTER, 30.0)
	gauges.set_rpm_range(redline_rpm + 800.0, redline_rpm)
	# Pod tarczami: bieg i kontrolki systemów (ABS/TCS/ESP).
	dash_label = Label3D.new()
	dash_label.name = "Dashboard"
	dash_label.text = ""
	dash_label.font_size = 28
	dash_label.pixel_size = 0.0008
	dash_label.position = Vector3(-0.38, 0.172, -0.33)
	dash_label.rotation = Vector3(deg_to_rad(-30.0), 0.0, 0.0)
	dash_label.modulate = Color(1.0, 0.75, 0.2)
	dash_label.shaded = false
	add_child(dash_label)


## Koło jako jedna siatka (oś obrotu = X, kołpak po stronie +X):
## bieżnik, zaokrąglone ścianki boczne (stożki ścięte), kołpak z wypukłym
## środkiem i 10 żebrami - widać obrót koła, a krawędzie łapią światło.
func _wheel_mesh(tire_m: Material, chrome_m: Material, dark_m: Material) -> ArrayMesh:
	var r := wheel_radius
	var mesh := ArrayMesh.new()
	var parts := [
		# [promień góra, promień dół, wysokość (wzdłuż X), środek X, materiał]
		[r, r, 0.16, 0.0, tire_m],                       # bieżnik
		[r - 0.025, r, 0.035, 0.0975, tire_m],           # ścianka zewnętrzna
		[r, r - 0.025, 0.035, -0.0975, tire_m],          # ścianka wewnętrzna
		[0.20, 0.22, 0.02, 0.118, chrome_m],             # obręcz kołpaka
		[0.12, 0.19, 0.03, 0.135, chrome_m],             # wypukłość kołpaka
		[0.05, 0.05, 0.02, 0.155, dark_m],               # środek
	]
	for part in parts:
		var c := CylinderMesh.new()
		c.top_radius = part[0]
		c.bottom_radius = part[1]
		c.height = part[2]
		c.radial_segments = 20
		c.rings = 1
		var arr := c.get_mesh_arrays()
		# Cylinder ma oś Y - obracamy na X (góra walca = +X) i przesuwamy.
		var xf := Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(part[3], 0, 0))
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for k in range(v.size()):
			v[k] = xf * v[k]
			nrm[k] = xf.basis * nrm[k]
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TANGENT] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[4])
	# Żebra kołpaka.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(10):
		var ang := TAU * k / 10.0
		var b := BoxMesh.new()
		b.size = Vector3(0.012, 0.07, 0.018)
		var bxf := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(0.148, 0.0, 0.0)) \
				* Transform3D(Basis(), Vector3(0, 0.12, 0))
		st.append_from(b, 0, bxf)
	st.set_material(dark_m)
	st.commit(mesh)
	return mesh


func _collision_box(n: String, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = n
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	add_child(cs)


func _box_mesh(n: String, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


# --------------------------------------------------------------------------
# Wnętrze sedana
# --------------------------------------------------------------------------
#
# Styl: włoski sedan z przełomu lat 60. i 70. (użytkownik 2026-11-08:
# kierownica "strasznie siermiężna", ma być bardziej "jak w fiacie 125").
# To inspiracja epoką, nie kopia konkretnego auta: duża kierownica
# z cienkim czarnym wieńcem i dwiema nawierconymi szprychami z satynowego
# metalu, chromowany pierścień klaksonu, piasta cofnięta ku kolumnie;
# deska z miękkim czarnym wałkiem u góry i listwą pod drewno z chromem,
# okrągłe zegary w osłonie, trzy małe zegary pomocnicze na środku,
# okrągłe nawiewy, radio z gałkami, przełączniki dźwigienkowe; osobne
# przednie fotele przeszyte w pionowe pasy, boczki drzwi z listwą,
# podłokietnikiem i korbką szyby, dźwignia biegów w tunelu, pedały,
# lusterko i osłony przeciwsłoneczne. Bez logo i znaków firmowych.
#
# Wydajność (Quest): nieruchoma część wnętrza to JEDNA siatka z jedną
# powierzchnią na materiał (8), kierownica i kolumna po jednej siatce
# (3 + 1). Wcześniej 10 osobnych pudeł = 10 wywołań rysowania, teraz ~12
# przy dużo większej liczbie szczegółów. Siatka wnętrza nie rzuca cieni
# (cień daje karoseria). Boty dostają wersję bez drobiazgów.

## Dokłada prymityw do zbioru `parts` (materiał -> SurfaceTool).
func _ip_add(parts: Dictionary, m: Material, mesh: Mesh, xf: Transform3D) -> void:
	if not parts.has(m):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[m] = st
	(parts[m] as SurfaceTool).append_from(mesh, 0, xf)


func _ip_box(parts: Dictionary, m: Material, size: Vector3, pos: Vector3, b := Basis()) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_ip_add(parts, m, bm, Transform3D(b, pos))


## Walec (albo stożek ścięty) wzdłuż osi Y bazy `b`.
func _ip_cyl(parts: Dictionary, m: Material, r_top: float, r_bot: float, h: float,
		pos: Vector3, b := Basis(), segs := 12) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	_ip_add(parts, m, c, Transform3D(b, pos))


## Pierścień wokół osi Y bazy `b`: `r` - promień osi rurki, `t` - promień rurki.
func _ip_ring(parts: Dictionary, m: Material, r: float, t: float, pos: Vector3,
		b := Basis(), segs := 24, sides := 6) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = r - t
	tm.outer_radius = r + t
	tm.rings = segs
	tm.ring_segments = sides
	_ip_add(parts, m, tm, Transform3D(b, pos))


func _ip_ball(parts: Dictionary, m: Material, r: float, pos: Vector3) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 5
	_ip_add(parts, m, s, Transform3D(Basis(), pos))


## Baza, której oś Y biegnie wzdłuż `dir`, a oś X możliwie blisko `side`
## (`side` nie może być równoległy do `dir`).
func _basis_along(dir: Vector3, side: Vector3) -> Basis:
	var y := dir.normalized()
	var z := side.cross(y).normalized()
	return Basis(y.cross(z), y, z)


## Płaskownik od `a` do `b`: szerokość `w` wzdłuż `side`, grubość `t`.
func _ip_bar(parts: Dictionary, m: Material, a: Vector3, b: Vector3, w: float, t: float,
		side := Vector3.RIGHT) -> void:
	_ip_box(parts, m, Vector3(w, a.distance_to(b), t), (a + b) * 0.5, _basis_along(b - a, side))


## Pręt (walec) od `a` do `b`.
func _ip_rod(parts: Dictionary, m: Material, a: Vector3, b: Vector3, r: float,
		side := Vector3.RIGHT, segs := 8) -> void:
	_ip_cyl(parts, m, r, r, a.distance_to(b), (a + b) * 0.5, _basis_along(b - a, side), segs)


## Scala zebrane prymitywy w jedną siatkę (powierzchnia na materiał).
func _ip_commit(parts: Dictionary, n: String, parent: Node3D) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for m in parts:
		var st: SurfaceTool = parts[m]
		st.set_material(m)
		st.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _build_interior(trim: Material, carpet: Material, headliner: Material,
		dark: Material, chrome: Material) -> void:
	var detail := not is_bot
	# Czarny, lekko błyszczący "bakelit" (wieniec, gałki, kolumna), satynowy
	# metal (szprychy, ramki, pedały) i listwa pod orzech.
	var bakelite := _mat(Color(0.025, 0.025, 0.028), 0.35)
	var alu := _mat(Color(0.72, 0.72, 0.70), 0.38)
	alu.metallic = 0.85
	var wood := _mat(Color(0.33, 0.17, 0.08), 0.45)
	_cockpit_mats.append(bakelite)
	_cockpit_mats.append(alu)
	_cockpit_mats.append(wood)
	var along_x := Basis(Vector3.BACK, PI * 0.5)     # oś Y prymitywu -> X auta
	var along_z := Basis(Vector3.RIGHT, PI * 0.5)    # oś Y prymitywu -> +Z (do kierowcy)
	var p := {}

	# Podłoga, tunel skrzyni, ściana grodziowa, podsufitka.
	_ip_box(p, carpet, Vector3(1.66, 0.04, 2.10), Vector3(0.0, -0.43, 0.50))
	_ip_box(p, carpet, Vector3(0.26, 0.10, 1.05), Vector3(0.0, -0.36, -0.02))
	_ip_box(p, carpet, Vector3(1.66, 0.42, 0.04), Vector3(0.0, -0.22, -0.55))
	_ip_box(p, headliner, Vector3(1.36, 0.02, 1.10), Vector3(0.0, 0.632, 0.55))

	# Deska: ciemny korpus (przód na z = -0,25), miękki czarny wałek nad
	# listwą pod drewno, pod listwą cienki chrom.
	_ip_box(p, dark, Vector3(1.62, 0.20, 0.34), Vector3(0.0, 0.05, -0.42))
	_ip_box(p, dark, Vector3(1.64, 0.03, 0.36), Vector3(0.0, 0.163, -0.43))
	_ip_cyl(p, dark, 0.032, 0.032, 1.64, Vector3(0.0, 0.148, -0.25), along_x, 10)
	_ip_box(p, wood, Vector3(1.56, 0.08, 0.012), Vector3(0.0, 0.07, -0.244))
	_ip_box(p, chrome, Vector3(1.56, 0.006, 0.014), Vector3(0.0, 0.027, -0.243))
	# Okrągłe nawiewy na końcach listwy: chromowana ramka, poziome kierownice.
	for vx in [-0.72, 0.72]:
		var vc := Vector3(vx, 0.07, -0.238)
		_ip_cyl(p, bakelite, 0.034, 0.034, 0.008, vc, along_z, 16)
		_ip_ring(p, chrome, 0.037, 0.004, vc + Vector3(0.0, 0.0, 0.003), along_z, 16, 4)
		if detail:
			for vy in [-0.015, 0.0, 0.015]:
				_ip_box(p, alu, Vector3(0.056, 0.004, 0.006), vc + Vector3(0.0, vy, 0.005))
	# Osłona zestawu zegarów (Gauges): daszek, boki i tył w układzie tarcz.
	if detail:
		var cl := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), SEDAN_CLUSTER)
		_ip_box(p, dark, Vector3(0.41, 0.016, 0.10), cl * Vector3(0.0, 0.098, 0.005), cl.basis)
		for s in [-1.0, 1.0]:
			_ip_box(p, dark, Vector3(0.02, 0.21, 0.09), cl * Vector3(s * 0.195, 0.0, -0.01), cl.basis)
		_ip_box(p, dark, Vector3(0.41, 0.21, 0.04), cl * Vector3(0.0, -0.01, -0.075), cl.basis)
		_ip_box(p, dark, Vector3(0.41, 0.04, 0.10), cl * Vector3(0.0, -0.11, -0.03), cl.basis)
		_build_dash_details(p, bakelite, alu, chrome, dark, headliner, along_z)

	# Przednie fotele osobno, środek przeszyty w pionowe pasy, wyższe boki.
	for sx in [-0.38, 0.38]:
		_ip_seat(p, trim, carpet, 0.52, Vector3(sx, -0.33, 0.42), 0.52,
				Vector3(sx, -0.02, 0.72), 14.0, 0.62, detail)
	_ip_seat(p, trim, carpet, 1.45, Vector3(0.0, -0.30, 1.30), 0.45,
			Vector3(0.0, 0.0, 1.55), 20.0, 0.60, detail)

	# Boczki drzwi (wewnętrzna ściana kabiny na x = ±0,83) i parapety okien
	# (szyby boczne stoją cofnięte na x = ±0,72 - parapet zakrywa szczelinę).
	for sx in [-1.0, 1.0]:
		var xi: float = sx * 0.822
		_ip_box(p, dark, Vector3(0.11, 0.02, 2.06), Vector3(sx * 0.775, 0.12, 0.50))
		_ip_box(p, trim, Vector3(0.012, 0.46, 0.94), Vector3(xi, -0.15, -0.03))   # przednie
		_ip_box(p, trim, Vector3(0.012, 0.46, 0.40), Vector3(xi, -0.15, 0.66))    # tylne, przed nadkolem
		_ip_box(p, trim, Vector3(0.012, 0.14, 0.48), Vector3(xi, 0.01, 1.10))     # tylne, nad nadkolem
		_ip_box(p, carpet, Vector3(0.014, 0.10, 1.34), Vector3(sx * 0.82, -0.33, 0.17))
		_ip_box(p, chrome, Vector3(0.006, 0.006, 1.84), Vector3(sx * 0.815, 0.0, 0.42))
		_ip_box(p, trim, Vector3(0.06, 0.05, 0.32), Vector3(sx * 0.79, -0.07, 0.06))  # podłokietnik
		_ip_box(p, chrome, Vector3(0.012, 0.022, 0.10), Vector3(sx * 0.812, 0.03, -0.28))  # klamka
		if detail:
			# Korbka szyby.
			var kc := Vector3(sx * 0.812, -0.16, -0.12)
			var ke := kc + Vector3(-sx * 0.008, -0.05, 0.03)
			_ip_cyl(p, alu, 0.016, 0.016, 0.012, kc, along_x, 10)
			_ip_bar(p, alu, kc + Vector3(-sx * 0.008, 0.0, 0.0), ke, 0.010, 0.005, Vector3.FORWARD)
			_ip_rod(p, bakelite, ke, ke + Vector3(-sx * 0.03, 0.0, 0.0), 0.007, Vector3.UP)

	# Dźwignia biegów w tunelu: chromowany pręt, czarna gałka, mieszek.
	var gb := Vector3(0.0, -0.30, -0.12)
	var gt := Vector3(0.0, 0.0, -0.05)
	_ip_ring(p, chrome, 0.05, 0.004, gb, Basis(), 16, 4)
	_ip_cyl(p, bakelite, 0.018, 0.048, 0.07, gb + Vector3(0.0, 0.035, 0.0), Basis(), 10)
	_ip_rod(p, chrome, gb, gt, 0.007)
	_ip_ball(p, bakelite, 0.026, gt)

	if detail:
		# Pedały: sprzęgło, hamulec, gaz.
		for px in [-0.50, -0.39, -0.27]:
			var pad := Vector3(px, -0.30, -0.42)
			_ip_bar(p, dark, Vector3(px, -0.02, -0.50), pad, 0.015, 0.012)
			var gas: bool = px > -0.3
			_ip_box(p, alu, Vector3(0.05 if gas else 0.07, 0.09 if gas else 0.06, 0.012),
					pad + Vector3(0.0, -0.02, 0.006), Basis(Vector3.RIGHT, deg_to_rad(-25.0)))
		# Lusterko wsteczne (chrom zamiast odbicia) i osłony przeciwsłoneczne.
		_ip_bar(p, dark, Vector3(0.0, 0.625, 0.01), Vector3(0.0, 0.59, -0.035), 0.012, 0.012)
		var mb := Basis(Vector3.UP, -0.2) * Basis(Vector3.RIGHT, -0.1)
		var mc := Vector3(0.0, 0.575, -0.045)
		_ip_box(p, dark, Vector3(0.22, 0.06, 0.022), mc, mb)
		_ip_box(p, chrome, Vector3(0.205, 0.048, 0.003), mc + mb * Vector3(0.0, 0.0, 0.0115), mb)
		for sx in [-0.40, 0.40]:
			_ip_box(p, headliner, Vector3(0.36, 0.012, 0.15), Vector3(sx, 0.615, 0.07),
					Basis(Vector3.RIGHT, deg_to_rad(8.0)))

	var interior := _ip_commit(p, "Interior", self)
	interior.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_steering_wheel(bakelite, alu, chrome, detail)


## Drobiazgi na desce: małe zegary, schowek, przełączniki, stacyjka, radio.
func _build_dash_details(p: Dictionary, bakelite: Material, alu: Material, chrome: Material,
		dark: Material, ivory: Material, along_z: Basis) -> void:
	# Trzy małe zegary pomocnicze na listwie (np. temperatura, olej, zegarek):
	# czarna tarcza, chromowana ramka, kreski i wskazówka. Tylko ozdoba.
	for gx in [-0.11, -0.04, 0.03]:
		var c := Vector3(gx, 0.07, -0.238)
		_ip_cyl(p, bakelite, 0.026, 0.026, 0.006, c, along_z, 16)
		_ip_ring(p, chrome, 0.0285, 0.0028, c + Vector3(0.0, 0.0, 0.002), along_z, 16, 4)
		for k in range(5):
			var tb := Basis(Vector3.BACK, deg_to_rad(120.0 - 60.0 * k))
			_ip_box(p, ivory, Vector3(0.0015, 0.005, 0.001), c + tb * Vector3(0.0, 0.019, 0.0035), tb)
		var nb := Basis(Vector3.BACK, 0.7 - gx * 9.0)
		_ip_box(p, ivory, Vector3(0.002, 0.018, 0.0015), c + nb * Vector3(0.0, 0.007, 0.0045), nb)
	# Schowek: obrys szczeliny na listwie i chromowany przycisk.
	for gy in [0.04, 0.10]:
		_ip_box(p, dark, Vector3(0.32, 0.003, 0.002), Vector3(0.46, gy, -0.2375))
	for gx in [0.30, 0.62]:
		_ip_box(p, dark, Vector3(0.003, 0.06, 0.002), Vector3(gx, 0.07, -0.2375))
	_ip_cyl(p, chrome, 0.008, 0.008, 0.008, Vector3(0.46, 0.085, -0.236), along_z, 10)
	# Przełączniki dźwigienkowe.
	for k in range(4):
		var tx := 0.12 + 0.035 * k
		_ip_bar(p, alu, Vector3(tx, 0.065, -0.238), Vector3(tx, 0.072, -0.215), 0.006, 0.005)
	# Stacyjka z prawej strony kolumny.
	_ip_ring(p, chrome, 0.012, 0.003, Vector3(-0.15, 0.0, -0.248), along_z, 12, 4)
	_ip_cyl(p, bakelite, 0.010, 0.010, 0.004, Vector3(-0.15, 0.0, -0.249), along_z, 10)
	# Radio na środku pod listwą: panel, okienko skali, gałki, przyciski.
	_ip_box(p, alu, Vector3(0.19, 0.045, 0.006), Vector3(0.10, -0.005, -0.247))
	_ip_box(p, bakelite, Vector3(0.09, 0.018, 0.004), Vector3(0.10, 0.002, -0.2435))
	_ip_box(p, ivory, Vector3(0.002, 0.014, 0.002), Vector3(0.09, 0.002, -0.241))
	for kx in [0.025, 0.175]:
		_ip_cyl(p, chrome, 0.009, 0.009, 0.016, Vector3(kx, -0.005, -0.241), along_z, 10)
	for k in range(5):
		_ip_box(p, bakelite, Vector3(0.012, 0.009, 0.008), Vector3(0.068 + 0.016 * k, -0.019, -0.243))


## Fotel albo kanapa: siedzisko i oparcie (pochylone o `tilt_deg`), środek
## z ciemniejszą wstawką przeszytą w pionowe pasy, wyższe boki.
func _ip_seat(p: Dictionary, trim: Material, insert: Material, w: float, cush: Vector3,
		depth: float, back: Vector3, tilt_deg: float, back_h: float, detail: bool) -> void:
	var pw := w - 0.18
	var n := maxi(int(round(pw / 0.07)), 2)
	_ip_box(p, trim, Vector3(w, 0.12, depth), cush)
	_ip_box(p, insert, Vector3(pw, 0.012, depth - 0.08), cush + Vector3(0.0, 0.064, 0.0))
	var bb := Basis(Vector3.RIGHT, deg_to_rad(tilt_deg))
	_ip_box(p, trim, Vector3(w, back_h, 0.12), back, bb)
	_ip_box(p, insert, Vector3(pw, back_h - 0.14, 0.012), back + bb * Vector3(0.0, 0.02, -0.064), bb)
	for s in [-1.0, 1.0]:
		var bx: float = s * (w * 0.5 - 0.035)
		_ip_box(p, trim, Vector3(0.07, 0.04, depth - 0.02), cush + Vector3(bx, 0.075, 0.0))
		_ip_box(p, trim, Vector3(0.07, back_h - 0.04, 0.04), back + bb * Vector3(bx, 0.0, -0.075), bb)
	if not detail:
		return
	for i in range(1, n):
		var x := -pw * 0.5 + pw * i / n
		_ip_box(p, trim, Vector3(0.012, 0.012, depth - 0.08), cush + Vector3(x, 0.07, 0.0))
		_ip_box(p, trim, Vector3(0.012, back_h - 0.14, 0.012), back + bb * Vector3(x, 0.02, -0.07), bb)


## Kierownica i kolumna. Kolumna nachylona 25° od poziomu, oś kierownicy
## (lokalne +Y) wskazuje na kierowcę; w płaszczyźnie koła -Z to "godzina
## 12", +X prawa strona kierowcy. Koło obraca się ze skrętem (14:1,
## w `_process`), kolumna stoi.
## Dwie szprychy lekko poniżej poziomu i brak górnej - przez górną połowę
## koła widać zegary (stara kierownica w krzyż zasłaniała je szprychą).
func _build_steering_wheel(bakelite: Material, alu: Material, chrome: Material, detail: bool) -> void:
	var column := Node3D.new()
	column.name = "SteeringColumn"
	column.position = Vector3(-0.38, 0.17, -0.12)
	column.rotation = Vector3(deg_to_rad(65.0), 0.0, 0.0)
	add_child(column)
	var cp := {}
	# Osłona kolumny (wchodzi w deskę) i manetka kierunkowskazów z lewej.
	_ip_cyl(cp, bakelite, 0.034, 0.030, 0.26, Vector3(0.0, -0.19, 0.0), Basis(), 12)
	if detail:
		var s0 := Vector3(-0.03, -0.085, 0.0)
		var s1 := Vector3(-0.17, -0.07, -0.02)
		_ip_rod(cp, bakelite, s0, s1, 0.005, Vector3.FORWARD, 6)
		_ip_ball(cp, bakelite, 0.010, s1)
	_ip_commit(cp, "ColumnMesh", column)

	_steering_wheel = Node3D.new()
	_steering_wheel.name = "SteeringWheel"
	column.add_child(_steering_wheel)
	var wp := {}
	# Wieniec Ø 39 cm, cienki (Ø 20 mm), czarny i lekko błyszczący.
	_ip_ring(wp, bakelite, 0.188, 0.010, Vector3.ZERO, Basis(), 40, 8)
	# Piasta cofnięta 4,5 cm ku kolumnie ("głęboka" kierownica), miękka
	# nakładka klaksonu, gładki chromowany środek bez znaku.
	_ip_cyl(wp, bakelite, 0.045, 0.045, 0.03, Vector3(0.0, -0.045, 0.0), Basis(), 16)
	_ip_cyl(wp, bakelite, 0.036, 0.043, 0.016, Vector3(0.0, -0.022, 0.0), Basis(), 16)
	_ip_cyl(wp, chrome, 0.017, 0.017, 0.004, Vector3(0.0, -0.013, 0.0), Basis(), 16)
	# Chromowany pierścień klaksonu oparty na szprychach.
	_ip_ring(wp, chrome, 0.102, 0.0028, Vector3(0.0, -0.025, 0.0), Basis(), 32, 4)
	var dip := deg_to_rad(15.0)
	for s in [-1.0, 1.0]:
		# Szprycha z satynowego metalu: szeroka przy piaście, węższa przy
		# wieńcu, opada od wieńca do cofniętej piasty.
		var d := Vector3(s * cos(dip), 0.0, sin(dip))
		var side := Vector3.UP.cross(d)
		var a := d * 0.042 + Vector3(0.0, -0.045, 0.0)
		var m := d * 0.11 + Vector3(0.0, -0.024, 0.0)
		var b := d * 0.183
		_ip_bar(wp, alu, a, m, 0.046, 0.005, side)
		_ip_bar(wp, alu, m, b, 0.026, 0.005, side)
		if detail:
			# Trzy nawiercone otwory (czarne krążki przez grubość szprychy).
			for h in [[a, m, 0.3], [a, m, 0.6], [m, b, 0.4]]:
				var h0: Vector3 = h[0]
				var h1: Vector3 = h[1]
				var nb := _basis_along(h1 - h0, side)
				_ip_cyl(wp, bakelite, 0.0065, 0.0065, 0.006, h0.lerp(h1, h[2]),
						Basis(nb.x, nb.z, -nb.y), 10)
	_ip_commit(wp, "WheelMesh", _steering_wheel)


func _make_tail_mat() -> StandardMaterial3D:
	_tail_mat = _mat(Color(0.6, 0.05, 0.04), 0.3)
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color(1.0, 0.08, 0.05)
	return _tail_mat


func _make_head_mat() -> StandardMaterial3D:
	var head := _mat(Color(1.0, 0.95, 0.8), 0.2)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.92, 0.75)
	head.emission_energy_multiplier = 0.6
	return head


# --------------------------------------------------------------------------
# Wgniecenia
# --------------------------------------------------------------------------
#
# Karoseria jest zbudowana z podzielonych prymitywów (oczko ~DENT_CELL),
# scalonych w układzie auta w jedną siatkę na materiał. Przy uderzeniu
# wierzchołki w promieniu od punktu kontaktu przesuwają się wzdłuż impulsu
# z gładkim zanikiem (kosinus), a łączne przesunięcie wierzchołka jest
# ograniczone do DENT_MAX, żeby blacha nie przebiła się na drugą stronę.
#
# Odkształca się tylko obraz. Kolizja zostaje sztywna - zmieniający się
# kształt fizyczny w trakcie jazdy psuje stabilność symulacji.
#
# Koszt: wgniecenie liczone tylko w chwili uderzenia, siatka przebudowywana
# najwyżej raz na klatkę obrazu i tylko, gdy coś się zmieniło.

const DENT_CELL := 0.15          # docelowy rozmiar oczka siatki [m]
const DENT_MAX := 0.22           # największe przesunięcie wierzchołka [m]
## Impuls kontaktu w jednym kroku fizyki, poniżej którego nic się nie dzieje.
## Spokojne stanie na podwoziu to ~m·g·dt ≈ 47 N·s, otarcie ~200-400.
@export var dent_threshold: float = 700.0
## Głębokość wgniecenia na N·s impulsu ponad próg.
@export var dent_per_impulse: float = 4.5e-5

var _dent_groups := {}           # nazwa -> {mat, verts, orig, normals, uvs, indices, mi, dirty}
var _dent_queue: Array = []      # [punkt lokalny, kierunek lokalny, głębokość] z kroku fizyki
var _impact_queue: Array = []    # [punkt lokalny, powaga 0..] - do uszkodzeń
var dent_count := 0              # liczba wgnieceń od ostatniej naprawy

# --------------------------------------------------------------------------
# Uszkodzenia (0..1). Zależne od miejsca uderzenia:
#   przód      -> silnik i chłodnica (mniej mocy)
#   tył        -> osprzęt silnika (trochę mniej mocy)
#   przy kole  -> hamulec i zawieszenie tego koła (słabsze hamowanie,
#                 krzywa geometria ściąga auto w bok)
#   lądowanie  -> zawieszenie (wszystkie koła) i skrzynia (wolniejsze biegi)
# "structure" to ogólny stan auta - przy 1.0 auto jest rozbite.
# --------------------------------------------------------------------------
var damage := {
	"structure": 0.0, "engine": 0.0, "gearbox": 0.0,
	"brakes": [0.0, 0.0, 0.0, 0.0], "suspension": [0.0, 0.0, 0.0, 0.0],
}
## Impuls kontaktu [N·s ponad próg wgnieceń] na pełne 100% powagi uderzenia.
@export var damage_impulse_scale: float = 9000.0
## Prędkość lądowania [m/s], powyżej której lądowanie uszkadza.
@export var damage_landing_speed: float = 7.5
var is_wrecked := false
var _settle_t := 0.0

# --------------------------------------------------------------------------
# Paliwo (bateria w elektryku). Zużycie z mocy, którą silnik faktycznie
# oddaje, plus wolne obroty (spalinowe). Pojemność dobrana tak, żeby przy
# spokojnej jeździe ~100 km/h (średnio ~30 kW) wystarczyło na ~12 km
# (użytkownik 2026-11-08: zasięg ~10-15 km zamiast 150 km - stacje co
# 5 odcinków, ~4-5 km, mają znaczenie, a walka z botami kosztuje paliwo).
# --------------------------------------------------------------------------
## Energia pełnego baku [kWh "na kołach"].
@export var tank_kwh: float = 3.6
## Moc na wolnych obrotach [kW] (tylko spalinowe).
@export var idle_kw: float = 1.5
var fuel := 1.0                    # 0..1


func _burn_fuel(power_w: float, delta: float) -> void:
	if is_bot:
		return
	var kw := power_w / 1000.0 + (0.0 if electric else idle_kw)
	fuel = maxf(fuel - kw * delta / 3600.0 / tank_kwh, 0.0)


## Zasięg na pozostałym paliwie przy spokojnej jeździe [km].
## ~0,3 kWh/km przy spokojnej jeździe (~30 kW przy ~100 km/h).
func range_km() -> float:
	return fuel * tank_kwh / 0.3


func refuel(amount: float) -> void:
	fuel = minf(fuel + amount, 1.0)


func _dent_begin(materials: Dictionary) -> void:
	_dent_groups.clear()
	for k in materials:
		_dent_groups[k] = {
			"mat": materials[k],
			"verts": PackedVector3Array(), "normals": PackedVector3Array(),
			"uvs": PackedVector2Array(), "indices": PackedInt32Array(),
		}


## Prostopadłościan z siatką podzieloną na oczka ~DENT_CELL.
func _dbox(group: String, size: Vector3, pos: Vector3, rot := Basis()) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_width = maxi(0, int(ceil(size.x / DENT_CELL)) - 1)
	bm.subdivide_height = maxi(0, int(ceil(size.y / DENT_CELL)) - 1)
	bm.subdivide_depth = maxi(0, int(ceil(size.z / DENT_CELL)) - 1)
	_dent_add(group, bm, Transform3D(rot, pos))


## Płyta między dwoma punktami w płaszczyźnie YZ (szyby, słupki).
func _dslab(group: String, from: Vector3, to: Vector3, width: float, thickness: float) -> void:
	var d := to - from
	# Obrót wokół X przenosi oś Y (0,1,0) na (0, cos θ, sin θ).
	var rot := Basis(Vector3.RIGHT, atan2(d.z, d.y))
	_dbox(group, Vector3(width, d.length(), thickness), (from + to) * 0.5, rot)


## Dokłada prymityw do siatki grupy, przeliczony do układu auta.
func _dent_add(group: String, prim: PrimitiveMesh, xf: Transform3D) -> void:
	var g: Dictionary = _dent_groups[group]
	var arr := prim.get_mesh_arrays()
	var base: int = g["verts"].size()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	for i in range(v.size()):
		g["verts"].append(xf * v[i])
		g["normals"].append((xf.basis * n[i]).normalized())
		g["uvs"].append(uv[i] if i < uv.size() else Vector2.ZERO)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		g["indices"].append(base + i)


func _dent_finish() -> void:
	for k in _dent_groups:
		var g: Dictionary = _dent_groups[k]
		if g["verts"].is_empty():
			continue
		g["orig"] = g["verts"].duplicate()
		g["orig_normals"] = g["normals"].duplicate()
		var mi := MeshInstance3D.new()
		mi.name = "Body_" + k
		mi.mesh = ArrayMesh.new()
		add_child(mi)
		g["mi"] = mi
		g["dirty"] = true
		_dent_rebuild(g)


func _dent_rebuild(g: Dictionary) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g["verts"]
	arrays[Mesh.ARRAY_NORMAL] = g["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = g["uvs"]
	arrays[Mesh.ARRAY_INDEX] = g["indices"]
	var mesh: ArrayMesh = g["mi"].mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, g["mat"])
	g["dirty"] = false


## Wgniata karoserię. Punkt i kierunek (w głąb auta) w układzie auta.
func dent(local_point: Vector3, local_dir: Vector3, depth: float) -> void:
	depth = minf(depth, DENT_MAX)
	if depth < 0.003:
		return
	var radius := 0.30 + depth * 2.5
	var dir := local_dir.normalized()
	for k in _dent_groups:
		var g: Dictionary = _dent_groups[k]
		if not g.has("orig"):
			continue
		var verts: PackedVector3Array = g["verts"]
		var orig: PackedVector3Array = g["orig"]
		var changed := false
		for i in range(verts.size()):
			var dist := verts[i].distance_to(local_point)
			if dist >= radius:
				continue
			var w := 0.5 * (1.0 + cos(PI * dist / radius))
			var moved := verts[i] + dir * depth * w
			# Limit łącznego przesunięcia względem kształtu fabrycznego.
			var off := moved - orig[i]
			if off.length() > DENT_MAX:
				moved = orig[i] + off.normalized() * DENT_MAX
			verts[i] = moved
			changed = true
		if changed:
			g["verts"] = verts
			g["dirty"] = true
	dent_count += 1


## Uszkodzenia z uderzenia w punkcie `p` (układ auta) o powadze `sev`.
func _damage_impact(p: Vector3, sev: float) -> void:
	sev = clampf(sev, 0.0, 1.5)
	if sev <= 0.0:
		return
	damage["structure"] += sev * 0.17
	if p.z < -1.5:
		damage["engine"] += sev * 0.30           # przód: silnik, chłodnica
	elif p.z > 1.7:
		damage["engine"] += sev * 0.08           # tył: osprzęt
	for i in range(4):
		var m: Vector3 = wheels[i].mount
		if Vector2(p.x - m.x, p.z - m.z).length() < 0.75:
			damage["brakes"][i] += sev * 0.35
			damage["suspension"][i] += sev * 0.35
	_clamp_damage()


## Twarde lądowanie: zawieszenie i skrzynia.
func _damage_landing(impact_speed: float) -> void:
	var sev := (impact_speed - damage_landing_speed) / 6.0
	if sev <= 0.0:
		return
	sev = minf(sev, 1.5)
	damage["structure"] += sev * 0.05
	damage["gearbox"] += sev * 0.15
	for i in range(4):
		damage["suspension"][i] += sev * 0.12
	_clamp_damage()


func _clamp_damage() -> void:
	for k in ["structure", "engine", "gearbox"]:
		damage[k] = clampf(damage[k], 0.0, 1.0)
	for k in ["brakes", "suspension"]:
		for i in range(4):
			damage[k][i] = clampf(damage[k][i], 0.0, 1.0)
	if damage["structure"] >= 1.0 and not is_wrecked:
		is_wrecked = true
		wrecked.emit()


## Ogólne uszkodzenie 0..1 (do HUD i końca jazdy).
func damage_total() -> float:
	return damage["structure"]


## Przywraca fabryczny kształt karoserii i naprawia wszystkie układy.
func repair() -> void:
	damage = {
		"structure": 0.0, "engine": 0.0, "gearbox": 0.0,
		"brakes": [0.0, 0.0, 0.0, 0.0], "suspension": [0.0, 0.0, 0.0, 0.0],
	}
	is_wrecked = false
	for k in _dent_groups:
		var g: Dictionary = _dent_groups[k]
		if g.has("orig"):
			g["verts"] = g["orig"].duplicate()
			g["normals"] = g["orig_normals"].duplicate()
			g["dirty"] = true
	dent_count = 0


## Normalne po wgnieceniu - z trójkątów, uśrednione na wierzchołek.
## Kierunek dopasowany do fabrycznych normalnych (kolejność wierzchołków
## w trójkątach Godota jest zgodna z ruchem wskazówek zegara).
func _recompute_normals(g: Dictionary) -> void:
	var verts: PackedVector3Array = g["verts"]
	var idx: PackedInt32Array = g["indices"]
	var acc := PackedVector3Array()
	acc.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var fn := (c - a).cross(b - a)
		acc[idx[t]] += fn
		acc[idx[t + 1]] += fn
		acc[idx[t + 2]] += fn
	var orig_n: PackedVector3Array = g["orig_normals"]
	for i in range(acc.size()):
		var nn := acc[i].normalized()
		if nn.dot(orig_n[i]) < -0.2:
			nn = -nn
		acc[i] = nn if nn != Vector3.ZERO else orig_n[i]
	g["normals"] = acc


## Odczyt kontaktów nadwozia z silnika fizyki. Impuls działa na auto, więc
## jego kierunek wskazuje w głąb karoserii - w tę stronę idzie wgniecenie.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var inv := state.transform.affine_inverse()
	for i in range(state.get_contact_count()):
		var imp := state.get_contact_impulse(i)
		var j := imp.length()
		if j < dent_threshold:
			continue
		var p := state.get_contact_local_position(i)
		_dent_queue.append([inv * p, inv.basis * (imp / j), (j - dent_threshold) * dent_per_impulse])
		_impact_queue.append([inv * p, (j - dent_threshold) / damage_impulse_scale])


## Płyta rozpięta między dwoma punktami w płaszczyźnie YZ (szyby, słupki).
## Lokalna oś Y płyty biegnie od `from` do `to`.
func _slab(n: String, from: Vector3, to: Vector3, width: float, thickness: float, m: Material) -> void:
	var d := to - from
	var mi := _box_mesh(n, Vector3(width, d.length(), thickness), (from + to) * 0.5, m)
	# Obrót wokół X przenosi oś Y (0,1,0) na (0, cos θ, sin θ).
	mi.rotation = Vector3(atan2(d.z, d.y), 0.0, 0.0)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## Wycieraczki i krople na przedniej szybie. Układ szyby: x w prawo, y w górę
## wzdłuż szyby, z = normalna do kabiny. Szyba biegnie od (0, 0,12, -0,55)
## do (0, 0,64, -0,02); krople i ramiona leżą tuż na zewnątrz.
func _build_wipers(dark: Material) -> void:
	var a := Vector3(0.0, 0.12, -0.55)
	var b := Vector3(0.0, 0.64, -0.02)
	var yv := (b - a).normalized()
	var zv := Vector3.RIGHT.cross(yv)
	var frame := Node3D.new()
	frame.name = "Windshield"
	frame.transform = Transform3D(Basis(Vector3.RIGHT, yv, zv), (a + b) * 0.5 - zv * 0.014)
	add_child(frame)
	var q := QuadMesh.new()
	q.size = Vector2(1.36, (b - a).length())
	_drops_mat = ShaderMaterial.new()
	_drops_mat.shader = load("res://shaders/raindrops.gdshader")
	_drops_mat.set_shader_parameter("sweep", WIPE_SWEEP)
	_drops_mat.set_shader_parameter("c_dur", WIPE_DUR)
	_drops_mat.set_shader_parameter("arm_len", 0.66)
	var qi := MeshInstance3D.new()
	qi.mesh = q
	qi.material_override = _drops_mat
	qi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	qi.visible = false
	qi.name = "Drops"
	frame.add_child(qi)
	for px in [-0.62, 0.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(px, -0.33, -0.006)
		frame.add_child(pivot)
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.66, 0.012, 0.012)
		arm.mesh = bm
		arm.material_override = dark
		arm.position = Vector3(0.33, 0.0, 0.0)
		pivot.add_child(arm)
		# Pióro: grubsza listwa na końcowych 2/3 ramienia.
		var blade := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.46, 0.02, 0.02)
		blade.mesh = bb
		blade.material_override = dark
		blade.position = Vector3(0.41, 0.0, -0.005)
		pivot.add_child(blade)
		_wipers.append(pivot)


func _update_wipers(delta: float) -> void:
	if _wipers.is_empty():
		return
	_wipe_t += delta
	var phase := (_wipe_t - _wipe_start) / WIPE_DUR
	if phase >= 1.0:
		_wipe_active = false
		phase = 0.0
	if not _wipe_active and rain > 0.05:
		# Mżawka: po każdym cyklu przerwa; deszcz: bez przerwy.
		var pause := WIPE_PAUSE if rain < 1.5 else 0.0
		if _wipe_t - (_wipe_start + WIPE_DUR) >= pause:
			_wipe_prev = _wipe_start
			_wipe_start = _wipe_t
			_wipe_active = true
			phase = 0.0
	var ang := WIPE_SWEEP * sin(PI * phase) if _wipe_active else 0.0
	for w in _wipers:
		w.rotation = Vector3(0.0, 0.0, ang)
	var drops := get_node_or_null("Windshield/Drops") as Node3D
	_drops_mat.set_shader_parameter("now", _wipe_t)
	_drops_mat.set_shader_parameter("c_start", _wipe_start)
	_drops_mat.set_shader_parameter("c_prev", _wipe_prev)
	# Tempo przybywania kropli: mżawka ~0,12/s na miejsce, deszcz ~0,6/s.
	_drops_mat.set_shader_parameter("rate", 0.12 * rain if rain < 1.0 else lerpf(0.12, 0.6, rain - 1.0))
	if drops:
		drops.visible = rain > 0.01


## Spojlery na klapie bagażnika: mała lotka na krawędzi albo duże skrzydło
## na dwóch wspornikach. Widoczny tylko wybrany (set_spoiler).
func _build_spoilers(mat: Material) -> void:
	var small := Node3D.new()
	small.name = "SpoilerSmall"
	_spoiler_box(small, Vector3(1.6, 0.035, 0.16), Vector3(0.0, 0.15, 2.18), mat, -0.25)
	var large := Node3D.new()
	large.name = "SpoilerLarge"
	for x in [-0.62, 0.62]:
		_spoiler_box(large, Vector3(0.05, 0.28, 0.12), Vector3(x, 0.26, 2.08), mat, 0.0)
	_spoiler_box(large, Vector3(1.74, 0.035, 0.34), Vector3(0.0, 0.41, 2.10), mat, -0.18)
	for x in [-0.87, 0.87]:
		_spoiler_box(large, Vector3(0.02, 0.12, 0.38), Vector3(x, 0.41, 2.10), mat, 0.0)
	for n in [small, large]:
		add_child(n)
	_spoiler_nodes = {"small": small, "large": large}
	set_spoiler(spoiler)


func _spoiler_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, pitch: float) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	mi.rotation = Vector3(pitch, 0.0, 0.0)
	parent.add_child(mi)


# --------------------------------------------------------------------------
# Model auta: sedan (własny, z wgnieceniami) albo concept car
# --------------------------------------------------------------------------

## "Car Concept" (Khronos glTF Sample Assets, CC BY 4.0 - Darmstadt Graphics
## Group GmbH, Eric Chadwick; oryginał Unity Fan), przygotowany przez
## tools/prepare_concept_car.sh. Model ma przód w +Z (obrót o 180°), większe
## koła i fotel kierowcy na środku - fizyka dostaje jego wymiary: mocowania
## kół, promień (przełożenie korygowane w apply_engine), kolizję z bryły.
## Wymiary zmierzone w modelu: rozstaw osi 2,80 m, kół 1,96 m, koło r 0,49.
const BASE_WHEEL_RADIUS := 0.33
const SEDAN_CLUSTER := Vector3(-0.38, 0.235, -0.37)   # gauges.build w _build_body
const CONCEPT := {
	"scene": "res://models/concept_car/car_player.glb",
	"mounts": [Vector3(-0.98, 0.0, -1.485), Vector3(0.98, 0.0, -1.485),
			Vector3(-0.98, 0.0, 1.314), Vector3(0.98, 0.0, 1.314)],
	"radius": 0.49,
	"model_y": -0.794,      # początek modelu w układzie auta (środek koła na ugięciu)
	# Fotel kierowcy na środku (układ jak w McLarenie F1: pasażerowie po
	# bokach z tyłu); oczy nad kierownicą (środek koła kierownicy: y -0.15,
	# z -0.93), dach od środka na ~0,33.
	"seat": Vector3(0.0, 0.15, -0.40),
	# Zestaw zegarów na desce za kierownicą (widoczny przez jej wnętrze).
	"gauges": Vector3(0.0, -0.03, -1.15),
	"body_box": [Vector3(1.90, 0.62, 4.30), Vector3(0.0, -0.42, -0.24)],
	"cabin_box": [Vector3(1.40, 0.50, 2.10), Vector3(0.0, 0.10, -0.10)],
	"wheels": ["WheelFrontL", "WheelFrontR", "WheelRearL", "WheelRearR"],
}
@export var body_model: String = "sedan"
var _concept: Node3D
static var _concept_scene: PackedScene
var _concept_steer: Node3D
var _concept_steer_axis := Vector3.FORWARD
var _concept_paint_mats: Array[BaseMaterial3D] = []
var _concept_cockpit_mats: Array[BaseMaterial3D] = []
var _paint_color := Color(0.8, 0.6, 0.18)
var _sedan := {}                       # zapamiętane wymiary sedana
var cockpit_offset := Vector3.ZERO     # przesunięcie fotela względem sedana
## Przesunięcie środka masy dla modelu: większe koła podnoszą nadwozie,
## środek masy zostaje na tej samej wysokości nad drogą co w sedanie i w tym
## samym miejscu względem osi (bez tego concept car zsuwał się z łuków).
var _model_com := Vector3.ZERO


func set_body_model(kind: String) -> void:
	if kind == body_model and (kind == "concept") == (_concept != null):
		return
	if _sedan.is_empty():
		var mounts := []
		for w in wheels:
			mounts.append(w.mount)
		_sedan = {"mounts": mounts, "radius": wheel_radius, "seat": seat.position,
				"body": [(get_node("BodyShape").shape as BoxShape3D).size, (get_node("BodyShape") as Node3D).position],
				"cabin": [(get_node("CabinShape").shape as BoxShape3D).size, (get_node("CabinShape") as Node3D).position],
				"gauges": gauges.position if gauges else Vector3.ZERO,
				"dash": dash_label.position if dash_label else Vector3.ZERO}
	if _concept:
		for m in _concept_cockpit_mats:
			_cockpit_mats.erase(m)
		_concept_cockpit_mats.clear()
		_concept.queue_free()
		_concept = null
		_concept_steer = null
		for w in wheels:
			for c in w.node.get_children():
				if c.has_meta("concept"):
					c.queue_free()
	var concept := kind == "concept" and ResourceLoader.exists(CONCEPT["scene"])
	body_model = kind if concept or kind == "sedan" else "sedan"
	var g: Dictionary = CONCEPT if concept else {}
	# Fizyka: mocowania kół, promień, kolizja.
	for i in range(4):
		wheels[i].mount = g["mounts"][i] if concept else _sedan["mounts"][i]
	wheel_radius = g["radius"] if concept else _sedan["radius"]
	_sphere.radius = wheel_radius
	_wheelbase = absf(wheels[0].mount.z - wheels[2].mount.z)
	_track_width = absf(wheels[1].mount.x - wheels[0].mount.x)
	if concept:
		var mid_s: float = (_sedan["mounts"][0].z + _sedan["mounts"][2].z) * 0.5
		var mid_c: float = (g["mounts"][0].z + g["mounts"][2].z) * 0.5
		_model_com = Vector3(0.0, -(float(g["radius"]) - float(_sedan["radius"])), mid_c - mid_s)
	else:
		_model_com = Vector3.ZERO
	var bb: Array = g["body_box"] if concept else _sedan["body"]
	var cb: Array = g["cabin_box"] if concept else _sedan["cabin"]
	var bs := get_node("BodyShape") as CollisionShape3D
	var cs := get_node("CabinShape") as CollisionShape3D
	(bs.shape as BoxShape3D).size = bb[0]
	bs.position = bb[1]
	(cs.shape as BoxShape3D).size = cb[0]
	cs.position = cb[1]
	# Fotel i to, co stoi przed nim (zegary, napis na desce).
	seat.position = g["seat"] if concept else _sedan["seat"]
	cockpit_offset = seat.position - _sedan["seat"]
	# Zestaw zegarów sedana stoi w (-0,38, 0,235, -0,37) - w concept carze
	# na desce za kierownicą, napis (bieg, kontrolki) pod nim.
	var gshift: Vector3 = (g["gauges"] - SEDAN_CLUSTER) if concept else Vector3.ZERO
	if gauges:
		gauges.position = _sedan["gauges"] + gshift
	if dash_label:
		dash_label.position = _sedan["dash"] + gshift
	# Wygląd sedana: karoseria, kabina, koła, spojlery, wycieraczki.
	for c in get_children():
		if c is MeshInstance3D or c.name in ["SteeringColumn", "Windshield", "SpoilerSmall", "SpoilerLarge"]:
			(c as Node3D).visible = not concept
	if not concept:
		set_spoiler(spoiler)
	for w in wheels:
		for c in w.node.get_children():
			if not c.has_meta("concept"):
				(c as Node3D).visible = not concept
	if concept:
		_build_concept()
	set_cockpit_transparency(_cockpit_alpha + 0.0001)
	set_cockpit_transparency(_cockpit_alpha - 0.0001)
	# Promień koła zmienia przełożenie - silnik od nowa.
	if engine_type != "":
		apply_engine(engine_type, engine_power_kw)


func _build_concept() -> void:
	# Scena wczytana raz na całą grę: przełączanie w menu (sedan <-> concept)
	# nie czyta i nie importuje modelu od nowa przy każdym kroku (na Queście
	# przełączenie przy 160% zamykało grę - GPU było już na 100%).
	if _concept_scene == null:
		_concept_scene = load(CONCEPT["scene"]) as PackedScene
	_concept = _concept_scene.instantiate() as Node3D
	_concept.name = "ConceptBody"
	_concept.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, CONCEPT["model_y"], 0.0))
	add_child(_concept)
	# Koła modelu jadą z naszymi kołami (ugięcie, skręt, obrót). Początek węzła
	# koła w modelu to środek koła.
	for i in range(4):
		var n := _concept.find_child(CONCEPT["wheels"][i], true, false) as Node3D
		if n == null:
			continue
		n.get_parent().remove_child(n)
		n.set_meta("concept", true)
		wheels[i].node.add_child(n)
		n.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	# Kierownica: obrót wokół osi kolumny (od piasty do koła kierownicy).
	var col := _concept.find_child("InteriorSteeringCylinder", true, false) as Node3D
	var rim := _concept.find_child("InteriorSteeringWheel01", true, false) as Node3D
	if col and rim:
		var pivot := Node3D.new()
		pivot.name = "SteerPivot"
		var parent := col.get_parent() as Node3D
		parent.add_child(pivot)
		pivot.position = col.position
		var axis := (rim.global_position - col.global_position)
		if axis.length() > 0.01:
			_concept_steer_axis = (parent.global_basis.inverse() * axis).normalized()
		var keep := col.global_transform
		parent.remove_child(col)
		pivot.add_child(col)
		col.global_transform = keep
		_concept_steer = pivot
	# Materiały: lakier (Paint 1/2) i przezroczystość kabiny dla wszystkiego
	# oprócz szyb i świateł.
	_concept_paint_mats.clear()
	var seen := {}
	var meshes: Array = _concept.find_children("*", "MeshInstance3D", true, false)
	for w in wheels:
		for c in w.node.get_children():
			if c.has_meta("concept"):
				meshes.append_array(c.find_children("*", "MeshInstance3D", true, false))
	for mi in meshes:
		var m3 := mi as MeshInstance3D
		for si in range(m3.mesh.get_surface_count()):
			var m := m3.get_active_material(si) as BaseMaterial3D
			if m == null or seen.has(m):
				continue
			seen[m] = true
			var nm := m.resource_name
			_fix_concept_material(m, nm)
			if nm.begins_with("Paint"):
				_concept_paint_mats.append(m)
			if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
					and not ("Glass" in nm or "light" in nm or "Mirror" in nm):
				_cockpit_mats.append(m)
				_concept_cockpit_mats.append(m)
	set_paint(_paint_color)
	# Wycieraczki i krople na szybie sedana nie pasują do tej szyby.
	var ws := get_node_or_null("Windshield") as Node3D
	if ws:
		ws.visible = false


## Poprawki materiałów modelu pod Godota i Questa: szkło używało
## KHR_materials_transmission (Godot go nie ma - szyby wychodziły białe
## i z kokpitu nic nie było widać), bok opony stracił kolor przy podmianie
## tekstury z logo, lakier był lustrzany.
func _fix_concept_material(m: BaseMaterial3D, nm: String) -> void:
	# Mapa zacieniania to wspólny atlas 2048 px, po uproszczeniu siatki
	# trafiała w złe miejsca (ciemne plamy na lakierze); bez niej też taniej.
	m.ao_enabled = false
	m.ao_texture = null
	if "Glass" in nm:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = null
		m.albedo_color = Color(0.25, 0.32, 0.36, 0.22)
		m.metallic = 0.0
		m.roughness = 0.05
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif nm.begins_with("Tire"):
		m.albedo_color = Color(0.05, 0.05, 0.05)
		m.metallic = 0.0
		m.roughness = 0.9
	elif nm == "Rim2":
		# Czysta biel, metaliczna - odbijała niebo i koła wyglądały na białe.
		m.albedo_color = Color(0.32, 0.33, 0.35)
		m.metallic = 0.4
		m.roughness = 0.45
	elif nm.begins_with("Paint"):
		m.metallic = minf(m.metallic, 0.35)
		m.roughness = maxf(m.roughness, 0.3)
