extends SceneTree
## Boty nie znikają na widoku (zlecenie boty-znikanie, 2026-11-12), logika
## bez sceny: TrafficZone.step nie usuwa widocznych aut ani nadmiaru przed
## graczem; TrafficZone.visible widzi auto 1,5 km przed maską (było 900 m).
##   godot --headless --xr-mode off -s res://tests/vanish_test.gd </dev/null

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  OK  " if ok else "  BŁĄD ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	var plan := HighwayPlan.new(777)
	var tz := TrafficZone.new(plan)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pd := 40000.0
	# Dużo aut przed graczem (nadmiar), niewidoczne; jedno widoczne daleko za
	# oknem; jedno niewidoczne daleko za oknem.
	var cars := []
	for i in range(30):
		cars.append({"id": i, "dist": pd + 100.0 + i * 40.0, "lane": i % 2, "oncoming": false,
				"raging": false, "visible": false})
	cars.append({"id": 100, "dist": pd - 900.0, "lane": 0, "oncoming": true, "raging": false, "visible": true})
	cars.append({"id": 101, "dist": pd - 900.0, "lane": 1, "oncoming": true, "raging": false, "visible": false})
	var r := tz.step(pd, cars, rng)
	var gone: Array = r["despawn"]
	_check(not gone.has(100), "widoczne auto za oknem zostaje")
	_check(gone.has(101), "niewidoczne auto za oknem znika")
	var ahead_gone := 0
	for id in gone:
		if id < 30:
			ahead_gone += 1
	_check(ahead_gone == 0, "nadmiar przed graczem nie znika (%d usuniętych)" % ahead_gone)
	# Widoczność: głowa i auto patrzą w -Z.
	var head := Vector3.ZERO
	var fwd := Vector3.FORWARD
	_check(TrafficZone.visible(head, fwd, fwd, Vector3(0, 0, -1500)), "auto 1,5 km przed maską widoczne")
	_check(not TrafficZone.visible(head, fwd, fwd, Vector3(0, 0, -2500)), "2,5 km przed maską - poza zasięgiem")
	_check(not TrafficZone.visible(head, -fwd, fwd, Vector3(0, 0, 1200)), "1,2 km za plecami przy obróconej głowie - poza 900 m")
	_check(TrafficZone.visible(head, fwd, fwd, Vector3(0, 0, 150)), "150 m za autem w lusterku")
	print("vanish_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails else 0)
