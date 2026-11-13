class_name PathSteer

## Prowadzenie po torze z modelu rowerowego (propozycja chmury 2026-11-11,
## inbox stabilnosc-200-odpowiedz): kurs docelowy z odchyłki (powrót na pas
## w ~2 s), żądany obrót z błędu kursu (0,5 s), skręt z modelu rowerowego,
## tłumienie prędkością obrotu, człon wyprzedzający z krzywizny. Stałe
## wzmocnienia (stary autopilot testów, sterowanie botów) rozbujały auto
## przy > 200 km/h. Używają: autopilot testów (tests/_autopilot.gd), bot
## ekstremista (BotDriver - jeździ 250-300 km/h).
## Znaki: `off` > 0 = auto na prawo od celu, `head_err` > 0 = tor skręca
## w lewo, `curve` [rad/m] > 0 = w lewo, wynik > 0 = skręt w prawo.


static func steer(car: StuntCar, off: float, head_err: float, curve := 0.0) -> float:
	var v := maxf(car.speed, 5.0)
	var psi_t := clampf(off / (v * 2.0), -0.3, 0.3)       # kurs docelowy [rad, + w lewo]
	var r_c := (psi_t + head_err) / 0.5 + v * curve        # żądany obrót [rad/s, + w lewo]
	var r_left := car.angular_velocity.dot(car.global_basis.y)
	var delta := car._wheelbase * (r_c + (r_c - r_left)) / v
	var max_a := deg_to_rad(car.max_steer_deg)
	if car.steer_assist:
		max_a = deg_to_rad(lerpf(car.max_steer_deg, car.high_speed_steer_deg,
				clampf(absf(car.speed) / car.steer_assist_speed, 0.0, 1.0)))
	return clampf(-delta / max_a, -1.0, 1.0)


## Znoszenie [°]: kąt między osią auta a prędkością w płaszczyźnie auta
## (bez składowej pionowej - pochylenie, garby i lądowania dawały
## fałszywe stopnie; chmura 2026-11-11).
static func beta_deg(car: RigidBody3D) -> float:
	var up := car.global_basis.y
	var v := car.linear_velocity - up * car.linear_velocity.dot(up)
	if v.length() < 0.5:
		return 0.0
	return rad_to_deg(absf((-car.global_basis.z).signed_angle_to(v.normalized(), up)))
