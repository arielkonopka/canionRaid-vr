extends RefCounted
class_name WorldOrigin

## Przesuwanie początku świata (floating origin) dla trybu "Autostrada".
##
## PROBLEM: Godot z pakietu Debiana jest zbudowany z pojedynczą precyzją -
## Vector3, Transform3D, wierzchołki i fizyka (Jolt) liczą na float32.
## Trasa nie zawraca (MAX_YAW), więc pozycja auta rośnie liniowo z dystansem:
##   1-2 km -> krok float32 0,12 mm, 10 km -> ~1 mm, 100 km -> ~8 mm,
##   300 km -> ~31 mm.
## Już od kilkunastu km drży obraz w VR (głowa + auto), a kontakt kół
## z jezdnią i wierzchołki jezdni "schodkują" o milimetry-centymetry.
##
## ROZWIĄZANIE: gdy auto oddali się od zera o więcej niż THRESHOLD, cały
## świat (kawałki trasy, auta, efekty) przesuwa się o wielokrotność QUANTUM
## tak, żeby auto wróciło w pobliże zera. Prawdziwe położenie w świecie to
## pozycja lokalna + `offset` (offset trzymany w liczbach float GDScriptu -
## 64 bity, bez utraty precyzji przez tysiące km).
##
## QUANTUM to potęga dwójki, a współrzędne są małe (< ~6 km), więc błąd
## odejmowania w float32 to najwyżej jeden krok (~0,2-0,5 mm); dla auta
## (x między S/2 a 2S) odejmowanie jest dokładne. Styki kawałków trasy mogą
## się rozjechać o ułamek milimetra - mniej niż dziś na 10. km.
##
## Moduł nie zna sceny. Scena jazdy woła co krok fizyki (na początku
## _physics_process, PRZED sterowaniem):
##   var s := origin.check(car.global_position)
##   if s != Vector3.ZERO:
##       origin.apply(s, get_tree().get_nodes_in_group(WorldOrigin.GROUP))
##       ... poprawki pamiętanych pozycji (lista w docs/AUTOSTRADA.md) ...
## Węzły do przesuwania należą do grupy GROUP (najwyższe w hierarchii:
## kawałek trasy, auto, bot, auto z naprzeciwka, teren, horyzont, wybuch).
## Ich dzieci jadą z nimi.

const GROUP := "origin_shift"
## Przesunięcie, gdy auto jest dalej niż tyle od zera (w poziomie) [m].
const THRESHOLD := 2048.0
## Przesuwamy o wielokrotności tej wartości [m] (potęga dwójki).
const QUANTUM := 1024.0
## Okres wzorów w shaderach liczonych z pozycji w świecie (ground, concrete,
## rock, shale, ocean): parametr globalny WRAP_PARAM = offset mod WRAP -
## shader dodaje go do wpos, a jego szum musi mieć okres WRAP
## (shaders/world_wrap.gdshaderinc). 6000 m dzieli się przez rozmiary oczek
## szumu ground.gdshader (250, 83,3, 50, 3,33, 0,667 m) - patrz spec.
## Parametr trzeba dopisać w project.godot ([shader_globals]), zanim
## skompiluje się pierwszy shader, który go używa.
const WRAP := 6000.0
const WRAP_PARAM := "world_origin_wrap"

## Łączne przesunięcie (prawdziwa pozycja = lokalna + offset), 64 bity.
var offset_x := 0.0
var offset_y := 0.0
var offset_z := 0.0
var shifts := 0


## Wektor przesunięcia, jeśli pozycja `p` (lokalna) za daleko od zera,
## inaczej Vector3.ZERO. Tylko w poziomie - wysokość zostaje.
static func check_pos(p: Vector3) -> Vector3:
	if absf(p.x) <= THRESHOLD and absf(p.z) <= THRESHOLD:
		return Vector3.ZERO
	return Vector3(snappedf(p.x, QUANTUM), 0.0, snappedf(p.z, QUANTUM))


func check(p: Vector3) -> Vector3:
	return check_pos(p)


## Przesuwa węzły o -shift i dopisuje shift do offsetu. Ciała sztywne
## zachowują prędkości (teleport w Jolt), interpolacja fizyki jest
## resetowana (inaczej przez klatkę rysuje się smuga przez 2 km).
func apply(shift: Vector3, nodes: Array) -> void:
	if shift == Vector3.ZERO:
		return
	for n in nodes:
		var n3 := n as Node3D
		if n3 == null or not n3.is_inside_tree():
			continue
		if n3 is RigidBody3D:
			var rb := n3 as RigidBody3D
			var lv := rb.linear_velocity
			var av := rb.angular_velocity
			rb.global_position -= shift
			rb.linear_velocity = lv
			rb.angular_velocity = av
		else:
			n3.global_position -= shift
		n3.reset_physics_interpolation()
	offset_x += shift.x
	offset_y += shift.y
	offset_z += shift.z
	shifts += 1
	_update_shader_param()


## Prawdziwa pozycja w świecie (64 bity) pozycji lokalnej - do zapisu,
## porównań między przesunięciami, debugowania.
func to_world(p: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([p.x + offset_x, p.y + offset_y, p.z + offset_z])


## Pozycja lokalna (bieżący układ) z prawdziwej pozycji w świecie.
func to_local(w: PackedFloat64Array) -> Vector3:
	return Vector3(w[0] - offset_x, w[1] - offset_y, w[2] - offset_z)


## Offset modulo WRAP - mała liczba dla shaderów (wzory z pozycji świata).
func wrap_offset() -> Vector3:
	return Vector3(fposmod(offset_x, WRAP), fposmod(offset_y, WRAP), fposmod(offset_z, WRAP))


## Parametr globalny shaderów (w testach headless bez renderera nic nie robi).
func _update_shader_param() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Parametr jest w project.godot ([shader_globals]) - tylko ustawiamy.
	# Było: sprawdzenie global_shader_parameter_get_list() (działa tylko
	# w edytorze, w grze pusta lista) i dodawanie przy każdym przesunięciu
	# świata - 2x ERROR w logu gogli na przesunięcie (2026-11-11).
	RenderingServer.global_shader_parameter_set(WRAP_PARAM, wrap_offset())


func reset() -> void:
	offset_x = 0.0
	offset_y = 0.0
	offset_z = 0.0
	shifts = 0
	_update_shader_param()
