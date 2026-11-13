extends SceneTree
## Nogi manekina gracza: lewa na sprzęgle (PlayerDummy.update(..., clutch)):
## wciśnięte sprzęgło przesuwa lewą kostkę do przodu (oś -Z auta) bez
## unoszenia, palce w dół (pedał),
## prawa noga bez zmian. Plus StuntCar.clutch_pedal: automat 0, manual
## przy zmianie biegu 1.
##   godot --headless --xr-mode off -s res://tests/dummy_clutch_test.gd </dev/null

var fails := 0
var car: StuntCar
var pd: PlayerDummy
var f := 0
var foot0: Vector3
var toe0: Vector3
var foot_r0: Vector3


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	car = StuntCar.new()
	root.add_child(car)
	car.freeze = true


func _bone(name: String, tail := false) -> Vector3:
	var i := pd.skel.find_bone(name)
	var g := pd.skel.get_bone_global_pose(i)
	var p := g.origin
	if tail:
		# Koniec kości: początek pierwszego dziecka (palce) albo 0,15 m wzdłuż Y.
		var ch := pd.skel.get_bone_children(i)
		p = pd.skel.get_bone_global_pose(ch[0]).origin if ch.size() > 0 else g * Vector3(0, 0.15, 0)
	return car.global_transform.affine_inverse() * (pd.skel.global_transform * p)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var a := Node3D.new()
		var b := Node3D.new()
		root.add_child(a)
		root.add_child(b)
		pd = PlayerDummy.new()
		pd.setup(car, a, b)
	if f < 5:
		return false
	if f == 5:
		pd.update(0.0, 0.0, 1.0, 0.0)
	if f == 7:
		foot0 = _bone("foot.L")
		toe0 = _bone("foot.L", true)
		foot_r0 = _bone("foot.R")
		pd.update(0.0, 0.0, 1.0, 1.0)
	if f == 9:
		var foot1 := _bone("foot.L")
		var toe1 := _bone("foot.L", true)
		var dr := _bone("foot.R").distance_to(foot_r0)
		print("  kostka L: %s -> %s, palce L: %s -> %s" % [foot0, foot1, toe0, toe1])
		_check(foot1.z < foot0.z - 0.03, "kostka do przodu o %.3f m" % (foot0.z - foot1.z))
		_check(foot1.y < foot0.y + 0.02, "kostka nie w górę (%.3f m)" % (foot1.y - foot0.y))
		_check(toe1.y < toe0.y - 0.015, "palce w dół o %.3f m (pedał)" % (toe0.y - toe1.y))
		_check(dr < 0.001, "prawa noga bez zmian (%.4f m)" % dr)
		# Prawa stopa: gaz wciśnięty - palce w dół.
		var rtoe0 := _bone("foot.R", true)
		pd.update(1.0, 0.0, 1.0, 1.0)
		var rtoe1 := _bone("foot.R", true)
		_check(rtoe1.y < rtoe0.y - 0.015, "prawa stopa: gaz - palce w dół o %.3f m" % (rtoe0.y - rtoe1.y))
		car.automatic = true
		_check(car.clutch_pedal() == 0.0, "automat - sprzęgło 0")
		car.automatic = false
		car._shift_timer = 0.2
		_check(car.clutch_pedal() == 1.0, "manual, zmiana biegu - sprzęgło 1")
		car._shift_timer = 0.0
		car._launching = false
		_check(car.clutch_pedal() == 0.0, "manual, w jeździe - sprzęgło 0")
		print("dummy_clutch_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
		quit(1 if fails else 0)
		return true
	return false
