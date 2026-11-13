extends SceneTree
## Ręce manekina gracza (użytkownik 2026-11-13: "dłonie odrywają się od
## rąk"): nadgarstek manekina (koniec łańcucha IK) przy celu - nadgarstku
## kontrolera - także gdy kontroler jest dalej, niż sięga ramię
## (wyciągnięcie ręki, gracz pochylony). Blisko - zgięty łokieć, bez
## rozciągania.
##   godot --headless --xr-mode off -s res://tests/dummy_arm_test.gd </dev/null

var fails := 0
var car: StuntCar
var pd: PlayerDummy
var ctrl: Array[Node3D] = []
var f := 0
var step := 0
## Nadgarstek po IK: get_bone_global_pose poza sygnałem skeleton_updated
## zwraca pozę bez modyfikatorów (TwoBoneIK3D) - czytamy w sygnale.
var hand_ik := Vector3.ZERO


func _on_skel_updated() -> void:
	hand_ik = _wpos("hand.R")
## [nazwa, odległość celu od barku jako ułamek długości ramienia, maks. przerwa]
const CASES := [["blisko (0,7 ramienia)", 0.7, 0.03], ["prawie wyprost (0,95)", 0.95, 0.03],
		["za daleko (1,3)", 1.3, 0.03], ["dużo za daleko (1,8)", 1.8, 0.0]]


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	car = StuntCar.new()
	root.add_child(car)
	car.freeze = true


func _wpos(bone: String) -> Vector3:
	var i := pd.skel.find_bone(bone)
	return pd.skel.global_transform * pd.skel.get_bone_global_pose(i).origin


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		for k in range(2):
			var n := Node3D.new()
			root.add_child(n)
			ctrl.append(n)
		pd = PlayerDummy.new()
		pd.setup(car, ctrl[0], ctrl[1])
		pd.skel.skeleton_updated.connect(_on_skel_updated)
	if f < 5:
		return false
	# Co 4 klatki nowy przypadek: kontroler prawej ręki przed barkiem, w dół
	# i do przodu, na zadanej odległości (wzdłuż -Z kontrolera jest dłoń,
	# nadgarstek WRIST_BACK za nią).
	var c: Array = CASES[mini(step, CASES.size() - 1)]
	var shoulder := _wpos("upper_arm.R")
	var reach: float = pd.arm_length(1)
	var dir := (-car.global_basis.z * 0.8 - car.global_basis.y * 0.5).normalized()
	var wrist := shoulder + dir * reach * float(c[1])
	ctrl[1].global_transform = Transform3D(Basis.looking_at(dir, car.global_basis.y), wrist + dir * PlayerDummy.WRIST_BACK)
	ctrl[0].global_transform = Transform3D(Basis.looking_at(dir, car.global_basis.y), _wpos("upper_arm.L") + dir * reach * 0.7 + dir * PlayerDummy.WRIST_BACK)
	pd.update(0.0, 0.0, 1.0)
	if (f - 5) % 4 == 3:
		var hand := hand_ik
		var gap := hand.distance_to(wrist)
		var sc: float = pd.skel.get_bone_pose_scale(pd.skel.find_bone("upper_arm.R")).y
		print("  %s: przerwa %.3f m, rozciągnięcie %.2f" % [c[0], gap, sc])
		if float(c[2]) > 0.0:
			_check(gap < float(c[2]), "%s - nadgarstek przy kontrolerze" % c[0])
		else:
			_check(sc <= PlayerDummy.ARM_STRETCH_MAX + 1e-3, "%s - rozciągnięcie najwyżej %.1f" % [c[0], PlayerDummy.ARM_STRETCH_MAX])
		if step == 0:
			_check(sc < 1.001, "blisko - bez rozciągania")
		step += 1
		if step >= CASES.size():
			print("dummy_arm_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			quit(1 if fails else 0)
			return true
	return false
