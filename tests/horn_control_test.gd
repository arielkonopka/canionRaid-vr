extends SceneTree
## Klakson nie może sam rozbijać botów (użytkownik 2026-11-11: "Boty, gdy
## na nie zatrąbić, często tracą kontrolę nad jazdą... Zdarza się, że tylko
## od tego mają wypadek"). Gracz jedzie przepisowo za kilkoma botami,
## trąbi; przez 10 s żaden bot nie może: obrócić się (> 60° od kierunku
## drogi przy > 20 km/h), przewrócić ani wypaść poza jezdnię. Wypisuje też
## największe przyspieszenie boczne bota (dla oceny "ostro, ale rozsądnie").
## Dwa przebiegi: wąwóz i autostrada.
##   godot --headless --xr-mode off -s res://tests/horn_control_test.gd </dev/null
##   godot --headless --xr-mode off -s res://tests/horn_control_test.gd -- autostrada </dev/null

var main
var car: StuntCar
var f := 0
var horn_f := -1
var worst_head := 0.0
var worst_lat := 0.0
var worst_off := 0.0
var flipped := 0
var prev_v := {}
var rng_seed := -1
var dbg := {}
const SPAWN := [70.0, 110.0, 150.0, 200.0]


func _initialize() -> void:
	var gs = root.get_node("GameSettings")
	gs.persist = false
	var args := OS.get_cmdline_user_args()
	gs.track_mode = "autostrada" if args.has("autostrada") else "canyon"
	# Bez podanych ziaren - losowe, ale ustawione i wypisane przy wyniku
	# (quest.sh przy błędzie pokazuje tylko linię z BŁĄD).
	var t0 := Time.get_ticks_usec()
	rng_seed = int(t0 % 100000)
	EndlessTrack.test_seed = int((t0 / 7) % 100000) + 1
	# Ziarno (seed=N): taktyki szału (randi w BotDriver), pasy i style botów
	# (_bot_rng), waśnie - do odtworzenia niestabilnego przebiegu.
	for a in args:
		if a.begins_with("seed="):
			rng_seed = int(a.substr(5))
		if a.begins_with("track="):
			EndlessTrack.test_seed = int(a.substr(6))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(delta: float) -> bool:
	f += 1
	if f == 5:
		car = main.get_node("Car")
		main._bot_timer = 9999.0
		main.race_state = main.Race.RACING
		if true:
			seed(rng_seed)
			main._bot_rng.seed = rng_seed
			main.feud.rng.seed = rng_seed
			print("ziarno %d" % rng_seed)
		for d in SPAWN:
			main._spawn_bot(main._last_safe_dist + d)
		print("boty: %d" % main._bots.size())
	if f < 5:
		return false
	# Gracz jedzie prosto osią swojego pasa ~ ograniczenia (bez kolizji z botami
	# - jest daleko za nimi i wolniej od szału).
	car.throttle = 0.6 if car.speed < 16.0 else 0.0
	car.brake = 0.0
	car.steer = 0.0
	if f == 240:                       # 2 s rozpędu
		main.player_horn()
		horn_f = f
		var n := 0
		for b in main._bots:
			if (b.get_node("Driver") as BotDriver).rage > 0.9:
				n += 1
		print("klakson: %d botów w szale" % n)
		if n == 0:
			print("horn_control_test: BŁĄD (nikt nie wpadł w szał)")
			return true
	if horn_f < 0:
		return false
	for b: StuntCar in main._bots:
		if not is_instance_valid(b):
			continue
		var drv: BotDriver = b.get_node("Driver")
		if drv.on_rail:
			continue
		var xf: Transform3D = main.track.transform_at_distance(drv.dist)
		var road_fwd := -xf.basis.z
		var fwd: Vector3 = -b.global_basis.z
		var kmh: float = absf(b.speed) * 3.6
		if kmh > 20.0 and drv._reverse_t <= 0.0:
			worst_head = maxf(worst_head, rad_to_deg(fwd.angle_to(road_fwd)))
		var smp: Array = main.track.samples_from(drv.dist, 1.0)
		if not smp.is_empty():
			var off: float = absf((b.global_position - (smp[0]["pos"] as Vector3)).dot(smp[0]["right"]))
			worst_off = maxf(worst_off, off - float(smp[0]["width"]) * 0.5)
		if b.global_basis.y.y < 0.3:
			flipped += 1
		if OS.get_cmdline_user_args().has("debug") and b.name.ends_with("_10") and (f - horn_f) % 12 == 0 and f - horn_f < 720 and f - horn_f > 360:
			var sm: Array = main.track.samples_from(drv.dist, 1.0)
			print("    t=%.1f v=%.0f szał=%.2f takt=%s tgt=%.1f off=%.1f w=%.1f hamulec=%.2f gaz=%.2f kontakt=%s" % [(f - horn_f) / 120.0, kmh, drv.rage, drv._tactic, drv._tgt_off_s, (b.global_position - (sm[0]["pos"] as Vector3)).dot(sm[0]["right"]) if not sm.is_empty() else 0.0, float(sm[0]["width"]) if not sm.is_empty() else 0.0, b.brake, b.throttle, str(b.last_hit.get("what", "-"))])
		if OS.get_cmdline_user_args().has("debug") and not dbg.has(b) and (b.global_basis.y.y < 0.3 or (kmh > 20.0 and rad_to_deg(fwd.angle_to(road_fwd)) > 45.0)):
			dbg[b] = true
			var ch = main.track._chunk_for(drv.dist)
			var near_meta := []
			for sg in ch.segments:
				if sg.has("meta"):
					near_meta.append(str(sg["meta"].keys()))
			var hits := []
			var sp := b.get_world_3d().direct_space_state
			var qq := PhysicsShapeQueryParameters3D.new()
			var sph := SphereShape3D.new()
			sph.radius = 4.0
			qq.shape = sph
			qq.transform = Transform3D(Basis(), b.global_position)
			qq.exclude = [b.get_rid()]
			for h in sp.intersect_shape(qq, 8):
				hits.append(str((h["collider"] as Node).get_path()))
			print("  OBIEKTY przy aucie: %s; meta kawałka: %s" % [str(hits), str(near_meta)])
			print("  WYPADEK %s t=%.2f s po klaksonie, %.0f km/h, taktyka %s, szał %.1f, kontakt %s %s, d_gracz %.0f, pas off %.1f" % [b.name, (f - horn_f) / 120.0, kmh, drv._tactic, drv.rage, str(b.last_hit.get("what", "?")), str(b.last_hit.get("j", 0)), drv.dist - main._last_safe_dist, drv._tgt_off_s])
		var id: int = b.get_instance_id()
		var v: Vector3 = b.linear_velocity
		if prev_v.has(id) and kmh > 20.0:
			var a: Vector3 = (v - prev_v[id]) / delta
			worst_lat = maxf(worst_lat, absf(a.dot(b.global_basis.x)))
		prev_v[id] = v
	if f == horn_f + 1200:             # 10 s po klaksonie
		print("najgorzej: obrót %.0f°, poza jezdnią %.1f m, a_bok %.1f m/s², przewrotek %d"
				% [worst_head, worst_off, worst_lat, flipped])
		var ok := worst_head < 60.0 and worst_off < 1.0 and flipped == 0
		print("horn_control_test: ", "OK" if ok else "BŁĄD (seed=%d track=%d, obrót %.0f°, poza %.1f m, przewrotek %d)" % [rng_seed, EndlessTrack.test_seed, worst_head, worst_off, flipped])
		return true
	return false
