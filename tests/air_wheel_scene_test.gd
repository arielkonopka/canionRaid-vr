extends SceneTree
## Kierownica w powietrzu na prawdziwym aucie (bez gogli): układ wieńca
## z StuntCar.steering_frame() i obrót wizualnej kierownicy 1:1.
## Obie ręce na 9:00 i 3:00, obrót o 60° zgodnie z ruchem wskazówek zegara
## z widoku kierowcy -> skręt w prawo, a punkt wieńca z 3:00 schodzi w dół.
##   godot --headless --xr-mode off -s res://tests/air_wheel_scene_test.gd </dev/null

var main
var car: StuntCar
var f := 0
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _process(_d: float) -> bool:
	f += 1
	if f < 5:
		return false
	var fr: Array = car.steering_frame()
	_check(not fr.is_empty(), "auto ma kierownicę")
	if fr.is_empty():
		return _end()
	var c: Vector3 = fr[0]
	var r: Vector3 = fr[1]
	var u: Vector3 = fr[2]
	var eye: Vector3 = car.seat.global_position
	_check(r.dot(car.global_basis.x) > 0.9, "'w prawo' = prawa strona auta (%.2f)" % r.dot(car.global_basis.x))
	_check(u.dot(Vector3.UP) > 0.3, "'w górę' = góra wieńca (%.2f)" % u.dot(Vector3.UP))
	_check(r.cross(u).dot(eye - c) > 0.0, "oś wieńca w stronę kierowcy")
	var aw := AirWheel.new()
	var rad := 0.19
	var steps := 30
	var s := 0.0
	for i in range(steps + 1):
		var th := deg_to_rad(60.0) * i / steps        # zgodnie z zegarem z widoku kierowcy
		var rp := c + (r * cos(th) - u * sin(th)) * rad
		var lp := c - (r * cos(th) - u * sin(th)) * rad
		s = aw.update([[lp, true], [rp, true]], c, r, u, 1.0 / 72.0)
	_check(s > 0.0 and absf(aw.angle - 60.0) < 1.0, "obrót o 60° zgodnie z zegarem = skręt w prawo (%.2f, %.0f°)" % [s, aw.angle])
	# Wizualnie: wieniec obrócony o kąt rąk, punkt z 3:00 w dół.
	car.steering_wheel_deg = aw.angle
	var sw: Node3D = car._steering_wheel
	var before := (sw.global_transform * Vector3.RIGHT).y
	car._visual_step(0.0)
	var after := (sw.global_transform * Vector3.RIGHT).y
	_check(after < before - 0.01, "wieniec w kokpicie kręci się z rękami (3:00 w dół: %.3f -> %.3f)" % [before, after])
	return _end()


func _end() -> bool:
	print("air_wheel_scene_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
	return true
