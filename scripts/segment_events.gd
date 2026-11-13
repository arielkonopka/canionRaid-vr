class_name SegmentEvents
extends RefCounted

## Zdarzenia odcinków (bajt b3 kodu SegmentCode; inbox
## 2026-11-13-urozmaicenia-plan-i-kod-odcinka, etap 1). Kod odcinka jest
## ukryty przed graczem (ustalenie użytkownika) - tylko log "ODCINEK ...".
##
## Najważniejsze: auto nie może pojawić się w polu widzenia, a przed autem
## gracza widać do TrafficZone.FAR_VIEW_DIST (2 km). Wolna przeszkoda
## postawiona 2 km przed graczem jest doganiana dopiero po kilku km, więc
## zdarzenie wyzwala się wg PRZEWIDYWANEGO SPOTKANIA: przeszkoda o prędkości
## s (ułamek prędkości gracza; ujemna = jedzie na gracza) postawiona HIDE_DIST
## przed graczem spotka go po HIDE_DIST / (1 - s) metrach jazdy gracza -
## wyzwalamy, gdy to wypada MEET_IN m w głąb odcinka (lead_for).
## Pościg od tyłu startuje przy wjeździe w odcinek (za graczem, poza
## lusterkiem), korek to okno gęstości w TrafficZone.
##
## Scena (xr_main) udostępnia: _spawn_bot, _spawn_oncoming, _bots,
## _oncoming, _drv, _can_vanish, feud, _bot_gang, _gang_paint, hwy_lane_off,
## _traffic, _score_pay, score, race_time, camera, car.

const HIDE_DIST := 2100.0             # > TrafficZone.FAR_VIEW_DIST
const MEET_IN := 300.0                # [m] spotkanie w głąb odcinka
const LOOKAHEAD := 8                  # ile odcinków naprzód sprawdzać
const EVENT_BOT_CAP := 16             # więcej botów - zdarzenie przepada
const AMBUSH_TRIGGER := 60.0          # [m] gracz tak blisko - zasadzka rusza
const BLOCK_TRIGGER := 35.0           # [m] gracz za blokadą - zajeżdżanie
const WRONG_WARN := 600.0             # [m] zapowiedź pod prąd (>= 4 s przy 140 km/h)
## Prędkość przeszkody jako ułamek limitu (spotkanie i speed_k bota).
const SPEED := {1: 0.6, 2: -1.0, 3: 0.0, 5: 0.6, 6: 0.75, 7: 0.5}

var code: SegmentCode
var main
var rng := RandomNumberGenerator.new()
## k -> wynik ("ok", "przepadło: ...") - do testów i logu.
var done := {}
## Zdarzenie wymuszone w teście: k -> [event, ev_level].
var forced := {}
var _cur_k := -1
var _jam_k := -1
var _horn_t := 0.0


func _init(p_code: SegmentCode, p_main, seed_v := 1) -> void:
	code = p_code
	main = p_main
	rng.seed = seed_v


## Odcinek k z ewentualnym wymuszeniem (test).
func seg(k: int) -> Dictionary:
	var s: Dictionary = code.segment(k)
	if forced.has(k):
		s = s.duplicate()
		s["event"] = int(forced[k][0])
		s["ev_level"] = int(forced[k][1])
	return s


## Faza odcinka gracza: w "rest" nic wrogiego nowego (ekstremista, waśnie,
## scenki z naprzeciwka).
func calm_at(d: float) -> bool:
	return seg(code.index_at(d))["phase"] == "rest"


## Droga gracza do spotkania z przeszkodą `gap` m przed nim, gdy przeszkoda
## jedzie s x prędkości gracza (s < 0: na gracza). INF - nie dogoni.
static func lead_for(s: float, gap: float) -> float:
	var rel := 1.0 - s
	return INF if rel <= 0.05 else gap / rel


func step(delta: float) -> void:
	var p: float = main._last_safe_dist
	var k := code.index_at(p)
	if k != _cur_k:
		_cur_k = k
		print("ODCINEK ", code.describe(k), (" [wymuszone zdarzenie %s]" % SegmentCode.EVENTS[int(forced[k][0])]) if forced.has(k) else "")
	for kk in range(k, k + LOOKAHEAD):
		if done.has(kk):
			continue
		var s := seg(kk)
		var ev := int(s["event"])
		if ev == 0:
			continue
		var start := kk * SegmentCode.SEG_LEN
		var end := start + SegmentCode.SEG_LEN
		if p > end:
			done[kk] = "przepadło: odcinek minięty"
			continue
		if _due(ev, p, start):
			var r := _start(kk, ev, int(s["ev_level"]), start, end)
			if r != "":
				done[kk] = r
				print("ZDARZENIE k %d %s: %s" % [kk, SegmentCode.EVENTS[ev], r])
	_update_active(delta)


## Czy już pora postawić zdarzenie (gracz w p, odcinek od `start`).
func _due(ev: int, p: float, start: float) -> bool:
	match ev:
		1:   # korek: okno gęstości, zanim ruch zacznie dokładać auta (700-1500 m)
			return p >= start - TrafficZone.AHEAD
		4:   # pościg od tyłu: przy wjeździe w odcinek
			return p >= start
	var lead := lead_for(float(SPEED.get(ev, 0.6)), HIDE_DIST)
	return p + minf(lead, 20000.0) >= start + MEET_IN


## Postawienie zdarzenia. "" = jeszcze nie (np. miejsce widoczne) - próba
## w następnym kroku; inny tekst = wynik (ok / przepadło).
func _start(k: int, ev: int, lvl: int, start: float, end: float) -> String:
	var p: float = main._last_safe_dist
	if ev == 1:
		main._traffic_ensure()
		main._traffic.jam_from = start
		main._traffic.jam_to = end
		_jam_k = k
		return "ok (korek %.0f-%.0f m)" % [start, end]
	if ev != 2 and main._bots.size() >= EVENT_BOT_CAP:
		return "przepadło: limit botów"
	match ev:
		2:
			return _wrong_way(p, lvl)
		3:
			return _ambush(p, lvl)
		4:
			return _chase(p, lvl)
		5:
			return _blockade(p, lvl)
		6:
			return _feud(p, lvl)
		7:
			return _truck(p, lvl)
	return "przepadło: nieznane"


## Miejsce przed graczem poza wzrokiem (-1 = brak: trasy jeszcze nie ma albo
## widać - spróbujemy w następnym kroku).
func _hidden_ahead(p: float, lane: int) -> float:
	var d := p + HIDE_DIST + rng.randf_range(0.0, 150.0)
	if main.track.is_gap_at(d) or d > main.track.total_length() - 30.0:
		return -1.0
	var xf: Transform3D = main.track.transform_at_distance(d)
	if not main._can_vanish(xf.origin + xf.basis.x * main.hwy_lane_off(lane)):
		return -1.0
	return d


func _limit(d: float) -> float:
	var smp: Dictionary = main.track.sample_at(d)
	return 110.0 if smp.is_empty() else float(smp["limit"])


## Bot zdarzenia: spawn i ustawienia kierowcy; null - nie wyszło.
func _bot(d: float, lane: int, k_speed: float, ev_name: String) -> StuntCar:
	var n: int = main._bots.size()
	main._spawn_bot(d, lane, _limit(d) * maxf(k_speed, 0.05))
	if main._bots.size() == n:
		return null
	var b: StuntCar = main._bots[-1]
	var drv: BotDriver = main._drv(b)
	drv.speed_k = k_speed
	drv.event = ev_name
	return b


func _wrong_way(p: float, _lvl: int) -> String:
	var d := _hidden_ahead(p, 1)
	if d < 0.0:
		return ""
	var v := _limit(d) * rng.randf_range(0.95, 1.1)
	var n: int = main._oncoming.size()
	main._spawn_oncoming(d, 0, v)
	if main._oncoming.size() == n:
		return ""
	var o: OncomingCar = main._oncoming[-1]
	o.wrong_way = true
	o.car.global_transform = main._wrong_way_pose(main.track.transform_at_distance(d), o.car.wheel_radius)
	return "ok (pod prąd %.0f m przed graczem, %.0f km/h)" % [d - p, v]


func _ambush(p: float, lvl: int) -> String:
	var d := _hidden_ahead(p, 0)
	if d < 0.0:
		return ""
	var nb := 1 + (1 if lvl >= 2 else 0)
	for i in range(nb):
		var di := d + i * 25.0
		var b := _bot(di, 0, 0.0, "ambush")
		if b == null:
			break
		var drv: BotDriver = main._drv(b)
		# Na pasie awaryjnym, stoi (zamrożony - bez kosztu fizyki).
		var xf: Transform3D = main.track.transform_at_distance(di)
		b.global_transform = Transform3D(xf.basis, xf.origin + xf.basis.x * drv._x_shoulder_off() + xf.basis.y * 0.9)
		b.linear_velocity = Vector3.ZERO
		b.freeze = true
		drv.hold = true
	return "ok (zasadzka, %d aut, %.0f m przed graczem)" % [nb, d - p]


func _chase(p: float, lvl: int) -> String:
	var n := 0
	for i in range(1 + lvl):
		var d := p - rng.randf_range(350.0, 500.0) - i * 40.0
		var xf: Transform3D = main.track.transform_at_distance(d)
		if not main._can_vanish(xf.origin + xf.basis.x * main.hwy_lane_off(1)):
			continue
		var b := _bot(d, 1, 1.2, "chase")
		if b == null:
			continue
		main._drv(b).enrage("chase")
		n += 1
	return "ok (pościg, %d aut)" % n if n > 0 else ""


func _blockade(p: float, _lvl: int) -> String:
	var d := _hidden_ahead(p, 1)
	if d < 0.0:
		return ""
	var k := float(SPEED[5])
	var a := _bot(d, 0, k, "blockade")
	var b := _bot(d + 3.0, 1, k, "blockade")
	if a == null or b == null:
		return "przepadło: spawn"
	return "ok (blokada %.0f m przed graczem)" % (d - p)


func _feud(p: float, lvl: int) -> String:
	var d := _hidden_ahead(p, 0)
	if d < 0.0:
		return ""
	var ga: int = rng.randi() % main.GANGS
	var gb: int = (ga + 1 + rng.randi() % (main.GANGS - 1)) % main.GANGS
	main.feud.set_hostile(ga, gb, true)
	var n := 0
	for i in range(1 + lvl):
		for g in [ga, gb]:
			var b := _bot(d + n * 30.0, n % 2, float(SPEED[6]), "feud")
			if b == null:
				continue
			var id := b.get_instance_id()
			main.feud.remove_bot(id, main.race_time, false)
			main._bot_gang[id] = g
			main.feud.add_bot(id, g)
			if main._gs:
				b.set_paint(main._gs.PAINTS[main._gang_paint(g)])
			n += 1
	return "ok (waśń gangów %d i %d, %d aut)" % [ga, gb, n]


func _truck(p: float, lvl: int) -> String:
	var d := _hidden_ahead(p, 0)
	if d < 0.0:
		return ""
	var t := _bot(d, 0, float(SPEED[7]), "truck")
	if t == null:
		return "przepadło: spawn"
	# Za nią 1-2 auta, które ją wyprzedzają lewym pasem.
	for i in range(1 + mini(lvl, 1)):
		_bot(d - 60.0 - i * 45.0, 1, 0.95, "truck_follow")
	return "ok (wolne auto %.0f m przed graczem)" % (d - p)


## Zdarzenia w toku: zasadzka rusza, blokada zajeżdża, pod prąd ostrzega
## i daje punkty za minięcie, korek się kończy.
func _update_active(delta: float) -> void:
	var p: float = main._last_safe_dist
	if _jam_k >= 0 and p > (_jam_k + 1) * SegmentCode.SEG_LEN + TrafficZone.BEHIND:
		main._traffic.jam_from = INF
		main._traffic.jam_to = -INF
		_jam_k = -1
	for b in main._bots:
		var drv: BotDriver = main._drv(b)
		if drv.event == "":
			continue
		var gap: float = drv.dist - p
		if drv.hold and gap < AMBUSH_TRIGGER:
			drv.hold = false
			b.freeze = false
			drv.enrage("ambush")
			print("ZASADZKA: rusza %.0f m przed graczem" % gap)
		elif drv.event == "blockade" and drv.rage < 0.05 and gap > 0.0 and gap < BLOCK_TRIGGER:
			drv.enrage("blockade")
	_horn_t -= delta
	for o in main._oncoming:
		if not o.wrong_way or not is_instance_valid(o.car):
			continue
		var c: StuntCar = o.car
		var ahead: float = o.dist - p
		if ahead < WRONG_WARN and ahead > -20.0:
			# Zapowiedź: miga długimi, trąbi; spokojne auta przed graczem
			# zjeżdżają na prawy pas.
			c.set_high_beam(1.0 if fmod(main.race_time, 0.5) < 0.25 else 0.0)
			if _horn_t <= 0.0:
				_horn_t = 1.2
				BotDriver.horn_on(c).play()
			for b in main._bots:
				var drv: BotDriver = main._drv(b)
				if drv.event == "" and drv.rage < 0.05 and drv.dist > p and drv.dist < o.dist:
					drv.lane = 0
		if absf(ahead) < 15.0:
			var lat := absf((c.global_position - main.car.global_position).dot(main.car.global_basis.x)) - 1.8
			o.min_gap = minf(o.min_gap, maxf(lat, 0.0))
		if not o.passed and ahead < -6.0:
			o.passed = true
			c.set_high_beam(0.0)
			# Bez kontaktu (odstęp boków > 5 cm; po zbliżeniu auto i tak
			# przechodzi na fizykę - loose nie znaczy zderzenia).
			if o.min_gap < INF and o.min_gap > 0.05:
				var pts := ExtremistBrain.pass_points(o.min_gap)
				main._score_pay(main.score.award_free("wrongway_pass", pts, main.race_time, "MINĄŁEŚ KIEROWCĘ POD PRĄD"))
