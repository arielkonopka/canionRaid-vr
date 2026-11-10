extends SceneTree
## Test przesuwania początku świata (WorldOrigin) na prawdziwej fizyce:
##   1. ciało sztywne w ruchu + "kawałek trasy" + dziecko kawałka: po
##      przesunięciu zachowują położenie względne i prędkości, offset się
##      sumuje, to_world / to_local w obie strony;
##   2. jazda 300 km krokami po 30 m (bez fizyki): liczba przesunięć,
##      pozycja auta zawsze < THRESHOLD + krok, prawdziwa pozycja (64 bity)
##      zgodna z oczekiwaną, błąd float32 bez przesuwania - dla porównania.
##   godot --headless --xr-mode off -s res://tests/world_origin_test.gd </dev/null
## Wynik: "WORLD_ORIGIN: OK" albo "WORLD_ORIGIN: BŁĘDY n" (kod wyjścia 1).

var errors := 0
var f := 0
var body: RigidBody3D
var chunk: Node3D
var marker: Node3D
var origin := WorldOrigin.new()


func _fail(what: String) -> void:
	errors += 1
	if errors <= 30:
		print("  BŁĄD: ", what)


func _initialize() -> void:
	body = RigidBody3D.new()
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 1.4, 4.5)
	cs.shape = bs
	body.add_child(cs)
	root.add_child(body)
	body.position = Vector3(2100.25, 1.0, -3000.5)     # rodzic = root w (0,0,0); w _initialize węzły nie są jeszcze w drzewie
	body.linear_velocity = Vector3(10.0, 0.0, -30.0)
	body.angular_velocity = Vector3(0.0, 0.2, 0.0)
	body.add_to_group(WorldOrigin.GROUP)
	chunk = Node3D.new()
	root.add_child(chunk)
	chunk.position = Vector3(1980.0, 0.0, -2900.0)
	chunk.add_to_group(WorldOrigin.GROUP)
	marker = Node3D.new()
	chunk.add_child(marker)
	marker.position = Vector3(5.0, 1.0, -40.0)


func _process(_d: float) -> bool:
	f += 1
	if f < 5:
		return false
	_test_shift()
	_test_long_drive()
	print("WORLD_ORIGIN: OK" if errors == 0 else "WORLD_ORIGIN: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)
	return true


func _test_shift() -> void:
	var p0 := body.global_position
	var v0 := body.linear_velocity
	var w0 := body.angular_velocity
	var rel0 := marker.global_position - p0
	var world0 := origin.to_world(p0)
	var s := origin.check(p0)
	print("auto w (%.2f, %.2f), przesunięcie (%.0f, %.0f)" % [p0.x, p0.z, s.x, s.z])
	if s != Vector3(2048.0, 0.0, -3072.0):
		_fail("check: %s" % s)
	origin.apply(s, get_nodes_in_group(WorldOrigin.GROUP))
	var p1 := body.global_position
	if not (p1 - (p0 - s)).is_zero_approx():
		_fail("ciało po przesunięciu w %s zamiast %s" % [p1, p0 - s])
	if p1.x != p0.x - s.x or p1.z != p0.z - s.z:
		_fail("odejmowanie niedokładne: %.6f / %.6f" % [p1.x, p0.x - s.x])
	if not (body.linear_velocity - v0).is_zero_approx() or not (body.angular_velocity - w0).is_zero_approx():
		_fail("prędkość po przesunięciu %s / %s" % [body.linear_velocity, body.angular_velocity])
	if not ((marker.global_position - body.global_position) - rel0).is_zero_approx():
		_fail("położenie względne dziecka kawałka zmienione")
	var world1 := origin.to_world(p1)
	for i in range(3):
		if absf(world1[i] - world0[i]) > 1e-4:
			_fail("to_world przed/po: %s / %s" % [world0, world1])
			break
	if not (origin.to_local(world1) - p1).is_zero_approx():
		_fail("to_local(to_world(p)) != p")
	if origin.check(p1) != Vector3.ZERO:
		_fail("po przesunięciu nadal za daleko")
	var w := origin.wrap_offset()
	if w.x < 0.0 or w.x >= WorldOrigin.WRAP or w.z < 0.0 or w.z >= WorldOrigin.WRAP:
		_fail("wrap_offset poza [0, WRAP): %s" % w)


## 300 km "jazdy" kursem 30° od osi -Z (jak trasa, która nie zawraca).
func _test_long_drive() -> void:
	var o := WorldOrigin.new()
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = Vector3.ZERO
	var dir := Vector3(sin(deg_to_rad(30.0)), 0.0, -cos(deg_to_rad(30.0)))
	var step := 30.0
	var steps := int(300000.0 / step)
	var naive := Vector3.ZERO            # float32 bez przesuwania
	var max_abs := 0.0
	for i in range(steps):
		n.global_position += dir * step
		naive += dir * step
		var s := o.check(n.global_position)
		if s != Vector3.ZERO:
			o.apply(s, [n])
		max_abs = maxf(max_abs, maxf(absf(n.global_position.x), absf(n.global_position.z)))
	var w := o.to_world(n.global_position)
	var ex := float(steps) * step * float(dir.x)
	var ez := float(steps) * step * float(dir.z)
	var err64 := Vector2(w[0] - ex, w[2] - ez).length()
	var err32 := Vector2(naive.x - ex, naive.z - ez).length()
	print("300 km: przesunięć %d, największa współrzędna %.0f m, błąd z przesuwaniem %.2f mm, bez %.0f mm" % [
			o.shifts, max_abs, err64 * 1000.0, err32 * 1000.0])
	if max_abs > WorldOrigin.THRESHOLD + step + 1.0:
		_fail("auto za daleko od zera: %.0f m" % max_abs)
	if o.shifts < 100:
		_fail("za mało przesunięć: %d" % o.shifts)
	# Krok 30 m w float32 przy małych współrzędnych: błąd sumowania
	# ~1e-4 m na krok -> do kilkudziesięciu cm na 10 000 kroków, ale ten sam
	# dla ruchu auta (fizyka i tak liczy przyrosty). Ważne, że nie rośnie
	# z odległością od startu jak bez przesuwania.
	if err64 > err32 and err32 > 0.01:
		_fail("z przesuwaniem gorzej niż bez: %.3f / %.3f m" % [err64, err32])
	n.free()
