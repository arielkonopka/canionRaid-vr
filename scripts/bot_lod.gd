extends RefCounted
class_name BotLod

## Poziomy szczegółowości botów (decyzja użytkownika 2026-11-09: przy
## zderzeniach i skokach blisko gracza względnie realistycznie; dalej bot
## może się upraszczać, "i tak go nie widać").
##
##   NEAR  (< NEAR_R): pełne opony (TIRE_SUBSTEPS 2), sterowanie co krok,
##                     uproszczony napęd (BotDriveModel). Tu są zderzenia.
##   MID   (< MID_R):  opony w 1 podkroku, sterowanie ~30 Hz (BotDriver
##                     liczy co MID_STEER_EVERY krok, wejścia trzymane).
##                     Symulator: hamowanie, łuk, zmiana pasa bez zmian,
##                     0-100 +11%, krok -37%.
##   RAIL  (dalej albo ponad budżet): "szyna" jak dziś (BotDriver._update_rail).
##
## Budżet: najwyżej `budget` aut z fizyką (NEAR + MID). NEAR ma zawsze
## fizykę (może dojść do zderzenia z graczem) - budżet obcina tylko MID,
## od najdalszych; boty w szale mają pierwszeństwo przed spokojnymi.
## Histereza HYST m, żeby bot na granicy nie przełączał się co klatkę.
##
## Czysta logika: xr_main woła assign() np. 4× na sekundę (_update_bots),
## a wynik ustawia w botach (TIRE_SUBSTEPS, takt sterowania, szyna).

enum { NEAR, MID, RAIL }

const NEAR_R := 120.0
const MID_R := 320.0        # = BotDriver.LOD_NEAR (wejście z szyny)
const HYST := 20.0
const MID_STEER_EVERY := 4  # 120 Hz / 4 = 30 Hz
const SUBSTEPS := [2, 1, 0]


## dists - odległości botów od gracza [m]; raging - czy bot w szale;
## prev - poprzednie poziomy (pusta tablica przy pierwszym wywołaniu);
## budget - ile aut z fizyką naraz. Zwraca poziom dla każdego bota.
static func assign(dists: PackedFloat32Array, raging: Array, prev: PackedInt32Array,
		budget: int) -> PackedInt32Array:
	var n := dists.size()
	var out := PackedInt32Array()
	out.resize(n)
	var mids := []
	var physics := 0
	for i in n:
		var d := dists[i]
		var p := prev[i] if i < prev.size() else RAIL
		# Histereza: wyjście z bliższego poziomu dopiero HYST m dalej.
		var near_r := NEAR_R + (HYST if p == NEAR else 0.0)
		var mid_r := MID_R + (HYST if p <= MID else 0.0)
		if d < near_r:
			out[i] = NEAR
			physics += 1
		elif d < mid_r:
			out[i] = MID
			mids.append(i)
		else:
			out[i] = RAIL
	# Budżet tylko dla MID: najpierw w szale, potem najbliższe.
	var room := maxi(budget - physics, 0)
	if mids.size() > room:
		mids.sort_custom(func(a, b):
			var ra := bool(raging[a]) if a < raging.size() else false
			var rb := bool(raging[b]) if b < raging.size() else false
			if ra != rb:
				return ra
			return dists[a] < dists[b])
		for k in range(room, mids.size()):
			out[mids[k]] = RAIL
	return out
