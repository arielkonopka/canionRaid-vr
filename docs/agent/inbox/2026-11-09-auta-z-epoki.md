Status: w toku (modele GGBotNet pobrane)
Od: wątek w chmurze "Dodaj nowe modele aut z epoki"
Decyzje użytkownika (2026-11-09):
- więcej aut z lat 70./80. do wyboru w menu, te same auta jeżdżą jako boty;
- **bryły z gotowych modeli CC0** z sieci (nie budowane w kodzie jak sedan);
- **pliki modeli w repo**, w `models/`, z wpisem w `CREDITS.md`;
- kabriolet dopisany do listy (komentarz użytkownika w propozycji);
- parametry fizyki dobrane symulacją w chmurze (użytkownik: "czy możesz tę
  pracę za agenta wykonać?") - wynik w tym zleceniu.
Otwarte: zgoda na konkretne paczki (patrz niżej) - nie pobieraj nic, dopóki
użytkownik jej nie da.

# Auta z epoki: modele, fizyka, boty

## Co jest w tej gałęzi

- `tools/car_sim.py` - symulator auta w Pythonie. Odwzorowuje fizykę
  z `stunt_car.gd` (zawieszenie z przechyłem, pochyleniem i ugięciem,
  opony MF ze stanem relaksacji i podkrokami, koła, silnik, automat, LSD,
  4x4 z wiskozą, ABS/TCS z wyprzedzeniem, ESP, ograniczenie skrętu,
  Ackermann, opór). Uproszczenia: płaska sucha jezdnia, małe kąty
  przechyłu (dachowania nie liczy do końca - zgłasza oderwanie dwóch kół).
- `tools/car_styles_tune.py` - założenia modeli (`STYLES`) i strojenie.
  Generuje `docs/car_styles_sim.md` (nastawy + wyniki manewrów)
  i `scripts/car_styles.gd` (klasa `CarStyles`, same dane). Wynik strojenia
  w `tools/car_styles_tuned.json`; `--quick` liczy sam raport z niego
  (~20 s), pełne strojenie ~10 min.
- Kalibracja symulatora z pomiarami z gry (HANDOVER):
  | Pomiar | Gra | Symulator |
  | --- | --- | --- |
  | 180 kW tył, 0-100 | 5,7 s (engine_test) | 5,85 s |
  | 180 kW przód 1200 kg, 0-100 | 6,9 s | 6,87 s |
  | 700 kW tył 1200 kg, 0-100 | 4,6-5 s | 4,98 s |
  | 100-0, całoroczne | 40,5 m (grip_test) | 37,4 m |
  | skręt 80 km/h, maks. | 0,93-0,98 g | 0,90 g (skidpad R60) |
  Hamowanie wychodzi ~8% krócej - możliwe, że grip_test liczy od innej
  prędkości albo z czasem narastania ciśnienia. Proszę sprawdź, jak
  grip_test mierzy drogę, i dopisz odpowiedź niżej (poprawię symulator).

## Co wyszło z symulacji (szczegóły w `docs/car_styles_sim.md`)

- Strojone: przełożenie główne (`final_mult`, największa prędkość przy
  przełożeniu najbliższym fabrycznemu), sprężyny (żeby upadek z 1,5 m
  dobijał nie mocniej niż sedan, limit ×1,25), stabilizatory (cel
  przechyłu na model), podział hamulców (obie osie blokują się naraz przy
  0,9 g, +4% na przód).
- **Balans stabilizatorów prawie nie zmienia podsterowności** w modelu opon
  gry (load sensitivity 0,1): pierwsze strojenie pod podsterowność
  wyzerowało tylny stabilizator i dało 7x przedni, a podsterowność
  ruszyła się o 0,3 deg/g. Wszystkie auta są więc bliskie neutralnych
  (0,2-0,45 deg/g). Jeśli użytkownik będzie chciał wyraźnie różnych
  charakterów w zakrętach, potrzebna większa `load_sensitivity` (to
  zmiana fizyki wszystkich aut - tylko po rozmowie z użytkownikiem).
- Z ESP wszystkie modele przechodzą sinus z przerwą przy 80 km/h. Przy
  120 km/h hatchback jest na granicy (0,33/0,25 przy normie 0,35/0,20) -
  `esp_char_speed` 28 m/s pasuje do rozstawu sedana; do rozważenia
  zależny od rozstawu osi.
- Bez TCS i ESP klin i muscle obracają się przy pełnym gazie w łuku (tył,
  130/180 kW) - charakter auta, nie błąd.
- Hak przy 80 km/h na całorocznych: żadne auto nie unosi dwóch kół
  (terenówka 5,1° przechyłu, furgon 5,0°; SSF 1,07-1,08 wobec 1,41
  w sedanie). Dachują dopiero przy większej przyczepności albo na
  krawężniku - symulator tego nie liczy (płaska jezdnia).
- Po upadku z 1,5 m kombi, hatchback, muscle i furgon dobijają spodem
  (zawieszenie miękkie albo mały prześwit) - na skoczniach będą częściej
  szorować. Sedan jest na granicy (0,00).
- Boty 250 kW: każdy model sterowny w łuku z pełnym gazem (znoszenie
  2-9°) i w sinusie.

## Co zrobić w grze

1. **`StuntCar.set_body_model(kind)`** dla stylów z `CarStyles.STYLES`
   (obok "sedan" i "concept"): mocowania kół, `wheel_radius`,
   `rest_length`, `body_mass`, `com_offset` (już z `_model_com`-podobnym
   sensem: wartość jest pełnym offsetem względem punktu odniesienia; FWD
   dalej dodaje `FWD_FRONT_SHIFT` w `apply_engine`), `body_inertia`
   (_base_inertia; inertia = (X pochylenie, Y odchylenie, Z przechył)),
   `aero_drag = ½·ρ·cd·area`, kolizja z `size` i `body_bottom`.
   Sedan zostaje bez zmian - jego wiersz w danych to wartości obecne.
2. **Mnożniki z danych** (nowe pola StuntCar): `final_mult` (mnoży
   `final_drive` w `apply_engine`, przed korektą promienia koła),
   `arb_front_mult`/`arb_rear_mult` i `spring_mult`/`damper_mult`
   (w `apply_suspension_preset`, po skalowaniu masą), `brake_front`/
   `brake_rear` (zamiast stałych 1900/1050; `_brake_scale` dalej działa).
3. **Menu** ("Nadwozie i opony" → "Model auta"): wybór modelu raz ustawia
   jego fabryczny napęd, rodzaj silnika, moc, masę i zawieszenie (pola
   `engine`, `power_kw`, `drive`, `mass`, `suspension`); gracz może je
   potem zmieniać jak dziś. Moce fabryczne leżą na progach `POWER_TIERS`.
   Podpowiedzi: krótko, czym model się wyróżnia (np. terenówka: "wysoki
   środek masy - w ostrym manewrze unosi koła"). Migracja ustawień.
4. **Boty**: `_spawn_bot` losuje model z `bot_weight` ([wąwóz, autostrada])
   ziarnem `_bot_rng` (odrodzenie odtwarza rozkład). Moc botów bez zmian
   (250 kW, w szale max(350, gracz)) - symulator sprawdził, że wszystkie
   modele są przy tym sterowne (tabela "Stabilność" w raporcie).
   `BotDriver` liczy prędkość w łukach z `SURFACES` - dla terenówki
   i furgonu może trzeba zapasu (wyższy środek masy); sprawdź w
   `bot_rage_test`.
5. **Bryły CC0** (po zgodzie użytkownika): kandydaci, wszystko CC0:
   - GGBotNet "PSX Style Cars" (OpenGameArt, 2,6 MB): kombi, saloon,
     hatchback, minivan, sedan, step van; 300-480 trójkątów, tekstury
     128 px; skala między autami niespójna - wyrównać do `size`;
   - Quaternius "Realistic Car Pack" (itch.io, 2,6 MB, FBX/OBJ);
   - Kenney "Car Kit" 2.0 (45 elementów, też szczątki).
   Bez wnętrz: gracz siedzi w kokpicie z epoki z sedana (fotel, deska,
   kierownica, zegary) przesuniętym do `seat` danego modelu, jak przy
   concept carze. Bez marek i napisów (tablice jak w concept: jasne pole).
   Kabriolet: z sedana/coupe paczki po odcięciu dachu (bez `CabinShape`,
   więc dachowanie kończy się gorzej - uczciwie).
   Wydajność: jedna siatka karoserii + 4 koła na bota, materiały
   scalone (atlas), siatka wczytana raz na model (jak `_concept_scene`).
6. **Testy**: `drive_test` dla każdego modelu (zawieszenia, obie
   skrzynie), `engine_test`, `grip_test`, `landing_test`, `bot_rage_test`,
   `title_test` po menu. Porównaj 0-100 / 100-0 / g w zakręcie
   z `docs/car_styles_sim.md` i dopisz rozbieżności niżej.

## Odpowiedź agenta lokalnego

2026-11-09: użytkownik zgodził się na GGBotNet "PSX Style Cars" i Quaternius
"Realistic Car Pack". GGBotNet pobrany z OpenGameArt (CC0) do
`models/ggbotnet/car_01..08` (OBJ+MTL+PNG, bez .blend, **bez wariantów
policji i taxi** - `car5_police_la` ma oznaczenie konkretnego miasta),
wpis w CREDITS.md. Quaternius: strona nie daje bezpośredniego linku
(JS/Google Drive) - poproszę użytkownika o ręczne pobranie do
`build/media_in/quaternius/`. Integracja `CarStyles` (pkt 1-6) - jeszcze
nie; grip_test mierzy drogę od chwili wciśnięcia hamulca przy 100 km/h
(sprawdzę dokładnie przy integracji i odpowiem).
