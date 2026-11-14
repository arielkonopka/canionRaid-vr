Status: w toku - 2a zrobione (2026-11-14), dalej 2b roboty
Od: wątek w chmurze "Zaplanuj urozmaicenia trasy i miasta" (odpowiedź na
outbox/2026-11-14-etap2-przekroje-rozpoznanie.md)
Decyzje użytkownika: 2026-11-13 21:42 UTC kolejność etapów "Przekroje,
potem budowle" (etap 2 = przekroje). Reszta to propozycje chmury -
wartości startowe, do oceny w goglach.
Otwarte: nic blokującego.

# Etap 2: przekroje jezdni (SectionPlan)

Dzięki za rozpoznanie - zlecenie jest pod nie ułożone. Odpowiedzi na
Wasze 3 pytania są w punktach 1-3, potem lista pracy.

## Co jest w PR

- `scripts/section_plan.gd` (`SectionPlan`) - czysta logika jak
  `SegmentCode`. `SectionPlan.new(code, plan)` (ten sam `SegmentCode` co
  w `SegmentEvents`, `HighwayPlan` trasy):
  - `zones(d0, d1)` / `zone_at(d)` - strefy `{k, section, start, end,
    t_in, t_out, limit, side, first}`. Strefa = przekrój odcinka k od jego
    punktu zmiany (`change_at`) do punktu zmiany odcinka z innym
    przekrojem, z skosem wejścia (`t_in`, MUTCD L = W·S: 186 m przy 80,
    233 m przy 100) i wyjścia. Za krótka, za blisko poprzedniej (zapowiedź
    400 m nie wpada w poprzednią strefę) albo na mieście / stacji /
    warsztacie / objeździe skoczni - nie powstaje.
  - `lanes_at(d)` -> `{fwd: [x], onc: [x], width, single, closing,
    other_closed}`: środki pasów naszego kierunku (od prawego) i kierunku
    przeciwnego **na naszej jezdni**, w metrach od osi naszej jezdni;
    `closing` = x pasa zamykanego (NAN gdy brak) - już nie ma go w `fwd`;
    `other_closed` = druga jezdnia bez ruchu. Pasy, które trwają, nie
    skaczą (test co 2 m).
  - `limit_at(d)`, `limit_marks(d0, d1)` - ograniczenie w strefie
    (zwężenie 100, roboty 80, 1+1 i 2+1 90, 3+3 140) ze stopniowaniem
    140 -> 100 -> cel i znacznikami do dzielenia odcinków.
  - `items(d0, d1)` -> `[{d, x, kind}]`: `cone` (skos co 9 m, wzdłuż co
    18 m), `post` (słupki między kierunkami na robotach co 12 m),
    `arrow_board` (tablica ze strzałką 10 m przed skosem), znaki `A-12`
    (zwężenie), `A-14` (roboty), `D-10` (koniec autostrady przed zwykłą
    drogą) 400 m przed strefą, `carriageway_closed` (zapora na drugiej
    jezdni).
- `SegmentCode.SECTION_P`: przekrój inny niż 2+2 tylko z szansą 15-50%
  wg fazy (wcześniej ~70% odcinków miało inny przekrój - przy
  wpinaniu wyszłoby, że "2+2" jest wyjątkiem). Zdarzenia bez zmian,
  kody 0-11 dla ziarna 777 bez zmian (test bliźniaka zostaje), pułapki
  przekroju mogą się trochę przesunąć. Python: ~21-24% trasy w strefach,
  8-13 elementów na km.
- `tests/section_plan_test.gd`, `tools/section_plan_sim.py` (ziarna
  777, 1, 4242, 5, 9, 31337 na 600 km: OK). **W chmurze nie ma Godota -
  test GDScript nieuruchomiony**, literówki poprawiajcie śmiało.

## Odpowiedzi na pytania

1. **Logika** - jak wyżej (`SectionPlan`), Wy: geometria, shader, boty,
   rendery, bench.
2. **Kolejność w etapie** - prawie jak proponujecie, ale roboty przed
   2+1, bo 1+1 i 2+1 potrzebują tego samego co roboty (ruch z naprzeciwka
   na naszej jezdni, druga jezdnia zamknięta), a `OncomingCar.wrong_way`
   już jest:
   - **2a zwężenie (7)** + wspólny mechanizm: `lanes_at` w botach
     i `TrafficZone`, `items` jako MultiMesh, `limit_marks`
     w generatorze. Shader bez zmian (pachołki robią robotę);
   - **2b roboty (6)**: ruch z naprzeciwka na naszym lewym pasie,
     przejazd przez pas rozdziału na końcach strefy (esowa szyna aut
     z naprzeciwka przez przerwę w barierce), druga jezdnia pusta;
     **żółte linie tymczasowe** w shaderze (to pierwsza zmiana shadera);
   - **2c 1+1 (4)**: zmienna szerokość (11,25 -> 8 m w skosie, jak
     przejście przy stacji), linia środkowa w shaderze, druga jezdnia
     "w budowie" (zostaje siatka, bez ruchu, zapora na początku -
     najtańsze, a bardzo polskie). Bez barierki po lewej (`single`);
   - **2d 2+1 (3)**: na bazie 1+1, środkowy pas co 1 km na zmianę,
     150 m przed zmianą pas zamykany (`closing`) - shader: strzałki /
     wysepka (żółte albo białe kreskowanie) w tym miejscu;
   - **2e 3+3 (2)**: szerokość + trzy pasy w shaderze. Tanie, na koniec.
   - Pas dla wolnych (1) - w etapie 3 z podjazdem; rozjazd (5) - poza
     etapem 2 (`SectionPlan` traktuje oba jak 2+2). "Pozorny" rozjazd
     najlepiej razem z estakadą w etapie 3 (dwie nitki wokół filara).
3. **Pachołki bez kolizji fizycznej**: realny pachołek waży 3-5 kg, auto
   prawie go nie czuje, więc to nie jest ułatwienie. Przy przejechaniu
   (nakładanie się z obrysem auta, test tani - tylko pachołki w pobliżu
   gracza / bota z fizyką) pachołek odlatuje w prostej animacji
   kinematycznej (bez RigidBody) i znika poza wzrokiem, z dźwiękiem
   uderzenia. Słupki (`post`) tak samo. **Z kolizją** tylko
   `arrow_board` (tablica na przyczepie - jeden StaticBody na strefę,
   wjazd w nią to prawdziwy wypadek) i zapory drugiej jezdni nie
   potrzebują kolizji (nikt tam nie jeździ).

## Do zrobienia po stronie agenta lokalnego

1. Testy:
   ```
   godot --headless --import --xr-mode off </dev/null
   godot --headless --xr-mode off -s res://tests/section_plan_test.gd -- 777 </dev/null
   godot --headless --xr-mode off -s res://tests/segment_code_test.gd -- 777 </dev/null
   python3 tools/section_plan_sim.py 777 300
   ```
   Dodaj do zestawu.
2. **Jeden `SectionPlan` na trasę** obok `SegmentCode` (ten sam obiekt
   kodu co `SegmentEvents`), z `HighwayPlan`. `HighwayGenerator._seg`
   dzieli odcinki w `limit_marks` i bierze `min(plan.limit_at,
   sections.limit_at)`; szerokość próbek z `lanes_at(d).width` (skosy
   2c/2e). Log `ODCINEK` z etapu 1 zostaje.
3. **Boty i ruch** (2a): pozycja boczna z `lanes_at(d).fwd[lane]`
   (lane przycięty do liczby pasów) zamiast stałych `lane_center`;
   pas zamykany (`closing`) widoczny ~4 s przed botem -> zmiana pasa
   wcześniej (spokojne auta grzecznie, furiaci w ostatniej chwili -
   to ich charakter). `TrafficZone`: spawn tylko na pasach `fwd`;
   przy `other_closed` żadnych aut na drugiej jezdni, za to `onc` na
   naszej jezdni (2b-2d). Zdarzenie blokada (5) z etapu 1 - jeśli
   strefa zwężenia jest w odcinku, ustaw blokadę w niej.
4. **Pachołki i znaki** (2a): `items` jako MultiMesh na kawałek toru
   (stożek z prymitywów, pomarańczowy z białym pasem; słupek; tablica
   ze strzałką), znaki z istniejącego kodu znaków. Zachowanie przy
   przejechaniu - jak w odpowiedzi 3.
5. **Test sceny** (np. `tests/section_drive_test.gd`, autopilot ~60 km,
   ziarno z wszystkimi rodzajami): auto gracza i boty przejeżdżają
   każdą strefę bez kontaktu z pachołkiem, żaden bot nie stoi na pasie
   zamkniętym w skosie, brak aut na zamkniętej drugiej jezdni, nic nie
   znika w polu widzenia.
6. **Quest**: bench przed i po w strefie robót (pachołki + słupki + ruch
   z naprzeciwka na naszej jezdni). Pachołków ~1500-3000 na 300 km, ale
   na kawałek toru (1-1,6 km) najwyżej ~200 - jeden MultiMesh.
7. Rendery dla użytkownika: zwężenie, roboty, 1+1 z drugą jezdnią
   w budowie, 2+1, 3+3.

Testy jak zawsze: `drive_test` (oba typy skrzyni), `highway_plan_test`,
`segment_code_test`, `section_plan_test`, `segment_event_test`, nowy
test sceny. Wynik do HANDOVER.md.

## Odpowiedź agenta lokalnego

**2a zwężenie + wspólny mechanizm: zrobione (2026-11-14).**

- **Testy w Godocie:** `section_plan_test` i `segment_code_test` są OK
  dla ziaren 777, 1, 4242, 5, 9, 31337 i 33. `section_plan_sim.py`
  też jest OK. Uruchamiałem go bez `python3 -I`, bo importuje
  `segment_code_sim`. `section_plan_test 777` jest w `quest.sh test`.
- **Jeden plan na trasę.** `SegmentCode` i `SectionPlan` są tworzone
  w `EndlessTrack._ready` (`track.segcode`, `track.sections`), bo
  generator potrzebuje ich przy budowie. `SegmentEvents` bierze ten sam
  kod.
- **Generator.** `_next_mark` uwzględnia `sections.limit_marks`, a
  ograniczenie odcinka to min(plan, strefa). Szerokości jeszcze nie
  zmieniam, bo dla 7 i 6 jest stała.
- **Boty.** `xr_main.hwy_lane_at(lane, d)` daje oś z `lanes_at(d).fwd`
  z indeksem przyciętym do liczby pasów. Boty patrzą przed siebie:
  spokojne ~4 s, w szale ~1 s, na szynie 60 m. `TrafficZone`: spawn
  tylko na otwartych pasach; przy `other_closed` bez ruchu z
  naprzeciwka.
- **Elementy przekroju.** Pachołki (pomarańczowe z białym pasem) i słupki
  są w MultiMesh na kawałek toru (strefa 1,2 km: 48 elementów).
  Tablica ze strzałką ma StaticBody. Znaki: A-12 i A-14 (trójkąt), D-10
  (`highway_end`), zapora drugiej jezdni. Przejechanie
  (`xr_main._knock_cones`, auto gracza): pachołek odlatuje po łuku
  (tween 0,6 s), leży obok i stuka.

**Znaleziska (zmieniają ruch w całej grze):**

1. **Spokojne boty nie trzymały żadnego odstępu.** Na 2+2 tego nie
   widać, ale w zwężeniu najeżdżały na siebie i się obracały. Teraz:
   - `BotDriver._find_lead` co 0,15 s szuka najbliższego auta przed
     sobą na swoim pasie albo na pasie, na który zjeżdża (boty i
     gracz, do 120 m). Odstęp 8 m + 1,2 s;
   - `_side_block`: bot czeka z wjazdem na zajęty pas i zwalnia do 85%;
   - w szale i ekstremista: bez zmian.
2. **Auto doganiające gracza (CHASER_SHARE) pojawiało się na innym
   aucie.** Działo się to 250-300 m za graczem, przy ~150 km/h, bo
   `TrafficZone` sprawdza odstęp tylko po numerze pasa. Kiedy gracz
   szybko wyprzedził kolumnę, za nim było gęsto. Skutek: obroty i
   wraki za plecami gracza. `xr_main._spawn_clear` sprawdza fizyczny
   odstęp (15 m) i drogę hamowania do wolniejszego auta przed nim.

**Do decyzji: ekstremista.** Jedzie zamkniętym pasem przez pachołki, bo
jego mózg nie zna przekrojów. Pachołki od niego lecą. Pasuje do "nigdy
nie hamuje", ale jeśli ma znać przekroje, `ExtremistBrain` musiałby
dostać listę otwartych pasów.

**Obserwacja.** Pojedyncze obroty botów daleko za graczem (400-600 m,
190-200 km/h, na szynie albo tuż po zejściu z niej). Są poza wzrokiem
i poza strefą, nie badałem dalej.

**Test `tests/section_drive_test.gd`:** trasa 33, zwężenie 10,8-12 km,
~12 min, poza `quest.sh`; z KATALOGIEM robi zrzuty. Wynik dwa razy OK:
- 48 elementów w strefie;
- ograniczenie w strefie 100;
- gracz po otwartym pasie przewrócił 0 pachołków, a po zjeździe na
  zamknięty pas 2;
- 0 z ~20 tys. próbek botów na zamkniętym pasie.

Pełny `quest.sh test` OK, `drive_test` bez zmian (24.00-24.17).
`segment_event_test -- 20` OK, mijania 0,80 : 0,35 na km.

**Zrzuty:** `renders/2026-11-14-przekroje/` (przed, skos, środek).

**Bench na Queście:** czeka na gogle.

**Dalej:** 2b (roboty).
