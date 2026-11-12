class_name AirWheel
extends RefCounted

## Kierownica "w powietrzu" (użytkownik 2026-11-11: "powietrzna kierownica
## jako opcja sterowania zamiast manetki"). Gracz łapie wieniec gripem
## (jedną albo dwiema rękami) i obraca go wokół osi kolumny kierowniczej.
## Kąt liczony przyrostowo (bez skoku przy złapaniu i przełożeniu rąk):
## dwie ręce - obrót linii między dłońmi, jedna - obrót dłoni wokół środka.
## Puszczona kierownica wraca do środka (jak prawdziwa przy jeździe).
## Znak: dodatni kąt = obrót zgodny z ruchem wskazówek zegara z widoku
## kierowcy = skręt w prawo (jak StuntCar.steer).
## Klasa bez zależności od sceny - test: tests/air_wheel_test.gd.

## Pełny skręt kół przy obrocie kierownicy o +-half_range stopni.
var half_range := 180.0
## Powrót puszczonej kierownicy do środka [°/s] (0 = zostaje, gdzie była).
var center_rate := 540.0
## Jedna ręka bliżej środka niż to [m] - kąt nieczytelny, kierownica stoi.
var min_radius := 0.05
var angle := 0.0                 # [°] obecny obrót kierownicy
var _prev := NAN                 # kąt rąk w poprzednim kroku [rad]
var _held_mask := 0              # które ręce trzymały (1 lewa, 2 prawa)


## hands: [[pozycja, trzyma], [pozycja, trzyma]] (lewa, prawa), w świecie.
## center: środek wieńca.
## right, up: kierunki "w prawo" i "w górę" w płaszczyźnie wieńca, tak jak
## je widzi kierowca (prawa ręka na 3:00, góra wieńca na 12:00). Oś kolumny
## to right x up (w stronę kierowcy). Przy kolumnie z węzła auta:
## right = basis.x, up = basis.y obróconej tarczy wieńca (bez obrotu
## samej kierownicy, czyli rodzica `SteeringWheel`).
## Zwraca skręt -1..1.
func update(hands: Array, center: Vector3, right: Vector3, up: Vector3, delta: float) -> float:
	var axis := right.cross(up).normalized()
	# Ortonormalna baza płaszczyzny (kolumna może być pochylona).
	var r := (right - axis * right.dot(axis)).normalized()
	var u := axis.cross(r)
	var mask := 0
	var pts: Array[Vector3] = []
	for i in range(2):
		if hands[i][1]:
			mask |= 1 << i
			var p: Vector3 = hands[i][0] - center
			pts.append(p - axis * p.dot(axis))
	if mask == 0:
		_prev = NAN
		_held_mask = 0
		angle = move_toward(angle, 0.0, center_rate * delta)
		return steer()
	var v: Vector3 = (pts[1] - pts[0]) if pts.size() == 2 else pts[0]
	if v.length() < min_radius:
		# Nieczytelny kąt: trzymana kierownica stoi; następny czytelny krok
		# zaczyna od nowa (bez skoku przy przejściu dłoni przez środek).
		_prev = NAN
		return steer()
	# Kąt w płaszczyźnie wieńca od "w prawo", rośnie przeciwnie do wskazówek
	# zegara (widok kierowcy), więc obrót w prawo daje ujemne d.
	var a := atan2(v.dot(u), v.dot(r))
	if mask != _held_mask or is_nan(_prev):
		_prev = a                     # złapanie / przełożenie ręki - bez skoku
		_held_mask = mask
	var d := wrapf(a - _prev, -PI, PI)
	_prev = a
	angle = clampf(angle - rad_to_deg(d), -half_range, half_range)
	return steer()


## Skręt -1..1 dla StuntCar.steer.
func steer() -> float:
	return clampf(angle / half_range, -1.0, 1.0)


## Kierownica na środek, bez trzymania (np. po place() / zmianie auta).
func reset() -> void:
	angle = 0.0
	_prev = NAN
	_held_mask = 0
