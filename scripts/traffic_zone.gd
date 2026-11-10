extends RefCounted
class_name TrafficZone

## Ruch w trybie "Autostrada" na całej długości, w obie strony (ustalenia
## użytkownika 2026-11-09): w strefie do HighwayPlan.TRAFFIC_RADIUS (5 km)
## od zabudowy 3-5 aut na kilometr, między miastami rzadki ruch 0,5-1/km.
## Auta, które nie są w furii, mogą znikać - ale tylko wtedy, gdy gracz ich
## nie widzi: za oknem wokół gracza albo jako nadmiar, gdy gęstość spada
## (wyjazd ze strefy miasta).
##
## Czysta logika decyzji, bez węzłów: scena jazdy co ~0,5 s podaje listę
## aut (dystans wzdłuż trasy, furia, czy widoczne) i dostaje, które auta
## usunąć i gdzie dodać nowe. Fizyka botów, pula aut i ich wygląd zostają
## w xr_main / BotDriver (pliki gorące - wpina agent lokalny).
##
## Jak to się ma do dzisiejszego `bot_limit` (limit z numeru odcinka): w trybie
## Autostrada liczbę spokojnych aut na naszej jezdni wyznacza ta gęstość
## (zamiast `bot_limit`); każde z nich może wpaść w furię jak dziś
## (wyprzedzenie, kontakt, waśnie FeudDirector). Auto w furii nie jest
## liczone do gęstości i nie znika.

## Okno, w którym utrzymujemy gęstość [m od gracza].
const AHEAD := 1500.0
const BEHIND := 300.0
## Nowe auta nie bliżej niż tyle przed graczem (daleko = poza szczegółami;
## dodatkowo scena sprawdza `visible`).
const SPAWN_MIN_AHEAD := 700.0
## Odstęp od innego auta na tym samym pasie przy dodawaniu [m].
const SPAWN_GAP := 40.0
## Najwyżej tyle nowych aut na wywołanie (koszt budowy auta rozłożony).
const MAX_SPAWN_PER_STEP := 1
## Za oknem (z zapasem) auto bez furii jest usuwane, gdy niewidoczne.
const DESPAWN_MARGIN := 300.0
## Nadmiar ponad `wanted` (np. po wyjeździe ze strefy miasta) - usuwamy
## niewidoczne auta bez furii, najdalsze od gracza najpierw, gdy aut jest
## więcej niż wanted + SURPLUS.
const SURPLUS := 1

## Nasza jezdnia między miastami: gęstość x tyle (użytkownik 2026-11-10:
## "za mało botów jeżdżących w moją stronę"). Przy tej samej gęstości auta
## z naprzeciwka mija się co kilkanaście sekund (zbliżanie ~250 km/h),
## a te w naszą stronę dogania się powoli - w oknie było ich 1-2. W strefie
## miasta zostaje gęstość z planu (3-5/km, ustalenie użytkownika).
const SAME_DIR_MULT := 2.5

## Widoczność (VR: głowa się obraca, są lusterka) - zgrubnie i z zapasem.
const VIEW_DIST := 900.0
const VIEW_HALF_ANGLE := deg_to_rad(70.0)
const MIRROR_DIST := 200.0
const MIRROR_HALF_ANGLE := deg_to_rad(25.0)

var plan: HighwayPlan


func _init(p: HighwayPlan) -> void:
	plan = p


## Ile aut powinno być w oknie wokół `player_dist` na jednej jezdni
## (całka gęstości po oknie, próbkowana co 100 m).
func wanted(player_dist: float, same_dir := false) -> int:
	var sum := 0.0
	var d := player_dist - BEHIND
	while d < player_dist + AHEAD:
		var k := SAME_DIR_MULT if same_dir and not plan.in_city_zone(d + 50.0) else 1.0
		sum += plan.traffic_density(d + 50.0) * 0.1 * k
		d += 100.0
	return int(round(sum))


## Decyzja na jeden krok.
## cars: [{"id", "dist", "lane", "oncoming": bool, "raging": bool, "visible": bool}]
##   lane: 0 = prawy, 1 = lewy (na swojej jezdni).
## Zwraca {"despawn": [id, ...], "spawn": [{"dist", "lane", "oncoming", "speed_kmh"}]}.
## Kandydaci do dodania - scena odrzuca tych, których gracz by zobaczył
## (`visible`), i woła ponownie przy następnym kroku.
func step(player_dist: float, cars: Array, rng: RandomNumberGenerator) -> Dictionary:
	var despawn := []
	var count := {false: 0, true: 0}
	var removable := {false: [], true: []}      # niewidoczne bez furii w oknie
	for c in cars:
		var d: float = c["dist"]
		var calm_hidden: bool = not c.get("raging", false) and not c.get("visible", true)
		var outside := d < player_dist - BEHIND - DESPAWN_MARGIN \
				or d > player_dist + AHEAD + DESPAWN_MARGIN
		if calm_hidden and outside:
			despawn.append(c["id"])
		elif d >= player_dist - BEHIND and d <= player_dist + AHEAD and not c.get("raging", false):
			var side := bool(c.get("oncoming", false))
			count[side] += 1
			if calm_hidden:
				removable[side].append(c)
	var spawn := []
	var want := {false: wanted(player_dist, true), true: wanted(player_dist)}   # klucz: oncoming
	# Nadmiar (gęstość spadła): najdalsze od gracza niewidoczne auta znikają.
	for side in [false, true]:
		var extra: int = int(count[side]) - int(want[side]) - SURPLUS
		if extra <= 0:
			continue
		var list: Array = removable[side]
		list.sort_custom(func(a, b): return absf(float(a["dist"]) - player_dist) > absf(float(b["dist"]) - player_dist))
		for i in range(mini(extra, list.size())):
			despawn.append(list[i]["id"])
			count[side] -= 1
	for oncoming in [false, true]:
		var missing: int = int(want[oncoming]) - int(count[oncoming])
		for _k in range(mini(missing, MAX_SPAWN_PER_STEP)):
			var cand := _candidate(player_dist, cars, spawn, oncoming, rng)
			if not cand.is_empty():
				spawn.append(cand)
	return {"despawn": despawn, "spawn": spawn}


func _candidate(player_dist: float, cars: Array, planned: Array, oncoming: bool,
		rng: RandomNumberGenerator) -> Dictionary:
	for _try in range(6):
		var d := rng.randf_range(player_dist + SPAWN_MIN_AHEAD, player_dist + AHEAD)
		if plan.traffic_density(d) <= 0.0:
			continue
		# Prawy pas częściej (jak na prawdziwej autostradzie).
		var lane := 0 if rng.randf() < 0.7 else 1
		var free := true
		for c in cars + planned:
			if bool(c.get("oncoming", false)) == oncoming and int(c.get("lane", 0)) == lane \
					and absf(float(c["dist"]) - d) < SPAWN_GAP:
				free = false
				break
		if not free:
			continue
		var limit := plan.limit_at(d)
		return {"dist": d, "lane": lane, "oncoming": oncoming,
				"speed_kmh": limit * rng.randf_range(0.8, 1.0) if lane == 0 else limit * rng.randf_range(0.95, 1.1)}
	return {}


## Czy punkt `p` może być widoczny dla gracza: w polu widzenia głowy
## (z zapasem na obrót) albo w lusterkach (stożek za autem). Bez zasłaniania
## przez budynki - ostrożnie: lepiej nie usunąć niż usunąć na oczach.
static func visible(head_pos: Vector3, head_fwd: Vector3, car_fwd: Vector3, p: Vector3) -> bool:
	var to := p - head_pos
	var dist := to.length()
	if dist < 1.0:
		return true
	var dir := to / dist
	if dist < VIEW_DIST and dir.dot(head_fwd.normalized()) > cos(VIEW_HALF_ANGLE):
		return true
	if dist < MIRROR_DIST and dir.dot(-car_fwd.normalized()) > cos(MIRROR_HALF_ANGLE):
		return true
	return false
