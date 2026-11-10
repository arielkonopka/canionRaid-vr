extends SceneTree
## Test logiki: uproszczony napęd botów (BotDriveModel) i poziomy
## szczegółowości botów (BotLod). Bez sceny i fizyki.
##   godot --headless --xr-mode off -s res://tests/bot_drive_test.gd </dev/null
## Porównanie z pełnym modelem jazdy: tools/bot_drive_sim.py (Python).
## Kod wyjścia 1 przy błędzie.

const BDM := preload("res://scripts/bot_drive_model.gd")
const LOD := preload("res://scripts/bot_lod.gd")

var fails := 0


func _initialize() -> void:
	_test_drive()
	_test_lod()
	print("bot_drive_test: %s (%d błędów)" % ["OK" if fails == 0 else "BŁĄD", fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  BŁĄD: ", what)


## Krzywa jak StuntCar.apply_engine("petrol", kw): kształt benzyny
## przeskalowany do mocy (szczyt próbkowany co 50 obr./min).
func _petrol_curve(kw: float) -> PackedVector2Array:
	var shape: Array = StuntCar.ENGINE_TYPES["petrol"]["shape"]
	var tmp := PackedVector2Array()
	for pt in shape:
		tmp.append(Vector2(pt[0], pt[1]))
	var peak := 0.0
	var r := tmp[0].x
	while r <= tmp[tmp.size() - 1].x:
		peak = maxf(peak, BDM._curve(tmp, r) * r / BDM.RPM_PER_RAD_S)
		r += 50.0
	var out := PackedVector2Array()
	for pt in tmp:
		out.append(Vector2(pt.x, pt.y * kw * 1000.0 / peak))
	return out


func _test_drive() -> void:
	var e: Dictionary = StuntCar.ENGINE_TYPES["petrol"]
	var gears := PackedFloat32Array(e["gears"])
	var m = BDM.from_car(_petrol_curve(250.0), gears, float(e["final"]), float(e["idle"]))
	_check(absf(m.p_max - 250000.0) < 2500.0, "moc maksymalna 250 kW (%.0f W)" % m.p_max)
	_check(is_equal_approx(m.ratio(0.0), m.r_first), "postój: przełożenie 1. biegu")
	_check(is_equal_approx(m.ratio(1000.0), m.r_top), "bardzo szybko: najwyższy bieg")
	var mid_w: float = m.w_pp / ((m.r_first + m.r_top) * 0.5)
	var r_mid: float = m.ratio(mid_w)
	_check(r_mid < m.r_first and r_mid > m.r_top, "w środku: przełożenie pośrednie")
	_check(is_equal_approx(m.engine_torque(1.0, 0.0, m.r_first, 18.0, 0.006), m.t_max),
			"ruszanie: największy moment")
	var t_mid: float = m.engine_torque(1.0, mid_w, r_mid, 18.0, 0.006)
	var p_mid: float = t_mid * mid_w * r_mid
	_check(absf(p_mid - BDM.K_FILL * m.p_max) < 0.01 * m.p_max,
			"stała moc K_FILL·P (%.0f W)" % p_mid)
	_check(is_equal_approx(m.engine_torque(0.5, mid_w, r_mid, 18.0, 0.006), t_mid * 0.5),
			"moment proporcjonalny do gazu")
	var eb: float = m.engine_torque(0.0, mid_w, r_mid, 18.0, 0.006)
	_check(eb < 0.0, "bez gazu: hamowanie silnikiem (%.1f Nm)" % eb)
	var rpm_v: float = m.rpm(mid_w, r_mid)
	_check(absf(rpm_v - m.w_pp * BDM.RPM_PER_RAD_S) < 1.0, "obroty przy mocy maksymalnej")


func _test_lod() -> void:
	var d := PackedFloat32Array([50.0, 150.0, 200.0, 300.0, 500.0])
	var rage := [false, true, false, false, false]
	var t: PackedInt32Array = LOD.assign(d, rage, PackedInt32Array(), 3)
	_check(t[0] == LOD.NEAR, "blisko = NEAR")
	_check(t[1] == LOD.MID and t[2] == LOD.MID, "budżet: MID dla najbliższych/w szale")
	_check(t[3] == LOD.RAIL, "ponad budżet = szyna (%s)" % str(t))
	_check(t[4] == LOD.RAIL, "daleko = szyna")
	# W szale ma pierwszeństwo przed bliższym spokojnym.
	var t2: PackedInt32Array = LOD.assign(PackedFloat32Array([50.0, 150.0, 300.0]),
			[false, false, true], PackedInt32Array(), 2)
	_check(t2[2] == LOD.MID and t2[1] == LOD.RAIL, "w szale przed spokojnym (%s)" % str(t2))
	# NEAR zawsze z fizyką, nawet ponad budżet.
	var t3: PackedInt32Array = LOD.assign(PackedFloat32Array([10.0, 20.0, 30.0]),
			[false, false, false], PackedInt32Array(), 1)
	_check(t3[0] == LOD.NEAR and t3[1] == LOD.NEAR and t3[2] == LOD.NEAR, "NEAR ponad budżet")
	# Histereza.
	var h: PackedInt32Array = LOD.assign(PackedFloat32Array([130.0, 130.0, 330.0]),
			[false, false, false], PackedInt32Array([LOD.NEAR, LOD.MID, LOD.MID]), 8)
	_check(h[0] == LOD.NEAR and h[1] == LOD.MID and h[2] == LOD.MID, "histereza (%s)" % str(h))
