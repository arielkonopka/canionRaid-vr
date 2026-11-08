extends Node3D
class_name GazeFollow

## Menu podążające za wzrokiem (prośba użytkownika: menu startowe i
## warsztatowe pojawiały się za wysoko i w stałym miejscu).
## Węzeł trzyma się `distance` m przed głową, na wysokości oczu + `height`.
## Za obrotem głowy idzie leniwie: dopiero gdy wzrok odejdzie o więcej niż
## DEADZONE, menu płynnie wraca na wprost - nie "przykleja się" do twarzy,
## więc da się na nie patrzeć ruchem oczu i czytać dolne wiersze.
## Dzieci (napisy) są zwrócone przodem (+Z) do gracza.

const DEADZONE := deg_to_rad(25.0)
const SETTLE := deg_to_rad(3.0)
const TURN_RATE := 4.0                # 1/s - szybkość powrotu na wprost
const HEIGHT_RATE := 3.0

var camera: Node3D
var distance := 2.0
var height := 0.0
var _yaw := 0.0
var _y := 0.0
var _follow := false
var _placed := false


func _ready() -> void:
	top_level = true


## Natychmiast na wprost wzroku (np. przy otwarciu menu).
func snap() -> void:
	_placed = false


func _process(delta: float) -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var head := camera.global_position
	var f := -camera.global_basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	var head_yaw := atan2(-f.x, -f.z)
	if not _placed:
		_placed = true
		_yaw = head_yaw
		_y = head.y + height
	var diff := angle_difference(_yaw, head_yaw)
	if absf(diff) > DEADZONE:
		_follow = true
	if _follow:
		_yaw = lerp_angle(_yaw, head_yaw, minf(TURN_RATE * delta, 1.0))
		if absf(angle_difference(_yaw, head_yaw)) < SETTLE:
			_follow = false
	_y = lerpf(_y, head.y + height, minf(HEIGHT_RATE * delta, 1.0))
	var b := Basis(Vector3.UP, _yaw)
	var p := head + b * Vector3(0.0, 0.0, -distance)
	p.y = _y
	global_transform = Transform3D(b, p)
