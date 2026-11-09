extends SceneTree
## Opcja "Wytrzymałość" (użytkownik 2026-11-09): mnożnik 1-10 dzieli
## uszkodzenia mechaniczne. Auto spada z 12 m na płaską ziemię (lądowanie
## ok. 15 m/s) przy wytrzymałości 1, 3 i 10; uszkodzenia mają maleć
## proporcjonalnie. Do tego to samo uderzenie w przód (_damage_impact).
##   godot --headless --xr-mode off -s res://tests/durability_test.gd </dev/null

const START := Vector3(-300.0, 12.75, 600.0)
const LEVELS := [1.0, 3.0, 10.0]

var main
var car
var cur := -1
var t := 0.0
var results := []
var fails := 0


func _initialize() -> void:
	root.get_node("GameSettings").persist = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	car = main.get_node("Car")
	main.get_node("Ground").set_meta("grip", 1.0)
	main.get_node("Ground").set_meta("surface", "dry")


func _physics_process(delta: float) -> bool:
	main.set_physics_process(false)
	car.throttle = 0.0
	car.brake = 1.0
	car.steer = 0.0
	if cur >= 0:
		t += delta
		if t < 3.0:
			return false
		var land: Dictionary = car.damage.duplicate(true)
		car.repair()
		car._damage_impact(Vector3(0.0, 0.0, -2.2), 1.0)
		var hit: Dictionary = car.damage.duplicate(true)
		car.repair()
		results.append([LEVELS[cur], land, hit])
		print("wytrzymałość x%-4.0f lądowanie: struktura %5.3f skrzynia %5.3f zawieszenie %5.3f | uderzenie w przód: struktura %5.3f silnik %5.3f" % [
				LEVELS[cur], land["structure"], land["gearbox"], land["suspension"][0],
				hit["structure"], hit["engine"]])
	cur += 1
	if cur >= LEVELS.size():
		_check()
		return true
	t = 0.0
	car.durability = LEVELS[cur]
	car.repair()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = Transform3D(Basis(), START)
	return false


func _check() -> void:
	var base: Array = results[0]
	if base[1]["gearbox"] <= 0.0:
		print("BŁĄD: lądowanie z 12 m nie uszkodziło auta przy x1")
		fails += 1
	for r in results.slice(1):
		var k: float = r[0]
		for pair in [[base[1]["gearbox"], r[1]["gearbox"], "lądowanie"], [base[2]["engine"], r[2]["engine"], "uderzenie"]]:
			var expect: float = pair[0] / k
			if absf(pair[1] - expect) > maxf(0.25 * expect, 0.01):
				print("BŁĄD: x%.0f %s: %.3f, oczekiwane ok. %.3f" % [k, pair[2], pair[1], expect])
				fails += 1
	print("durability_test: ", "OK" if fails == 0 else "BŁĄD (%d)" % fails)
