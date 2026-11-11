extends SceneTree
## Test warstwy pogody (WeatherPlan): fronty z zapowiedzią (chmury przed
## opadem), jezdnia mokra tam, gdzie pada, pogoda niezależna od kolejności
## pytań, zgodność z tools/weather_sim.py (ten sam hash), granice stref
## nawierzchni, wygląd nieba. Bez sceny, sekundy.
##   godot --headless --xr-mode off -s res://tests/weather_plan_test.gd -- [ziarno] </dev/null
## Wynik: "WEATHER_PLAN: OK" albo "WEATHER_PLAN: BŁĘDY n" (kod wyjścia 1).
## Liczby z Pythona: python3 tools/weather_sim.py 777 300

var errors := 0


func _fail(what: String) -> void:
	errors += 1
	if errors <= 30:
		print("  BŁĄD: ", what)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v := int(args[0]) if args.size() > 0 else 777
	_python_twin()
	_invariants(WeatherPlan.new(seed_v))
	_order(seed_v)
	_changes(WeatherPlan.new(seed_v))
	_biomes(seed_v)
	_look()
	print("WEATHER_PLAN: OK" if errors == 0 else "WEATHER_PLAN: BŁĘDY %d" % errors)
	quit(0 if errors == 0 else 1)


## Te same liczby co w Pythonie (ziarno 777, bez planu = biom "fields").
func _python_twin() -> void:
	var w := WeatherPlan.new(777)
	if not is_equal_approx(w._h01(3, 1), 0.7751795824151486):
		_fail("hash inny niż w Pythonie: %f" % w._h01(3, 1))
	var expect := {1: [13361.546, 15934.54, 1.0], 5: [60140.749, 62214.773, 1.0],
			8: [96444.954, 99029.323, 2.0], 9: [112462.002, 114959.556, 2.0],
			11: [136791.991, 139277.369, 1.0]}
	for b in range(12):
		var f := w.front(b)
		if expect.has(b) != (not f.is_empty()):
			_fail("blok %d: front %s, Python %s" % [b, not f.is_empty(), expect.has(b)])
			continue
		if f.is_empty():
			continue
		var e: Array = expect[b]
		if absf(float(f["start"]) - float(e[0])) > 0.01 or absf(float(f["rain_start"]) - float(e[1])) > 0.01 \
				or float(f["peak"]) != float(e[2]):
			_fail("blok %d: %s, Python %s" % [b, f, e])


func _invariants(w: WeatherPlan) -> void:
	var d := 0.0
	var fronts := 0
	while d < 300000.0:
		var x := w.weather(d)
		var s := w.surface(d)
		if float(x["rain"]) >= WeatherPlan.WET_RAIN and s != "wet":
			_fail("pada %.2f, a jezdnia %s na %.0f m" % [x["rain"], s, d])
		if d < WeatherPlan.FRONT_FIRST and (float(x["cloud"]) > 0.0 or s != "dry"):
			_fail("pogoda przed FRONT_FIRST na %.0f m" % d)
		if float(x["cloud"]) < 0.0 or float(x["cloud"]) > 1.0 or float(x["rain"]) < 0.0 or float(x["rain"]) > 2.0:
			_fail("zakres na %.0f m: %s" % [d, x])
		if w.surface(d, true) == "ice" and not bool(x["freezing"]):
			_fail("lód bez mrozu na %.0f m" % d)
		d += 25.0
	for b in range(int(300000.0 / WeatherPlan.FRONT_BLOCK) + 1):
		var f := w.front(b)
		if f.is_empty():
			continue
		fronts += 1
		var start: float = f["start"]
		var r0: float = f["rain_start"]
		# Zapowiedź: co najmniej APPROACH_MIN chmurzenia przed opadem, a gdy
		# zaczyna padać, niebo jest już ciemne.
		if r0 - start < WeatherPlan.APPROACH_MIN - 0.001:
			_fail("za krótka zapowiedź w bloku %d" % b)
		if float(w.weather(r0 + WeatherPlan.RAMP)["cloud"]) < 0.9:
			_fail("pada spod jasnego nieba w bloku %d" % b)
		if float(f["end"]) + WeatherPlan.DRY_LAG > float(b + 1) * WeatherPlan.FRONT_BLOCK + 0.001:
			_fail("front wychodzi poza blok %d" % b)
	# Średnio front co ~17-27 km (Python: 11-17 frontów na 300 km).
	if fronts < 8 or fronts > 22:
		_fail("frontów na 300 km: %d" % fronts)


## Leniwe liczenie nie może zależeć od kolejności pytań.
func _order(seed_v: int) -> void:
	var a := WeatherPlan.new(seed_v)
	var b := WeatherPlan.new(seed_v)
	for d in [250000.0, 17000.0, 99000.0]:
		b.weather(d)
	for d in [16000.0, 63000.0, 100000.0, 250000.0]:
		if str(a.weather(d)) != str(b.weather(d)):
			_fail("kolejność pytań zmienia pogodę na %.0f m" % d)


## surface_changes zgadza się z surface (granice dokładnie w miejscach zmian).
func _changes(w: WeatherPlan) -> void:
	var ch := w.surface_changes(0.0, 300000.0)
	var prev := -1.0
	for c in ch:
		var d: float = c["d"]
		if d < prev:
			_fail("surface_changes nieposortowane")
		prev = d
		if w.surface(d + 0.5) != String(c["surface"]):
			_fail("za granicą %.0f m nawierzchnia %s, a lista mówi %s" % [d, w.surface(d + 0.5), c["surface"]])
		if w.surface(d - 0.5) == String(c["surface"]):
			_fail("przed granicą %.0f m już %s" % [d, c["surface"]])


## Biom z planu zmienia charakter frontu.
func _biomes(seed_v: int) -> void:
	var plan := HighwayPlan.new(seed_v)
	var w := WeatherPlan.new(seed_v, plan)
	var seen := {}
	for b in range(1, 200):
		var f := w.front(b)
		if f.is_empty():
			continue
		var mid := (float(f["rain_start"]) + float(f["rain_end"])) * 0.5
		var biome := plan.biome_at(mid)
		seen[String(f["kind"])] = true
		if biome == "desert" and (String(f["kind"]) != "dust" or float(f["peak"]) != 0.0):
			_fail("pustynia z deszczem w bloku %d" % b)
		if bool(f["freezing"]) and biome != "mountains":
			_fail("mróz poza górami w bloku %d (%s)" % [b, biome])
		if biome == "desert" and w.surface(mid) != "dry":
			_fail("mokro na pustyni w bloku %d" % b)
	print("  rodzaje frontów (2400 km): ", seen.keys())


func _look() -> void:
	var clear := WeatherPlan.look({})
	var storm := WeatherPlan.look({"cloud": 1.0, "fog": 0.15, "kind": "rain"})
	if not (clear["sky_top"] as Color).is_equal_approx(WeatherPlan.SKY_TOP_CLEAR):
		_fail("pogodne niebo inne niż w main.tscn")
	if float(storm["sun_energy"]) >= float(clear["sun_energy"]):
		_fail("słońce w burzy nie słabnie")
	var top: Color = storm["sky_top"]
	if top.s > 0.25 or top.v > 0.4:
		_fail("niebo w burzy nie jest ciemnoszare: %s" % top)
