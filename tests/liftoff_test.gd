extends SceneTree
## Puszczenie gazu w łuku (elektryk 1000 kW w kołach, 4x4, 2500 kg, odzysk
## mocny, ESP wł.) - użytkownik 2026-11-10: "pod gazem trzyma, na luzie
## wpada w poślizg", "powyżej setki nadsterowny". Stały skręt ~120 km/h,
## po 6 s gaz puszczony; znoszenie ma zostać małe.
##   godot --headless --xr-mode off -s res://tests/liftoff_test.gd -- [odzysk=strong] [tempo=1.0] [esp|noesp] [skręt=0.18] </dev/null
var c: StuntCar
var f := 0
var t := 0.0
var max_beta := 0.0
var max_yaw := 0.0
var spun := false
func _initialize():
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(4000, 1, 4000)
	cs.shape = bx; cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs); root.add_child(ground)
	c = StuntCar.new()
	c.position = Vector3(0, 1.0, 0)
	root.add_child(c)
func _physics_process(d):
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 1:
		Engine.time_scale = float(a[1]) if a.size() > 1 else 1.0
		c.drive_layout = "awd"
		c.hub_motors = true
		c.regen_level = a[0] if a.size() > 0 else "strong"
		c.automatic = true
		c.apply_engine("electric", 1000)
		c.set_body_mass(2500)
		c.set_aero("sport")
		c.apply_suspension_preset("sport")
		c.esp_enabled = a.size() < 3 or a[2] == "esp"
	if f < 30:
		return false
	if f == 30:
		c.linear_velocity = Vector3(0, 0, -120.0 / 3.6)
		for w in c.wheels:
			w.omega = 120.0 / 3.6 / c.wheel_radius
	t += d
	var v := c.linear_velocity.length()
	# Stały skręt i gaz trzymający ~120 km/h, po 6 s gaz puszczony w łuku.
	c.steer = float(a[3]) if a.size() > 3 else 0.18
	if t < 6.0:
		c.throttle = clampf((120.0 / 3.6 - v) * 0.3 + 0.25, 0.0, 1.0)
	else:
		c.throttle = 0.0
		var fwd := -c.global_basis.z
		var beta := rad_to_deg(fwd.signed_angle_to(c.linear_velocity.normalized(), Vector3.UP))
		max_beta = maxf(max_beta, absf(beta))
		max_yaw = maxf(max_yaw, absf(c.angular_velocity.y))
	if t > 9.0:
		print("odzysk %s, %s: max kąt znoszenia %.1f°, max odchylanie %.2f rad/s, prędkość na końcu %.0f km/h" % [c.regen_level, "ESP" if c.esp_enabled else "bez ESP", max_beta, max_yaw, v * 3.6])
		var ok := max_beta < 6.0 or not c.esp_enabled
		print("liftoff_test: ", "OK" if ok else "BŁĄD (znoszenie %.1f° >= 6°)" % max_beta)
		quit()
	return false
