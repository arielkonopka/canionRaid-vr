class_name PlayerDummy
extends Node3D

## Gracz jako manekin crash-test (użytkownik 2026-11-12: "fajnie by było,
## gdyby gracz był tym manekinem ... a nie tylko dłonie"): tułów i nogi
## w fotelu, głowa ukryta (tam jest kamera), ramiona do kontrolerów
## (TwoBoneIK3D: bark - łokieć - nadgarstek, łokieć w dół i na zewnątrz),
## dłonie z kontrolerów (dummy_hand_L/R - właściwy obrót i chwyt), własne
## dłonie tułowia schowane. Prawa noga: przenosi się między gazem
## a hamulcem i wciska pedał wg spustów.
## Model: tools/prepare_dummy.py -> models/dummy/player_dummy.glb (poza
## siedząca = spoczynkowa, zero w biodrach, przód +Z - obracamy o 180°).

const SCENE := "res://models/dummy/player_dummy.glb"
## Oczy względem bioder (jak StuntCar.DUMMY_EYE, w układzie auta, przód -Z).
const EYE := Vector3(0.0, 0.77, 0.04)
## Nadgarstek za środkiem dłoni kontrolera (+Z kontrolera = do nadgarstka).
const WRIST_BACK := 0.07

var skel: Skeleton3D
var _ik: TwoBoneIK3D
var _targets: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _ctrl: Array[Node3D] = []
var _thigh_r := -1
var _foot_r := -1
var _thigh_rest: Quaternion
var _foot_rest: Quaternion
var _press := 0.0
var _brake_side := 0.0
## Powtórka wypadku: kontrolery z zapisu (w układzie auta), a nie z rąk
## gracza - ten stoi wtedy obok jako obserwator.
var replay_hands: Array[Transform3D] = []


static func available() -> bool:
	return ResourceLoader.exists(SCENE)


## car: auto gracza (siedzi na car.seat), left/right: kontrolery (albo
## dowolne węzły z pozycją dłoni).
func setup(car: StuntCar, left: Node3D, right: Node3D) -> void:
	name = "PlayerDummy"
	car.add_child(self)
	var model: Node3D = load(SCENE).instantiate()
	model.rotation = Vector3(0.0, PI, 0.0)          # przód modelu +Z -> auto -Z
	add_child(model)
	position = car.seat.position - EYE
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Głowa (kamera) i własne dłonie (są dłonie kontrolerów) schowane.
	for b in ["head", "hand.L", "hand.R"]:
		var i := skel.find_bone(b)
		if i >= 0:
			skel.set_bone_pose_scale(i, Vector3.ONE * 0.001)
	_ctrl = [left, right]
	_ik = TwoBoneIK3D.new()
	skel.add_child(_ik)
	_ik.setting_count = 2
	for k in range(2):
		var s := "L" if k == 0 else "R"
		var t := Node3D.new()
		t.name = "IKTarget" + s
		add_child(t)
		_targets.append(t)
		var p := Node3D.new()
		p.name = "IKPole" + s
		add_child(p)
		_poles.append(p)
		_ik.set_root_bone_name(k, "upper_arm." + s)
		_ik.set_middle_bone_name(k, "forearm." + s)
		_ik.set_end_bone_name(k, "hand." + s)
		_ik.set_target_node(k, _ik.get_path_to(t))
		_ik.set_pole_node(k, _ik.get_path_to(p))
	_thigh_r = skel.find_bone("thigh.R")
	_foot_r = skel.find_bone("foot.R")
	if _thigh_r >= 0:
		_thigh_rest = skel.get_bone_pose_rotation(_thigh_r)
	if _foot_r >= 0:
		_foot_rest = skel.get_bone_pose_rotation(_foot_r)


## Powtórka wypadku: widać głowę i dłonie tułowia (kamera jest poza autem,
## dłonie kontrolerów są wtedy przy obserwatorze). Pozy kontrolerów w układzie
## auta: replay_hands (dwie) albo [] = z rąk gracza.
func set_replay(on: bool) -> void:
	if skel == null:
		return
	for b in ["head", "hand.L", "hand.R"]:
		var i := skel.find_bone(b)
		if i >= 0:
			skel.set_bone_pose_scale(i, Vector3.ONE * (1.0 if on else 0.001))
	if not on:
		replay_hands.clear()


func update(throttle: float, brake: float, delta: float) -> void:
	if skel == null:
		return
	var car := get_parent() as StuntCar
	if car:
		position = car.seat.position - EYE      # model auta mógł zmienić fotel
	for k in range(2):
		var c := _ctrl[k]
		if c == null:
			continue
		var cxf := c.global_transform
		if replay_hands.size() == 2 and car:
			cxf = car.global_transform * replay_hands[k]
		# Cel IK: nadgarstek za środkiem dłoni kontrolera.
		var wrist := cxf * Vector3(0.0, 0.0, WRIST_BACK)
		_targets[k].global_position = wrist
		# Łokieć w dół i na zewnątrz (strona ręki) - biegun pod barkiem.
		var side := -1.0 if k == 0 else 1.0
		_poles[k].global_position = global_transform * Vector3(side * 0.6, 0.0, 0.2)
	# Prawa stopa: na hamulec (do środka), gdy hamulec mocniejszy niż gaz;
	# pedał wciśnięty wg spustu. Wygładzone - noga nie skacze.
	var to_brake := 1.0 if brake > throttle + 0.05 else 0.0
	_brake_side = move_toward(_brake_side, to_brake, 6.0 * delta)
	_press = move_toward(_press, maxf(throttle, brake), 8.0 * delta)
	if _thigh_r >= 0:
		skel.set_bone_pose_rotation(_thigh_r, _thigh_rest * Quaternion(Vector3.UP, deg_to_rad(9.0) * _brake_side))
	if _foot_r >= 0:
		skel.set_bone_pose_rotation(_foot_r, _foot_rest * Quaternion(Vector3.RIGHT, deg_to_rad(-22.0) * _press))
