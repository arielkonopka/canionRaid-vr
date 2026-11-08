extends Node3D
class_name Explosion

## Eksplozja auta: błysk światła, kula ognia, iskry, dym i rozrzucone
## części karoserii (prawdziwe bryły z fizyką). Sama się usuwa po kilku
## sekundach. Wszystko z prymitywów i CPUParticles3D (bezpieczne na Queście).

const LIFETIME := 6.0

var paint := Color(0.8, 0.6, 0.18)
## Auta, z którymi części wraku nie kolidują (nowe auto gracza staje na
## miejscu wypadku - obijało się o części i wirowało bez końca).
var ignore: Array = []
var _t := 0.0
var _flash: OmniLight3D
var _fire: MeshInstance3D
var _fire_mat: StandardMaterial3D
var _debris: Array[RigidBody3D] = []


func _ready() -> void:
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.7, 0.35)
	_flash.light_energy = 12.0
	_flash.omni_range = 30.0
	add_child(_flash)

	_fire_mat = StandardMaterial3D.new()
	_fire_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	_fire_mat.emission_enabled = true
	_fire_mat.emission = Color(1.0, 0.45, 0.1)
	_fire_mat.emission_energy_multiplier = 4.0
	_fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 16
	sph.rings = 8
	sph.material = _fire_mat
	_fire = MeshInstance3D.new()
	_fire.mesh = sph
	_fire.scale = Vector3.ONE * 0.5
	add_child(_fire)

	add_child(_particles(Color(1.0, 0.75, 0.3), 120, 0.9, 18.0, 0.08, -9.8, true))   # iskry
	add_child(_particles(Color(0.18, 0.17, 0.16, 0.55), 40, 4.5, 3.0, 1.6, 1.5, false))  # dym

	# Części karoserii: kilka brył w kolorze lakieru, rozrzuconych impulsem.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paint
	for i in range(9):
		var rb := RigidBody3D.new()
		rb.mass = 15.0
		var size := Vector3(rng.randf_range(0.2, 0.7), rng.randf_range(0.05, 0.15), rng.randf_range(0.2, 0.8))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat if i % 3 != 0 else _dark()
		mi.mesh = bm
		rb.add_child(mi)
		rb.position = Vector3(rng.randf_range(-0.8, 0.8), 0.5, rng.randf_range(-1.5, 1.5))
		add_child(rb)
		for body in ignore:
			if is_instance_valid(body):
				rb.add_collision_exception_with(body)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.8, 1.6), rng.randf_range(-1, 1)).normalized()
		rb.apply_central_impulse(dir * rb.mass * rng.randf_range(8.0, 16.0))
		rb.angular_velocity = Vector3(rng.randf_range(-10, 10), rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		_debris.append(rb)


func _dark() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.06, 0.06)
	return m


func _particles(col: Color, amount: int, life: float, speed: float, size: float,
		gravity: float, sparks: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95 if sparks else 0.6
	p.emitting = true
	p.direction = Vector3.UP
	p.spread = 90.0 if sparks else 35.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	if not sparks:
		p.scale_amount_curve = _grow_curve()
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Rozmiar cząstki ustawiony na siatce - skala cząstek CPUParticles3D
	# bywała pomijana i iskry wychodziły jako metrowe kwadraty.
	if sparks:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		var q := QuadMesh.new()
		q.size = Vector2.ONE * size
		q.material = m
		p.mesh = q
	else:
		# Dym: miękkie, nieregularne kule.
		var sm := SphereMesh.new()
		sm.radius = size * 0.5
		sm.height = size
		sm.radial_segments = 8
		sm.rings = 4
		sm.material = m
		p.mesh = sm
	return p


func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(1.0, 1.0))
	return c


func _process(delta: float) -> void:
	_t += delta
	# Błysk gaśnie w 0,6 s, kula ognia rośnie do ~6 m i blednie w 1,2 s.
	_flash.light_energy = maxf(12.0 * (1.0 - _t / 0.6), 0.0)
	var k := clampf(_t / 1.2, 0.0, 1.0)
	_fire.scale = Vector3.ONE * lerpf(0.5, 3.2, sqrt(k))
	_fire_mat.albedo_color.a = 0.9 * (1.0 - k)
	_fire.visible = k < 1.0
	if _t > LIFETIME:
		queue_free()
