extends RefCounted
class_name WorkshopShop

## Cennik warsztatu: naprawy strefami i zakupy za punkty z furii drogowej
## (ScoreKeeper). Czysta logika - menu warsztatu (xr_main) pokazuje
## `offers(...)` i woła `buy(...)`.
##
## Strefy odpowiadają `StuntCar.damage`: "engine", "gearbox", "structure"
## (liczby 0..1) oraz "brakes", "suspension" (tablice 4 kół 0..1).
## Cena = stawka strefy × uszkodzenie (suma kół dla tablic), zaokrąglona
## w górę do 10 pkt. "Pełna naprawa" = suma stref z rabatem.
##
## Skala: jeden porządny pościg daje ~500-800 pkt (tests/score_test.gd),
## pełne rozbicie (wszystko 100%) kosztuje 3700 pkt (pełna naprawa z rabatem
## 3150) - wojownik musi
## zarabiać na naprawy, uciekinier odkłada na ulepszenia.

const RATES := {
	"engine": 900,        # silnik, chłodnica - najdroższe, zabiera moc
	"gearbox": 500,
	"structure": 1000,    # karoseria / ogólny stan (blacharka, wgniecenia)
	"brakes": 150,        # za koło
	"suspension": 175,    # za koło
}
const LABELS := {
	"engine": "Silnik", "gearbox": "Skrzynia", "structure": "Karoseria",
	"brakes": "Hamulce", "suspension": "Zawieszenie", "full": "Pełna naprawa",
}
const FULL_DISCOUNT := 0.15
## Poniżej tego uszkodzenia strefa nie trafia na listę (szum po otarciach).
const MIN_DAMAGE := 0.02

## Zakupy poza naprawą. `effect` interpretuje gra (xr_main / StuntCar);
## ceny do strojenia. Jawne pomoce oznaczone `aid` - zawsze wyłączalne
## w menu (CLAUDE.md: bez ukrytych ułatwień).
const UPGRADES := [
	{"id": "life", "label": "Zapasowe auto (+1 życie)", "cost": 2500, "effect": "life"},
	{"id": "tier_skip", "label": "Mocniejszy silnik o próg wyżej", "cost": 1800, "effect": "tier"},
	{"id": "bullbar", "label": "Orurowanie przodu (+masa, taran)", "cost": 900, "effect": "bullbar"},
	{"id": "tank", "label": "Większy bak / bateria (+40%)", "cost": 700, "effect": "tank"},
	{"id": "cb_radio", "label": "Radio CB: boty w szale na mapce", "cost": 600, "effect": "cb_radio", "aid": true},
]


## Koszt naprawy jednej strefy przy danym uszkodzeniu.
static func zone_cost(damage: Dictionary, zone: String) -> int:
	return _round10(float(RATES[zone]) * _amount(damage, zone))


## Oferty dla menu: naprawy stref z uszkodzeniem, pełna naprawa (gdy więcej
## niż jedna strefa), ulepszenia jeszcze nie kupione. Każda oferta:
## {id, label, cost, affordable}.
static func offers(damage: Dictionary, points: int, owned: Array = []) -> Array:
	var out := []
	var total := 0
	var zones := 0
	for z in RATES:
		if _amount(damage, z) < MIN_DAMAGE:
			continue
		var c := zone_cost(damage, z)
		total += c
		zones += 1
		out.append({"id": "repair:" + z, "label": "%s %d%%" % [LABELS[z], roundi(_level(damage, z) * 100.0)],
				"cost": c, "affordable": c <= points})
	if zones > 1:
		var full := _round10(float(total) * (1.0 - FULL_DISCOUNT))
		out.push_front({"id": "repair:full", "label": LABELS["full"], "cost": full,
				"affordable": full <= points})
	for u in UPGRADES:
		if u["id"] in owned and u["id"] != "life" and u["id"] != "tier_skip":
			continue
		out.append({"id": u["id"], "label": u["label"], "cost": int(u["cost"]),
				"affordable": int(u["cost"]) <= points})
	return out


## Zakup oferty `id` za punkty z `keeper` (ScoreKeeper). Naprawa zmienia
## `damage` w miejscu (słownik auta). Zwraca efekt do wykonania przez grę
## ("repaired", "life", "tier", "bullbar", ...) albo "" gdy się nie udało.
## Uwaga: pełna naprawa karoserii powinna też wyprostować wgniecenia -
## gra woła wtedy StuntCar.repair() zamiast zerować słownik.
static func buy(id: String, damage: Dictionary, keeper) -> String:
	var cost := -1
	var effect := ""
	if id.begins_with("repair:"):
		var z := id.substr(7)
		if z == "full":
			var total := 0
			for k in RATES:
				if _amount(damage, k) >= MIN_DAMAGE:
					total += zone_cost(damage, k)
			cost = _round10(float(total) * (1.0 - FULL_DISCOUNT))
			effect = "repaired_full"
		elif RATES.has(z):
			cost = zone_cost(damage, z)
			effect = "repaired"
		if cost < 0 or not keeper.spend(cost):
			return ""
		if z == "full":
			for k in RATES:
				_clear(damage, k)
		else:
			_clear(damage, z)
		return effect
	for u in UPGRADES:
		if u["id"] == id:
			if keeper.spend(int(u["cost"])):
				return String(u["effect"])
			return ""
	return ""


static func _amount(damage: Dictionary, zone: String) -> float:
	var v = damage.get(zone, 0.0)
	if v is Array:
		var s := 0.0
		for x in v:
			s += float(x)
		return s
	return float(v)


## Poziom do napisu: dla kół - najgorsze koło.
static func _level(damage: Dictionary, zone: String) -> float:
	var v = damage.get(zone, 0.0)
	if v is Array:
		return float(v.max()) if not v.is_empty() else 0.0
	return float(v)


static func _clear(damage: Dictionary, zone: String) -> void:
	var v = damage.get(zone, 0.0)
	if v is Array:
		for i in v.size():
			v[i] = 0.0
	else:
		damage[zone] = 0.0


static func _round10(x: float) -> int:
	return int(ceil(x / 10.0 - 0.0001)) * 10
