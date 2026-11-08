extends SceneTree
## Autostrada: auto postawione 1 m za lewą krawędzią jezdni (pas
## rozdziału), 0,4 m za prawą (pobocze przed barierą) i na środku drugiej
## jezdni nie spada
## (przegląd PR #7: bez kolizji pobocza spadało pod nasyp).
##   godot --headless --xr-mode off -s res://tests/highway_test.gd </dev/null
var f := 0
var main
var car
var d := -1.0
var cases := []
var cur := -1
var t := 0.0
var y0 := 0.0
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	root.get_node("GameSettings").track_mode = "canyon"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")


func _physics_process(delta: float) -> bool:
	f += 1
	main.set_physics_process(false)
	var tr = main.track
	if d < 0.0:
		var p := 0.0
		while p < 6000.0 and d < 0.0:
			tr.update_progress(p)
			for c in tr._chunks:
				if c.highway:
					var r: Vector2 = c.dist_range()
					d = r.x + 450.0
			p += 200.0
		tr.update_progress(d)
		var smp: Dictionary = tr.samples_from(d, 2.0)[0]
		var hw: float = float(smp["width"]) * 0.5
		cases = [["1 m za lewą krawędzią (pas rozdziału)", -(hw + 1.0)],
				# Prawa bariera stoi 0,6 m za krawędzią - pobocze przed nią.
				["0,4 m za prawą krawędzią (pobocze)", hw + 0.4],
				["środek drugiej jezdni", -(2.0 * hw + TrackGenerator.HIGHWAY_MEDIAN)]]
		print("autostrada na %.0f m" % d)
		return false
	if f < 20:
		return false
	if cur < 0 or t > 2.5:
		if cur >= 0:
			var drop: float = y0 - car.global_position.y
			var ok := drop < 1.0
			if not ok:
				fails += 1
			print("  %-40s spadek %.2f m  %s" % [cases[cur][0], drop, "OK" if ok else "BŁĄD"])
		cur += 1
		if cur >= cases.size():
			print("highway_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
		var xf: Transform3D = tr.transform_at_distance(d)
		car.place(Transform3D(xf.basis, xf.origin + xf.basis.x * float(cases[cur][1]) + xf.basis.y * 0.9))
		car._settle_t = 0.0
		y0 = car.global_position.y
		t = 0.0
		return false
	t += delta
	car.throttle = 0.0
	car.brake = 1.0
	return false
