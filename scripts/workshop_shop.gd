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
## Ceny zależą od auta (użytkownik 2026-11-09: "naprawy poszczególnych
## uszkodzeń z cenami zależnymi od auta"): słownik `car` =
## {"mass": kg, "kw": moc, "type": "petrol"|"diesel"|"electric", "hub": bool}
## (patrz `car_spec`). Pusty słownik = auto odniesienia (1300 kg, 130 kW,
## benzyna) - mnożniki 1,0, ceny jak w tabeli RATES.
##
## Dwa miejsca sprzedaży (`venue`): "workshop" (warsztat w mieście - wszystko)
## i "station" (stacja: tylko naprawy, drożej o STATION_MARKUP, bez rabatu
## za pełną naprawę i bez zakupów). Na stacji auto musi stać na pasie stacji
## (xr_main), tak jak w warsztacie.
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

const STATION_MARKUP := 1.25
## Auto odniesienia dla cen z RATES.
const REF_MASS := 1300.0
const REF_KW := 130.0

## Zakupy poza naprawą (tylko w warsztacie). `effect` interpretuje gra
## (xr_main / StuntCar); ceny do strojenia, część skalowana autem
## (`scale`: "body" - masa, "life" - masa i moc, "tank" - rodzaj napędu).
## Wymiana silnika to osobne oferty `engine_offer` (zależne od progu mocy).
## Jawne pomoce oznaczone `aid` - zawsze wyłączalne w menu (CLAUDE.md: bez
## ukrytych ułatwień).
const UPGRADES := [
	{"id": "life", "label": "Zapasowe auto (+1 życie)", "cost": 2500, "effect": "life", "scale": "life"},
	{"id": "bullbar", "label": "Orurowanie przodu (+masa, taran)", "cost": 900, "effect": "bullbar", "scale": "body"},
	{"id": "tank", "label": "Większy bak / bateria (+40%)", "cost": 700, "effect": "tank", "scale": "tank"},
	{"id": "cb_radio", "label": "Radio CB: boty w szale na mapce", "cost": 600, "effect": "cb_radio", "aid": true},
]
## Wymiana silnika: cena za kW mocy nowego silnika (130 kW benzyna = 1300 pkt),
## mnożnik rodzaju napędu, minus odkup starego (ENGINE_TRADE_IN jego ceny,
## pomniejszony o uszkodzenie).
const ENGINE_PER_KW := 10.0
const ENGINE_TYPE_MUL := {"petrol": 1.0, "diesel": 1.1, "electric": 1.3}
const HUB_MUL := 1.5
const ENGINE_TRADE_IN := 0.4


## Słownik `car` z auta (StuntCar albo cokolwiek z tymi polami).
static func car_spec(c) -> Dictionary:
	return {"mass": float(c.car_mass), "kw": float(c.engine_power_kw),
			"type": String(c.engine_type), "hub": bool(c.hub_motors)}


## Mnożnik ceny strefy dla auta: karoseria, hamulce i zawieszenie rosną
## z masą, silnik z mocą (elektryk droższy, silniki w kołach jeszcze
## bardziej), skrzynia słabiej z mocą (elektryk: jedna przekładnia).
static func zone_factor(car: Dictionary, zone: String) -> float:
	if car.is_empty():
		return 1.0
	var m := maxf(float(car.get("mass", REF_MASS)), 300.0) / REF_MASS
	var p := maxf(float(car.get("kw", REF_KW)), 10.0) / REF_KW
	var t := String(car.get("type", "petrol"))
	match zone:
		"engine":
			var f := pow(p, 0.6) * (1.2 if t == "electric" else 1.0)
			return f * (HUB_MUL if car.get("hub", false) else 1.0)
		"gearbox":
			return pow(p, 0.4) * (0.5 if t == "electric" else 1.0)
		_:
			return pow(m, 0.7)


## Cena nowego silnika `type` o mocy `kw` przy obecnym aucie `car`
## (z odkupem starego). Nigdy poniżej 10 pkt.
static func engine_cost(type: String, kw: float, car: Dictionary = {}, damage: Dictionary = {}, hub := false) -> int:
	var price := ENGINE_PER_KW * kw * float(ENGINE_TYPE_MUL.get(type, 1.0)) * (HUB_MUL if hub else 1.0)
	if not car.is_empty():
		var old := ENGINE_PER_KW * float(car.get("kw", 0.0)) \
				* float(ENGINE_TYPE_MUL.get(String(car.get("type", "petrol")), 1.0)) \
				* (HUB_MUL if car.get("hub", false) else 1.0)
		price -= old * ENGINE_TRADE_IN * (1.0 - clampf(float(damage.get("engine", 0.0)), 0.0, 1.0))
	return maxi(_round10(price), 10)


## Oferta wymiany silnika do menu warsztatu (xr_main buduje listę silników
## z progów mocy i dokłada te oferty). Efekt przy zakupie: "engine".
static func engine_offer(type: String, kw: float, label: String, points: int,
		car: Dictionary = {}, damage: Dictionary = {}, hub := false) -> Dictionary:
	var c := engine_cost(type, kw, car, damage, hub)
	return {"id": "engine:%s:%d%s" % [type, int(kw), ":hub" if hub else ""], "label": label,
			"cost": c, "affordable": c <= points}


static func _upgrade_cost(u: Dictionary, car: Dictionary) -> int:
	var base := float(u["cost"])
	if car.is_empty():
		return int(base)
	match String(u.get("scale", "")):
		"body":
			return _round10(base * zone_factor(car, "structure"))
		"life":
			# Zapasowe auto: takie samo jak obecne - masa i moc.
			return _round10(base * 0.5 * (zone_factor(car, "structure") + zone_factor(car, "engine")))
		"tank":
			return _round10(base * (1.6 if String(car.get("type", "")) == "electric" else 1.0))
	return int(base)


## Koszt naprawy jednej strefy przy danym uszkodzeniu, dla auta `car`
## w miejscu `venue`.
static func zone_cost(damage: Dictionary, zone: String, car: Dictionary = {}, venue := "workshop") -> int:
	var mk := STATION_MARKUP if venue == "station" else 1.0
	return _round10(float(RATES[zone]) * _amount(damage, zone) * zone_factor(car, zone) * mk)


static func _full_cost(damage: Dictionary, car: Dictionary) -> int:
	var total := 0
	for k in RATES:
		if _amount(damage, k) >= MIN_DAMAGE:
			total += zone_cost(damage, k, car)
	return _round10(float(total) * (1.0 - FULL_DISCOUNT))


## Oferty dla menu: naprawy stref z uszkodzeniem, pełna naprawa (gdy więcej
## niż jedna strefa, tylko w warsztacie), ulepszenia jeszcze nie kupione
## (tylko w warsztacie). Każda oferta: {id, label, cost, affordable}.
static func offers(damage: Dictionary, points: int, owned: Array = [], car: Dictionary = {},
		venue := "workshop") -> Array:
	var out := []
	var zones := 0
	for z in RATES:
		if _amount(damage, z) < MIN_DAMAGE:
			continue
		var c := zone_cost(damage, z, car, venue)
		zones += 1
		out.append({"id": "repair:" + z, "label": "%s %d%%" % [LABELS[z], roundi(_level(damage, z) * 100.0)],
				"cost": c, "affordable": c <= points})
	if venue == "station":
		return out
	if zones > 1:
		var full := _full_cost(damage, car)
		out.push_front({"id": "repair:full", "label": LABELS["full"], "cost": full,
				"affordable": full <= points})
	for u in UPGRADES:
		if u["id"] in owned and u["id"] != "life":
			continue
		var uc := _upgrade_cost(u, car)
		out.append({"id": u["id"], "label": u["label"], "cost": uc, "affordable": uc <= points})
	return out


## Zakup oferty `id` za punkty z `keeper` (ScoreKeeper). Naprawa zmienia
## `damage` w miejscu (słownik auta). Zwraca efekt do wykonania przez grę
## ("repaired", "repaired_full", "life", "bullbar", "tank", "cb_radio",
## "engine") albo "" gdy się nie udało (za mało punktów, oferta niedostępna
## w tym miejscu). Wymiana silnika: gra czyta typ i moc z `id`
## ("engine:<typ>:<kW>[:hub]", `parse_engine`).
## Uwaga: pełna naprawa karoserii powinna też wyprostować wgniecenia -
## gra woła wtedy StuntCar.repair() zamiast zerować słownik.
static func buy(id: String, damage: Dictionary, keeper, car: Dictionary = {}, venue := "workshop") -> String:
	if id.begins_with("repair:"):
		var z := id.substr(7)
		var cost := -1
		var effect := ""
		if z == "full":
			if venue == "station":
				return ""
			cost = _full_cost(damage, car)
			effect = "repaired_full"
		elif RATES.has(z):
			cost = zone_cost(damage, z, car, venue)
			effect = "repaired"
		if cost < 0 or not keeper.spend(cost):
			return ""
		if z == "full":
			for k in RATES:
				_clear(damage, k)
		else:
			_clear(damage, z)
		return effect
	if venue == "station":
		return ""
	if id.begins_with("engine:"):
		var e := parse_engine(id)
		if e.is_empty() or not keeper.spend(engine_cost(e["type"], e["kw"], car, damage, e["hub"])):
			return ""
		return "engine"
	for u in UPGRADES:
		if u["id"] == id:
			if keeper.spend(_upgrade_cost(u, car)):
				return String(u["effect"])
			return ""
	return ""


## "engine:electric:250:hub" -> {type, kw, hub}; {} przy złym formacie.
static func parse_engine(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts.size() < 3 or parts[0] != "engine" or not ENGINE_TYPE_MUL.has(parts[1]):
		return {}
	return {"type": parts[1], "kw": float(parts[2]), "hub": parts.size() > 3 and parts[3] == "hub"}


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
