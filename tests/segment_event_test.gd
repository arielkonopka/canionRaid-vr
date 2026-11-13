extends SceneTree
## Zdarzenia odcinków w grze (SegmentEvents, inbox urozmaicenia-plan-i-kod-
## odcinka pkt 5): autostrada, gracz prowadzony ~130 km/h prawym pasem.
## W odcinkach 3, 5, ..., 15 wymuszone zdarzenia 1..7 (korek, pod prąd, zasadzka,
## pościg, blokada, waśń, ciężarówka); dalej kod sam (do LIMIT_KM).
## Sprawdza: każde wymuszone zdarzenie postawione, zasadzka rusza, pod prąd
## mija gracza, żadne auto nie pojawia się ani nie znika w polu widzenia,
## botów <= limit, w odcinkach "rest" nie pojawia się ekstremista.
## Wypisuje spotkania na km (auta w naszą stronę : z naprzeciwka).
##   godot --headless --xr-mode off -s res://tests/segment_event_test.gd -- [km] </dev/null

const FIRST_K := 3
const SPEED := 36.0                    # [m/s] gracz
var limit_km := 20.0
var main
var f := 0
var fails := 0
var start_d := 0.0
var max_bots := 0
var seen_vis := {}                     # id -> widoczne w poprzedniej klatce
var pop_in := 0
var pop_out := 0
var pop_info: Array = []
var osk_out := 0
var ambush_go := false
var wrong_passed := false
var x_in_rest := 0
var had_x := false
var same_pass := 0
var onc_pass := 0
var rel := {}                          # id -> czy przed graczem (do liczenia mijań)


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	gs.weather = "dry"
	gs.crash_replay = false
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		limit_km = float(a[0])
	EndlessTrack.test_seed = 33
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


var last_desc := {}                    # id -> opis z ostatniej klatki


func _ids() -> Dictionary:
	var out := {}
	for b in main._bots:
		out[b.get_instance_id()] = b
		var drv: BotDriver = main._drv(b)
		var dead: bool = b.is_wrecked or drv.flipped_time > 2.5 or b.global_position.y < -40.0
		last_desc[b.get_instance_id()] = "bot %s zd=%s szał=%.1f d=%.0f%s" % [b.name, drv.event, drv.rage, drv.dist - main._last_safe_dist, " WRAK" if dead else ""]
	for o in main._oncoming:
		out[(o.car as Node).get_instance_id()] = o.car
		last_desc[(o.car as Node).get_instance_id()] = "naprzeciw %s osk=%s pp=%s loose=%s d=%.0f" % [o.car.name, o.osk, o.wrong_way, o.loose, o.dist - main._last_safe_dist]
	return out


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main.car.place(main._safe_pose(300.0))
		main.car._settle_t = 0.0
		main._last_safe_dist = 300.0
		start_d = 300.0
	if f < 8:
		return false
	if f == 8:
		main._update_segments(0.0)
		# Co 2 odcinki - w grze reżyser rozrzedza zdarzenia; co odcinek
		# nakładały się i pościg przepadał na limicie botów.
		for i in range(7):
			main.segments.forced[FIRST_K + 2 * i] = [i + 1, 1]
	# Bez utraty życia (gracz prowadzony na siłę - zderzenia z blokadą itp.).
	main._grace_t = 1.0
	var cxf: Transform3D = main.track.transform_at_distance(main._last_safe_dist + 2.0)
	var off: float = (main.car.global_position - cxf.origin).dot(cxf.basis.x) - main.hwy_lane_off(0)
	main.car.global_basis = cxf.basis
	main.car.linear_velocity = -cxf.basis.z * SPEED - cxf.basis.x * off * 2.0 + cxf.basis.y * minf(main.car.linear_velocity.dot(cxf.basis.y), 0.0)
	main.car.angular_velocity = Vector3.ZERO
	var p: float = main._last_safe_dist
	max_bots = maxi(max_bots, main._bots.size())
	# Pojawienie / zniknięcie w polu widzenia (głowa + lusterko).
	var head: Vector3 = main.camera.global_position
	var hf: Vector3 = -main.camera.global_basis.z
	var cf: Vector3 = -main.car.global_basis.z
	var now := _ids()
	for id in now:
		var c: Node3D = now[id]
		var vis: bool = c.visible and TrafficZone.visible(head, hf, cf, c.global_position)
		if not seen_vis.has(id) and vis and f > 40:
			pop_in += 1
			pop_info.append("pojawienie %s %.0f m (%s)" % [c.name, c.global_position.distance_to(head), last_desc.get(id, "")])
		seen_vis[id] = vis
	for id in seen_vis.keys():
		if not now.has(id):
			rel.erase(id)
			# Wrak wybucha - to ma być widać. Scenka z naprzeciwka (osk) sama
			# chowa auto (stan "hidden" w OncomingSkirmish) - osobno, zgłoszone.
			var desc := str(last_desc.get(id, ""))
			if seen_vis[id] and desc.contains("osk=") and not desc.contains("osk= "):
				osk_out += 1
				pop_info.append("(scenka osk) " + desc)
			elif seen_vis[id] and not desc.ends_with("WRAK"):
				pop_out += 1
				pop_info.append("zniknięcie " + desc)
			seen_vis.erase(id)
	# Mijania (auta w naszą stronę wyprzedzone albo wyprzedzające; z naprzeciwka).
	# Histereza 10 m: auto jadące obok gracza nie liczy się wiele razy.
	for b in main._bots:
		var id: int = b.get_instance_id()
		var dd: float = main._drv(b).dist - p
		if absf(dd) < 10.0:
			continue
		var ahead: bool = dd > 0.0
		if rel.has(id) and rel[id] != ahead:
			same_pass += 1
		rel[id] = ahead
	for o in main._oncoming:
		var id: int = (o.car as Node).get_instance_id()
		var ahead2: bool = o.dist > p
		if rel.has(id) and rel[id] and not ahead2:
			onc_pass += 1
			if o.wrong_way:
				wrong_passed = true
		rel[id] = ahead2
	for b in main._bots:
		var drv: BotDriver = main._drv(b)
		if drv.event == "ambush" and not drv.hold:
			ambush_go = true
	# Ekstremista w odcinku "rest".
	var x = main._extremist
	if x and not had_x and main.segments.calm_at(p):
		x_in_rest += 1
	had_x = x != null
	if p - start_d > limit_km * 1000.0:
		return _end()
	return false


func _end() -> bool:
	var km: float = (main._last_safe_dist - start_d) / 1000.0
	print("  przejechane %.1f km, maks. botów %d" % [km, max_bots])
	for k in main.segments.done:
		print("  k %d %s: %s" % [k, SegmentCode.EVENTS[int(main.segments.seg(k)["event"])], main.segments.done[k]])
	for i in range(7):
		var k := FIRST_K + 2 * i
		var r: String = main.segments.done.get(k, "brak")
		_check(r.begins_with("ok"), "wymuszone %s (k %d): %s" % [SegmentCode.EVENTS[i + 1], k, r])
	_check(ambush_go, "zasadzka ruszyła")
	_check(wrong_passed, "kierowca pod prąd minął gracza")
	_check(max_bots <= SegmentEvents.EVENT_BOT_CAP + 4, "botów najwyżej %d (było %d)" % [SegmentEvents.EVENT_BOT_CAP + 4, max_bots])
	_check(pop_in == 0 and pop_out == 0, "w polu widzenia: pojawień %d, zniknięć %d %s" % [pop_in, pop_out, ""])
	for line in pop_info:
		print("    ", line)
	if osk_out > 0:
		print("  UWAGA: scenka z naprzeciwka schowała %d aut na widoku (OncomingSkirmish, nie zdarzenia odcinka)" % osk_out)
	_check(x_in_rest == 0, "ekstremista w odcinku rest: %d" % x_in_rest)
	print("  mijania na km: w naszą stronę %.2f, z naprzeciwka %.2f (1 : %.1f)" % [same_pass / km, onc_pass / km, onc_pass / maxf(same_pass, 1.0)])
	print("segment_event_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
