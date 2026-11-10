extends RefCounted
class_name FeudDirector

## Waśnie między botami (użytkownik 2026-11-09): boty należą do gangów,
## gangi mogą się nawzajem nie lubić; gdy są **w zasięgu wzroku gracza**,
## prowadzą potyczki między sobą. **Atak gracza na bota w potyczce od razu
## łączy wrogów w sojusz** - obie strony (i ich gangi) biorą na cel gracza.
##
## Czysta logika, bez węzłów: xr_main zgłasza zdarzenia (wyprzedzenie,
## kontakt, bliskość), dyrektor mówi, kto kogo atakuje (`target_of`), i zwraca
## zdarzenia do wyświetlenia / punktów. Kosztuje tylko przy zdarzeniach.
## Losowość przez wstrzyknięty RandomNumberGenerator (testy, powtarzalność
## odcinka - jak `_bot_rng`).
##
## Integracja (agent lokalny):
##   - spawn bota: add_bot(id, gang); znika/wybucha: remove_bot(id, now, wybuch)
##   - nowy odcinek: roll_relations(gangi, odcinek)
##   - xr_main (~10 Hz, tylko boty z fizyką): wyprzedzenia bot-bot →
##     on_overtake; pary wrogów bliżej niż NEAR_SPARK_R → on_near;
##     `in_sight` = obaj bliżej niż SIGHT_R od gracza (i najlepiej przed nim)
##   - kontakt (body_entered): on_contact(a, b, now, in_sight); gracz = PLAYER
##   - BotDriver: w potyczce cel = target_of(id) (id bota), w sojuszu PLAYER;
##     NONE → własna logika szału jak dziś (gracz po uderzeniu, posiłki); taktyki działają na dowolny cel (uogólnić `player`
##     w _rage_plan na `target`)
##   - zdarzenia "alliance" → napis "SOJUSZ!" i klakson wszystkich,
##     "feud_wreck" z provoked → ScoreKeeper.award_free(...)

const PLAYER := 0
const NONE := -1

const SIGHT_R := 200.0          # [m] potyczki tylko tak blisko gracza
const NEAR_SPARK_R := 60.0      # [m] wrogowie tak blisko mogą zacząć sami (było 40)
const OVERTAKE_CHANCE := 0.5    # wyprzedzony wróg wpada w szał na wyprzedzającego
## Samoistna potyczka wrogów obok siebie, na sekundę. Użytkownik 2026-11-10:
## więcej walk na naszej jezdni (było 0,08).
const SPARK_CHANCE_PER_S := 0.2
const CONTACT_NEUTRAL_CHANCE := 0.3  # zderzenie botów z gangów neutralnych
const ALLIANCE_TIME := 45.0     # [s] sojusznicy nie walczą ze sobą
const PROVOKE_TIME := 3.0       # [s] potyczka po kontakcie gracza = prowokacja
const FEUD_TIMEOUT := 25.0      # [s] potyczka gaśnie, gdy nikt nikogo nie dopadnie
## Punkty (do ScoreKeeper.award_free) - tylko za potyczki sprowokowane przez gracza.
const POINTS := {"provoke": 150, "feud_wreck": 400}

var rng := RandomNumberGenerator.new()
var gang := {}            # id bota → gang (int)
var target := {}          # id bota → cel (PLAYER / id bota); brak = spokój
var _hostile := {}        # klucz pary gangów → true
var _allied_until := {}   # klucz pary gangów → czas końca sojuszu
var _feud_t := {}         # id bota → czas rozpoczęcia jego potyczki
var _provoked := {}       # id bota → potyczka sprowokowana przez gracza
var _player_touch := {}   # id bota → czas ostatniego kontaktu z graczem


# --- gangi i relacje ---------------------------------------------------

func add_bot(id: int, g: int) -> void:
	gang[id] = g


## Losuje wrogość między gangami na odcinek. Szansa rośnie z odcinkiem
## (stopniowana trudność z wizji): 25% na pierwszych, do 70%.
func roll_relations(gangs: Array, section: int) -> void:
	_hostile.clear()
	var p := clampf(0.25 + 0.015 * float(section), 0.25, 0.7)
	for i in gangs.size():
		for j in range(i + 1, gangs.size()):
			if rng.randf() < p:
				_hostile[_key(gangs[i], gangs[j])] = true


func set_hostile(g1: int, g2: int, on: bool) -> void:
	if on:
		_hostile[_key(g1, g2)] = true
	else:
		_hostile.erase(_key(g1, g2))


## Czy gangi są wrogie w tym odcinku (bez sojuszy - do kolorów scenek).
func gangs_hostile(g1: int, g2: int) -> bool:
	return g1 != g2 and _hostile.has(_key(g1, g2))


func hostile(a: int, b: int, now: float) -> bool:
	if not gang.has(a) or not gang.has(b):
		return false
	var ga: int = gang[a]
	var gb: int = gang[b]
	if ga == gb or allied(ga, gb, now):
		return false
	return _hostile.has(_key(ga, gb))


func allied(g1: int, g2: int, now: float) -> bool:
	return float(_allied_until.get(_key(g1, g2), -1.0)) > now


func target_of(id: int) -> int:
	return int(target.get(id, NONE))


func in_feud(id: int) -> bool:
	return target_of(id) > PLAYER


# --- zdarzenia z gry ---------------------------------------------------

## Bot `passer` wyprzedził bota `passed`.
func on_overtake(passer: int, passed: int, now: float, in_sight: bool) -> Array:
	if not in_sight or not hostile(passer, passed, now) or target_of(passed) == PLAYER:
		return []
	if rng.randf() >= OVERTAKE_CHANCE:
		return []
	return _start_feud(passed, passer, now)


## Wrogowie jadą obok siebie (bliżej niż NEAR_SPARK_R) przez `dt` sekund.
func on_near(a: int, b: int, dt: float, now: float, in_sight: bool) -> Array:
	if not in_sight or not hostile(a, b, now) or in_feud(a) or in_feud(b):
		return []
	if target_of(a) == PLAYER or target_of(b) == PLAYER:
		return []
	if rng.randf() >= SPARK_CHANCE_PER_S * dt:
		return []
	return _start_feud(a, b, now)


## Kontakt dwóch aut; jedno z nich może być graczem (PLAYER).
func on_contact(a: int, b: int, now: float, in_sight: bool) -> Array:
	if a == PLAYER or b == PLAYER:
		var bot := b if a == PLAYER else a
		return _player_hit(bot, now)
	if not in_sight:
		return []
	if target_of(a) == PLAYER or target_of(b) == PLAYER:
		return []                      # w sojuszu przeciw graczowi nie walczą
	if not gang.has(a) or not gang.has(b) or gang[a] == gang[b]:
		return []
	if hostile(a, b, now) or rng.randf() < CONTACT_NEUTRAL_CHANCE:
		var g1: int = gang[a]
		var g2: int = gang[b]
		if allied(g1, g2, now):
			return []
		_hostile[_key(g1, g2)] = true  # zderzenie robi z nich wrogów
		return _start_feud(a, b, now) + _start_feud(b, a, now)
	return []


## Bot znika (`wreck` = wybuch). Jego przeciwnicy wracają do spokoju albo
## szukają innego celu (gra może zawołać on_near dla nowych par).
func remove_bot(id: int, now: float, wreck: bool) -> Array:
	var out := []
	if wreck and in_feud(id):
		var prov := bool(_provoked.get(id, false))
		out.append({"kind": "feud_wreck", "id": id, "provoked": prov,
				"points": POINTS["feud_wreck"] if prov else 0})
	for other in target.keys():
		if int(target[other]) == id:
			target.erase(other)
			_feud_t.erase(other)
			out.append({"kind": "feud_end", "id": other})
	gang.erase(id)
	target.erase(id)
	_feud_t.erase(id)
	_provoked.erase(id)
	_player_touch.erase(id)
	return out


## Co jakiś czas (np. 1 Hz): wygaszanie zbyt długich potyczek.
func update(now: float) -> Array:
	var out := []
	for id in _feud_t.keys():
		if now - float(_feud_t[id]) > FEUD_TIMEOUT and in_feud(id):
			target.erase(id)
			_feud_t.erase(id)
			out.append({"kind": "feud_end", "id": id})
	return out


## Gracz w szale wobec bota zakończył się (BotDriver uspokoił bota).
func calm(id: int) -> void:
	target.erase(id)
	_feud_t.erase(id)


# --- wnętrze -------------------------------------------------------------

func _start_feud(attacker: int, victim: int, now: float) -> Array:
	if target_of(attacker) == victim:
		return []
	target[attacker] = victim
	_feud_t[attacker] = now
	var prov := _touched(attacker, now) or _touched(victim, now)
	_provoked[attacker] = prov
	if prov:
		_provoked[victim] = true
	var ev := {"kind": "skirmish", "a": attacker, "b": victim, "provoked": prov,
			"points": POINTS["provoke"] if prov else 0}
	return [ev]


## Gracz uderzył bota. Bot w potyczce → sojusz: obie strony potyczki i ich
## gangi biorą na cel gracza, a gangi są sojusznikami przez ALLIANCE_TIME.
func _player_hit(bot: int, now: float) -> Array:
	_player_touch[bot] = now
	if not gang.has(bot):
		return []
	var foe := target_of(bot)
	var involved := {}                 # gangi do sojuszu
	involved[gang[bot]] = true
	if foe > PLAYER and gang.has(foe):
		involved[gang[foe]] = true
	for other in target.keys():         # ktoś walczy z tym botem
		if int(target[other]) == bot and gang.has(other):
			involved[gang[other]] = true
	if involved.size() < 2:
		# Bot nie w potyczce: zwykły szał na gracza prowadzi BotDriver
		# (enrage "player_hit"), tu tylko zapamiętany kontakt - wepchnięcie
		# go we wroga w ciągu PROVOKE_TIME to prowokacja.
		return []
	var gs: Array = involved.keys()
	for i in gs.size():
		for j in range(i + 1, gs.size()):
			_allied_until[_key(gs[i], gs[j])] = now + ALLIANCE_TIME
	var ids := []
	for id in gang.keys():
		if involved.has(gang[id]) and (in_feud(id) or id == bot or id == foe):
			target[id] = PLAYER
			_feud_t.erase(id)
			ids.append(id)
	return [{"kind": "alliance", "ids": ids, "gangs": gs}]


func _touched(id: int, now: float) -> bool:
	return now - float(_player_touch.get(id, -1000.0)) <= PROVOKE_TIME


static func _key(g1: int, g2: int) -> int:
	return mini(g1, g2) * 100000 + maxi(g1, g2)
