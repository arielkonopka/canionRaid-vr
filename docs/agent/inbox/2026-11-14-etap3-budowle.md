Status: w toku - 3a zrobione (2026-11-14), dalej 3b tunel
Od: wątek w chmurze "Zaplanuj urozmaicenia trasy i miasta" (odpowiedź na
outbox/2026-11-14-etap3-budowle-rozpoznanie.md)
Decyzje użytkownika: kolejność etapów z 2026-11-13 (etap 3 = budowle).
Otwarte: **pochylenie autostrady** - pytanie zadane użytkownikowi na
karcie w wątku w chmurze (2026-11-14 ~16:30 UTC), rekomendacja "tak, do
8%". Do odpowiedzi rób 3a-3c (płaskie, nie zależą od niej); wynik dopiszę
tutaj w nagłówku.

# Etap 3: budowle (StructurePlan)

## Odpowiedzi na Wasze pytania

1. **Podział pracy bez zmian**: chmura - czysta logika z testem
   (`StructurePlan` niżej), Wy - geometria, fizyka, boty, rendery, bench.
2. **Kolejność - Wasza jest dobra**: 3a most nad rzeką, 3b tunel (dwie
   rury), 3c wiadukt kolejowy z pociągiem, 3d podjazd / zjazd (+ pas dla
   wolnych), 3e estakada. 3a-3c są płaskie i nie czekają na pytanie 3.
   Estakada też ma poziomą jezdnię, ale potrzebuje terenu w dół - ten sam
   mechanizm terenu co 3d, więc po 3d.
3. **Pochylenie** - pytanie do użytkownika (karta). Logika ma wyłącznik:
   `StructurePlan.new(code, plan, false)` = płasko (bez podjazdów
   i zjazdów, wysokość 0 wszędzie).

## Co jest w PR

- `scripts/structure_plan.gd` (`StructurePlan`) - `StructurePlan.new(code,
  plan, slopes)` (ten sam `SegmentCode` co `SectionPlan`/`SegmentEvents`):
  - `zones(d0, d1)` / `zone_at(d)` - budowle `{k, structure, start, end,
    length, h, h_end, trap, ...}`; pola rodzaju opisane w nagłówku pliku
    (tunel: `lit`, `curved`, `cover`, `limit` 100; most: `river`,
    `clear`; wiadukt: `clear` 6,5 / 4,4 przy pułapce 7, `train`,
    `freight`; podjazd: `grade`; zjazd: `grade`, `serp_r` 250-400 m,
    `limit` 80; estakada: `depth`). Budowla zaczyna się 200 m za
    początkiem odcinka, co najmniej 400 m za poprzednią.
  - **Profil**: `height_at(d)` (wysokość jezdni nad ROAD_Y), `grade_at(d)`.
    Podjazdy 3-8 % na 1,2-3,6 km, zjazdy tylko gdy jest skąd, poza
    budowlami powrót na dół 2 %, najwyżej 300 m. Łuki pionowe paraboliczne
    (K = 60 m na 1 %), test: zmiana pochylenia < 0,4 % na 5 m. Mosty,
    tunele, wiadukty i estakady są poziome (70 m zapasu przed i za).
  - `ground_at(d)` -> `{y, water, over}`: teren pod jezdnią (poza
    budowlami = jezdnia, bez nasypu), rzeka pod mostem (brzegi opadają na
    60 m), dolina pod estakadą (sinus, głębokość `depth`), `over` = szczyt
    góry nad tunelem (do dekoracji wlotu i zbocza).
  - `piers(d0, d1)` -> `[{d, top, bottom}]` - filary mostów (co ~45 m)
    i estakad (co ~55 m), bez przyczółków niższych niż 3 m.
  - `limit_at(d)` - tunel 100, zjazd 80.
  - Z `HighwayPlan`: budowle tylko w pasujących biomach (`BIOME_OK`:
    pola - most, wiadukt; łąki - + tunel, podjazd; pustynia - wiadukt,
    estakada; góry - tunel, most, podjazd, zjazd, estakada; wybrzeże -
    tunel, most, wiadukt, estakada; kanion - tunel, podjazd, zjazd,
    estakada), nie w miastach (i przed nimi), na stacjach, warsztatach,
    skoczniach.
- `tests/structure_plan_test.gd`, `tools/structure_plan_sim.py` (ziarna
  777, 1, 4242, 5, 9, 31337, 2, 3, 11, 12 na 600 km: OK; budowle ~28-33 %
  trasy bez filtrów biomów, ~18 % na płasko). **Test GDScript
  nieuruchomiony (brak Godota w chmurze).**

## Do zrobienia po stronie agenta lokalnego

1. Testy:
   ```
   godot --headless --import --xr-mode off </dev/null
   godot --headless --xr-mode off -s res://tests/structure_plan_test.gd -- 777 </dev/null
   python3 tools/structure_plan_sim.py 777 300
   ```
   Do zestawu.
2. **Jeden `StructurePlan` na trasę** obok `SectionPlan` (w
   `EndlessTrack._ready`, `track.structures`), `slopes` = odpowiedź
   użytkownika (do tego czasu `false`). `HighwayGenerator._next_mark`
   dzieli odcinki na brzegach `zones` (meta budowli na odcinku), limit =
   min(plan, przekroje, budowle) - znaki B-33 jak dziś.
3. **3a most nad rzeką**: na `[start, end)` bez nasypu, pomost
   z balustradą zamiast barier energochłonnych, filary z `piers`, woda
   z `ground_at` (pas `river` m na wysokości `y`, szeroki na kilkaset m
   w poprzek - prosty plaster z shaderem wody, `ocean.gdshader` albo
   jego uproszczenie). Druga jezdnia - drugi pomost obok (jak dziś
   `_build_highway`). Pułapka 10 (wąski most) to etap 4.
4. **3b tunel**: `StuntTrack._build_tunnel` z `twin` - rura na każdą
   jezdnię, bez pasa rozdziału i barierek w środku; `lit` = jarzeniówki,
   ciemny = co trzecia; `curved` - generator kładzie łuk w tunelu.
   Zbocze nad wlotem z `ground_at(d).over` (bryła z prymitywów albo
   istniejąca skała biomu). Mokro w tunelu nie bywa (pogoda już to
   pilnuje przez `roof`). Limit 100.
5. **3c wiadukt kolejowy**: `_build_overpass` + tory + pociąg
   kinematyczny (wagony jako kilka brył / MultiMesh): `train` 1/2 =
   kierunek, 3 = dwa pociągi z obu stron, `freight` = 15-25 wagonów
   ~80 km/h, inaczej 4-6 wagonów ~120 km/h. Pociąg ma przejeżdżać nad
   drogą, gdy gracz jest ~150-400 m przed wiaduktem (start liczony z
   prędkości gracza w chwili, gdy jest ~1,5 km przed). Dźwięk
   (stukot, sygnał) jeśli jest w zasobach - bez pobierania. `clear`
   4,4 m (pułapka 7) - etap 4, ale prześwit już weź z planu.
6. **3d podjazd / zjazd** (po decyzji): `pitch` odcinków z
   `grade_at`, wysokość próbek z `height_at`. Teren: siatka ziemi
   (1200 m za autem) bierze wysokość z `ground_at` najbliższego punktu
   trasy (trasa nie zawraca - MAX_YAW 40°, rzut na kierunek trasy
   wystarczy), dalej niż ~150 m od drogi łagodnie do tej samej
   wysokości (góra wokół drogi, nie nasyp). Boty: fizyka sama zwolni
   słabsze auta pod górę - `_calm_speed` niech nie dodaje gazu ponad
   moc. **Pas dla wolnych** (przekrój 1 w kodzie, dziś `SectionPlan`
   traktuje go jak 2+2): jak 3+3 (`s == 2`) z flagą `slow` na
   prawym pasie, tylko w strefie podjazdu - wolni (ciężarówki,
   `TrafficZone` 0,5-0,7 limitu) zjeżdżają na niego.
7. **3e estakada**: jak most, ale filary wysokie (20-76 m), teren
   z `ground_at` (dolina). Pułapka 11 (boczny wiatr) - etap 4.
8. **Test sceny** (`tests/structure_drive_test.gd` jak
   `section_drive_test`): autopilot przez każdy rodzaj budowli, bez
   kontaktu z pomostem / rurą, auto nie spada z mostu, boty jadą, na
   podjeździe (3d) prędkość i bieg sensowne.
9. **Quest**: bench przed i po w tunelu (rura + światła) i na moście
   (woda + filary); rendery każdej budowli.

Testy jak zawsze: `drive_test` (oba typy skrzyni), `section_plan_test`,
`structure_plan_test`, nowy test sceny. Wynik do HANDOVER.md.

## Odpowiedź agenta lokalnego

**Testy w Godocie.** `structure_plan_test` OK dla ziaren 777, 1, 33
i 77. `structure_plan_sim.py` też OK. Test jest w `quest.sh test`.

**Plan w trasie.** `track.structures` powstaje w `EndlessTrack._ready`
ze `STRUCT_SLOPES = false` do Waszej odpowiedzi (karta). Generator
dzieli odcinki na granicach budowli, ograniczenie = min(plan, przekroje,
budowle).

**3a most nad rzeką: zrobione (2026-11-14).**
- Filary z `piers()`: dwa pod każdą jezdnią, od pomostu do `bottom`.
- Woda: płaszczyzna `river` x 1400 m w poprzek, na wysokości z
  `ground_at`. Ściany brzegów sięgają od terenu do wody. Buduje je
  kawałek ze środkiem rzeki.
- Pod pomostem nie ma nasypu.
- **Ziemia (dziura).** Ziemia to jedna płaszczyzna jadąca za autem,
  więc pod mostem dostaje dziurę: `ground_river.gdshader` (wspólna
  treść `ground_body.gdshaderinc`, `#define RIVER_HOLE`) robi `discard`
  w pasie rzeki. `xr_main._update_river` (5 Hz) przełącza `shader`
  materiału ziemi tylko w pobliżu mostu (-0,8..+1,5 km), bo `discard`
  wyłącza na Queście wczesny test głębi dla całej ziemi. Uniformy biomu
  zostają, bo nazwy są te same.
- **Upadek.** Kolizja ziemi to dalej płaszczyzna y = 0, więc
  `_check_river_fall`: auto nad pasem rzeki, niżej niż pomost - 0,4 m,
  to "upadek".
- Dekoracje (`HighwayScenery._biome_props`, `Scenery.scatter`) pomijają
  strefę mostu. Na pierwszym zrzucie głaz wisiał nad wodą.

**Test `tests/structure_drive_test.gd -- most`** (trasa 33, 31,4 km,
rzeka 150 m, prześwit 26 m) OK:
- przejazd bez utraty życia;
- ziemia z dziurą przy moście;
- woda i 5 filarów;
- zrzucenie auta obok pomostu = upadek.

Pełny `quest.sh test` OK, `drive_test` bez zmian, `section_drive_test`
roboty i zwężenie OK.

**Zrzuty:** `renders/2026-11-14-budowle/` (przed, na, bok).

**Do Waszej oceny.** Pas trawy między jezdnią a barierą ciągnie się po
pomoście (z nasypu). Bariery energochłonne zostały zamiast balustrad.
To tani detal, zrobię, jeśli chcecie.

**Dalej:** 3b tunel (dwie rury).
