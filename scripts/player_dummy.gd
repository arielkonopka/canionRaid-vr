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
var _thigh_l := -1
var _shin_l := -1
var _foot_l := -1
var _thigh_l_rest: Quaternion
var _shin_l_rest: Quaternion
var _foot_l_rest: Quaternion
var _clutch := 0.0
## Lewa noga na sprzęgle (manual): kolano się prostuje (łydka), udo
## opada, żeby kostka nie poszła w górę po łuku, stopa wciska pedał.
## Kąty z pomiaru kości (tests/dummy_clutch_test.gd): kostka ~4 cm do
## przodu na tej samej wysokości, palce ~2 cm w dół. Sam wyprost kolana
## unosił kostkę o 19 cm, samo udo opuszczało ją i cofało.
const CLUTCH_THIGH_DEG := 20.0
const CLUTCH_SHIN_DEG := -40.0
const CLUTCH_FOOT_DEG := 40.0
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
	_thigh_l = skel.find_bone("thigh.L")
	_shin_l = skel.find_bone("shin.L")
	_foot_l = skel.find_bone("foot.L")
	if _thigh_l >= 0:
		_thigh_l_rest = skel.get_bone_pose_rotation(_thigh_l)
	if _shin_l >= 0:
		_shin_l_rest = skel.get_bone_pose_rotation(_shin_l)
	if _foot_l >= 0:
		_foot_l_rest = skel.get_bone_pose_rotation(_foot_l)
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


## clutch: wciśnięcie sprzęgła 0..1 (StuntCar.clutch_pedal, manual).
func update(throttle: float, brake: float, delta: float, clutch := 0.0) -> void:
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
		# Dodatni kąt = palce w dół (pomiar kości w dummy_clutch_test; -22°
		# unosiło palce o 3,5 cm przy wciśniętym gazie).
		skel.set_bone_pose_rotation(_foot_r, _foot_rest * Quaternion(Vector3.RIGHT, deg_to_rad(22.0) * _press))
	# Lewa stopa: sprzęgło szybko w dół (zmiana biegu trwa ~0,2 s), wolniej
	# w górę - jak noga kierowcy.
	var rate := 14.0 if clutch > _clutch else 6.0
	_clutch = move_toward(_clutch, clampf(clutch, 0.0, 1.0), rate * delta)
	if _thigh_l >= 0:
		skel.set_bone_pose_rotation(_thigh_l, _thigh_l_rest * Quaternion(Vector3.RIGHT, deg_to_rad(CLUTCH_THIGH_DEG) * _clutch))
	if _shin_l >= 0:
		skel.set_bone_pose_rotation(_shin_l, _shin_l_rest * Quaternion(Vector3.RIGHT, deg_to_rad(CLUTCH_SHIN_DEG) * _clutch))
	if _foot_l >= 0:
		skel.set_bone_pose_rotation(_foot_l, _foot_l_rest * Quaternion(Vector3.RIGHT, deg_to_rad(CLUTCH_FOOT_DEG) * _clutch))
