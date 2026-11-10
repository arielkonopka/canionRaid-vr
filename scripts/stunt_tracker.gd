extends RefCounted
class_name StuntTracker

## Detektor sztuczek (tryb kaskaderski, ale działa też w Furii): skoki
## z obrotami, pętle i beczki. Czysta logika - gra woła `step(...)` raz na
## krok fizyki gracza (koszt: kilka mnożeń), zwraca listę zakończonych
## sztuczek, które idą do ScoreKeeper.award_free(kind, points, now, text).
##
## Wejście w kroku: basis auta (świat), prędkość kątowa (świat, rad/s),
## liczba kół na ziemi, prędkość [m/s], wektor "góra" toru w tym miejscu
## (dla zwykłej drogi Vector3.UP; na pętli normalna jezdni - wtedy jazda
## po pętli nie jest "dachowaniem"), czas.
##
## W powietrzu: całkujemy prędkość kątową w układzie auta - x = przewrót
## (salto przód/tył), z = beczka (obrót wokół osi jazdy), y = obrót płaski.
## Po lądowaniu: pełne obroty z tolerancją LAND_TOL (np. 300° liczy się jako
## 1 obrót, jeśli auto wylądowało na kołach), czyste lądowanie = auto
## równo z jezdnią (basis.y · góra toru > CLEAN_DOT) i wszystkie 4 koła
## w ciągu CLEAN_TIME.
##
## Na ziemi: całkujemy obrót wokół osi x i z auta względem świata. Pętla =
## |przewrót| ≥ ~330° bez oderwania; beczka (korkociąg) = |obrót z| ≥ ~330°.
## Liczniki zerują się, gdy auto stoi prosto (basis.y.y > 0,95) przez
## RESET_TIME - zwykłe garby i łuki nie uzbierają pełnego obrotu.

const MIN_AIR := 0.35          # [s] krótsze oderwania to nie skok
const LAND_TOL := 1.0471976       # 60°
const CLEAN_DOT := 0.9
const CLEAN_TIME := 0.3
const FULL_TURN := 5.7595865      # 330°
const RESET_TIME := 1.5

const POINTS := {
	"air_unit": 100,       # jednostka punktów za czas lotu (air_units)
	"flip": 400,           # salto (za pełny obrót)
	"roll": 350,           # beczka w powietrzu
	"spin": 150,           # obrót płaski 360°
	"clean": 1.5,          # mnożnik za czyste lądowanie
	"loop": 600,           # pętla
	"barrel": 500,         # przejazd przez beczkę (korkociąg)
}

var airborne := false
var air_t := 0.0
var _air_rot := Vector3.ZERO      # x przewrót, y obrót płaski, z beczka
var _landing_t := -1.0            # czas od pierwszego dotknięcia (ocena lądowania)
var _pending := {}                # skok czekający na ocenę lądowania
var _ground_rot := Vector2.ZERO   # x przewrót, y beczka (na ziemi)
var _upright_t := 0.0


## Jeden krok. Zwraca listę sztuczek: {kind, points, text, ...}.
func step(delta: float, basis: Basis, ang_vel: Vector3, wheels: int,
		speed: float, track_up: Vector3 = Vector3.UP) -> Array:
	var out := []
	var local_w := basis.inverse() * ang_vel
	if wheels == 0:
		if not airborne:
			airborne = true
			air_t = 0.0
			_air_rot = Vector3.ZERO
			_pending = {}
			_landing_t = -1.0
		air_t += delta
		_air_rot += local_w * delta
	else:
		if airborne:
			airborne = false
			if air_t >= MIN_AIR:
				_pending = {"air_t": air_t, "rot": _air_rot}
				_landing_t = 0.0
		if not _pending.is_empty():
			_landing_t += delta
			var level := basis.y.dot(track_up.normalized()) > CLEAN_DOT
			if wheels == 4 or _landing_t > CLEAN_TIME:
				var clean := wheels == 4 and _landing_t <= CLEAN_TIME and level
				out.append(_score_jump(_pending, clean, level))
				_pending = {}
		# Na ziemi: pętle i beczki.
		_ground_rot += Vector2(local_w.x, local_w.z) * delta
		if basis.y.y > 0.95:
			_upright_t += delta
			if _upright_t > RESET_TIME:
				_ground_rot = Vector2.ZERO
		else:
			_upright_t = 0.0
		if absf(_ground_rot.x) >= FULL_TURN:
			out.append({"kind": "loop", "points": POINTS["loop"], "text": "PĘTLA",
					"speed_kmh": speed * 3.6})
			_ground_rot.x = 0.0
		if absf(_ground_rot.y) >= FULL_TURN:
			out.append({"kind": "barrel", "points": POINTS["barrel"], "text": "BECZKA",
					"speed_kmh": speed * 3.6})
			_ground_rot.y = 0.0
	return out


## Punkty za czas lotu zakończonego przeżyciem (użytkownik 2026-11-09:
## "im dłuższy i zakończony przeżyciem, tym więcej punktów"; 1 jednostka =
## POINTS.air_unit = 100 pkt): lot < 2 s - nic; 2-10 s - 1; od 10 do 30 s
## +1 co 5 s; od 30 do 40 s +1 co 2 s; potem +1 co sekundę.
static func air_units(t: float) -> int:
	if t < 2.0:
		return 0
	var u := 1
	if t >= 10.0:
		u += int(floor((minf(t, 30.0) - 10.0) / 5.0))
	if t >= 30.0:
		u += int(floor((minf(t, 40.0) - 30.0) / 2.0))
	if t >= 40.0:
		u += int(floor(t - 40.0))
	return u


## Ocena skoku po lądowaniu. Obroty liczą się tylko przy lądowaniu na
## kołach (`level`) - na dachu nie ma punktów za salto.
func _score_jump(p: Dictionary, clean: bool, level: bool) -> Dictionary:
	var rot: Vector3 = p["rot"]
	var flips := _turns(rot.x) if level else 0
	var spins := _turns(rot.y) if level else 0
	var rolls := _turns(rot.z) if level else 0
	# Za czas lotu tylko po wylądowaniu na kołach (przeżycie).
	var pts := float(POINTS["air_unit"] * (air_units(float(p["air_t"])) if level else 0))
	pts += POINTS["flip"] * flips + POINTS["spin"] * spins + POINTS["roll"] * rolls
	if clean:
		pts *= float(POINTS["clean"])
	var parts := PackedStringArray()
	if flips > 0:
		parts.append("SALTO" + (" x%d" % flips if flips > 1 else ""))
	if rolls > 0:
		parts.append("BECZKA" + (" x%d" % rolls if rolls > 1 else ""))
	if spins > 0:
		parts.append("OBRÓT" + (" x%d" % spins if spins > 1 else ""))
	if parts.is_empty():
		parts.append("SKOK %.1f s" % float(p["air_t"]))
	if clean:
		parts.append("CZYSTO")
	return {"kind": "jump", "points": int(round(pts)), "text": " ".join(parts),
			"air_t": p["air_t"], "flips": flips, "rolls": rolls, "spins": spins,
			"clean": clean}


## Pełne obroty z tolerancją: 300° = 1, 650° = 2 (przy LAND_TOL 60°).
static func _turns(a: float) -> int:
	return int(floor((absf(a) + LAND_TOL) / TAU))
