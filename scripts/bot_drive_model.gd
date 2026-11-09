extends RefCounted
class_name BotDriveModel

## Uproszczony napęd botów (decyzja użytkownika 2026-11-09: "oszukiwać na
## napędzie botów, ale nie na oponach i bezwładności"; 5% różnicy prędkości
## nie przeszkadza). Auto gracza tego NIE używa.
##
## Zamiast skrzyni z biegami, sprzęgła, decyzji o zmianie biegu i obrotów
## silnika jako osobnego stanu: "przełożenie równoważne" r_eq, które trzyma
## silnik przy obrotach mocy maksymalnej (jak idealna skrzynia bezstopniowa),
## w granicach przełożenia 1. i najwyższego biegu. Moment silnika:
##   gaz × min(K_FILL × P_max / ω_silnika, T_max)
## K_FILL < 1 oddaje dziury między biegami i czas zmiany w prawdziwej
## skrzyni - skalibrowane w tools/bot_drive_sim.py do pełnego modelu
## (0-100 -5%, 0-160 +1%, hamowanie +1%, łuk i zmiana pasa 0%).
##
## Zostaje bez zmian (w StuntCar): opony, zawieszenie, nadwozie, kolizje,
## uszkodzenia, TCS, ABS, hamowanie silnikiem (ten sam wzór), bezwładność
## silnika widziana na kołach (I_e × r_eq², woła ją StuntCar jak dziś
## z _total_ratio). ESP bot nie potrzebuje (sam steruje torem).
##
## Integracja (agent lokalny, stunt_car.gd), gdy `is_bot and simple_drive`:
##   - raz po apply_engine: drive = BotDriveModel.from_car(torque_curve,
##     gear_ratios, final_drive, idle_rpm)
##   - _update_gearbox: przy gear >= 1 tylko `gear = 1`, sprzęgło zawsze
##     zamknięte, bez zmian biegów (logika wstecznego dla wychodzenia
##     z utknięcia zostaje);
##   - _total_ratio(1) → drive.ratio(_driven_omega());
##   - _engine_torque_at_clutch → drive.engine_torque(pedał,
##     _driven_omega(), r_eq, engine_brake_a, engine_brake_b);
##   - _update_engine_rpm → engine_rpm = drive.rpm(_driven_omega(), r_eq);
##   - _update_esp pominięte (_esp_factor = 1, _esp_brake = 0).

## Kalibracja do pełnego modelu (tools/bot_drive_sim.py, 250 i 350 kW).
const K_FILL := 0.86
const RPM_PER_RAD_S := 60.0 / TAU

var p_max := 0.0        # [W] moc maksymalna z krzywej
var w_pp := 0.0         # [rad/s] obroty mocy maksymalnej
var t_max := 0.0        # [Nm] największy moment z krzywej
var r_first := 1.0      # przełożenie całkowite 1. biegu
var r_top := 1.0        # przełożenie całkowite najwyższego biegu
var w_idle := 0.0       # [rad/s] obroty biegu jałowego


## Model z danych auta (krzywa momentu jak StuntCar.torque_curve: x = obr/min,
## y = Nm, już przeskalowana do mocy).
static func from_car(torque_curve: PackedVector2Array, gear_ratios: PackedFloat32Array,
		final_drive: float, idle_rpm: float) -> BotDriveModel:
	var m := BotDriveModel.new()
	var r := torque_curve[0].x
	var last := torque_curve[torque_curve.size() - 1].x
	while r <= last:
		var t := _curve(torque_curve, r)
		var p := t * r / RPM_PER_RAD_S
		if p > m.p_max:
			m.p_max = p
			m.w_pp = r / RPM_PER_RAD_S
		m.t_max = maxf(m.t_max, t)
		r += 50.0
	m.r_first = gear_ratios[0] * final_drive
	m.r_top = gear_ratios[gear_ratios.size() - 1] * final_drive
	m.w_idle = idle_rpm / RPM_PER_RAD_S
	return m


## Przełożenie równoważne przy danej prędkości kątowej kół napędzanych.
func ratio(driven_omega: float) -> float:
	var wo := maxf(absf(driven_omega), 0.1)
	return clampf(w_pp / wo, r_top, r_first)


## Obroty silnika [obr/min] (do wyglądu/dźwięku, jeśli kiedyś potrzebne).
func rpm(driven_omega: float, r_eq: float) -> float:
	return maxf(absf(driven_omega) * r_eq, w_idle) * RPM_PER_RAD_S


## Moment na sprzęgle [Nm], jak StuntCar._engine_torque_at_clutch: z gazem
## napęd, bez gazu hamowanie silnikiem (ten sam wzór, zanika przy 0 obr.).
func engine_torque(pedal: float, driven_omega: float, r_eq: float,
		brake_a: float, brake_b: float) -> float:
	var w_e := maxf(absf(driven_omega) * r_eq, w_idle)
	if pedal > 0.02:
		return pedal * minf(K_FILL * p_max / w_e, t_max)
	var rpm_e := w_e * RPM_PER_RAD_S
	var fade := clampf(rpm_e / 400.0, 0.0, 1.0)
	return -(brake_a + brake_b * rpm_e) * fade


static func _curve(c: PackedVector2Array, rpm_v: float) -> float:
	if rpm_v <= c[0].x:
		return c[0].y
	for i in range(1, c.size()):
		if rpm_v <= c[i].x:
			var t := (rpm_v - c[i - 1].x) / (c[i].x - c[i - 1].x)
			return lerpf(c[i - 1].y, c[i].y, t)
	return c[c.size() - 1].y
