Status: nowe
Od: agent lokalny, 2026-11-10 (noc, użytkownik śpi; gogle offline)
Dotyczy: `inbox/2026-11-10-plan-nocy.md`, PR #46-#50

# Noc: co zrobione lokalnie, co dla chmury

## Zrobione i przetestowane (pełny `./quest.sh test`)

- Punkty 5-10 Waszego planu zrobiłem równolegle przed scaleniem. Przy
  scaleniu wziąłem **Wasze wersje**: oznakowanie rozwidleń
  (`_island_front`, `_island_warning`), `WorkshopShop` (dopłata na stacji,
  silnik z odkupem, `car_spec`), ruch (`lane_center`, nadmiar,
  `base_traffic`). Moje duplikaty usunięte, `xr_main` dostosowany:
  warsztat i stacja jako sklep (`_ws_build`, oferty `engine:*` z
  `engine_offer`), klakson (lewy drążek / H, szał w 250 m), menu pauzy =
  ustawienia gry z grupą "Radio" i pytaniem przed restartem, spust
  zatwierdza w menu, B wraca. Testy: `shop_test`, `horn_test`,
  `pause_test`, `stunt_shop_test`, `highway_plan_test`,
  `oncoming_skirmish_test` OK.
- **`city_graph_test` NIE przechodzi** (30 błędów): po zawróceniu na
  tym samym odcinku (`nxt = frm`, 10% kroków) `current_a/current_b` nie
  odwracają kierunku ("po skręcie bieżąca (2,0)->(1,0) zamiast
  (1,0)->(2,0)"). Moduł niewpięty - proszę o poprawkę w `CityGraph.update`
  (albo w teście, jeśli zawracanie ma zostawiać kierunek).
- Autostrada etap 2-3 lokalnie: biomy (paleta ziemi, horyzont na biom,
  morze), ruch `TrafficZone` na obu jezdniach, pula botów, rendery.
- **Błędy w `HighwayScenery` znalezione na renderach**: `_box` i `_quad`
  miały odwróconą kolejność wierzchołków (Godot: przód = zgodnie z ruchem
  wskazówek zegara) - wszystkie pudła (budynki, słupki, latarnie, ekrany)
  i wierzch chodników były odrzucane jako tylne ściany. Poprawione.
  Uwaga na przyszłe siatki z SurfaceTool.
- `road.gdshader`: parametr `layout` (0 wąwóz, 1 autostrada, 2 jezdnia
  z naprzeciwka lustrzanie): 2 pasy po 3,75, opaska 0,75, pas awaryjny 3,
  bez wyścigowych krawężników. W mieście bez barier energochłonnych,
  trawy i nasypu (chodnik `HighwayScenery._sidewalks`).
- Rendery: `docs/renders/` (opis w README tam).

## Prośby na noc (bez Godota)

1. `CityGraph` - poprawka zawracania (wyżej).
2. Przejrzyjcie rendery `docs/renders/*.jpg` i zgłoście, co wygląda źle
   (proporcje budynków, chodniki, okna, przejście biomów) - poprawię.
3. **Integracja aut z epoki** (`inbox/2026-11-09-auta-z-epoki.md`):
   modele OBJ są w `models/ggbotnet/car_01..08` i `models/quaternius/`
   (NormalCar1/2, SportsCar/2, SUV). Proszę o mapowanie: który plik OBJ
   do którego stylu `CarStyles`, skala/obrót/pozycja kół (z wymiarów
   `size` w `car_styles.gd`) - zrobię wczytanie i wpięcie.
4. `FeudDirector` + `OncomingSkirmish` - wpięcie w xr_main zrobię, gdy
   mi napiszecie, czy na autostradzie potyczki mają działać tylko przy
   miastach, czy wszędzie (budżet fizyki botów 8 - raport W3).

## Odpowiedź wątku

### Pkt 4 (wątek "Zaprojektuj nowe strategie botów road rage", 2026-11-10 ~00:10)

**Wszędzie na autostradzie, nie tylko przy miastach.** Użytkownik
(2026-11-09, 23:17) prosi wprost o "całą trasę na autostradzie (ruch w dwie
strony), furię drogową, także między botami". Nie wiąże jej z miastami.
Gdyby rano chciał inaczej, zmiana to jeden warunek przy starcie potyczki.

Budżet fizyki 8 (W3) trzymają te reguły, ważne wszędzie, także w mieście:

1. **Żetony pościgu, K = 4**, wspólne dla szału na gracza i waśni. Fizykę
   w szale ma tylko bot z żetonem. Bez żetonu bot w szale jedzie po szynie
   z prędkością pościgu poza wzrokiem i dostaje żeton, gdy ktoś odpadnie.
   To wymaga zmiany w `_update_rail` (`rage > 0` przestaje wymuszać
   fizykę, zamiast tego decyduje `has_token`).
2. **Waśń fizyczna startuje tylko**, gdy oba boty są w stożku
   `TrafficZone.visible` i bliżej niż `LOD_NEAR` (120 m), oba mają
   fizykę i są dwa wolne żetony. `MAX_FEUDS = 2` zostaje jako górny limit.
   Dalej waśni nie zaczynamy w ogóle. Zamiast niej rolę tła gra
   `OncomingSkirmish` na drugiej jezdni (klatki kluczowe, zero fizyki).
   Waśni skryptowej na naszej jezdni na razie nie robimy. Gdy pomiar
   pokaże zapas, wrócimy do tego.
3. Waśń, której strona wyjedzie poza `1,5 × LOD_NEAR` albo stożek na
   dłużej niż 2 s: `feud.calm(id)` + `end_feud()`, a żetony wracają do puli.
4. Sojusz po ataku gracza (`alliance`): uczestnicy mają już żetony. Nowi
   członkowie gangu dołączają tylko na wolnych żetonach, reszta zostaje
   spokojna.
5. W mieście reguły są te same. Jeśli PERF pokaże, że miasto (budynki,
   skrzyżowania) jest droższe w renderze, zmniejsz tam K do 3. To jedna
   stała, bez zmiany logiki.

Reszta jak w `inbox/2026-11-10-wasnie-na-autostradzie.md`. Z tego pliku
pkt 4 (`in_sight` ≤ 200 m) zastępuje reguła 2 powyżej (120 m), a pkt 6
uzupełniają żetony.

### Przegląd renderów (pkt 2)

Od: wątek w chmurze "Doprowadź grę do pełnej trasy autostradowej", 2026-11-10 ~00:10.

Pkt 1 (CityGraph), 3 (auta z epoki) i 4 (waśnie: tylko przy miastach czy
wszędzie) przekazał wątek monitorujący do właściwych wątków - odpowiedzi
przyjdą osobno. Tu pkt 2: przegląd renderów. Kolejność = ważność.

### Rendery - co wygląda źle

1. **Duże miasto to dwa rzędy budynków na pustyni**
   (`miasto_duze_z_gory`, `miasto_male_z_gory`). Z drogi jeszcze uchodzi,
   ale już z niewielkiej wysokości (skok, wielka skocznia) widać "ścianę"
   wzdłuż jezdni i gołą ziemię zaraz za nią. Propozycja: 2-3 dalsze rzędy
   jako tanie bryły bez kolizji (MultiMesh, jeden materiał, `visibility_range`),
   gęstość i wysokość malejące od jezdni; pod miastem zamiast piasku/trawy
   biomu - szary "grunt miejski" (parkingi, place) w promieniu zabudowy.
   W dużym mieście co ~150-250 m przecznica (przerwa w rzędzie + pas
   jezdni w bok na 20-30 m) - wtedy wygląda jak miasto, a jest gotowe
   miejsce na etap 5 (leniwy graf ulic).
2. **Budynki wyglądają na zaokrąglone / wygięte** (`miasto_duze_centrum`,
   `miasto_duze_detal`): jasność zmienia się płynnie wzdłuż płaskiej
   ściany i przez narożnik, dachy w widoku z góry wyglądają jak poduszki.
   Wygląda na wygładzone normalne (wspólne wierzchołki w narożnikach albo
   normalne liczone przed poprawką kolejności wierzchołków) albo na
   oświetlenie w `facade.gdshader` zależne od pozycji. Każda ściana pudła
   powinna mieć własne wierzchołki i stałą normalną.
3. **Okna przecięte po przekątnej** (`miasto_male_ulica`,
   `warsztat_w_miescie` - prawa strona): część okien ma ukośny podział na
   dwa odcienie, jakby dwa trójkąty ściany miały różne UV albo inną
   normalną. Sprawdź UV fasady na obu trójkątach ściany (po zamianie
   kolejności wierzchołków w `_box`/`_quad` UV musiały pójść za
   wierzchołkami).
4. **Ciemnoszare trójkąty u podstawy budynków** (`miasto_duze_centrum`
   lewa i prawa strona, `miasto_duze_detal`, `warsztat_w_miescie` lewa):
   wyglądają na końce skarpy nasypu albo ukośne daszki z poprzedniego
   błędu - w mieście nasypu ma nie być. Do znalezienia, co to za siatka.
5. **Chodnik**: bardzo jasny, gładki, wygląda na wysoką płytę (z
   `miasto_duze_detal` ~0,5 m nad jezdnią). Krawężnik ~0,15 m, kolor
   szary beton (jak bariera środkowa, nie biały), delikatne fugi co 2 m
   w shaderze albo kolorze wierzchołków.
6. **Wielka skocznia jest niewidoczna** (`wielka_skocznia_wjazd`,
   `_bok`): próg 3,5° na długim stole z obu ujęć wygląda jak zwykła
   droga. Przy 400 km/h gracz musi ją zobaczyć z daleka. Propozycja:
   nawierzchnia rozbiegu i stołu w czerwono-białe pasy poprzeczne
   (`road.gdshader`, `layout` 3), tablice U-3 po obu stronach progu,
   znak 1 km i 500 m przed. Ujęcie z boku niżej (5-10 m nad ziemią,
   60-80 m od osi), żeby było widać profil.
7. **Warsztat w mieście nie jest widoczny** na `warsztat_w_miescie`
   (kamera s0+230 patrzy na s0+420, warsztat ma być 300 m za początkiem
   zabudowy): albo kadr go mija, albo hala nie powstaje w trybie
   Autostrada. Proszę o ujęcie z ~60 m przed zjazdem i sprawdzenie, czy
   jest zjazd, znak i hala.
8. **Stacja** - ujęcie z ~600 m, czerwony dach ledwo widać. Proszę
   o ujęcie z ~80 m przed zjazdem (pas zjazdu, wysepka, dystrybutory).
9. **Pas zieleni przy jezdni w biomach pustynia/wąwóz** (`biome_desert_fwd`,
   `biome_canyon_fwd`): zielona trawa na pustyni razi. Kolor pasa
   z palety biomu (żwir/piasek). W wąwozie-biomie poza tym brak wąwozu -
   płaska ziemia i mesy daleko; jeśli to zamierzone (autostrada "przez
   region wąwozów"), to OK, ale nazwa myli - może "płaskowyż".
10. **Korony drzew** (`wielka_skocznia_bok`, `stacja_paliw`): wyglądają na
    puste w środku / oświetlone od spodu (ciemny pas w połowie korony).
    Możliwe, że `Scenery._cone` ma tę samą odwróconą kolejność
    wierzchołków co `_box` - drzewa w wąwozie mogły tego nie pokazać, bo
    patrzyło się na nie z jednej strony. Warto sprawdzić tak samo jak
    pudła.
11. Drobne: ekrany akustyczne na dojeździe do miasta wyglądają dobrze;
    bariera środkowa i pas awaryjny też. Linie na jezdni z naprzeciwka
    poprawne (lustrzane).

Nic z tego nie blokuje wpięcia waśni ani sklepu - to strojenie wyglądu.
Kolejność proponowana: 2-4 (błędy siatek, szybkie), 6 (bezpieczeństwo
gracza przy 400 km/h), 5, 9, 10, potem 1 (głębia miast - przy etapie 5).

### Pkt 3 (wątek "Dodaj nowe modele aut z epoki", 2026-11-10)

Od: wątek "Dodaj nowe modele aut z epoki": **bryły są
gotowe w układzie auta z gry**, nie trzeba liczyć skali ani obrotu.

- `models/period_cars/<model>/body.obj` (+ `body.mtl`) i `wheel.obj` dla
  kombi, hatchback, muscle, furgon, klin, kabriolet, terenowka. Robi je
  `tools/prepare_period_cars.py` (wywołuje go `tools/car_styles_tune.py`).
  Układ jak StuntCar: metry, przód -Z, prawo +X, y = 0 na płaszczyźnie
  mocowań. Karoseria bez kół, ustawiona tak, że koła w `mounts - UP *
  spring_len` przy ugięciu statycznym trafiają w nadkola (sprawdzone
  renderem). Koło: środek w zerze, oś X, zewnętrzna strona na +X - jak
  siatka koła sedana (dla lewych obrót o 180°, jak teraz).
- Mapowanie (długość auta ustala skalę, jednolitą - reszta wymiarów
  i fizyka policzone z siatki, więc rozstaw osi/kół i promień w
  `scripts/car_styles.gd` się zmieniły i strojenie poszło od nowa):
  | Model | Źródło | Skala |
  | --- | --- | --- |
  | kombi | ggbotnet/car_01 (kombi) | 0,751 |
  | hatchback | ggbotnet/car_03 (3-drzwiowy) | 0,659 |
  | muscle | ggbotnet/car_05 (długi sedan, winylowy dach) | 0,658 |
  | furgon | ggbotnet/car_04 (minivan) | 0,722 |
  | klin | quaternius/SportsCar2 | 1,095 |
  | kabriolet | quaternius/SportsCar, dach odcięty (ściany powyżej linii okien) | 1,109 |
  | terenowka | quaternius/SUV | 1,057 |
  Sedan zostaje własny (wgniecenia). Nieużyte: car_02 (saloon) i
  NormalCar1/2 - można je dać botom jako warianty sedana/hatchbacka
  z tą samą fizyką; car_06 (spalony wrak) - pasuje jako bryła po
  wybuchu; car_07 (lata 20.) i car_08 (furgon dostawczy) - poza epoką
  albo za duży.
- `scripts/car_styles.gd`: doszły `model`, `wheel_model`, `seat` (oczy
  kierowcy: dach - 0,24 m, 0,63 rozstawu za osią przednią; furgon 0,45 -
  kabina nad osią) i `spring_mult`/`damper_mult`.
- Lakier: GGBotNet ma warianty tekstury (`car_blue.png`, `car4_grey.png`
  itd.) - kolor przez podmianę tekstury albo mnożenie albedo; Quaternius -
  materiał nadwozia (`White`, `Orange`) jak "Paint *" w concept carze.
- Pułapka: `ggbotnet/car_03/Car3.mtl` wskazuje `Car3.png`, a plik to
  `car3.png` - na Linuksie tekstura się nie wczyta. Wyeksportowane
  `body.mtl` mają poprawione ścieżki (względne, wielkość liter z dysku).
- Wyniki: `docs/car_styles_sim.md`. Nowe po zmianie geometrii: hatchback
  (rozstaw kół 1,29 m z bryły) przy 120 km/h w sinusie z przerwą obraca
  się mimo ESP - przy 80 km/h OK. Do rozważenia `esp_char_speed` zależny
  od rozstawu osi; sprawdź w grze, zanim cokolwiek zmienisz.
