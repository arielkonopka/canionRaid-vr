extends SceneTree
## "Trasa się skończyła" (zgłoszenia 2026-11-09..11, wraca co jakiś czas).
## Auto przesuwane wzdłuż autostrady (bez fizyki jazdy), dwie awarie:
##  1. co 2 s `_current` cofany na 0 - okno szukania zostaje w tyle
##     (hipoteza chmury: lot nad wcześniejszym kawałkiem);
##  2. `_watch_track` w ogóle nie działa (race_state FINISHED - zastępuje
##     błąd skryptu przed update_progress, hipoteza chmury dla "na prostej").
## Za każdym razem przed autem ma być zbudowana trasa (> 300 m).
##   godot --headless --xr-mode off -s res://tests/endless_progress_test.gd </dev/null

var main
var f := 0
var t := 0.0
var fails := 0
var min_ahead := INF
var min_ahead2 := INF
const V := 60.0
const PHASE1 := 70.0     # [s] ~4,2 km
const PHASE2 := 120.0    # [s] ~7,2 km - dłużej niż zbudowana trasa przed autem


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	gs.track_mode = "autostrada"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		main.race_state = main.Race.RACING
		main._traffic_t = 1e9
		main._bot_timer = 1e9
	if f <= 5:
		return false
	t += delta
	var d := 300.0 + t * V
	var tr = main.track
	if d > tr.total_length() - 5.0:
		_check(false, "auto dojechało do końca trasy przy %.0f m (%s)" % [d, tr.debug_state()])
		return _finish()
	var xf: Transform3D = tr.transform_at_distance(d)
	main.car.global_transform = Transform3D(xf.basis, xf.origin + xf.basis.y * 0.7)
	main.car.linear_velocity = -xf.basis.z * V
	var ahead: float = tr.total_length() - d
	if t < PHASE1:
		if fmod(t, 2.0) < delta:
			tr._current = 0
		if t > 3.0:
			min_ahead = minf(min_ahead, ahead)
	else:
		main.race_state = main.Race.FINISHED
		min_ahead2 = minf(min_ahead2, ahead)
	if t >= PHASE1 + PHASE2:
		return _finish()
	return false


func _finish() -> bool:
	_check(min_ahead > 300.0, "cofany _current: przed autem zawsze trasa (min %.0f m)" % min_ahead)
	# Bez _watch_track `_last_safe_dist` stoi - zostaje sama linia prosta
	# (ENSURE_R 300 m), więc przed autem bywa mniej niż w fazie 1.
	_check(min_ahead2 > 150.0, "bez _watch_track: trasa dalej rośnie (min %.0f m)" % min_ahead2)
	print("endless_progress_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
