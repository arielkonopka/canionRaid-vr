class_name AirWheel
extends RefCounted

## Kierownica "w powietrzu" (użytkownik 2026-11-11: "powietrzna kierownica
## jako opcja sterowania zamiast manetki"). Gracz łapie wieniec gripem
## (jedną albo dwiema rękami) i obraca go wokół osi kolumny kierowniczej.
## Kąt liczony przyrostowo (bez skoku przy złapaniu i przełożeniu rąk):
## dwie ręce - obrót linii między dłońmi, jedna - obrót dłoni wokół środka.
## Puszczona kierownica wraca do środka (jak prawdziwa przy jeździe).
## Znak: dodatni kąt = skręt w prawo (jak StuntCar.steer).

## Pełny skręt kół przy obrocie kierownicy o +-half_range stopni.
var half_range := 180.0
## Powrót puszczonej kierownicy do środka [°/s].
var center_rate := 540.0
var angle := 0.0                 # [°] obecny obrót kierownicy
var _prev := NAN                 # kąt rąk w poprzednim kroku [rad]
var _held_mask := 0              # które ręce trzymały (1 lewa, 2 prawa)


## hands: [[pozycja, trzyma], [pozycja, trzyma]] (lewa, prawa), w świecie.
## center/axis: środek wieńca i oś kolumny (od wieńca w stronę kierowcy
## albo od niego - znak bierze się z prawej osi `right`).
## right: kierunek "w prawo" w płaszczyźnie wieńca (prawa ręka przy 3:00).
func update(hands: Array, center: Vector3, axis: Vector3, right: Vector3, delta: float) -> float:
	axis = axis.normalized()
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
	if v.length() < 0.02:
		return steer()
	# Kąt w płaszczyźnie wieńca względem "w prawo"; obrót zgodny z ruchem
	# wskazówek zegara (widok kierowcy) = skręt w prawo.
	var up_in_plane := axis.cross(right).normalized()
	var a := atan2(v.dot(up_in_plane), v.dot(right))
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
