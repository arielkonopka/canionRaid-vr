extends RefCounted
class_name OncomingSkirmish

## Potyczka botów na drugiej jezdni autostrady, widoczna dla gracza
## z przeciwnego kierunku (użytkownik 2026-11-09: "furia drogowa między
## botami mogłaby być widoczna dla samochodów jadących w drugą stronę";
## tryb Autostrada docelowo na całej długości).
##
## Auta z naprzeciwka są kinematyczne (xr_main._update_oncoming: dist, v,
## lane), za barierą i mijają gracza z prędkością względną 250+ km/h -
## gracz widzi je 3-6 s. Pełna fizyka byłaby marnotrawstwem (decyzja
## użytkownika: daleko / poza zasięgiem gracza bot może się upraszczać).
## Dlatego scenka jest **reżyserowana**: krzywe pasa, prędkości, obrotu
## i przechyłu dwóch aut + zdarzenia (klakson, uderzenie, iskry, dym,
## wybuch) w czasie. Koszt: kilka interpolacji na klatkę.
##
## Integracja (agent lokalny, xr_main):
##   - gdy na autostradzie przed graczem jest wolne miejsce na drugiej
##     jezdni: sk = OncomingSkirmish.random(rng); dwa auta z puli oncoming
##     (kolory dwóch wrogich gangów z FeudDirector, jeśli są), B w dist,
##     A w dist + sk.offset_a (A za B w jego kierunku jazdy);
##   - start, gdy odstęp od gracza ≤ trigger_gap(prędkość zbliżania);
##   - co klatkę: ev = sk.step(delta); B: dist_b -= v_bazowe ×
##     state_b["v"] × delta; A: dist_a = dist_b + sk.gap (NIE całkować A
##     osobno - odstęp wzdłuż trasy liczy scenka przy V_REF, więc
##     geometria zbliżeń nie zależy od prędkości bazowej 110-140 km/h);
##     dla obu: lane = state["lane"], obrót bazy o state["yaw"]
##     (stopnie, wokół osi pionowej auta), przechył state["roll"];
##     state["hidden"] → do puli (np. po wybuchu);
##   - zdarzenia: "horn" (klakson auta), "hit" (dźwięk uderzenia,
##     wgniecenie z boku), "sparks" (iskry przy barierze), "smoke" (dym
##     opon), "boom" (Explosion jak przy botach) - pole "car": "a"/"b".
##   - tylko gdy gracz jedzie autostradą i OncomingSkirmish.fits(szerokość); potyczka nie daje punktów
##     (gracz nie może w niej uczestniczyć - jest za barierą).

## Klimaks scenki ma wypaść tyle metrów przed graczem (w polu widzenia,
## wystarczająco blisko, żeby było widać szczegóły).
const CLIMAX_DIST := 180.0
const MIN_SEP := 1.7      # [m] środki aut w poprzek, poniżej = przenikanie
## Prędkość odniesienia [m/s] do całkowania odstępu A-B (gap). Auto A
## jedzie wtedy o (V_REF - v_bazowe)·(a_v - b_v) ≤ ~3 m/s inaczej niż
## z mnożnika - niewidoczne, a zbliżenia są zawsze takie, jak zaprojektowane.
const V_REF := 35.0
## Najwęższa jezdnia [m], na której scenki wyglądają dobrze: pasy w
## klatkach są względne (lane × lane_w), a przy lane_w < 4 m auta
## w podejściu do pita nachodzą na siebie. Na węższej - nie startować.
const MIN_ROAD_W := 13.0

## Autostrada 2+2 (HighwayGenerator, jezdnia 11,25 m - węższa niż
## MIN_ROAD_W): pas scenki L liczony od krawędzi przy pasie rozdziału -
## L = -1 środek auta HWY_EDGE_IN m od tej krawędzi, L = 1,45 HWY_EDGE_OUT m
## od krawędzi pobocza, liniowo (przy 11,25 m: 3,41 m na jednostkę L,
## sprawdzane w oncoming_skirmish_test).
const HWY_EDGE_IN := 2.0
const HWY_EDGE_OUT := 0.9


## Odległość środka auta od krawędzi jezdni przy pasie rozdziału [m].
static func hwy_from_median(lane: float, road_w: float) -> float:
	return HWY_EDGE_IN + (lane + 1.0) * hwy_unit(road_w)


## Metry na jednostkę pasa scenki na autostradzie.
static func hwy_unit(road_w: float) -> float:
	return (road_w - HWY_EDGE_IN - HWY_EDGE_OUT) / 2.45


## Scenki: klatki kluczowe [t, a_lane, a_v, a_yaw, a_roll, b_lane, b_v, b_yaw, b_roll],
## pasy drugiej jezdni jak w xr_main (-1 przy pasie rozdziału, 1 przy
## poboczu, 1,45 = przy barierze zewnętrznej); v = mnożnik prędkości
## bazowej; kąty w stopniach. Interpolacja smoothstep między klatkami.
const SCENES := {
	# A wyprzedza B, zajeżdża mu drogę i hamuje; B ucieka na prawy pas.
	"cut": {
		"offset_a": 8.0, "climax": 3.6, "weight": 3.0,
		"keys": [
			[0.0, 0.0, 1.0, 0, 0, 0.0, 1.0, 0, 0],
			[1.0, -1.0, 1.25, -4, 0, 0.0, 1.0, 0, 0],
			[2.6, -1.0, 1.25, 0, 0, 0.0, 1.0, 0, 0],
			[3.3, 0.0, 1.0, 5, 0, 0.0, 1.0, 0, 0],
			[3.7, 0.0, 0.55, 0, 0, 0.3, 0.8, 10, 2],
			[4.4, 0.0, 0.7, 0, 0, 1.0, 0.85, 4, 0],
			[6.0, 0.0, 1.1, 0, 0, 1.0, 0.95, 0, 0],
		],
		"events": [[3.3, "horn", "b"], [3.6, "smoke", "a"], [3.7, "horn", "b"], [3.8, "smoke", "b"]],
	},
	# Ocieranie bokami: A dwa razy uderza B, B szoruje o barierę.
	"swipe": {
		"offset_a": 0.0, "climax": 2.6, "weight": 3.0,
		"keys": [
			[0.0, -1.0, 1.0, 0, 0, 0.0, 1.0, 0, 0],
			[0.9, -0.62, 1.0, 6, -3, 0.0, 1.0, 0, 0],
			[1.3, -0.9, 1.0, 0, 0, 0.45, 0.97, 6, 3],
			[2.0, -0.5, 1.0, 7, -3, 0.45, 0.97, 0, 0],
			[2.6, -0.6, 1.0, 0, 0, 1.45, 0.85, 12, 5],
			[3.8, -0.3, 1.15, 0, 0, 1.45, 0.65, 3, 0],
			[6.0, 0.0, 1.2, 0, 0, 1.3, 0.75, 0, 0],
		],
		"events": [[0.9, "horn", "a"], [0.95, "hit", "b"], [2.05, "hit", "b"],
				[2.6, "sparks", "b"], [3.2, "sparks", "b"]],
	},
	# Pit: A trąca tył B, B obraca się i staje tyłem na poboczu.
	"pit": {
		"offset_a": 4.5, "climax": 2.8, "weight": 2.0,
		"keys": [
			[0.0, -0.8, 1.06, 0, 0, 0.0, 1.0, 0, 0],
			[1.4, -0.5, 1.06, 8, 0, 0.0, 1.0, 0, 0],
			[1.7, -0.6, 1.0, 0, 0, 0.15, 0.9, 30, 3],
			[2.8, -0.4, 1.05, 0, 0, 0.9, 0.5, 150, 6],
			[3.8, -0.2, 1.1, 0, 0, 1.35, 0.15, 200, 0],
			[6.0, 0.0, 1.15, 0, 0, 1.4, 0.0, 200, 0],
		],
		"events": [[1.45, "hit", "b"], [1.6, "smoke", "b"], [2.4, "smoke", "b"]],
	},
	# Rzadko: B po uderzeniu wjeżdża w barierę i wybucha.
	"wreck": {
		"offset_a": 0.0, "climax": 2.4, "weight": 1.0,
		"keys": [
			[0.0, -1.0, 1.0, 0, 0, 0.0, 1.0, 0, 0],
			[1.0, -0.6, 1.0, 8, -3, 0.0, 1.0, 0, 0],
			[1.4, -0.85, 1.0, 0, 0, 0.6, 0.95, 25, 6],
			[2.2, -0.6, 1.0, 0, 0, 1.45, 0.6, 40, 25],
			[2.6, -0.4, 1.1, 0, 0, 1.45, 0.0, 55, 35],
			[6.0, 0.0, 1.2, 0, 0, 1.45, 0.0, 55, 35],
		],
		"events": [[1.0, "horn", "a"], [1.05, "hit", "b"], [2.2, "sparks", "b"],
				[2.6, "boom", "b"]],
		"hide_b_at": 2.65,
	},
}

var kind := ""
var t := 0.0
var done := false
var offset_a := 0.0
## Odstęp A od B wzdłuż trasy [m], dodatni = A za B (w kierunku jazdy B).
var gap := 0.0
var climax := 0.0
var state_a := {}
var state_b := {}
var _keys: Array = []
var _events: Array = []
var _next_ev := 0
var _hide_b_at := INF


func _init(k: String = "cut") -> void:
	kind = k
	var s: Dictionary = SCENES[k]
	_keys = s["keys"]
	_events = s["events"]
	offset_a = s["offset_a"]
	climax = s["climax"]
	_hide_b_at = s.get("hide_b_at", INF)
	gap = offset_a
	_apply(0.0)


## Losowa scenka według wag ("wreck" rzadko).
static func random(rng: RandomNumberGenerator) -> OncomingSkirmish:
	var total := 0.0
	for k in SCENES:
		total += float(SCENES[k]["weight"])
	var r := rng.randf() * total
	for k in SCENES:
		r -= float(SCENES[k]["weight"])
		if r <= 0.0:
			return OncomingSkirmish.new(k)
	return OncomingSkirmish.new("cut")


## Przy jakim odstępie od gracza [m] (wzdłuż trasy) zacząć scenkę, żeby
## klimaks wypadł CLIMAX_DIST m przed graczem. closing_mps = prędkość
## gracza + prędkość aut z naprzeciwka [m/s].
func trigger_gap(closing_mps: float) -> float:
	return CLIMAX_DIST + maxf(closing_mps, 0.0) * climax


## Czy jezdnia o szerokości road_w [m] (jak "width" z próbek trasy)
## mieści scenki bez przenikania aut.
static func fits(road_w: float) -> bool:
	return road_w >= MIN_ROAD_W


func duration() -> float:
	return float(_keys[_keys.size() - 1][0])


## Krok scenki. Zwraca zdarzenia, które wypadły w tym kroku:
## [{"type": "horn"/"hit"/"sparks"/"smoke"/"boom", "car": "a"/"b"}].
func step(dt: float) -> Array:
	if done:
		return []
	t += dt
	var out := []
	while _next_ev < _events.size() and float(_events[_next_ev][0]) <= t:
		out.append({"type": _events[_next_ev][1], "car": _events[_next_ev][2]})
		_next_ev += 1
	_apply(t)
	gap -= V_REF * (float(state_a["v"]) - float(state_b["v"])) * dt
	if t >= duration():
		done = true
	return out


func _apply(tt: float) -> void:
	var i := 0
	while i < _keys.size() - 2 and tt > float(_keys[i + 1][0]):
		i += 1
	var k0: Array = _keys[i]
	var k1: Array = _keys[mini(i + 1, _keys.size() - 1)]
	var span := float(k1[0]) - float(k0[0])
	var u := 1.0 if span <= 0.0 else clampf((tt - float(k0[0])) / span, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var v := []
	for j in range(1, 9):
		v.append(lerpf(float(k0[j]), float(k1[j]), u))
	state_a = {"lane": v[0], "v": v[1], "yaw": v[2], "roll": v[3], "hidden": false}
	state_b = {"lane": v[4], "v": v[5], "yaw": v[6], "roll": v[7], "hidden": tt >= _hide_b_at}
