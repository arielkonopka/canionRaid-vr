Status: nowe
Od: wątek w chmurze "Zaplanuj urozmaicenia trasy i miasta"
Decyzje użytkownika: 2026-11-11 22:58 UTC "Tak, zleć od razu" - poprawki
botów idą przed resztą planu urozmaiceń. Zgłoszenie użytkownika
(2026-11-11 22:24 UTC): "boty już mamy, są naprawdę ekstra, może za dużo
jedzie w drugą stronę, a za mało w gracza, no i nie powinny znikać tak
na widoku...". Szerszy kontekst (odcinek z 4 bajtów, reżyser napięcia):
dokument "Urozmaicenia trasy: odcinek z 4 bajtów" w wątku - to osobne,
późniejsze zlecenie.

# Boty: nie znikają na widoku, więcej ruchu w stronę gracza

Stan kodu: `main` z 2026-11-11 (po #64). Numery linii z tego stanu.

## 1. Znikanie na widoku

`TrafficZone.visible` jest sprawdzane przed usunięciem tylko w
`TrafficZone.step` (spokojne auta poza oknem i nadmiar). Inne miejsca
oddają auto do puli bez pytania, czy gracz je widzi:

| Miejsce | Dziś | Kiedy gracz to widzi |
|---|---|---|
| `xr_main.gd:2608` auto z naprzeciwka | `rail = []` gdy `d2 < _last_safe_dist - 150` -> `_pool_oncoming` | lusterko (`MIRROR_DIST` 200 m), obejrzenie się w goglach |
| `xr_main.gd:2598` auto z naprzeciwka po zderzeniu ("loose") | po `LOOSE_TIME` 30 s albo > 400 m od gracza | wrak w lusterku, obejrzenie się po stłuczce |
| `xr_main.gd:2686` scenka `OncomingSkirmish` | `_osk_end()` gdy `oa.dist < gracz - 150` | lusterko |
| `xr_main.gd:1077` bot w szale | > 700 m za albo > 2000 m przed graczem | rzadko, ale na prostej możliwe |
| `traffic_zone.gd:47` `VIEW_DIST` 900 m | auto dalej niż 900 m = "niewidoczne" -> może zniknąć jako nadmiar albo poza oknem | na prostej autostradzie auto 1-1,8 km przed graczem to wciąż widoczna kropka (z reflektorami tym bardziej) |

Prośba:

1. Jedna funkcja w `xr_main`, np. `_can_vanish(node) -> bool`:
   `not TrafficZone.visible(head, head_fwd, car_fwd, pos)` (to samo co w
   `_update_traffic`). Wołana przed **każdym** `_pool_oncoming`,
   `_retire_bot` (poza wrakami po wybuchu - te mają własną scenę),
   `_osk_end` (ukrycie aut scenki). Gdy auto jest widoczne - zostaje
   i próbujemy znowu w następnym kroku (co 0,5 s wystarczy).
2. Auta z naprzeciwka za graczem: szyna do `TrafficZone.BEHIND` (300 m)
   zamiast 150 m, potem `_can_vanish`. Jeśli `rail_at` za graczem nie
   ma już toru (kawałek usunięty), auto zostaje w ostatniej pozycji
   ukryte dopiero, gdy niewidoczne - albo trzymaj kawałek za graczem
   o ten zapas dłużej (co tańsze, wybierz sam).
3. Auto po zderzeniu ("loose"): `LOOSE_TIME` i 400 m zostają jako
   warunek, ale usunięcie dopiero przy `_can_vanish`.
4. `TrafficZone`:
   - nadmiar (`SURPLUS`) usuwać **tylko za graczem**
     (`dist < player_dist`), najdalsze najpierw - przed graczem nadmiar
     sam się rozładuje;
   - przed graczem widoczność do zasięgu rysowania auta
     (`visibility_range_end` modelu auta / jego LOD, jeśli jest; inaczej
     ~2000 m), a nie 900 m. 900 m może zostać dla głowy obróconej do tyłu.
   - Nowe auta i tak pojawiają się poza stożkiem (`_update_traffic`
     sprawdza `visible` przy spawnie) - to zostaje.
5. Test (np. `tests/vanish_test.gd`, logika bez sceny jak
   `highway_plan_test`): auto w stożku głowy albo lusterka nigdy nie
   trafia do `despawn`; nadmiar przed graczem nie jest usuwany.

## 2. Za dużo aut z naprzeciwka, za mało w stronę gracza

To nie gęstość, tylko prędkość mijania. Na kilometr jazdy gracz spotyka:

- z naprzeciwka: `rho * (v_gracza + v_auta) / v_gracza`
- w swoją stronę: `rho * |v_gracza - v_auta| / v_gracza`

Dziś auta w naszą stronę jadą 0,8-1,0 limitu (prawy pas, 70%) i
0,95-1,1 (lewy) - `traffic_zone.gd:132`. Przy graczu 140 km/h średnia
różnica to ~9 km/h, więc mimo `SAME_DIR_MULT` 2,5 aut z naprzeciwka
spotyka się ~12 razy częściej (przy 180 km/h ~2,5 raza). W strefie
miasta mnożnika nie ma wcale.

Prośba (wartości startowe, do oceny z użytkownikiem w goglach):

1. **Wolniejszy prawy pas**: ok. 40% aut prawego pasa to "ciężarówki"
   i wolni: 0,5-0,7 limitu (70-100 km/h przy 140), reszta jak dziś.
   Jeśli jest model ciężarówki/dostawczaka w `CarStyles` - ten wygląd;
   jeśli nie, zwykłe auto (bez nowych pobrań).
2. **Doganianie od tyłu**: ok. 25% nowych aut w naszą stronę pojawia się
   300-600 m **za** graczem (poza stożkiem lusterka - `visible` jak przy
   spawnie przed graczem) z prędkością 1,15-1,35 limitu, na lewym pasie.
   W lusterku rośnie światło, które może być furiatem - napięcie bez
   nowej mechaniki.
3. `SAME_DIR_MULT` także w strefie miasta (np. 1,5), żeby przy miastach
   nie wracała przewaga aut z naprzeciwka.
4. Zmierz w `highway_plan_test` / nowym teście: liczba spotkań na km
   (wyprzedzenia + bycie wyprzedzanym vs mijanie z naprzeciwka) przy
   graczu 140 i 180 km/h; cel na start: stosunek nie gorszy niż 1 : 2.

"Za mało w gracza" w pełni rozwiąże dopiero bajt zdarzeń z planu
urozmaiceń (kierowca pod prąd, zasadzka z wjazdu, blokada) - osobne
zlecenie. Tu tylko ruch i znikanie.

## Testy po zmianie

`drive_test` (zgodnie z CLAUDE.md), nowy test znikania, `highway_plan_test`,
krótka jazda w goglach: spojrzenie w lusterko po minięciu auta
z naprzeciwka i obejrzenie się po stłuczce - auto ma zostać.
Wynik do HANDOVER.md.
