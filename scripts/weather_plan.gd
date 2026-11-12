extends RefCounted
class_name WeatherPlan

## Warstwa pogody trybu "Autostrada" (użytkownik 2026-11-11: "w przypadku
## deszczu niebo powinno się robić ciemnoszare", "rozważmy dodanie warstwy
## pogody"). Projekt: dokument "Urozmaicenia trasy: odcinek z 4 bajtów",
## sekcja "Warstwa pogody"; zlecenie: docs/agent/inbox/2026-11-12-warstwa-pogody.md.
##
## Czysta logika jak HighwayPlan: pogoda to funkcja ziarna i kilometra `d`,
## deterministyczna, leniwa, bez stanu i bez węzłów sceny. Odpowiednik
## w Pythonie: tools/weather_sim.py (ten sam hash, te same liczby).
##
## FRONTY: trasa jest podzielona na bloki FRONT_BLOCK metrów. W bloku jest
## najwyżej jeden front, z szansą rosnącą z dystansem. Front ma trzy części:
##   chmurzenie (APPROACH) - niebo ciemnieje, jeszcze sucho (to jest
##     zapowiedź śliskiej drogi: 2-3 km = 50-75 s przy 140 km/h),
##   opad (CORE) - mżawka albo ulewa, krótkie narastanie na brzegach,
##   przejaśnienie (CLEAR) - chmury odchodzą, jezdnia schnie DRY_LAG metrów.
## Biom zmienia charakter frontu (pustynia: pył zamiast deszczu, góry:
## mróz i śnieg, wybrzeże: wiatr i mgła).
##
## Wyjście w miejscu `d`: weather(d) - liczby dla nieba, mgły, deszczu,
## wiatru; surface(d, on_bridge) - nawierzchnia dla generatora ("dry", "wet",
## "ice"); surface_changes(d0, d1) - granice stref do dzielenia odcinków.
## Tunel zawsze suchy - o tym decyduje generator (roof), nie ten plik.

const FRONT_BLOCK := 12000.0
## Pierwsze metry trasy bez pogody (oswojenie z autem, jak JUMP_FIRST).
const FRONT_FIRST := 6000.0
## Szansa frontu w bloku: P0 na starcie, +P_PER_KM na km, do P_MAX.
const P0 := 0.35
const P_PER_KM := 0.0015
const P_MAX := 0.7
const APPROACH_MIN := 2000.0
const APPROACH_MAX := 3000.0
const CORE_MIN := 1000.0
const CORE_MAX := 4000.0
const CLEAR := 1500.0
## Narastanie opadu na brzegach rdzenia [m].
const RAMP := 300.0
## Jezdnia mokra jeszcze tyle metrów po końcu opadu.
const DRY_LAG := 1000.0
## Szansa ulewy (zamiast mżawki): od DOWNPOUR0 do DOWNPOUR_MAX z dystansem.
const DOWNPOUR0 := 0.3
const DOWNPOUR_MAX := 0.6
const DOWNPOUR_PER_KM := 0.001
## Góry: szansa mrozu (śnieg, lód na mostach).
const MOUNTAIN_FREEZE := 0.5
## Opad, od którego jezdnia jest mokra (0 sucho, 1 mżawka, 2 ulewa).
const WET_RAIN := 0.5

var seed_value := 1
## Plan trasy (biomy). Może być null - wtedy biom "fields" wszędzie (testy).
var plan: HighwayPlan = null


func _init(seed_v := 1, p_plan: HighwayPlan = null) -> void:
	seed_value = seed_v
	plan = p_plan


# --------------------------------------------------------------------------
# Hash (całkowity, 32 bity, ten sam w tools/weather_sim.py i CityGraph)
# --------------------------------------------------------------------------

static func _mix(h: int, v: int) -> int:
	h = (h ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFFFFFF


## Liczba [0, 1) z ziarna, numeru bloku i "soli".
func _h01(block: int, salt: int) -> float:
	var h := _mix(0x9E3779B9, seed_value)
	h = _mix(h, block)
	h = _mix(h, salt)
	return float(h) / 4294967296.0


# --------------------------------------------------------------------------
# Fronty
# --------------------------------------------------------------------------

## Front w bloku b albo {} (brak). Pola: start, rain_start, rain_end, end
## (wszystko w metrach od startu trasy), peak (1 mżawka / 2 ulewa),
## kind ("rain", "snow", "dust", "wind"), freezing, fog, wind, wind_sign.
func front(b: int) -> Dictionary:
	if b < 0:
		return {}
	var b0 := float(b) * FRONT_BLOCK
	var km := b0 / 1000.0
	var p := minf(P0 + P_PER_KM * km, P_MAX)
	if _h01(b, 1) >= p:
		return {}
	var approach := lerpf(APPROACH_MIN, APPROACH_MAX, _h01(b, 2))
	var core := lerpf(CORE_MIN, CORE_MAX, _h01(b, 3))
	var total := approach + core + CLEAR
	# Z zapasem DRY_LAG: mokra jezdnia nie wychodzi poza blok (front_at
	# sprawdza tylko blok, w którym jest d).
	var start := b0 + _h01(b, 4) * (FRONT_BLOCK - total - DRY_LAG)
	if start < FRONT_FIRST:
		return {}
	var p_down := minf(DOWNPOUR0 + DOWNPOUR_PER_KM * km, DOWNPOUR_MAX)
	var f := {
		"start": start,
		"rain_start": start + approach,
		"rain_end": start + approach + core,
		"end": start + total,
		"peak": 2.0 if _h01(b, 5) < p_down else 1.0,
		"kind": "rain",
		"freezing": false,
		"fog": 0.15,
		"wind": 0.2 * _h01(b, 6),
		"wind_sign": 1.0 if _h01(b, 7) < 0.5 else -1.0,
	}
	# Charakter z biomu w środku opadu.
	var mid := (float(f["rain_start"]) + float(f["rain_end"])) * 0.5
	match _biome(mid):
		"desert":
			f["kind"] = "dust"
			f["peak"] = 0.0                      # bez opadu, jezdnia sucha
			f["fog"] = 0.6
			f["wind"] = 0.4 + 0.4 * _h01(b, 6)
		"mountains":
			f["fog"] = 0.4
			if _h01(b, 8) < MOUNTAIN_FREEZE:
				f["kind"] = "snow"
				f["freezing"] = true
		"seaside":
			f["kind"] = "wind"
			f["fog"] = 0.35
			f["wind"] = 0.5 + 0.5 * _h01(b, 6)
	return f


func _biome(d: float) -> String:
	return plan.biome_at(d) if plan != null else "fields"


## Front, który obejmuje d ({} - pogoda czysta). Front razem z mokrą jezdnią
## (DRY_LAG) nie wychodzi poza swój blok, więc wystarczy jeden blok.
func front_at(d: float) -> Dictionary:
	var b := int(floor(maxf(d, 0.0) / FRONT_BLOCK))
	var f := front(b)
	if f.is_empty() or d < float(f["start"]) or d >= float(f["end"]) + DRY_LAG:
		return {}
	return f


static func _smooth(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


## Pogoda w miejscu d: {"cloud" 0..1, "rain" 0..2, "fog" 0..1, "wind" 0..1,
## "wind_sign" ±1, "kind", "freezing"}. Bez frontu: wszystko 0, kind "".
func weather(d: float) -> Dictionary:
	var w := {"cloud": 0.0, "rain": 0.0, "fog": 0.0, "wind": 0.0, "wind_sign": 1.0,
			"kind": "", "freezing": false}
	var f := front_at(d)
	if f.is_empty() or d >= float(f["end"]):
		return w
	var s0: float = f["start"]
	var r0: float = f["rain_start"]
	var r1: float = f["rain_end"]
	var e: float = f["end"]
	# Chmury: narastają przez całe podejście, schodzą przez przejaśnienie.
	var cloud := _smooth(s0, r0, d) * (1.0 - _smooth(r1, e, d))
	# Opad: tylko w rdzeniu, z krótkim narastaniem na brzegach.
	var rain := float(f["peak"]) * _smooth(r0, r0 + RAMP, d) * (1.0 - _smooth(r1 - RAMP, r1, d))
	w["cloud"] = cloud
	w["rain"] = rain
	w["fog"] = float(f["fog"]) * cloud
	w["wind"] = float(f["wind"]) * cloud
	w["wind_sign"] = f["wind_sign"]
	w["kind"] = f["kind"]
	w["freezing"] = f["freezing"]
	return w


## Nawierzchnia w miejscu d (bez tunelu - tunel jest suchy, decyduje
## generator). Mokro od początku opadu do DRY_LAG za jego końcem; przy
## mrozie most zamarza pierwszy ("ice"), reszta drogi mokra (breja).
func surface(d: float, on_bridge := false) -> String:
	var f := front_at(d)
	if f.is_empty() or float(f["peak"]) < WET_RAIN:
		return "dry"
	if d < float(f["rain_start"]) or d >= float(f["rain_end"]) + DRY_LAG:
		return "dry"
	if bool(f["freezing"]) and on_bridge:
		return "ice"
	return "wet"


## Granice stref nawierzchni (bez mostów) w [d0, d1): lista {"d", "surface"}
## posortowana - generator dzieli odcinki dokładnie w tych miejscach (jak
## HighwayPlan.limit_changes).
func surface_changes(d0: float, d1: float) -> Array:
	var out := []
	var b0 := int(floor(maxf(d0, 0.0) / FRONT_BLOCK))
	var b1 := int(floor(maxf(d1, 0.0) / FRONT_BLOCK))
	for b in range(b0, b1 + 1):
		var f := front(b)
		if f.is_empty() or float(f["peak"]) < WET_RAIN:
			continue
		var wet0: float = f["rain_start"]
		var wet1: float = float(f["rain_end"]) + DRY_LAG
		if wet0 >= d0 and wet0 < d1:
			out.append({"d": wet0, "surface": "wet"})
		if wet1 >= d0 and wet1 < d1:
			out.append({"d": wet1, "surface": "dry"})
	return out


# --------------------------------------------------------------------------
# Wygląd (czysta funkcja - scena tylko przepisuje wartości)
# --------------------------------------------------------------------------

## Pogodne niebo = wartości z scenes/main.tscn; burzowe = ciemnoszare.
const SKY_TOP_CLEAR := Color(0.22, 0.42, 0.78)
const SKY_TOP_STORM := Color(0.26, 0.28, 0.31)
const SKY_HORIZON_CLEAR := Color(0.74, 0.82, 0.9)
const SKY_HORIZON_STORM := Color(0.46, 0.48, 0.5)
const SKY_DUST := Color(0.72, 0.6, 0.44)
const SUN_CLEAR := 1.35
const SUN_STORM := 0.35
const FOG_CLEAR := 0.0007
const FOG_MAX := 0.006
const AMBIENT_CLEAR := Color(0.62, 0.64, 0.68)
const AMBIENT_STORM := Color(0.42, 0.43, 0.45)


## Wartości dla WorldEnvironment, nieba i słońca z pogody w miejscu gracza
## (wygładzonej w czasie przez scenę). {"sky_top", "sky_horizon",
## "sun_energy", "fog_density", "fog_color", "ambient"}.
static func look(w: Dictionary) -> Dictionary:
	var c := clampf(float(w.get("cloud", 0.0)), 0.0, 1.0)
	var dust := String(w.get("kind", "")) == "dust"
	var top := SKY_TOP_CLEAR.lerp(SKY_DUST if dust else SKY_TOP_STORM, c)
	var hor := SKY_HORIZON_CLEAR.lerp(SKY_DUST if dust else SKY_HORIZON_STORM, c)
	var fog := clampf(float(w.get("fog", 0.0)), 0.0, 1.0)
	return {
		"sky_top": top,
		"sky_horizon": hor,
		"sun_energy": lerpf(SUN_CLEAR, SUN_STORM, c),
		"fog_density": lerpf(FOG_CLEAR, FOG_MAX, fog),
		"fog_color": hor,
		"ambient": AMBIENT_CLEAR.lerp(AMBIENT_STORM, c),
	}
