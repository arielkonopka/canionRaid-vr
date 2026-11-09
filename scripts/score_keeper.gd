extends RefCounted
class_name ScoreKeeper

## Punkty za furię drogową: ucieczka albo walka (specyfikacja
## docs/agent/inbox/2026-11-08-punktacja-szalu.md, decyzje użytkownika tamże).
##
## Czysta logika, bez węzłów i bez fizyki: gra (BotDriver, xr_main) zgłasza
## zdarzenia, ScoreKeeper liczy punkty, serię i portfel. Dzięki temu da się
## to testować bez sceny (tests/score_test.gd) i nic nie kosztuje co klatkę -
## każda metoda jest wołana tylko przy zdarzeniu.
##
## Czas `now` [s] podaje wołający (np. race_time albo zegar jazdy), żeby test
## mógł go przesuwać.
##
## Integracja (po stronie gry):
##   - bot wpada w szał           → open_chase(id, origin, now)
##   - kontakt bot-gracz          → note_contact(id, now)
##   - uszkodzenia bota po kontakcie → damage_dealt(id, d_structure, now, kmh)
##   - koniec fazy ataku          → end_attack(id, hit, min_gap, kmh, now)
##   - bot zgubiony 700 m za      → close_chase(id, "lost", now, kmh)
##   - szał wygasł                → close_chase(id, "calmed", now, kmh)
##   - wybuch bota                → close_chase(id, "wreck", now, kmh)
##   - inne (pit, wmanewrowanie, skok, formacja) → award(kind, id, now, kmh)
##   - sztuczka (StuntTracker)    → award_free(kind, pts, now, label)
##   - nowy odcinek               → new_section()
## Każda metoda zwraca listę wypłat (Dictionary: kind, points, combo, text)
## do wyświetlenia (pula Label3D, tylko przy zdarzeniu) i do logu
## (log_line - "SCORE: ...").

## Pochodzenie szału. "player_hit": gracz uderzył spokojnego bota. Od
## 2026-11-09 (użytkownik: "ścigałem się z botami i nie dostałem punktów za
## stłuczki" -> wybór "bez mandatu, punkty za wszystko") bez mandatu, a taki
## pościg płaci jak każdy inny. Wcześniej: mandat -100 i pościg bez punktów. "reinforce": posiłki.
## "overtake": furia po wyprzedzeniu. "self": bot sam zaczął (na przyszłość).
const ORIGINS := ["player_hit", "reinforce", "overtake", "self"]

## Punkty bazowe. Strojenie tylko tutaj (albo nadpisanie `base` w instancji).
const BASE := {
	# ucieczka
	"lost": 120,          # bot w szale zgubiony (znika za graczem)
	"calmed": 80,         # szał wygasł, bot ani razu nie trafił gracza
	"dodge": 40,          # atak bez kontaktu, minął o < NEAR_MISS
	"ambush_dodge": 120,  # unik zasadzki (wyjazd przed maskę) - premia (wizja)
	"outmaneuver": 150,   # bot rozbił się o coś innego tuż po uniku
	"jump_escape": 200,   # gracz przeskoczył, bot zepsuł skok
	# walka
	"wreck": 300,         # eksplozja bota, ostatni kontakt gracza < BLAME_TIME (premia)
	"damage": 400,        # obrażenia zadane: za 100% "structure" bota
	"pit": 150,           # gracz obrócił bota (> 90°)
	"formation": 250,     # rozbita formacja (kleszcze, ściana)
	# kara
	"fine": -100,         # uderzenie spokojnego bota (mandat)
}
## Napisy na wyskakujących etykietach (krótkie - VR, czytane kątem oka).
const LABELS := {
	"lost": "ZGUBIONY", "calmed": "USPOKOJONY", "dodge": "UNIK", "ambush_dodge": "ZASADZKA!", "damage": "TRAFIENIE",
	"outmaneuver": "WMANEWROWANY", "jump_escape": "SKOK!",
	"wreck": "ROZBITY", "pit": "OBRÓCONY", "formation": "PRZEBITY",
	"fine": "MANDAT",
}
const NEAR_MISS := 1.5        # [m] - unik, gdy minął bliżej niż tyle
const BLAME_TIME := 3.0       # [s] - wybuch liczony graczowi po kontakcie
const DAMAGE_STEP := 0.1      # wypłata za obrażenia co 10% "structure"
const COMBO_WINDOW := 12.0    # [s] - kolejne zdarzenie przedłuża serię
const COMBO_STEP := 0.25      # mnożnik serii: 1 + krok·(n-1)
const COMBO_MAX := 3.0
## Malejąca nagroda za kolejne pościgi w odcinku: 1 / (1 + k·n).
## Użytkownik: farmienie mu nie przeszkadza, więc domyślnie wyłączone.
var diminish_k := 0.0

var base: Dictionary = BASE.duplicate()
var points := 0               # portfel (do wydania w warsztacie)
var total_earned := 0         # suma zarobionych (statystyka, wynik)
var combo := 0
var _combo_t := -1000.0
var _section_chases := 0
## id bota → karta pościgu (Dictionary).
var chases := {}


## Bot wpada w szał. Zwraca wypłaty (dziś zawsze pusta - mandat zniesiony;
## stała "fine" zostaje, gdyby kara wróciła).
func open_chase(id: int, origin: String, now: float) -> Array:
	if chases.has(id):
		var c: Dictionary = chases[id]
		# Ponowny szał w trakcie pościgu - pochodzenie zostaje pierwsze,
		# chyba że gracz uderzył spokojnego bota (to i tak już mandat).
		c["last_rage_t"] = now
		return []
	chases[id] = {
		"origin": origin,
		"paid": true,
		"start_t": now,
		"last_rage_t": now,
		"attacks": 0,
		"dodges": 0,
		"hits_on_player": 0,
		"last_contact_t": -1000.0,
		"last_dodge_t": -1000.0,
		"min_gap": INF,
	}
	return []


## Kontakt bot-gracz (sygnał body_entered).
func note_contact(id: int, now: float) -> void:
	var c: Dictionary = chases.get(id, {})
	if c.is_empty():
		return
	c["last_contact_t"] = now
	c["hits_on_player"] = int(c["hits_on_player"]) + 1


## Koniec fazy ataku (pit/ram/ambush/block). `hit` - był kontakt w tej
## fazie; `min_gap` - najmniejsza odległość w poprzek [m] przy |ahead| < 4.
func end_attack(id: int, hit: bool, min_gap: float, kmh: float, now: float,
		tactic: String = "") -> Array:
	var c: Dictionary = chases.get(id, {})
	if c.is_empty():
		return []
	c["attacks"] = int(c["attacks"]) + 1
	c["min_gap"] = minf(float(c["min_gap"]), min_gap)
	if hit or min_gap >= NEAR_MISS:
		return []
	c["dodges"] = int(c["dodges"]) + 1
	c["last_dodge_t"] = now
	return award("ambush_dodge" if tactic == "ambush" else "dodge", id, now, kmh)


## Obrażenia zadane botowi przez gracza: przyrost `StuntCar.damage["structure"]`
## bota (0..1) w kontakcie z graczem. Małe przyrosty się sumują i wypłacają
## od DAMAGE_STEP, żeby nie zasypywać gracza napisami. Wybuch daje osobno
## premię "wreck".
func damage_dealt(id: int, d_structure: float, now: float, kmh: float) -> Array:
	var c: Dictionary = chases.get(id, {})
	if c.is_empty() or d_structure <= 0.0:
		return []
	c["dmg_acc"] = float(c.get("dmg_acc", 0.0)) + d_structure
	if float(c["dmg_acc"]) < DAMAGE_STEP:
		return []
	var amount: float = c["dmg_acc"]
	c["dmg_acc"] = 0.0
	if not bool(c["paid"]):
		return []
	var mult := danger(c, now, kmh) * _diminish()
	var n := _bump_combo(now)
	var combo_mult := minf(1.0 + COMBO_STEP * float(n - 1), COMBO_MAX)
	var pts := int(round(float(base["damage"]) * amount * mult * combo_mult))
	return [_pay("damage", pts, n)]


## Koniec pościgu: "lost", "calmed" albo "wreck". Usuwa kartę.
func close_chase(id: int, reason: String, now: float, kmh: float) -> Array:
	var c: Dictionary = chases.get(id, {})
	if c.is_empty():
		return []
	var out := []
	match reason:
		"lost":
			out = award("lost", id, now, kmh)
		"calmed":
			if int(c["hits_on_player"]) == 0:
				out = award("calmed", id, now, kmh)
		"wreck":
			if now - float(c["last_contact_t"]) <= BLAME_TIME:
				out = award("wreck", id, now, kmh)
			elif now - float(c["last_dodge_t"]) <= BLAME_TIME:
				out = award("outmaneuver", id, now, kmh)
	chases.erase(id)
	_section_chases += 1
	return out


## Zdarzenie punktowane z pościgu bota `id`.
func award(kind: String, id: int, now: float, kmh: float) -> Array:
	var c: Dictionary = chases.get(id, {})
	if c.is_empty() or not bool(c["paid"]) or not base.has(kind):
		return []
	var mult := danger(c, now, kmh) * _diminish()
	var n := _bump_combo(now)
	var combo_mult := minf(1.0 + COMBO_STEP * float(n - 1), COMBO_MAX)
	var pts := int(round(float(base[kind]) * mult * combo_mult))
	return [_pay(kind, pts, n)]


## Punkty spoza pościgu (sztuczki z StuntTracker, tryb kaskaderski):
## gotowa wartość `pts`, tylko z mnożnikiem serii.
func award_free(kind: String, pts: int, now: float, label: String = "") -> Array:
	if pts == 0:
		return []
	var n := _bump_combo(now)
	var combo_mult := minf(1.0 + COMBO_STEP * float(n - 1), COMBO_MAX)
	return [_pay(kind, int(round(float(pts) * combo_mult)), n, label)]


## Mnożnik niebezpieczeństwa: czas pościgu, liczba botów w szale, prędkość.
func danger(c: Dictionary, now: float, kmh: float) -> float:
	var t := now - float(c["start_t"])
	var dur := 1.0 + clampf(t / 30.0, 0.0, 1.0)              # 1..2
	var pack := 1.0 + 0.25 * float(maxi(chases.size() - 1, 0)) # +25% za bota
	var spd := clampf(kmh / 100.0, 0.5, 2.0)
	return dur * minf(pack, 2.0) * spd


## Nowy odcinek: zerowanie licznika pościgów (malejąca nagroda).
func new_section() -> void:
	_section_chases = 0


## Wydatek w warsztacie. false, gdy brak punktów.
func spend(amount: int) -> bool:
	if amount < 0 or amount > points:
		return false
	points -= amount
	return true


## Czy seria jeszcze trwa (do wyświetlania "xN" przy wyniku).
func combo_active(now: float) -> bool:
	return combo > 1 and now - _combo_t <= COMBO_WINDOW


## Linia do logu (strojenie po przejazdach na Queście).
static func log_line(p: Dictionary) -> String:
	return "SCORE: %s %+d (seria %d)" % [p["kind"], p["points"], p["combo"]]


func _diminish() -> float:
	return 1.0 / (1.0 + diminish_k * float(_section_chases))


func _bump_combo(now: float) -> int:
	combo = combo + 1 if now - _combo_t <= COMBO_WINDOW else 1
	_combo_t = now
	return combo


func _pay(kind: String, pts: int, n: int, label: String = "") -> Dictionary:
	# Mandat nie schodzi poniżej zera w portfelu.
	points = maxi(points + pts, 0)
	if pts > 0:
		total_earned += pts
	var text := "%+d %s" % [pts, label if label != "" else LABELS.get(kind, kind)]
	if n > 1:
		text += " x%d" % n
	return {"kind": kind, "points": pts, "combo": n, "text": text}
