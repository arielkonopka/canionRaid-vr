extends SceneTree
## Autostrada: koła poza asfaltem mają podłogę (pas rozdziału i pobocze
## z kolizją). Auto stawiane tak, że jedna strona kół stoi poza jezdnią
## (lewe na pasie rozdziału przed barierą środkową, prawe na poboczu przed
## barierą energochłonną); sprawdzamy kontakt tych kół i wysokość punktu
## styku (~poziom jezdni). Do tego auto na środku drugiej jezdni.
## Przegląd PR #7: sam "spadek auta" nie łapał braku kolizji - auto jest
## szersze niż pas do bariery i zawsze opiera się na asfalcie albo barierze.
##   godot --headless --xr-mode off -s res://tests/highway_test.gd </dev/null
var f := 0
var main
var car
var d := -1.0
var road_y := 0.0
var cases := []
var cur := -1
var t := 0.0
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
		# [opis, przesunięcie środka auta, koła do sprawdzenia]
		cases = [["lewe koła na pasie rozdziału", -(hw - 0.1), [0, 2]],
				["prawe koła na poboczu", hw - 0.5, [1, 3]],
				["środek drugiej jezdni", -(2.0 * hw + TrackGenerator.HIGHWAY_MEDIAN), [0, 1, 2, 3]]]
		print("autostrada na %.0f m" % d)
		return false
	if f < 20:
		return false
	if cur < 0 or t > 1.5:
		if cur >= 0:
			var ok := true
			var info := PackedStringArray()
			for i in cases[cur][2]:
				var w = car.wheels[i]
				var dy: float = (w.contact_point.y - road_y) if w.contact else INF
				info.append("koło %d: %s" % [i, ("styk %+.2f m" % dy) if w.contact else "BRAK STYKU"])
				if not w.contact or absf(dy) > 0.2:
					ok = false
			if not ok:
				fails += 1
			print("  %-32s %s  %s" % [cases[cur][0], ", ".join(info), "OK" if ok else "BŁĄD"])
		cur += 1
		if cur >= cases.size():
			print("highway_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
			return true
		var xf: Transform3D = tr.transform_at_distance(d)
		var pos: Vector3 = xf.origin + xf.basis.x * float(cases[cur][1])
		road_y = pos.y
		car.place(Transform3D(xf.basis, pos + xf.basis.y * 0.8))
		car._settle_t = 0.0
		t = 0.0
		return false
	t += delta
	car.throttle = 0.0
	car.brake = 1.0
	return false
