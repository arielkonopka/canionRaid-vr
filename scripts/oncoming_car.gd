class_name OncomingCar
extends RefCounted

## Auto z naprzeciwka (xr_main._oncoming): zamiast słownika z flagami
## "loose"/"osk" (przegląd chmury D8 - pierwszy krok do wydzielenia ruchu
## z naprzeciwka z xr_main).
##   RAIL     - kinematyczne, jedzie po szynie drugiej jezdni (dist, v, lane);
##   SKIRMISH - w scence OncomingSkirmish (rola `osk`: "a" / "b");
##   LOOSE    - przy graczu przeszło na pełną fizykę (_loosen_oncoming).

enum State { RAIL, SKIRMISH, LOOSE }

var car: StuntCar
var dist := 0.0              # [m] położenie na trasie (malejące - jedzie do gracza)
var v := 0.0                 # [m/s]
var lane := 0.0              # pas licząc od pasa rozdziału
var loose := false
var loose_t := 0.0           # [s] od przejścia na fizykę
var osk := ""                # rola w scence ("" = poza scenką)


func _init(c: StuntCar = null, d := 0.0, speed := 0.0, lane_i := 0.0) -> void:
	car = c
	dist = d
	v = speed
	lane = lane_i


func state() -> State:
	if loose:
		return State.LOOSE
	return State.SKIRMISH if osk != "" else State.RAIL
