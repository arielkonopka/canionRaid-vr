class_name Haptics
extends RefCounted

## Wibracje kontrolerów (użytkownik 2026-11-11: "reaktywność drążków -
## powinny reagować na uderzenia i różne takie"; 2026-11-12: "niech wibruje
## w dłoniach, co trzymają"). Czysta logika: step() zwraca impulsy
## [ręka 0 lewa / 1 prawa, amplituda 0..1, czas s], scena wysyła je do
## XRController3D.trigger_haptic_pulse("haptic", ...). Test: haptics_test.
##   zderzenie / lądowanie - obie ręce, siła z impulsu / prędkości;
##   pobocze (trawa, skała, tarka) - drżenie z prędkością;
##   ABS - pulsowanie w ręce hamulca; buksowanie / TCS - w ręce gazu;
##   faktura drogi - osobny przełącznik (może męczyć), domyślnie wył.
## Kierownica w powietrzu: wszystko tylko w rękach, które trzymają wieniec.

const ROUGH := ["grass", "rock", "kicker", "gravel"]
## Odstęp impulsów dla efektów ciągłych [s] (kontroler wibruje cały czas,
## gdy kolejne impulsy zachodzą na siebie).
const TICK := 0.06

var strength := 0.5          # Wył. 0 / Słabe 0,5 / Mocne 1
var road_texture := false
var _t := 0.0
var _last_hit_ms := 0
var _landing := 0.0


## Lądowanie z sygnału StuntCar.landed (prędkość uderzenia [m/s]).
func on_landed(impact_speed: float) -> void:
	_landing = maxf(_landing, clampf((impact_speed - 2.0) / 10.0, 0.0, 1.0))


## s: {"speed": m/s, "hit_j": N·s, "hit_ms": int, "abs": bool, "tcs": bool,
##   "slip": maks. poślizg kół napędzanych (1 = szczyt), "rough": 0..1 kół na
##   pobocze, "brake_hand": 0/1, "gas_hand": 0/1, "holding": [bool, bool]
##   albo [] (drążek - obie ręce)}
func step(delta: float, s: Dictionary) -> Array:
	var out := []
	if strength <= 0.0:
		return out
	var hold: Array = s.get("holding", [])
	var hands := [0, 1]
	if not hold.is_empty():
		hands = []
		for i in range(2):
			if hold[i]:
				hands.append(i)
	# Uderzenie: raz na nowy kontakt (last_hit ma czas w ms).
	var hit_ms: int = int(s.get("hit_ms", 0))
	if hit_ms != _last_hit_ms and float(s.get("hit_j", 0.0)) > 1500.0:
		_last_hit_ms = hit_ms
		var a := clampf(float(s["hit_j"]) / 15000.0, 0.25, 1.0)
		for h in hands:
			out.append([h, a * strength, 0.12 + 0.2 * a])
	if _landing > 0.0:
		for h in hands:
			out.append([h, _landing * strength, 0.15])
		_landing = 0.0
	_t -= delta
	if _t > 0.0:
		return out
	_t = TICK
	var v: float = absf(float(s.get("speed", 0.0)))
	var cont := [0.0, 0.0]
	var rough: float = float(s.get("rough", 0.0))
	if rough > 0.0 and v > 2.0:
		var a := rough * clampf(0.15 + v / 60.0, 0.0, 0.6)
		cont[0] = maxf(cont[0], a)
		cont[1] = maxf(cont[1], a)
	if road_texture and v > 5.0:
		var a := clampf(0.04 + v / 1000.0, 0.0, 0.15)
		cont[0] = maxf(cont[0], a)
		cont[1] = maxf(cont[1], a)
	if s.get("abs", false):
		var bh: int = int(s.get("brake_hand", 0))
		cont[bh] = maxf(cont[bh], 0.45)
	if s.get("tcs", false) or float(s.get("slip", 0.0)) > 1.2:
		var gh: int = int(s.get("gas_hand", 1))
		cont[gh] = maxf(cont[gh], 0.3)
	for h in hands:
		# W kierownicy w powietrzu ABS i TCS czuć w trzymających rękach.
		var a: float = cont[h]
		if not hold.is_empty():
			a = maxf(cont[0], cont[1])
		if a > 0.01:
			out.append([h, a * strength, TICK * 1.3])
	return out
