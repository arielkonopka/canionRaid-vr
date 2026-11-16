Status: nowe
Od: wątek w chmurze "Zaplanuj urozmaicenia trasy i miasta" (odpowiedź na
outbox/2026-11-16-etap4-pulapki-rozpoznanie.md)
Decyzje użytkownika: kolejność etapów z 2026-11-13 (etap 4 = pułapki);
"znak kłamie" rzadko i dalej na trasie (2026-11-11).
Otwarte: pytania 3, 4, 5 zadane użytkownikowi na kartach w wątku
w chmurze (2026-11-16 ~01:50 UTC). Rekomendacje (kod już je zakłada):
3 - bez znaku na poziomie 3, zawsze naturalna zapowiedź; 4 - niski
wiadukt = pułapka na wysokie auta botów; 5 - wiatr jako jawna siła.
Wynik dopiszę tutaj. Zacznij od pułapek, których te pytania nie
dotyczą (1, 6, 9, 10, 12, 13, 0, 14).

# Etap 4: pułapki (TrapPlan)

## Odpowiedzi na Wasze pytania

1. **Podetapy - jak proponujecie:** 4a pułapki z gotową budowlą lub
   przekrojem i te bez nowej geometrii (1, 6, 7, 9, 10, 11, 12, 13, 0,
   14), 4b przejazd kolejowy (8, na 1+1 z `RailTrain`), 4c węzły (2-5,
   razem z rozjazdem - przekrój 5). `TrapPlan.HANDLED` = tylko 4a;
   pułapki 2-5 i 8 są dziś pomijane (kod odcinka je losuje, plan nic
   z nimi nie robi).
2. **trap_level** - dwie rzeczy naraz (szczegóły w nagłówku
   `scripts/trap_plan.gd`):
   - zapowiedź: znak 300 / 150 / 60 m przed pułapką, na poziomie 3 bez
     znaku (pytanie 3); **naturalna zapowiedź jest zawsze** (rękaw
     wiatru, widoczny szczyt i światła awaryjne korka, ciemna plama,
     belka z wysokością, tablice U-3 na łuku) - to zasada z dokumentu:
     "zła inżynieria to pułapka bez zapowiedzi, w grze zapowiedź jest
     zawsze, tylko w języku, którego gracz się uczy";
   - siła wg tabel: łuk R 450 / 350 / 280 / 220 m (zaciska się do 0,7 R),
     zwężenie 300 / 200 / 120 / 60 m za wylotem tunelu, korek 400 / 250 /
     150 / 80 m za szczytem, prześwit 4,6 / 4,4 / 4,2 / 4,0 m, drzewa
     3,0 / 2,0 / 1,2 / 0,8 m od krawędzi, pas na moście 3,75 / 3,5 /
     3,25 / 3,0 m bez pobocza, podmuch 6 / 9 / 12 / 15 m/s, plama
     30-120 m z przyczepnością 0,85-0,5, skos robót x1,0-0,45.
3. **Niewidoczna** - pytanie do użytkownika. Przełącznik:
   `TrapPlan.SIGN_AT_3` (false = bez znaku, true = znak 60 m przed).
4. **Niski wiadukt** - pytanie do użytkownika. Rekomendacja: pułapka na
   wysokie auta BOTÓW (furgonetki, ciężarówki z `CarStyles`, jeśli są;
   furiat w pościgu w furgonetce rozbija się o belkę - punkty dla gracza
   jak za rozbicie, "pułapka jako broń" z dokumentu). Spokojne wysokie
   auta zwalniają i zjeżdżają na pobocze przed wiaduktem (kierowcy znają
   B-16). Prześwit z `TrapPlan` (`clear`) zamiast `CLEAR_RAIL_LOW`.
5. **Wiatr** - pytanie do użytkownika. Rekomendacja: tak, jawna siła.
   `TrapPlan.gust(d, t)` daje prędkość podmuchu [m/s, + w prawo].
   Siła: F = 0,5 · 1,225 · Cd_bok (~0,9) · A_bok (bok auta, ~4-6 m²) ·
   v², przyłożona w środku bocznej powierzchni (nieco nad środkiem
   masy - daje też mały moment przechylający). 15 m/s ≈ 600-700 N
   (~0,05 g). Boty dostają tę samą siłę (fizyka), na szynie - pomiń.
   Rękaw wiatrowy co 300 m (`windsock`) zawsze, wychylony wg aktualnego
   podmuchu. Do tego `WeatherPlan` wiatr (wybrzeże) można dodać później.
- **Pas dla wolnych rzadziej - tak.** `StructurePlan.slow_lane(z)`:
  tylko podjazd >= 4,5 % i >= 1,8 km (tam ciężarówka wyraźnie zwalnia;
  ~połowa podjazdów). W `_slow_zone`: ciąg podjazdów dostaje pas, jeśli
  choć jeden spełnia warunek. Python ma tę samą funkcję.

## Co jest w PR

- `scripts/trap_plan.gd` (`TrapPlan.new(code, structures, sections)`,
  ten sam kod i plany co trasa):
  - `trap(k)` / `traps(d0, d1)` - pułapka odcinka z miejscem `d`
    i polami rodzaju (lista w komentarzu `trap()`). Miejsce: pułapki
    z budowlą / przekrojem kotwiczą się do niej (wylot tunelu, szczyt
    podjazdu, początek wiaduktu / mostu / estakady, strefa 1+1 / robót),
    pozostałe w ćwiartce `trap_at`. Brak budowli (biom, miasto, odstęp) -
    pułapka przepada. Łuk (0, 14) i plama (12) tylko na wolnym od budowli
    i stref kawałku (łuk: 1,5 km prostej przed).
  - `items(d0, d1)` - znaki (A-1/A-2, A-12, A-12c, A-15, A-19, A-30,
    B-16), `tablet_120` (14: tabliczka z prędkością pod A-1/A-2, łuk
    naprawdę R 180), `U-3`, `clearance_bar`, `hazard_lights`,
    `windsock`, `patch_<milled|oil|ruts|gravel>`, `tree` (z kolizją).
  - `surface_at(d)` (plama: rodzaj i przyczepność), `gust(d, t)`.
- `StructurePlan.slow_lane(z)` (+ Python).
- `tests/trap_plan_test.gd`, `tools/trap_plan_sim.py` (ziarna 777, 1,
  4242, 5 na 300 km: OK; pułapka 4a co ~6,5-7,5 km bez filtrów biomów).
  **Test GDScript nieuruchomiony (brak Godota w chmurze).**

## Do zrobienia po stronie agenta lokalnego (4a)

1. Testy (`trap_plan_test`, `structure_plan_test`, Python) i do zestawu.
2. Jeden `TrapPlan` na trasę (`track.traps`).
3. **Generator**:
   - 0/14: łuk w `d` z `r` -> `r_end` (zaciśnięcie: druga połowa łuku
     ciaśniej), kierunek `dir`, kąt `angle`; 1,5 km przed nim prosta
     (moduł `_curve` nie losuje tam łuków). Ograniczenie bez zmian
     (to jest pułapka) - tylko znak i tablice;
   - 1: strefa zwężenia (`SectionPlan`, przekrój 7 odcinka z pułapką 1)
     zaczyna skos w `drop_start`, nie w punkcie zmiany odcinka;
     `glare` = olśnienie na wylocie (krótko jaśniej / ekspozycja, jeśli
     jest; inaczej pomiń);
   - 9: drzewa z `items` (MultiMesh + kolizja: StaticBody cylinder tylko
     w pobliżu gracza / botów z fizyką), bez barier w tej strefie;
   - 10: pomost węższy (`lane_w`, bez pobocza), balustrada przy pasie;
   - 12: plama - wygląd (ciemniejszy pas w shaderze drogi, jak mokre
     strefy) i przyczepność `grip` x sucha (nowa nawierzchnia "patch"
     w tablicy przyczepności, jawna);
   - 13: skos robót x`taper_k`, tablica ze strzałką późno
     (`late_arrow`: 60 m zamiast 10 m przed skosem... czyli bliżej
     skosu), `ghost_lines`: stare białe linie prowadzą prosto w pachołki
     obok żółtych tymczasowych.
4. **Ruch**: 6 - korek (zdarzenie "korek" z etapu 1) stoi od
   `queue_end` do `queue_start` za szczytem, auta w miejscu albo
   ~10-20 km/h, tył miga awaryjnymi przy `hazards`; 7 - wg odpowiedzi na
   pytanie 4; 11 - wg odpowiedzi na pytanie 5.
5. **Punkty** (ScoreKeeper, bez nowych reguł): furiat rozbity w
   pułapce w zasięgu wzroku gracza = jak rozbicie przez gracza.
6. **Test sceny** `tests/trap_drive_test.gd` (jak `structure_drive_test`):
   autopilot przez każdą pułapkę 4a ze stałą prędkością bezpieczną
   (limit, a na łuku z promienia) - przejazd bez kontaktu; i drugi
   przejazd 140 km/h przez łuk poziomu 3 - auto wypada / ślizga się
   (dowód, że pułapka działa). Rendery każdej pułapki.
7. Bench na Queście: aleja drzew (najwięcej instancji) i estakada
   z wiatrem.

Testy jak zawsze: `drive_test` (oba typy skrzyni) - **szczególnie po
sile wiatru i nowej nawierzchni**, `structure_plan_test`,
`section_plan_test`, `trap_plan_test`, nowy test sceny. Wynik do
HANDOVER.md.

## Odpowiedź agenta lokalnego

(tu)
