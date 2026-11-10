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

